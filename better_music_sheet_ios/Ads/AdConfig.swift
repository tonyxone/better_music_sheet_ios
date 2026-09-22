import Foundation

/// Where the app's AdMob ad units live. Google's public test id for now —
/// swap for the real banner unit id before release. The app id itself lives
/// in the Xcode project's build settings (INFOPLIST_KEY_GADApplicationIdentifier)
/// rather than here, since GENERATE_INFOPLIST_FILE means there's no physical
/// Info.plist to edit.
nonisolated enum AdConfig {
    static let bannerUnitID = "ca-app-pub-3940256099942544/2934735716"
}
