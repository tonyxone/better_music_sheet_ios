import Foundation

/// Where the app's AdMob ad units live. Google's public test id for now —
/// swap for the real banner unit id before release. The app id itself lives
/// in better_music_sheet_ios-Info.plist at the repo root, which Xcode merges
/// into the generated Info.plist. It can't be an INFOPLIST_KEY_ build setting:
/// Xcode silently drops keys it doesn't know, and the SDK then aborts at
/// launch for want of an app id.
nonisolated enum AdConfig {
    /// Off for now: no banners are shown and the SDK isn't started. Flip to
    /// true to bring them back for free users.
    static let isEnabled = false

    static let bannerUnitID = "ca-app-pub-3940256099942544/2934735716"
}
