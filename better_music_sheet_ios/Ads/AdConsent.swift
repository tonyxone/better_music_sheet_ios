import GoogleMobileAds
import SwiftUI
import UIKit
import UserMessagingPlatform

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

    private init() {
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
#if DEBUG
            print("[AdConsent] \(error.localizedDescription)")
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
        privacyOptionsRequired = consent.privacyOptionsRequirementStatus == .required
        if canRequestAds { startAds() }
    }

    private func startAds() {
        guard AdConfig.isEnabled, !adsStarted else { return }
        adsStarted = true
        MobileAds.shared.start(completionHandler: nil)
    }
}

/// Where a banner goes: gathers consent the first time it's shown and holds
/// the space empty until ads may be requested.
struct AdBannerSlot: View {
    @State private var consent = AdConsent.shared

    var body: some View {
        Group {
            if consent.canRequestAds {
                AdBannerView().frame(height: 50)
            }
        }
        .task { await consent.gather() }
    }
}
