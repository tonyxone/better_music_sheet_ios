import CoreGraphics
import Foundation

@MainActor
@Observable
final class UploadModel {
    enum State: Sendable, Equatable {
        case idle
        case reading
        case straightening
        case uploading
        case failed(String)
    }

    private(set) var state: State = .idle
    var options: AnnotationOptions
    /// Set when the panel was opened with ads watched (see UploadCredits):
    /// the upload goes past the free sheet, and spends the ads once accepted.
    var adUnlock = false

    private let uploader: SheetUploader

    init(uploader: SheetUploader = SheetUploader()) {
        self.uploader = uploader
        self.options = AnnotationOptions.load()
    }

    var isBusy: Bool { state == .reading || state == .straightening || state == .uploading }

    /// Returns the new job's id, or nil when it failed — the message is in
    /// `state` either way.
    func upload(from url: URL) async -> String? {
        state = .reading
        // A file handed over by the document picker lives outside our
        // sandbox until we ask for it.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard SheetUploader.isSupported(filename: url.lastPathComponent) else {
            state = .failed(String(localized: "Only PDF, JPG and PNG files are supported.", bundle: .app))
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            state = .failed(String(localized: "Couldn't read that file. \(error.localizedDescription)", bundle: .app))
            return nil
        }

        return await upload(filename: url.lastPathComponent, data: data)
    }

    /// A photo of a page, straightened first (PagePhoto) off the main thread.
    func upload(photo: Data) async -> String? {
        state = .straightening
        let page = await Task.detached(priority: .userInitiated) { PagePhoto.straightened(photo) }.value
        guard let page else {
            state = .failed(String(localized: "Couldn't read the photo.", bundle: .app))
            return nil
        }
        return await upload(filename: "Photo.jpg", data: page)
    }

    /// The camera's scanned pages, already straightened, as one sheet.
    func upload(scan pages: [CGImage]) async -> String? {
        state = .reading
        let file = await Task.detached(priority: .userInitiated) {
            PagePhoto.scanned(pages, maxBytes: AppConfig.maxUploadBytes)
        }.value
        guard let file else {
            state = .failed(String(localized: "Couldn't read the photo.", bundle: .app))
            return nil
        }
        return await upload(filename: file.filename, data: file.data)
    }

    func upload(filename: String, data: Data) async -> String? {
        state = .uploading
        do {
            let jobID = try await uploader.upload(filename: filename, data: data, options: options,
                                                  adUnlock: adUnlock)
            if adUnlock {
                UploadCredits.shared.spend()
                adUnlock = false
            }
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
