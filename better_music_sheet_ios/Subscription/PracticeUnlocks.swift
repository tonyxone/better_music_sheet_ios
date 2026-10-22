import Foundation

/// Which sheets a free user has unlocked for practice by watching a rewarded
/// ad (see RewardedAdLoader), and until when. Without one, practice plays the
/// first `freeMeasures` measures only; Premium has no limit.
///
/// Each ad unlocks one sheet for `unlockDuration`, on this device only.
@MainActor
@Observable
final class PracticeUnlocks {
    static let shared = PracticeUnlocks()

    /// How much of a locked sheet practice plays.
    nonisolated static let freeMeasures = 8
    /// How long one ad unlocks a sheet for.
    nonisolated static let unlockDuration: TimeInterval = 60 * 60

    private static let storageKey = "bms_practice_unlock_expiry"
    /// Unlocks that never expired, from builds before unlocks were timed.
    private static let legacyKey = "bms_practice_unlocks"
    /// When each unlocked sheet locks again, as epoch seconds.
    private(set) var expiries: [String: Double]
    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        defaults.removeObject(forKey: Self.legacyKey)
        let stored = defaults.dictionary(forKey: Self.storageKey) as? [String: Double] ?? [:]
        let current = now().timeIntervalSince1970
        self.expiries = stored.filter { $0.value > current }
    }

    /// When this sheet locks again, or nil if it isn't unlocked now.
    func unlockedUntil(_ jobID: String) -> Date? {
        guard let expiry = expiries[jobID], expiry > now().timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: expiry)
    }

    func isUnlocked(_ jobID: String) -> Bool { unlockedUntil(jobID) != nil }

    /// Starts a fresh hour, even if some of an earlier one is left.
    func unlock(_ jobID: String) {
        let current = now().timeIntervalSince1970
        var kept = expiries.filter { $0.value > current }
        kept[jobID] = current + Self.unlockDuration
        expiries = kept
        defaults.set(kept, forKey: Self.storageKey)
    }

    /// Where a locked sheet's practice stops: the start of the first measure
    /// past the free ones, counting only measures that take time. Nil when
    /// the whole piece fits, so a short piece never asks for an ad.
    nonisolated static func previewEndBeat(in timeline: Timeline, freeMeasures: Int = freeMeasures) -> Double? {
        let playable = timeline.measures.filter { $0.lengthBeats > 0 }
        guard playable.count > freeMeasures else { return nil }
        return playable[freeMeasures].startBeat
    }
}
