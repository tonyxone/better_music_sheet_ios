import Foundation
import Testing
@testable import better_music_sheet_ios

struct JobProgressTests {

    private func job(_ status: String, stage: String?) throws -> AnnotationJob {
        var fields: [String: Any] = [
            "jobId": "j", "musicSheetId": "m", "status": status, "style": "letter",
            "octave": false, "fontSize": 12, "createdAt": 0, "updatedAt": 0,
        ]
        fields["stage"] = stage
        return try JSONDecoder().decode(AnnotationJob.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    @Test func stagesMoveTheBarForwardInOrder() throws {
        let stages: [(String, String?)] = [
            ("uploading", "Uploading sheet"),
            ("queued", nil),
            ("processing", "Reading sheet music · about 2 minutes"),
            ("processing", "Re-reading unclear pages"),
            ("processing", "Matching pitches to notes"),
            ("processing", "Building playback timeline · 1,204 notes"),
            ("processing", "Drawing the annotated sheet"),
        ]
        let ranges = try stages.map { try job($0.0, stage: $0.1).progressRange }
        for (earlier, later) in zip(ranges, ranges.dropFirst()) {
            #expect(earlier.upperBound <= later.lowerBound)
        }
        #expect(ranges.last!.upperBound < 1)
    }

    @Test func recognitionIsSplitByPage() throws {
        let second = try job("processing", stage: "Reading sheet music (page 2 of 4) · about 3 minutes").progressRange
        let whole = try job("processing", stage: "Reading sheet music").progressRange
        let share = (whole.upperBound - whole.lowerBound) / 4
        #expect(abs(second.lowerBound - (whole.lowerBound + share)) < 1e-9)
        #expect(abs(second.upperBound - (whole.lowerBound + 2 * share)) < 1e-9)
    }

    @Test func anImpossiblePageFallsBackToTheWholeStage() throws {
        let bogus = try job("processing", stage: "Reading sheet music (page 9 of 4)").progressRange
        #expect(bogus == (try job("processing", stage: "Reading sheet music").progressRange))
    }
}
