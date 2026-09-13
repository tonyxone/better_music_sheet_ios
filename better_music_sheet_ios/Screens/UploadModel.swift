import Foundation

@MainActor
@Observable
final class UploadModel {
    enum State: Sendable, Equatable {
        case idle
        case reading
        case uploading
        case failed(String)
    }

    private(set) var state: State = .idle
    var options: AnnotationOptions

    private let uploader: SheetUploader

    init(uploader: SheetUploader = SheetUploader()) {
        self.uploader = uploader
        self.options = AnnotationOptions.load()
    }

    var isBusy: Bool { state == .reading || state == .uploading }

    /// Returns the new job's id, or nil when it failed — the message is in
    /// `state` either way.
    func upload(from url: URL) async -> String? {
        state = .reading
        // A file handed over by the document picker lives outside our
        // sandbox until we ask for it.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard SheetUploader.isSupported(filename: url.lastPathComponent) else {
            state = .failed("Only PDF, JPG and PNG files are supported.")
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            state = .failed("Couldn't read that file. \(error.localizedDescription)")
            return nil
        }

        return await upload(filename: url.lastPathComponent, data: data)
    }

    func upload(filename: String, data: Data) async -> String? {
        state = .uploading
        do {
            let jobID = try await uploader.upload(filename: filename, data: data, options: options)
            state = .idle
            return jobID
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
            return nil
        }
    }

    func clearError() {
        if case .failed = state { state = .idle }
    }
}
