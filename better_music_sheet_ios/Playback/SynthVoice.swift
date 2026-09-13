import Foundation

/// One note for the synthesizer, placed on the audio engine's sample clock.
nonisolated struct SynthNote: Sendable, Hashable {
    let midi: Int
    let velocity: Double
    /// Absolute frames on the engine's clock: when the key goes down, and when
    /// it is released. The sound carries on briefly past `endFrame` while the
    /// release fades.
    let startFrame: Int64
    let endFrame: Int64
}

/// The sound of one note: a triangle wave under a piano-like envelope.
///
/// Ported from the web app's app/play/basic-synth.ts. Deliberately synthesized
/// rather than sampled — the point of playback here is hearing which keys
/// sound, and this needs no bundled instrument. The envelope reproduces that
/// file's Web Audio automation curve so the two apps sound alike.
nonisolated enum SynthVoice {
    /// Master level. A dense chord sums many voices, and full gain clips.
    static let masterGain: Double = 0.22
    /// Time constant of the release fade is a third of this.
    static let releaseSeconds: Double = 0.08
    /// After this long the release is inaudible and the voice can be dropped;
    /// the web app stops its oscillator at the same point.
    static var tailSeconds: Double { releaseSeconds * 3 }

    /// Web Audio's exponential ramps cannot reach zero, so the curve starts
    /// and ends here instead.
    private static let floorLevel = 0.0001

    struct Envelope: Sendable, Hashable {
        let peak: Double
        let sustain: Double
        let attack: Double
        let decay: Double
        /// When the release begins, in seconds from the note's start.
        let releaseStart: Double
    }

    static func frequency(midi: Int) -> Double {
        440 * pow(2, Double(midi - 69) / 12)
    }

    static func envelope(velocity: Double, duration: Double) -> Envelope {
        let clamped = max(1, min(127, velocity))
        let peak = 0.9 * pow(clamped / 100, 1.5)
        let attack = min(0.006, max(0.001, duration / 3))
        // A real piano decays continuously rather than holding at its peak,
        // which is most of what makes this read as a piano at all.
        let decay = max(0.001, min(0.35, (duration - attack) * 0.5))
        return Envelope(peak: peak, sustain: peak * 0.31, attack: attack, decay: decay,
                        // Even the shortest grace note finishes its attack
                        // before releasing, or it would be a click.
                        releaseStart: max(attack + 0.02, duration))
    }

    /// Amplitude `t` seconds after the note starts.
    static func gain(at t: Double, envelope e: Envelope) -> Double {
        guard t >= 0 else { return 0 }
        if t < e.releaseStart { return held(at: t, envelope: e) }
        let sinceRelease = t - e.releaseStart
        guard sinceRelease < tailSeconds else { return 0 }
        let from = held(at: e.releaseStart, envelope: e)
        return floorLevel + (from - floorLevel) * exp(-sinceRelease / (releaseSeconds / 3))
    }

    /// The curve before release: a short linear attack, an exponential slide
    /// from the peak to the sustain level, then a hold.
    private static func held(at t: Double, envelope e: Envelope) -> Double {
        if t < e.attack {
            return floorLevel + (e.peak - floorLevel) * (t / e.attack)
        }
        if t < e.attack + e.decay {
            return e.peak * pow(e.sustain / e.peak, (t - e.attack) / e.decay)
        }
        return e.sustain
    }

    /// A triangle wave in -1...1. A sine reads as a dull flute; a triangle has
    /// enough harmonics to sound struck.
    static func triangle(phase: Double) -> Double {
        let p = phase - phase.rounded(.down)
        return p < 0.5 ? 4 * p - 1 : 3 - 4 * p
    }
}
