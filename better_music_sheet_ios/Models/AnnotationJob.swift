import Foundation

/// One annotation job. Mirrors `AnnotationJob` in the web app's lib/api.ts,
/// which in turn mirrors the row `server.py` returns.
nonisolated struct AnnotationJob: Codable, Sendable, Identifiable, Hashable {
    /// Unknown is not a real backend state — it exists so a status added to
    /// the API later degrades to "we don't know" instead of failing the whole
    /// decode and emptying the library.
    enum Status: String, Codable, Sendable, Hashable {
        case uploading, queued, processing, done, failed, unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }

        var isInProgress: Bool {
            switch self {
            case .uploading, .queued, .processing: true
            case .done, .failed, .unknown: false
            }
        }
    }

    let jobID: String
    let musicSheetID: String
    let status: Status
    let sheetName: String?
    let error: String?
    let stage: String?
    let labeledGroups: Int?
    let style: String
    let octave: Bool
    let fontSize: Double
    let dpi: Int?
    let createdAt: Double
    let updatedAt: Double

    var id: String { jobID }

    private enum CodingKeys: String, CodingKey {
        case jobID = "jobId"
        case musicSheetID = "musicSheetId"
        case status, error, stage, style, octave, dpi
        case sheetName, labeledGroups, fontSize, createdAt, updatedAt
    }

    var createdDate: Date { Date(timeIntervalSince1970: createdAt) }
    var displayName: String { sheetName ?? musicSheetID }
}
