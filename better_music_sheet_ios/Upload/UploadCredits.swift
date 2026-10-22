import Foundation

/// Rewarded ads a free user has finished toward uploading past the free sheet
/// (see RewardedAdLoader.upload). Each such upload takes `adsPerUpload` —
/// one, since a single rewarded ad from Google often plays two videos;
/// the backend lets it through on the app's word (UploadRequest.ad_unlock).
///
/// The ads for one upload are watched in one go: closing one early throws
/// away the ones before it (`abandon()`). A full set is kept until an upload
/// is accepted, so an upload that fails can be tried again without ads.
/// Kept on this device only.
@MainActor
@Observable
final class UploadCredits {
    static let shared = UploadCredits()

    nonisolated static let adsPerUpload = 1

    private static let storageKey = "bms_upload_ad_credits"
    private(set) var adsWatched: Int
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-upload-credits") {
            defaults.removeObject(forKey: Self.storageKey)
        }
#endif
        // Only a full set outlives the run of ads that earned it.
        let stored = max(0, defaults.integer(forKey: Self.storageKey))
        self.adsWatched = stored >= Self.adsPerUpload ? stored : 0
    }

    /// Enough ads watched for one upload.
    var isReady: Bool { adsWatched >= Self.adsPerUpload }

    func earn() {
        set(adsWatched + 1)
    }

    /// An ad closed before its reward: the ones watched before it in this
    /// run don't count either. A full set already earned is kept.
    func abandon() {
        if !isReady { set(0) }
    }

    /// Called once the backend has accepted an upload that used the ads.
    func spend() {
        set(max(0, adsWatched - Self.adsPerUpload))
    }

    private func set(_ count: Int) {
        adsWatched = count
        defaults.set(count, forKey: Self.storageKey)
    }
}
