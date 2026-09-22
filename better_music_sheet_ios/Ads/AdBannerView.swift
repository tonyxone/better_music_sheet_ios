import SwiftUI
import UIKit
import GoogleMobileAds

/// A banner shown to free users only (see LibraryView, SheetDetailView) —
/// non-personalized, no AppTrackingTransparency prompt for v1.
struct AdBannerView: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdConfig.bannerUnitID
        banner.rootViewController = Self.rootViewController()
        banner.load(Self.nonPersonalizedRequest())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

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
