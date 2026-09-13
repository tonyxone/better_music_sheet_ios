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

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    var hasWorkInProgress: Bool { jobs.contains { $0.status.isInProgress } }

    func load() async {
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
