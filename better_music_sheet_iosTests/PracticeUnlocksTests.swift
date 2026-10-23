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

    @Test func anUnlockLastsAnHour() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let unlocks = PracticeUnlocks(defaults: freshDefaults(), now: { now })
        unlocks.unlock("job-1")

        #expect(unlocks.unlockedUntil("job-1") == now.addingTimeInterval(3600))
        now += 3599
        #expect(unlocks.isUnlocked("job-1"))
        now += 1
        #expect(!unlocks.isUnlocked("job-1"))
        #expect(unlocks.unlockedUntil("job-1") == nil)
    }

    @Test func anotherAdStartsAFreshHour() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let unlocks = PracticeUnlocks(defaults: freshDefaults(), now: { now })
        unlocks.unlock("job-1")
        now += 4000
        unlocks.unlock("job-1")

        #expect(unlocks.unlockedUntil("job-1") == now.addingTimeInterval(3600))
    }

    @Test func expiredUnlocksAreForgotten() {
        let defaults = freshDefaults()
        var now = Date(timeIntervalSince1970: 1_000_000)
        let unlocks = PracticeUnlocks(defaults: defaults, now: { now })
        unlocks.unlock("job-1")
        now += 1800
        unlocks.unlock("job-2")
        now += 2000

        #expect(PracticeUnlocks(defaults: defaults, now: { now }).expiries.keys.sorted() == ["job-2"])
    }

    @Test func untimedUnlocksFromOlderBuildsDontCarryOver() {
        let defaults = freshDefaults()
        defaults.set(["job-1"], forKey: "bms_practice_unlocks")

        #expect(!PracticeUnlocks(defaults: defaults).isUnlocked("job-1"))
        #expect(defaults.object(forKey: "bms_practice_unlocks") == nil)
    }

    @Test func readingUnlocksLastAnHourAndAreKeptApart() {
        let defaults = freshDefaults()
        var now = Date(timeIntervalSince1970: 1_000_000)
        let reading = PracticeUnlocks(defaults: defaults, now: { now },
                                      storageKey: "reading", duration: PracticeUnlocks.readingDuration)
        reading.unlock("job-1")

        #expect(!PracticeUnlocks(defaults: defaults, now: { now }).isUnlocked("job-1"))
        now += 60 * 60 - 1
        #expect(reading.isUnlocked("job-1"))
        now += 1
        #expect(!reading.isUnlocked("job-1"))
    }

    @Test func theFirstUploadIsTheFreeSheet() {
        let sheets = [(id: "newer", createdAt: 300.0), (id: "first", createdAt: 100.0), (id: "middle", createdAt: 200.0)]
        #expect(PracticeUnlocks.freeSheetID(among: sheets) == "first")
        // Down to one, that one is free, whichever it was.
        #expect(PracticeUnlocks.freeSheetID(among: [(id: "newer", createdAt: 300)]) == "newer")
        #expect(PracticeUnlocks.freeSheetID(among: []) == nil)
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
