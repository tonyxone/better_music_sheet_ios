import GoogleMobileAds
import SwiftUI
import UIKit
import UserMessagingPlatform
import OSLog

/// Google's consent requirements for ads (GDPR in the EEA and UK, and US state
/// privacy laws), through its User Messaging Platform. The message itself is
/// configured in AdMob under Privacy & messaging; this asks for it when needed
/// and only starts the ads SDK once Google says ads may be requested.
///
/// Gathered the first time a banner would show rather than at launch, so a
/// Premium account, which never sees ads, is never asked.
@MainActor
@Observable
final class AdConsent {
    static let shared = AdConsent()

    /// Whether banners may load. True straight away when an earlier launch
    /// already settled consent, as Google recommends.
    private(set) var canRequestAds: Bool
    /// Whether the user must be offered a way to change their choice (the
    /// Account screen's Ad Privacy Choices).
    private(set) var privacyOptionsRequired = false

    private var gathering = false
    private var adsStarted = false
    private let logger = Logger(subsystem: "com.bettermusicsheet.app", category: "Ads")

    private init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-ad-consent") {
            UMPConsentInformation.sharedInstance.reset()
        }
#endif
        canRequestAds = UMPConsentInformation.sharedInstance.canRequestAds
        if canRequestAds { startAds() }
    }

    /// Refreshes consent and shows Google's form if this user still has to
    /// answer it. Safe to call often: it runs once at a time, and the form
    /// only appears when required.
    func gather() async {
        guard AdConfig.isEnabled, !gathering else { return }
        gathering = true
        defer { gathering = false }
        let consent = UMPConsentInformation.sharedInstance
        do {
            try await consent.requestConsentInfoUpdate(with: UMPRequestParameters())
            try await UMPConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            // No network or no message configured: fall through to whatever
            // an earlier launch settled, which may still allow ads.
            logger.error("Consent update failed: \(error.localizedDescription, privacy: .public)")
#if DEBUG
            print("[Ads] Consent update failed: \(error.localizedDescription)")
#endif
        }
        update()
    }

    /// Google's form for changing an earlier choice.
    func presentPrivacyOptions() async {
        try? await UMPConsentForm.presentPrivacyOptionsForm(from: nil)
        update()
    }

    private func update() {
        let consent = UMPConsentInformation.sharedInstance
        canRequestAds = consent.canRequestAds
        logger.notice("Consent refreshed; can request ads: \(self.canRequestAds)")
#if DEBUG
        print("[Ads] Consent refreshed; can request ads: \(canRequestAds)")
#endif
        privacyOptionsRequired = consent.privacyOptionsRequirementStatus == .required
        if canRequestAds { startAds() }
    }

    private func startAds() {
        guard AdConfig.isEnabled, !adsStarted else { return }
        adsStarted = true
        MobileAds.shared.start(completionHandler: nil)
    }
}

/// Keeps the consent task alive even before consent is available, but reserves
/// screen space only after a banner has successfully loaded.
struct AdBannerSlot: View {
    @State private var consent = AdConsent.shared
    @State private var hasLoadedAd = false

    var body: some View {
        ZStack {
            Color.clear
            if consent.canRequestAds {
                AdBannerView(hasLoadedAd: $hasLoadedAd)
                    .frame(width: 320, height: 50)
            }
        }
        .frame(height: consent.canRequestAds && hasLoadedAd ? 50 : 0)
        .clipped()
        .task { await consent.gather() }
    }
}
