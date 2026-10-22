import GoogleMobileAds
import UIKit
import OSLog

/// The full-screen ads a free user watches to unlock practice on a sheet
/// (see PracticeUnlocks) or to upload past the free sheet (see
/// UploadCredits). One ad is kept loaded ahead for each, so Watch Ad plays
/// at once.
///
/// Only a finished ad counts: Google calls the reward handler once the user
/// has watched long enough, and closing it before then unlocks nothing.
@MainActor
@Observable
final class RewardedAdLoader: NSObject {
    static let practice = RewardedAdLoader(unitID: AdConfig.rewardedUnitID, keep: 1)
    static let upload = RewardedAdLoader(unitID: AdConfig.uploadRewardedUnitID, keep: UploadCredits.adsPerUpload)

    private(set) var isLoading = false
    var isReady: Bool { !ads.isEmpty }

    private let unitID: String
    private let keep: Int
    private var ads: [RewardedAd] = []
    /// Resumed when the ad showing is closed, with whether it was earned.
    private var finish: CheckedContinuation<Bool, Never>?
    private var earned = false
    private let logger = Logger(subsystem: "com.bettermusicsheet.app", category: "Ads")

    private init(unitID: String, keep: Int) {
        self.unitID = unitID
        self.keep = keep
    }

    /// Settles consent first, as banners do, so nothing is requested before
    /// Google says it may be. Safe to call often.
    func load() async {
        guard AdConfig.isEnabled, ads.count < keep, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await AdConsent.shared.gather()
        guard AdConsent.shared.canRequestAds else { return }
        do {
            while ads.count < keep {
                ads.append(try await RewardedAd.load(with: unitID,
                                                     request: AdConfig.nonPersonalizedRequest()))
                logger.notice("Rewarded ad loaded")
#if DEBUG
                print("[Ads] Rewarded ad loaded")
#endif
            }
        } catch {
            let failure = error as NSError
            logger.error("Rewarded ad failed: \(failure.domain, privacy: .public) code \(failure.code): \(failure.localizedDescription, privacy: .public)")
#if DEBUG
            print("[Ads] Rewarded ad failed: \(failure.domain) code \(failure.code): \(failure.localizedDescription)")
#endif
        }
    }

    /// Shows the ad, loading one first if none is waiting. True only when the
    /// user earned the reward; false when there was no ad to show, it
    /// couldn't be shown, or it was closed early.
    func present() async -> Bool {
        if ads.isEmpty { await load() }
        guard !ads.isEmpty, finish == nil, let presenter = Self.presenter() else { return false }
        let ad = ads.removeFirst()
        earned = false
        ad.fullScreenContentDelegate = self
        let result = await withCheckedContinuation { continuation in
            finish = continuation
            ad.present(from: presenter) { [weak self] in
                self?.earned = true
            }
        }
        Task { await load() }
        return result
    }

    private func complete() {
        let earned = earned
        finish?.resume(returning: earned)
        finish = nil
        logger.notice("Rewarded ad closed; earned: \(earned)")
#if DEBUG
        print("[Ads] Rewarded ad closed; earned: \(earned)")
#endif
    }

    /// The topmost screen: the ad can't present from one that is already
    /// presenting something (a sheet, say).
    private static func presenter() -> UIViewController? {
        var top = AdConfig.rootViewController()
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

extension RewardedAdLoader: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        complete()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        logger.error("Rewarded ad couldn't present: \(error.localizedDescription, privacy: .public)")
        earned = false
        complete()
    }
}
