import Foundation
import Testing
@testable import better_music_sheet_ios

@MainActor
struct UploadCreditsTests {
    /// A throwaway suite per test, so credits never leak between tests (or
    /// into the real app's UserDefaults).
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    @Test func anUploadTakesTwoAds() {
        let credits = UploadCredits(defaults: freshDefaults())
        #expect(!credits.isReady)
        credits.earn()
        #expect(!credits.isReady)
        credits.earn()
        #expect(credits.isReady)
    }

    @Test func closingAnAdEarlyStartsTheCountOver() {
        let credits = UploadCredits(defaults: freshDefaults())
        credits.earn()
        credits.abandon()

        #expect(credits.adsWatched == 0)
    }

    @Test func aFullSetSurvivesAnAbandonAndARelaunch() {
        let defaults = freshDefaults()
        let credits = UploadCredits(defaults: defaults)
        credits.earn()
        credits.earn()
        credits.abandon()

        #expect(credits.isReady)
        #expect(UploadCredits(defaults: defaults).isReady)
    }

    @Test func halfASetDoesntSurviveARelaunch() {
        let defaults = freshDefaults()
        UploadCredits(defaults: defaults).earn()

        #expect(UploadCredits(defaults: defaults).adsWatched == 0)
    }

    @Test func anAcceptedUploadSpendsTheSet() {
        let defaults = freshDefaults()
        let credits = UploadCredits(defaults: defaults)
        credits.earn()
        credits.earn()
        credits.spend()

        #expect(credits.adsWatched == 0)
        #expect(!UploadCredits(defaults: defaults).isReady)
    }
}
