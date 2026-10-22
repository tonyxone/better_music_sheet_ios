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

    @Test func anUploadTakesOneAd() {
        #expect(UploadCredits.adsPerUpload == 1)
        let credits = UploadCredits(defaults: freshDefaults())
        #expect(!credits.isReady)
        credits.earn()
        #expect(credits.isReady)
    }

    @Test func closingTheAdEarlyEarnsNothing() {
        let credits = UploadCredits(defaults: freshDefaults())
        credits.abandon()

        #expect(credits.adsWatched == 0)
        #expect(!credits.isReady)
    }

    @Test func anEarnedAdSurvivesAnAbandonAndARelaunch() {
        let defaults = freshDefaults()
        let credits = UploadCredits(defaults: defaults)
        credits.earn()
        credits.abandon()

        #expect(credits.isReady)
        #expect(UploadCredits(defaults: defaults).isReady)
    }

    @Test func anAcceptedUploadSpendsTheAd() {
        let defaults = freshDefaults()
        let credits = UploadCredits(defaults: defaults)
        credits.earn()
        credits.spend()

        #expect(credits.adsWatched == 0)
        #expect(!UploadCredits(defaults: defaults).isReady)
    }

    @Test func aSecondAdFromAnOlderBuildStillOnlyCoversOneUpload() {
        let defaults = freshDefaults()
        let credits = UploadCredits(defaults: defaults)
        credits.earn()
        credits.earn()
        credits.spend()

        #expect(credits.isReady)
        credits.spend()
        #expect(!credits.isReady)
    }
}
