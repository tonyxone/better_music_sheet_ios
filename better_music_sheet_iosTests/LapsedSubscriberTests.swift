import Foundation
import Testing
@testable import better_music_sheet_ios

/// A subscriber uploads several sheets, then the subscription (or its trial)
/// ends: the first upload stays free to open, the rest take an ad each, for
/// an hour of clock time.
@MainActor
struct LapsedSubscriberTests {
    private typealias Sheet = (id: String, createdAt: Double)

    private let first: Sheet = ("first", 100)
    private let second: Sheet = ("second", 200)
    private let third: Sheet = ("third", 300)

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    private func locked(_ sheet: Sheet, kept: [Sheet], premium: Bool,
                        reading: PracticeUnlocks, adsEnabled: Bool = true) -> Bool {
        PracticeUnlocks.needsReadingAd(sheet.id, isDone: true, kept: kept,
                                       isPremium: premium, adsEnabled: adsEnabled)
            && !reading.isUnlocked(sheet.id)
    }

    @Test func whileSubscribedNothingIsLocked() {
        let reading = PracticeUnlocks(defaults: freshDefaults(), storageKey: "r",
                                      duration: PracticeUnlocks.readingDuration)
        let kept = [third, second, first]
        for sheet in kept {
            #expect(!locked(sheet, kept: kept, premium: true, reading: reading))
        }
    }

    @Test func afterItEndsOnlyTheFirstUploadOpensFreely() {
        let reading = PracticeUnlocks(defaults: freshDefaults(), storageKey: "r",
                                      duration: PracticeUnlocks.readingDuration)
        // Newest first, as the backend lists them.
        let kept = [third, second, first]
        #expect(!locked(first, kept: kept, premium: false, reading: reading))
        #expect(locked(second, kept: kept, premium: false, reading: reading))
        #expect(locked(third, kept: kept, premium: false, reading: reading))
    }

    @Test func anAdOpensOneSheetForAnHourOfClockTime() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let defaults = freshDefaults()
        let reading = PracticeUnlocks(defaults: defaults, now: { now }, storageKey: "r",
                                      duration: PracticeUnlocks.readingDuration)
        let practice = PracticeUnlocks(defaults: defaults, now: { now })
        let kept = [third, second, first]

        // What LibraryView.watchSheetAd does once the ad is earned.
        reading.unlock(second.id)
        practice.unlock(second.id)

        #expect(!locked(second, kept: kept, premium: false, reading: reading))
        #expect(practice.isUnlocked(second.id))
        #expect(locked(third, kept: kept, premium: false, reading: reading))

        // The app closed for most of the hour: still open, from storage.
        now += 59 * 60
        let relaunched = PracticeUnlocks(defaults: defaults, now: { now }, storageKey: "r",
                                         duration: PracticeUnlocks.readingDuration)
        #expect(!locked(second, kept: kept, premium: false, reading: relaunched))

        // An hour after the ad, closed or not, it takes another.
        now += 60
        #expect(locked(second, kept: kept, premium: false, reading: relaunched))
        #expect(!practice.isUnlocked(second.id))
    }

    @Test func deletingDownToOneSheetMakesItFreeWhicheverItIs() {
        let reading = PracticeUnlocks(defaults: freshDefaults(), storageKey: "r",
                                      duration: PracticeUnlocks.readingDuration)
        #expect(!locked(third, kept: [third], premium: false, reading: reading))
        // With the first deleted, the oldest left is the free one.
        #expect(!locked(second, kept: [third, second], premium: false, reading: reading))
        #expect(locked(third, kept: [third, second], premium: false, reading: reading))
    }

    @Test func subscribingAgainOpensEverything() {
        let reading = PracticeUnlocks(defaults: freshDefaults(), storageKey: "r",
                                      duration: PracticeUnlocks.readingDuration)
        let kept = [third, second, first]
        #expect(locked(third, kept: kept, premium: false, reading: reading))
        #expect(!locked(third, kept: kept, premium: true, reading: reading))
    }

    @Test func sheetsStillReadingNeverLock() {
        #expect(!PracticeUnlocks.needsReadingAd(third.id, isDone: false, kept: [third, second, first],
                                                isPremium: false, adsEnabled: true))
    }

    @Test func withAdsSwitchedOffNothingLocks() {
        let reading = PracticeUnlocks(defaults: freshDefaults(), storageKey: "r",
                                      duration: PracticeUnlocks.readingDuration)
        #expect(!locked(third, kept: [third, second, first], premium: false, reading: reading, adsEnabled: false))
    }
}
