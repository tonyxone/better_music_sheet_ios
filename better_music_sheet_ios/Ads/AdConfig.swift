import Foundation

/// Where the app's AdMob ad units live. Debug builds (installed from Xcode)
/// use Google's test banner, so tapping an ad while developing never counts
/// as an invalid click on the real account. The app id itself lives
/// in better_music_sheet_ios-Info.plist at the repo root, which Xcode merges
/// into the generated Info.plist. It can't be an INFOPLIST_KEY_ build setting:
/// Xcode silently drops keys it doesn't know, and the SDK then aborts at
/// launch for want of an app id.
nonisolated enum AdConfig {
    /// Banners show to anyone without Premium, on the library, sheet and
    /// practice pages. False hides them everywhere and skips starting the SDK.
    static let isEnabled = true

#if DEBUG
    static let bannerUnitID = "ca-app-pub-3940256099942544/2435281174"
#else
    static let bannerUnitID = "ca-app-pub-3606656264491246/5951929085"
#endif
}
