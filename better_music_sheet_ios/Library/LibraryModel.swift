import Foundation

@MainActor
@Observable
final class LibraryModel {
    enum State: Sendable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var jobs: [AnnotationJob] = []
    /// Refreshed alongside the library itself, so the toolbar's name updates
    /// the moment a sign-in or sign-out actually takes effect, rather than
    /// needing its own separate poll.
    private(set) var currentUser: User?

    private let client: APIClient
    private let sessions: SessionStore
    private let entitlements: EntitlementStore

    init(client: APIClient = .shared, sessions: SessionStore = .shared, entitlements: EntitlementStore = .shared) {
        self.client = client
        self.sessions = sessions
        self.entitlements = entitlements
    }

    var hasWorkInProgress: Bool { jobs.contains { $0.status.isInProgress } }

    // MARK: - Pagination

    /// The backend's own GET /api/sheets has no paging of its own — it
    /// always returns the whole history in one response — so this pages the
    /// already-fetched list purely on the client, rather than the network
    /// call itself. A page grows only when asked (loadMore()) and otherwise
    /// survives a background refresh untouched, so polling or pulling to
    /// refresh never collapses a list someone has already scrolled through.
    private static let pageSize = 20
    private(set) var visibleCount = pageSize

    var visibleJobs: [AnnotationJob] { Array(jobs.prefix(visibleCount)) }
    var hasMoreToShow: Bool { visibleCount < jobs.count }

    func loadMore() {
        visibleCount = min(visibleCount + Self.pageSize, jobs.count)
    }

    private static let pollInterval: Duration = .seconds(3)

    /// Rows show each job's stage inline, so while anything is still being
    /// recognised the list has to keep asking. Without this a row froze on
    /// whatever stage it had when the list was loaded — typically "Waiting
    /// for a recognition worker" — long after the sheet was done.
    ///
    /// A failed refresh keeps the rows on screen and still counts as work in
    /// progress, so a dropped connection is simply retried on the next tick.
    func pollWhileWorking() async {
        while hasWorkInProgress {
            do {
                try await Task.sleep(for: Self.pollInterval)
            } catch {
                return  // the view went away
            }
            await load()
        }
    }

    func load() async {
        currentUser = await sessions.current()?.user
        // Runs alongside rather than ahead of the sheet fetch below — a slow
        // subscription check shouldn't hold up the library the user came
        // here to see. This is also what re-checks entitlement "on account
        // change," since every sign-in and sign-out already calls load().
        Task { await entitlements.refresh() }
        if jobs.isEmpty { state = .loading }
        do {
            let fetched: [AnnotationJob] = try await client.get("/api/sheets")
            jobs = fetched.sorted { $0.createdAt > $1.createdAt }
            state = .loaded
        } catch {
            // Keep whatever is already on screen; a failed refresh should not
            // empty a library the user was just looking at.
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func delete(_ job: AnnotationJob) async {
        let previous = jobs
        jobs.removeAll { $0.jobID == job.jobID }
        do {
            try await client.send("/api/sheets/\(job.jobID)", method: "DELETE")
        } catch {
            jobs = previous
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
