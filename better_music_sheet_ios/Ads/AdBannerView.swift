import SwiftUI
import UIKit
import GoogleMobileAds
import OSLog

/// A banner shown to free users only (see LibraryView, SheetDetailView) —
/// non-personalized, no AppTrackingTransparency prompt for v1.
struct AdBannerView: UIViewRepresentable {
    @Binding var hasLoadedAd: Bool
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdConfig.bannerUnitID
        banner.rootViewController = Self.rootViewController()
        banner.delegate = context.coordinator
        banner.load(Self.nonPersonalizedRequest())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(hasLoadedAd: $hasLoadedAd) }

    final class Coordinator: NSObject, BannerViewDelegate {
        private var hasLoadedAd: Binding<Bool>
        private let logger = Logger(subsystem: "com.bettermusicsheet.app", category: "Ads")

        init(hasLoadedAd: Binding<Bool>) { self.hasLoadedAd = hasLoadedAd }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            hasLoadedAd.wrappedValue = true
            logger.notice("Banner loaded")
#if DEBUG
            print("[Ads] Banner loaded")
#endif
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            hasLoadedAd.wrappedValue = false
            let failure = error as NSError
            logger.error("Banner failed: \(failure.domain, privacy: .public) code \(failure.code): \(failure.localizedDescription, privacy: .public)")
#if DEBUG
            print("[Ads] Banner failed: \(failure.domain) code \(failure.code): \(failure.localizedDescription)")
#endif
        }
    }

    /// v1 skips the AppTrackingTransparency prompt entirely, which means it
    /// must ask AdMob for non-personalized ads explicitly rather than rely on
    /// IDFA simply being unavailable.
    private static func nonPersonalizedRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
