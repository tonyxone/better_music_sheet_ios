import Foundation

/// Which sheets a free user has unlocked by watching a rewarded ad (see
/// RewardedAdLoader), and until when — on this device only. Premium has no
/// limits.
///
/// `shared` is practice: without an unlock it plays the first `freeMeasures`
/// measures only, and an ad opens the whole sheet for `unlockDuration`.
/// `reading` is for a free account holding more than its one sheet (most
/// often a lapsed subscriber): every sheet but its first needs an ad to open,
/// for `readingDuration`.
@MainActor
@Observable
final class PracticeUnlocks {
    static let shared = PracticeUnlocks()
    static let reading = PracticeUnlocks(storageKey: "bms_reading_unlock_expiry", duration: readingDuration)

    /// How much of a locked sheet practice plays.
    nonisolated static let freeMeasures = 8
    /// How long one ad unlocks a sheet's practice for.
    nonisolated static let unlockDuration: TimeInterval = 60 * 60
    /// How long one ad opens a locked sheet for, practice included. Clock
    /// time: it runs on while the app is closed.
    nonisolated static let readingDuration: TimeInterval = 60 * 60

    private static let practiceKey = "bms_practice_unlock_expiry"
    /// Unlocks that never expired, from builds before unlocks were timed.
    private static let legacyKey = "bms_practice_unlocks"
    /// When each unlocked sheet locks again, as epoch seconds.
    private(set) var expiries: [String: Double]
    private let defaults: UserDefaults
    private let now: () -> Date
    private let storageKey: String
    private let duration: TimeInterval

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         storageKey: String = practiceKey, duration: TimeInterval = unlockDuration) {
        self.defaults = defaults
        self.now = now
        self.storageKey = storageKey
        self.duration = duration
        if storageKey == Self.practiceKey { defaults.removeObject(forKey: Self.legacyKey) }
        let stored = defaults.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
        let current = now().timeIntervalSince1970
        self.expiries = stored.filter { $0.value > current }
    }

    /// When this sheet locks again, or nil if it isn't unlocked now.
    func unlockedUntil(_ jobID: String) -> Date? {
        guard let expiry = expiries[jobID], expiry > now().timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: expiry)
    }

    func isUnlocked(_ jobID: String) -> Bool { unlockedUntil(jobID) != nil }

    /// Starts a fresh period, even if some of an earlier one is left.
    func unlock(_ jobID: String) {
        let current = now().timeIntervalSince1970
        var kept = expiries.filter { $0.value > current }
        kept[jobID] = current + duration
        expiries = kept
        defaults.set(kept, forKey: storageKey)
    }

    /// The one sheet a free account opens without an ad: its first upload,
    /// or whichever is left when only one is. Nil when there is none.
    nonisolated static func freeSheetID(among sheets: [(id: String, createdAt: Double)]) -> String? {
        sheets.min { $0.createdAt < $1.createdAt }?.id
    }

    /// Whether opening this sheet takes an ad (before any unlock): a free
    /// account holding more than its one sheet — most often a lapsed
    /// subscriber's — opens all but its first that way. `kept` is the
    /// account's sheets that count (not failed); only finished ones lock.
    nonisolated static func needsReadingAd(_ id: String, isDone: Bool,
                                           kept: [(id: String, createdAt: Double)],
                                           isPremium: Bool, adsEnabled: Bool) -> Bool {
        guard adsEnabled, !isPremium, isDone, kept.count > 1 else { return false }
        return id != freeSheetID(among: kept)
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
