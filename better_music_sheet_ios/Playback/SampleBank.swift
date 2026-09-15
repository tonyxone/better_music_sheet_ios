import Foundation

/// A loaded instrument: its preset and the recordings it needs, decoded.
///
/// Immutable once built, so the render thread can read it without locking.
nonisolated final class SampleBank: Sendable {
    struct Recording: Sendable {
        /// Mono, at 16 bits: half the memory of floating point, which matters
        /// with a hundred piano samples loaded at once.
        let frames: [Int16]
        let sampleRate: Double
    }

    /// Everything needed to start a voice for one matched sample.
    struct Strike: Sendable {
        let recording: Int
        /// Recording frames advanced per output frame: the pitch shift and the
        /// sample-rate conversion together.
        let step: Double
        let gain: Double
        let ampRelease: Double
        let cutoffHz: Double?
        /// Loop points in recording frames.
        let loop: ClosedRange<Double>?
    }

    let preset: SamplePreset
    let recordings: [Recording]
    private let indexBySample: [String: Int]

    init(preset: SamplePreset, recordings byName: [String: Recording]) {
        self.preset = preset
        var recordings: [Recording] = []
        var index: [String: Int] = [:]
        for name in preset.sampleNames {
            guard let recording = byName[name] else { continue }
            index[name] = recordings.count
            recordings.append(recording)
        }
        self.recordings = recordings
        self.indexBySample = index
    }

    /// What sounds for one note, resolved as smplr's `resolveParams` and
    /// `Voice` do. A sample that failed to load is skipped, as smplr skips a
    /// missing buffer.
    func strikes(midi: Int, velocity: Double, outputRate: Double) -> [Strike] {
        // MIDI velocity is a whole number from 1 to 127. Recognition can
        // interpolate dynamics to fractional values, and one between two
        // layers would match neither; the web app rounds for the same reason.
        let rounded = Int(max(1, min(127, velocity)).rounded())
        return preset.matches(midi: midi, velocity: rounded).compactMap { region in
            guard let index = indexBySample[region.sample] else { return nil }
            let recording = recordings[index]
            let cents = (Double(midi - (region.pitch ?? midi)) + region.tune) * 100
            return Strike(recording: index,
                          step: pow(2, cents / 1200) * recording.sampleRate / outputRate,
                          gain: SamplePreset.velocityGain(rounded)
                              * SamplePreset.gain(decibels: region.volumeDB)
                              * preset.gain,
                          ampRelease: region.ampRelease ?? preset.ampRelease,
                          cutoffHz: region.cutoffHz,
                          loop: region.loop.map { ($0.lowerBound * recording.sampleRate)...($0.upperBound * recording.sampleRate) })
        }
    }
}
