import Foundation

/// Which sheets a free user has unlocked for practice by watching a rewarded
/// ad (see RewardedAdLoader). Without one, practice plays the first
/// `freeMeasures` measures only; Premium has no limit.
///
/// Kept on this device only, for good: a reinstall or another device asks again.
@MainActor
@Observable
final class PracticeUnlocks {
    static let shared = PracticeUnlocks()

    /// How much of a locked sheet practice plays.
    nonisolated static let freeMeasures = 8

    private static let storageKey = "bms_practice_unlocks"
    private(set) var jobIDs: Set<String>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.jobIDs = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    func isUnlocked(_ jobID: String) -> Bool { jobIDs.contains(jobID) }

    func unlock(_ jobID: String) {
        guard jobIDs.insert(jobID).inserted else { return }
        defaults.set(jobIDs.sorted(), forKey: Self.storageKey)
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
