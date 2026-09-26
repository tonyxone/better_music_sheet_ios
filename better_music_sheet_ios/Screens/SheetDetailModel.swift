import Foundation

/// Where a sheet lives in the app's navigation. Addressed by job id rather
/// than by a whole job, so a sheet that was just uploaded can be opened
/// before the library has refreshed.
nonisolated struct SheetRoute: Hashable, Sendable {
    /// Which of a sheet's two pages to open.
    enum Page: Hashable, Sendable {
        case sheet
        case practice
    }

    let jobID: String
    /// What to show in the title bar until the real row arrives.
    let provisionalName: String
    var page: Page = .sheet
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
    private(set) var originalPDFData: Data?
    private(set) var isLoadingOriginal = false
    /// The reader's own changes, and the names as data to make them on.
    /// Built once the sheet is done; nil until then.
    private(set) var editor: SheetEditorModel?

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

    /// Fetches the uploaded PDF only when the reader asks to see it. The
    /// annotated PDF is still ready immediately when a sheet opens.
    func loadOriginal() async throws {
        guard originalPDFData == nil, !isLoadingOriginal else { return }
        isLoadingOriginal = true
        defer { isLoadingOriginal = false }
        originalPDFData = try await files.data(jobID: route.jobID, artifact: .original)
    }

    /// Follows the job until it reaches a final state, then fetches the PDF.
    ///
    /// Safe to call again — the view restarts it whenever the app returns to
    /// the foreground — because it always begins by asking for the current
    /// state rather than trusting whatever is on screen.
    func run() async {
        guard await refresh() else { return }

        while job == nil || job?.status.isInProgress == true {
            do {
                try await Task.sleep(for: Self.pollInterval)
            } catch {
                return  // the view went away
            }
            guard await refresh() else { return }
        }

        guard job?.status == .done else { return }
        await loadFile()
    }

    /// Returns false only when polling should stop for good.
    ///
    /// A transport failure is not a verdict on the job — most often it is the
    /// phone locking mid-recognition — so it leaves the current stage on
    /// screen and lets the next tick try again. Previously one dropped request
    /// ended polling, and a sheet whose very first check failed stayed on
    /// "Queued" forever, because a nil job never entered the loop.
    private func refresh() async -> Bool {
        do {
            let fetched: AnnotationJob = try await client.get("/api/sheets/\(route.jobID)")
            job = fetched
            apply(fetched)
            return true
        } catch APIError.transport(_) {
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
        guard pdfData == nil || editor == nil else { return }
        stage = .loadingFile
        do {
            let assets = try? await files.assets(jobID: route.jobID)
            if pdfData == nil {
                pdfData = try await files.data(jobID: route.jobID, artifact: .pdf, assets: assets)
            }
            editor = await makeEditor(assets: assets)
            stage = .ready
        } catch {
            stage = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// The names are drawn from data over the ORIGINAL upload, rather than
    /// shown baked into the annotated PDF — that is what makes them editable.
    /// Without a stored PDF original or the label data, the annotated copy is
    /// shown instead, and only marks and notes can be added on top of it.
    /// Everything here is best-effort: the annotated sheet is already in hand.
    private func makeEditor(assets: SheetAssets?) async -> SheetEditorModel {
        let store = SheetEditsStore(jobID: route.jobID, client: client)
        async let edits: Void = store.load()
        async let timeline = try? files.timeline(jobID: route.jobID)
        async let sources = Self.labelSources(jobID: route.jobID, assets: assets, files: files)
        let (original, labelData) = await sources
        var labels: LabelSet?
        if let original {
            originalPDFData = original
            labels = labelData.flatMap(LabelSet.decode)
            // Sheets annotated before label export: read the names back out
            // of the annotated PDF, as the web app does.
            if labels == nil, let annotated = pdfData {
                let linkedTo = await timeline
                labels = await Task.detached { LabelSet.reading(pdf: annotated, timeline: linkedTo) }.value
            }
        }
        await edits
        if let keys = store.doc?.labels.keys { labels = labels?.adoptingIDs(of: keys) }
        return SheetEditorModel(store: store, labels: labels, timeline: await timeline)
    }

    /// The original upload, when it's a PDF the names can be drawn over, and
    /// the label data if the sheet has any.
    nonisolated static func labelSources(jobID: String, assets: SheetAssets?, files: SheetFiles) async -> (Data?, Data?) {
        guard let assets, assets.originalIsPDF else { return (nil, nil) }
        async let original = try? files.data(jobID: jobID, artifact: .original, assets: assets)
        async let labels = assets.labels == nil ? nil : try? files.data(jobID: jobID, artifact: .labels, assets: assets)
        guard let data = await original, data.starts(with: Data("%PDF-".utf8)) else { return (nil, nil) }
        return (data, await labels)
    }

    /// The annotated PDF written somewhere the share sheet can reach, named
    /// the way the user would expect rather than by job id.
    func exportURL() -> URL? {
        guard let pdfData else { return nil }
        return write(pdfData, suffix: " (annotated)")
    }

    /// The uploaded file, under the name it was uploaded with.
    func originalExportURL() -> URL? {
        guard let originalPDFData else { return nil }
        return write(originalPDFData, suffix: "")
    }

    /// What the preview shows right now — the names over the original, or
    /// the original alone, or the annotated copy when the names can't be
    /// drawn — with the reader's names, drawings and notes.
    func customizedExportURL(showingOriginal: Bool) -> URL? {
        guard let editor else { return nil }
        let namesLive = editor.namesLive && originalPDFData != nil
        guard let base = showingOriginal || namesLive ? originalPDFData : pdfData else { return nil }
        var content = SheetOverlayContent(labels: editor.labels, edits: editor.doc,
                                          showsNames: namesLive && !showingOriginal)
        content.editing = false
        guard let data = SheetExport.customizedPDF(base: base, content: content) else { return nil }
        return write(data, suffix: " (customized)")
    }

    private func write(_ data: Data, suffix: String) -> URL? {
        let stem = (title as NSString).deletingPathExtension
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(stem)\(suffix).pdf")
        return (try? data.write(to: url, options: .atomic)) == nil ? nil : url
    }
}
