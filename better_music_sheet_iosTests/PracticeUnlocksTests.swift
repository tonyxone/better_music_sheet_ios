import Foundation
import Testing
@testable import better_music_sheet_ios

@MainActor
struct PracticeUnlocksTests {
    /// A throwaway suite per test, so unlocks never leak between tests (or
    /// into the real app's UserDefaults).
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    /// Four-beat measures, with any listed lengths overriding.
    private func timeline(measures count: Int, lengths: [Int: Double] = [:]) -> Timeline {
        var start = 0.0
        let measures = (0..<count).map { index in
            let length = lengths[index] ?? 4
            defer { start += length }
            return TimelineMeasure(index: index, label: "\(index + 1)", startBeat: start,
                                   lengthBeats: length, distinctMidis: [])
        }
        return Timeline(version: 1, tempoBpmDefault: 120, totalBeats: start, measures: measures, notes: [])
    }

    @Test func anUnlockOutlivesTheStoreThatMadeIt() {
        let defaults = freshDefaults()
        PracticeUnlocks(defaults: defaults).unlock("job-1")

        let reopened = PracticeUnlocks(defaults: defaults)
        #expect(reopened.isUnlocked("job-1"))
        #expect(!reopened.isUnlocked("job-2"))
    }

    @Test func sheetsUnlockOneAtATime() {
        let unlocks = PracticeUnlocks(defaults: freshDefaults())
        unlocks.unlock("job-1")
        unlocks.unlock("job-1")
        unlocks.unlock("job-2")

        #expect(unlocks.jobIDs == ["job-1", "job-2"])
    }

    @Test func aPieceThatFitsThePreviewIsNeverLocked() {
        #expect(PracticeUnlocks.previewEndBeat(in: timeline(measures: 8)) == nil)
        #expect(PracticeUnlocks.previewEndBeat(in: timeline(measures: 3)) == nil)
    }

    @Test func thePreviewEndsWhereTheNinthMeasureStarts() {
        #expect(PracticeUnlocks.previewEndBeat(in: timeline(measures: 20)) == 32)
    }

    @Test func emptyMeasuresDontCountTowardThePreview() {
        // A zero-length measure 3 takes no time, so the ninth to sound is index 9.
        let withEmpty = timeline(measures: 12, lengths: [2: 0])
        #expect(PracticeUnlocks.previewEndBeat(in: withEmpty) == withEmpty.measures[9].startBeat)
        #expect(PracticeUnlocks.previewEndBeat(in: timeline(measures: 9, lengths: [2: 0])) == nil)
    }
}
