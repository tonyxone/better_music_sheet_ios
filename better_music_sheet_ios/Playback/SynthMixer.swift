import Foundation

/// Mixes scheduled notes into audio, one block at a time.
///
/// Single-threaded by design: the audio engine owns one of these on its render
/// thread behind a lock, and the tests drive it directly. Time is absolute
/// frames on the engine's clock, and each voice's waveform phase is computed
/// from elapsed time rather than accumulated, so rendering the same frames
/// always produces the same samples.
nonisolated struct SynthMixer: Sendable {
    private struct Voice: Sendable {
        let startFrame: Int64
        /// First frame after the release tail, when the voice goes silent.
        let silentFrame: Int64
        let frequency: Double
        let envelope: SynthVoice.Envelope
    }

    let sampleRate: Double
    private var notes: [SynthNote] = []
    private var nextNote = 0
    private var voices: [Voice] = []

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        // Reserved up front so starting a voice on the render thread does not
        // allocate at any realistic chord density.
        voices.reserveCapacity(128)
    }

    var activeVoiceCount: Int { voices.count }

    /// Replaces whatever was scheduled. `notes` need not be sorted.
    mutating func load(_ notes: [SynthNote]) {
        self.notes = notes.sorted { $0.startFrame < $1.startFrame }
        nextNote = 0
        voices.removeAll(keepingCapacity: true)
    }

    /// Stops everything at once: nothing scheduled, nothing sounding.
    mutating func silence() {
        load([])
    }

    /// Renders `frameCount` frames beginning at absolute frame `frame`,
    /// overwriting `buffer`.
    mutating func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int, startingAt frame: Int64) {
        buffer.update(repeating: 0, count: frameCount)
        guard frameCount > 0 else { return }
        let blockEnd = frame + Int64(frameCount)

        while nextNote < notes.count, notes[nextNote].startFrame < blockEnd {
            let note = notes[nextNote]
            nextNote += 1
            let duration = Double(note.endFrame - note.startFrame) / sampleRate
            let envelope = SynthVoice.envelope(velocity: note.velocity, duration: duration)
            let silentFrame = note.startFrame
                + Int64(((envelope.releaseStart + SynthVoice.tailSeconds) * sampleRate).rounded(.up))
            // A note whose whole sound ended before this block — because the
            // schedule was loaded late — would only produce a click.
            guard silentFrame > frame else { continue }
            voices.append(Voice(startFrame: note.startFrame, silentFrame: silentFrame,
                                frequency: SynthVoice.frequency(midi: note.midi), envelope: envelope))
        }

        for voice in voices {
            let first = max(0, Int(voice.startFrame - frame))
            let last = min(frameCount, Int(voice.silentFrame - frame))
            guard first < last else { continue }
            for index in first..<last {
                let t = Double(frame + Int64(index) - voice.startFrame) / sampleRate
                let sample = SynthVoice.triangle(phase: t * voice.frequency)
                    * SynthVoice.gain(at: t, envelope: voice.envelope)
                    * SynthVoice.masterGain
                buffer[index] += Float(sample)
            }
        }

        voices.removeAll { $0.silentFrame <= blockEnd }

        // Hard limit rather than wrap: a big enough chord can still sum past
        // full scale, and clipping is far less jarring than overflow noise.
        for index in 0..<frameCount {
            buffer[index] = max(-1, min(1, buffer[index]))
        }
    }
}
