import Foundation

/// Mixes scheduled notes into audio, one block at a time.
///
/// Single-threaded by design: the audio engine owns one of these on its render
/// thread behind a lock, and the tests drive it directly. Time is absolute
/// frames on the engine's clock, and each voice's position is computed from
/// elapsed time rather than accumulated, so rendering the same frames always
/// produces the same samples.
///
/// With no sample bank it plays the basic synth; with one, the bank's
/// recordings, shaped as smplr shapes them.
nonisolated struct SynthMixer: Sendable {
    private struct Scheduled: Sendable {
        let note: SynthNote
        /// Resolved when the schedule is loaded, on the main thread, so
        /// starting a voice on the render thread never searches or allocates.
        let strikes: [SampleBank.Strike]
    }

    private struct Voice: Sendable {
        let startFrame: Int64
        /// First frame after the voice's sound has ended.
        let silentFrame: Int64
        let source: Source
        var filter: LowPass?
    }

    private enum Source: Sendable {
        case synth(frequency: Double, envelope: SynthVoice.Envelope)
        case sample(Sampled)
    }

    private struct Sampled: Sendable {
        let recording: Int
        let step: Double
        let gain: Double
        /// When the key is released and the linear fade to silence begins.
        let releaseFrame: Int64
        let releaseFrames: Double
        let loop: ClosedRange<Double>?
        /// The last recording frame that can be interpolated from.
        let lastFrame: Double
    }

    /// The web app's master level for sampled instruments, ahead of its
    /// limiter. The basic synth sets its own.
    static let sampledMasterGain: Double = 0.65

    let sampleRate: Double
    private(set) var bank: SampleBank?
    private var notes: [Scheduled] = []
    private var nextNote = 0
    private var voices: [Voice] = []

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        // Reserved up front so starting a voice on the render thread does not
        // allocate at any realistic chord density.
        voices.reserveCapacity(256)
    }

    var activeVoiceCount: Int { voices.count }

    /// Switches instrument. Nil returns to the basic synth. Whatever was
    /// scheduled is dropped, since it was resolved for the old one.
    mutating func setBank(_ bank: SampleBank?) {
        self.bank = bank
        load([])
    }

    /// Replaces whatever was scheduled. `notes` need not be sorted.
    mutating func load(_ notes: [SynthNote]) {
        let rate = sampleRate
        let bank = bank
        self.notes = notes
            .sorted { $0.startFrame < $1.startFrame }
            .map { note in
                Scheduled(note: note,
                          strikes: bank?.strikes(midi: note.midi, velocity: note.velocity, outputRate: rate) ?? [])
            }
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

        while nextNote < notes.count, notes[nextNote].note.startFrame < blockEnd {
            let scheduled = notes[nextNote]
            nextNote += 1
            if let bank {
                for strike in scheduled.strikes {
                    startSample(scheduled.note, strike: strike, in: bank, blockStart: frame)
                }
            } else {
                startSynth(scheduled.note, blockStart: frame)
            }
        }

        for index in voices.indices {
            let voice = voices[index]
            let first = max(0, Int(voice.startFrame - frame))
            let last = min(frameCount, Int(voice.silentFrame - frame))
            guard first < last else { continue }

            switch voice.source {
            case .synth(let frequency, let envelope):
                for offset in first..<last {
                    let t = Double(frame + Int64(offset) - voice.startFrame) / sampleRate
                    let sample = SynthVoice.triangle(phase: t * frequency)
                        * SynthVoice.gain(at: t, envelope: envelope)
                        * SynthVoice.masterGain
                    buffer[offset] += Float(sample)
                }

            case .sample(let sampled):
                guard let bank else { continue }
                var filter = voice.filter
                bank.recordings[sampled.recording].frames.withUnsafeBufferPointer { recording in
                    for offset in first..<last {
                        let absolute = frame + Int64(offset)
                        var position = Double(absolute - voice.startFrame) * sampled.step
                        if let loop = sampled.loop, position >= loop.upperBound {
                            position = loop.lowerBound
                                + (position - loop.lowerBound).truncatingRemainder(dividingBy: loop.upperBound - loop.lowerBound)
                        }
                        guard position < sampled.lastFrame else { break }

                        let whole = Int(position)
                        let fraction = position - Double(whole)
                        let a = Double(recording[whole])
                        let b = Double(recording[whole + 1])
                        var sample = (a + (b - a) * fraction) / 32_768

                        // smplr's release: a linear ramp from full level to
                        // silence over the release time.
                        if absolute >= sampled.releaseFrame {
                            sample *= max(0, 1 - Double(absolute - sampled.releaseFrame) / sampled.releaseFrames)
                        }
                        sample *= sampled.gain * Self.sampledMasterGain
                        if filter != nil { sample = filter!.process(sample) }
                        buffer[offset] += Float(sample)
                    }
                }
                voices[index].filter = filter
            }
        }

        voices.removeAll { $0.silentFrame <= blockEnd }

        if bank != nil {
            // The web app ends its sampled chain in a limiter; a soft knee does
            // the same job without a compressor's state.
            for index in 0..<frameCount {
                buffer[index] = Self.softLimit(buffer[index])
            }
        } else {
            // Hard limit rather than wrap: a big enough chord can still sum past
            // full scale, and clipping is far less jarring than overflow noise.
            for index in 0..<frameCount {
                buffer[index] = max(-1, min(1, buffer[index]))
            }
        }
    }

    private mutating func startSynth(_ note: SynthNote, blockStart frame: Int64) {
        let duration = Double(note.endFrame - note.startFrame) / sampleRate
        let envelope = SynthVoice.envelope(velocity: note.velocity, duration: duration)
        let silentFrame = note.startFrame
            + Int64(((envelope.releaseStart + SynthVoice.tailSeconds) * sampleRate).rounded(.up))
        // A note whose whole sound ended before this block — because the
        // schedule was loaded late — would only produce a click.
        guard silentFrame > frame else { return }
        voices.append(Voice(startFrame: note.startFrame, silentFrame: silentFrame,
                            source: .synth(frequency: SynthVoice.frequency(midi: note.midi), envelope: envelope)))
    }

    private mutating func startSample(_ note: SynthNote, strike: SampleBank.Strike,
                                      in bank: SampleBank, blockStart frame: Int64) {
        let length = bank.recordings[strike.recording].frames.count
        guard length > 1, strike.step > 0 else { return }
        let lastFrame = Double(length - 1)
        let releaseFrames = max(1, strike.ampRelease * sampleRate)

        var silentFrame = note.endFrame + Int64(releaseFrames.rounded(.up))
        // A loop only helps if it lies inside the recording.
        let loop = strike.loop.flatMap { $0.upperBound <= lastFrame && $0.upperBound > $0.lowerBound ? $0 : nil }
        if loop == nil {
            silentFrame = min(silentFrame, note.startFrame + Int64((lastFrame / strike.step).rounded(.up)))
        }
        guard silentFrame > frame else { return }

        voices.append(Voice(
            startFrame: note.startFrame,
            silentFrame: silentFrame,
            source: .sample(Sampled(recording: strike.recording, step: strike.step, gain: strike.gain,
                                    releaseFrame: note.endFrame, releaseFrames: releaseFrames,
                                    loop: loop, lastFrame: lastFrame)),
            filter: strike.cutoffHz.map { LowPass(cutoffHz: $0, sampleRate: sampleRate) }
        ))
    }

    /// Unity below half scale, then an ever-flattening curve that never
    /// quite reaches full scale.
    static func softLimit(_ x: Float) -> Float {
        let threshold: Float = 0.5
        let magnitude = abs(x)
        guard magnitude > threshold else { return x }
        let limited = threshold + (1 - threshold) * tanh((magnitude - threshold) / (1 - threshold))
        return x < 0 ? -limited : limited
    }
}

/// A Web Audio `BiquadFilterNode` lowpass at its default Q, for the grand
/// piano's softest layer, which smplr darkens this way.
nonisolated struct LowPass: Sendable {
    private let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(cutoffHz: Double, sampleRate: Double, qDecibels: Double = 1) {
        let w0 = 2 * Double.pi * min(cutoffHz, sampleRate * 0.49) / sampleRate
        let alpha = sin(w0) / (2 * pow(10, qDecibels / 20))
        let cosine = cos(w0)
        let a0 = 1 + alpha
        b0 = (1 - cosine) / 2 / a0
        b1 = (1 - cosine) / a0
        b2 = b0
        a1 = -2 * cosine / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}
