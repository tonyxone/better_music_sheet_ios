import Foundation

/// Piecewise integration and inversion of the score's tempo map, so audio,
/// seeking and the visuals all run off one clock.
///
/// Ported from the web app's app/play/tempo.ts. Beats are quarter-note units
/// throughout; `beatAt`/`secondsAt` are exact inverses of each other.
nonisolated struct TempoClock: Sendable {
    private struct Segment {
        let beat: Double
        let seconds: Double
        let secondsPerBeat: Double
    }

    /// No matter how the score's own tempo, a BPM override and the speed
    /// control combine, playback never exceeds this. Past it, short notes
    /// round toward zero duration and dense chords overlap into noise
    /// rather than music.
    ///
    /// A static on the type rather than a file-scope constant: the app
    /// target compiles with main-actor-by-default isolation, which would
    /// make a global `let` unreachable from this nonisolated struct.
    private static let maxEffectiveBPM: Double = 300

    private let segments: [Segment]

    /// The speed actually applied, after the ceiling above. Equal to the
    /// requested speed unless a BPM override pushed the combination past it —
    /// exposed so the UI can show what is really happening rather than
    /// echoing back a number that isn't being honoured.
    let rate: Double

    init(timeline: Timeline, speed: Double = 1, baseBPM: Double? = nil) {
        let fallback = timeline.tempoBpmDefault > 0 ? timeline.tempoBpmDefault : 96

        var input = (timeline.tempoMap?.isEmpty == false
                     ? timeline.tempoMap!
                     : [TempoEvent(startBeat: 0, bpm: fallback, beatUnitQuarters: nil)])
            .filter { $0.bpm.isFinite && $0.bpm > 0 && $0.startBeat.isFinite }
            .sorted { $0.startBeat < $1.startBeat }

        if input.isEmpty || input[0].startBeat > 0 {
            input.insert(TempoEvent(startBeat: 0, bpm: fallback, beatUnitQuarters: nil), at: 0)
        }

        let scale = (baseBPM.map { $0 > 0 } ?? false) ? baseBPM! / input[0].bpm : 1

        // Checked against the FASTEST tempo anywhere in the piece, not just
        // the opening one: a score that speeds up partway through would
        // otherwise blow past the ceiling there even with a slow opening.
        //
        // The speed control gives way here, not the BPM override — the
        // override is a number the user explicitly typed, and silently
        // changing it out from under them is worse than capping the more
        // casual "how fast should this go" multiplier.
        let fastestScoreBPM = input.map(\.bpm).max() ?? fallback
        let requestedRate = (speed.isFinite && speed > 0) ? speed : 1
        self.rate = min(requestedRate, Self.maxEffectiveBPM / (fastestScoreBPM * scale))

        var seconds: Double = 0
        var built: [Segment] = []
        built.reserveCapacity(input.count)
        for (i, event) in input.enumerated() {
            if i > 0 {
                let previous = input[i - 1]
                seconds += (event.startBeat - previous.startBeat) * 60 / (previous.bpm * scale * rate)
            }
            built.append(Segment(beat: event.startBeat,
                                 seconds: seconds,
                                 secondsPerBeat: 60 / (event.bpm * scale * rate)))
        }
        self.segments = built
    }

    /// Extrapolates before beat 0, which is what makes the count-in work.
    func seconds(atBeat beat: Double) -> Double {
        var segment = segments[0]
        for candidate in segments {
            if candidate.beat > beat { break }
            segment = candidate
        }
        return segment.seconds + (beat - segment.beat) * segment.secondsPerBeat
    }

    func beat(atSeconds seconds: Double) -> Double {
        var segment = segments[0]
        for candidate in segments {
            if candidate.seconds > seconds { break }
            segment = candidate
        }
        return segment.beat + (seconds - segment.seconds) / segment.secondsPerBeat
    }
}

/// What the tempo field shows and accepts. The audio clock always works in
/// quarter beats, but a score in 6/8 marked "dotted quarter = 60" should say
/// 60, not 90 — so the display divides by the score's own beat unit and
/// multiplies back on the way in.
nonisolated struct TempoControl: Sendable {
    let bpm: Double
    let unit: String
    private let quarters: Double

    init(timeline: Timeline, quarterBPM: Double? = nil) {
        let opening = timeline.tempoMap?.first
        let unitQuarters = opening?.beatUnitQuarters
        let quarters = (unitQuarters?.isFinite == true && (unitQuarters ?? 0) > 0) ? unitQuarters! : 1
        self.quarters = quarters

        let names: [Double: String] = [
            0.25: "sixteenth note", 0.5: "eighth note", 0.75: "dotted eighth note",
            1: "quarter note", 1.5: "dotted quarter note", 2: "half note",
            3: "dotted half note", 4: "whole note", 6: "dotted whole note",
        ]
        self.unit = names[quarters] ?? "\(quarters) quarter notes"

        let source = quarterBPM ?? opening?.bpm ?? timeline.tempoBpmDefault
        self.bpm = (source / quarters * 1000).rounded() / 1000
    }

    func toQuarterBPM(_ bpm: Double) -> Double { bpm * quarters }
}
