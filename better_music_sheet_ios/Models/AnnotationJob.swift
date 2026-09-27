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

    /// The slice of a progress bar the job's current stage covers. The backend
    /// reports only a stage name (processor.py STAGES), so the bar's position
    /// is inferred from it: recognition gets most of the width because it
    /// takes most of the time, split per page once "(page x of y)" appears.
    var progressRange: ClosedRange<Double> {
        let stage = stage ?? ""
        if status == .uploading || stage.hasPrefix("Uploading") { return 0.00...0.08 }
        if stage.hasPrefix("Reading sheet music") {
            let reading = 0.12...0.70
            guard let (page, pages) = Self.page(in: stage) else { return reading }
            let share = (reading.upperBound - reading.lowerBound) / Double(pages)
            let start = reading.lowerBound + share * Double(page - 1)
            return start...(start + share)
        }
        if stage.hasPrefix("Re-reading unclear pages") { return 0.70...0.82 }
        if stage.hasPrefix("Matching pitches to notes") { return 0.82...0.90 }
        if stage.hasPrefix("Building playback timeline") { return 0.90...0.95 }
        if stage.hasPrefix("Drawing the annotated sheet") { return 0.95...0.99 }
        // Queued, waiting for a worker, or retrying.
        return 0.08...0.12
    }

    /// "(page 2 of 5)" as (2, 5); worker.py appends it during recognition.
    private static func page(in stage: String) -> (Int, Int)? {
        guard let match = stage.firstMatch(of: /\(page (\d+) of (\d+)\)/),
              let page = Int(match.1), let pages = Int(match.2),
              pages > 0, (1...pages).contains(page) else { return nil }
        return (page, pages)
    }
}
