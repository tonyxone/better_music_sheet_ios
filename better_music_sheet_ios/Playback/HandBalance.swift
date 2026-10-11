import Foundation

/// The left/right hand balance for playback, from -1 (the left hand alone) to
/// 1 (the right alone); 0 plays both as written. Kept per sheet and on this
/// device only: it suits practising one piece, not the reader in general.
/// Ported from the web app's lib/hand-balance.ts and app/play/playback.ts.
nonisolated enum HandBalance {
    static let range: ClosedRange<Double> = -1...1

    /// Snaps to even near the middle, where a drag can't otherwise land.
    static func normalized(_ value: Double) -> Double {
        guard value.isFinite, abs(value) >= 0.08 else { return 0 }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    /// How much of its written velocity a hand keeps. A velocity, not a gain:
    /// one sampler sounds both hands, and the quieter hand is played softer,
    /// as a pianist would. Gain is velocity squared (SamplePreset.velocityGain),
    /// so the square root makes the hand's level fall in step with the slider,
    /// to silence at the end.
    static func velocityScale(balance: Double, role: Int) -> Double {
        let cut = role == 1 ? max(0, balance) : max(0, -balance)
        return (1 - min(1, cut)).squareRoot()
    }

    /// Each hand's level as a percentage, for VoiceOver.
    static func levels(_ balance: Double) -> (left: Int, right: Int) {
        (Int(((1 - max(0, balance)) * 100).rounded()), Int(((1 + min(0, balance)) * 100).rounded()))
    }

    private static func storageKey(_ jobID: String) -> String { "hand-balance:\(jobID)" }

    static func load(jobID: String, from defaults: UserDefaults = .standard) -> Double {
        normalized(defaults.double(forKey: storageKey(jobID)))
    }

    static func save(_ balance: Double, jobID: String, to defaults: UserDefaults = .standard) {
        if balance == 0 {
            defaults.removeObject(forKey: storageKey(jobID))
        } else {
            defaults.set(balance, forKey: storageKey(jobID))
        }
    }
}
