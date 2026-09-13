import Foundation

/// Where a sheet lives in the app's navigation. Addressed by job id rather
/// than by a whole job, so a sheet that was just uploaded can be opened
/// before the library has refreshed.
nonisolated struct SheetRoute: Hashable, Sendable {
    let jobID: String
    /// What to show in the title bar until the real row arrives.
    let provisionalName: String
}

/// Follows one sheet from wherever it is now to something you can read:
/// polls while it is being recognised, then fetches the annotated PDF.
@MainActor
@Observable
final class SheetDetailModel {
    enum Stage: Sendable, Equatable {
        case working(String)
        case loadingFile
        case ready
        case failed(String)
    }

    private(set) var job: AnnotationJob?
    private(set) var stage: Stage = .working("Queued")
    private(set) var pdfData: Data?

    private let route: SheetRoute
    private let client: APIClient
    private let files: SheetFiles
    private static let pollInterval: Duration = .milliseconds(2500)

    init(route: SheetRoute, job: AnnotationJob? = nil,
         client: APIClient = .shared, files: SheetFiles = SheetFiles()) {
        self.route = route
        self.job = job
        self.client = client
        self.files = files
        if let job { apply(job) }
    }

    var title: String { job?.displayName ?? route.provisionalName }

    func run() async {
        if job == nil, await refresh() == false { return }

        while job?.status.isInProgress == true {
            do {
                try await Task.sleep(for: Self.pollInterval)
            } catch {
                return  // the view went away
            }
            if await refresh() == false { return }
        }

        guard job?.status == .done else { return }
        await loadFile()
    }

    @discardableResult
    private func refresh() async -> Bool {
        do {
            let fetched: AnnotationJob = try await client.get("/api/sheets/\(route.jobID)")
            job = fetched
            apply(fetched)
            return true
        } catch {
            stage = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
            return false
        }
    }

    private func apply(_ job: AnnotationJob) {
        switch job.status {
        case .done: stage = pdfData == nil ? .loadingFile : .ready
        case .failed: stage = .failed(job.error ?? "Recognition failed for this sheet.")
        default: stage = .working(job.stage ?? "Queued")
        }
    }

    private func loadFile() async {
        guard pdfData == nil else { return }
        stage = .loadingFile
        do {
            pdfData = try await files.data(jobID: route.jobID, artifact: .pdf)
            stage = .ready
        } catch {
            stage = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// The annotated PDF written somewhere the share sheet can reach, named
    /// the way the user would expect rather than by job id.
    func exportURL() -> URL? {
        guard let pdfData else { return nil }
        let stem = (title as NSString).deletingPathExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(stem) (annotated).pdf")
        return (try? pdfData.write(to: url, options: .atomic)) == nil ? nil : url
    }
}
