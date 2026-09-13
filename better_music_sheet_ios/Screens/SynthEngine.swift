import AVFAudio
import Synchronization

/// The part of the synthesizer the audio thread touches.
///
/// Kept apart from `SynthEngine` so the render block can capture it before
/// the engine itself has finished initializing.
nonisolated final class SynthRenderState: @unchecked Sendable {
    /// Guards `mixer`. The render thread only ever *tries* this lock, and plays
    /// one block of silence if the main thread is mid-update, rather than
    /// blocking the audio thread.
    let lock = NSLock()
    var mixer: SynthMixer
    /// Frames rendered since the engine started: the clock that sound, the
    /// highlight and the playhead are all timed against.
    let renderedFrames = Atomic<Int64>(0)
    let muted = Atomic<Bool>(false)

    init(sampleRate: Double) {
        mixer = SynthMixer(sampleRate: sampleRate)
    }

    func render(frameCount: AVAudioFrameCount, into bufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let count = Int(frameCount)
        let start = renderedFrames.load(ordering: .relaxed)
        defer { renderedFrames.store(start + Int64(count), ordering: .relaxed) }

        guard let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return 0 }
        if lock.try() {
            mixer.render(into: first, frameCount: count, startingAt: start)
            lock.unlock()
        } else {
            first.update(repeating: 0, count: count)
        }
        if muted.load(ordering: .relaxed) {
            // Rendered anyway, so voices, timing and the keyboard stay exactly
            // as they would be; only the output is silenced.
            first.update(repeating: 0, count: count)
        }
        for index in 1..<buffers.count {
            buffers[index].mData?.assumingMemoryBound(to: Float.self).update(from: first, count: count)
        }
        return 0
    }
}

/// A small synthesizer on AVAudioEngine.
nonisolated final class SynthEngine: @unchecked Sendable {
    let sampleRate: Double
    /// Sound leaves the device this long after it is rendered. Subtracted from
    /// the visual clock so the highlight moves with what you hear.
    let outputLatencyFrames: Int64

    private let engine: AVAudioEngine
    private let state: SynthRenderState

    init() throws {
        let session = AVAudioSession.sharedInstance()
        // Playback, not ambient: it should sound with the silent switch on,
        // as music apps do.
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let rate = hardwareRate > 0 ? hardwareRate : 48_000
        let state = SynthRenderState(sampleRate: rate)

        self.engine = engine
        self.state = state
        self.sampleRate = rate
        self.outputLatencyFrames = Int64((session.outputLatency * rate).rounded())

        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
            throw SynthEngineError.unsupportedFormat
        }
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            state.render(frameCount: frameCount, into: bufferList)
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        try engine.start()
    }

    var currentFrame: Int64 { state.renderedFrames.load(ordering: .relaxed) }

    func schedule(_ notes: [SynthNote]) {
        restartIfNeeded()
        state.lock.lock()
        state.mixer.load(notes)
        state.lock.unlock()
    }

    func silence() {
        state.lock.lock()
        state.mixer.silence()
        state.lock.unlock()
    }

    func setMuted(_ muted: Bool) {
        state.muted.store(muted, ordering: .relaxed)
    }

    /// The system stops the engine on an interruption — a call, another app
    /// taking the audio session. Without this the next Play would schedule
    /// notes onto a clock that is no longer running.
    private func restartIfNeeded() {
        guard !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
    }

    deinit {
        engine.stop()
    }
}

nonisolated enum SynthEngineError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        "This device's audio output format isn't supported."
    }
}
