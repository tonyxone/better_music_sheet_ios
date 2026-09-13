import CoreGraphics
import Foundation

/// Plays a sheet, and reports where in the music playback is for the
/// highlight and playhead drawn over the page.
@MainActor
@Observable
final class PlayerModel {
    enum Availability: Equatable {
        case unloaded
        case loading
        case ready
        /// No playback for this sheet — most often one annotated before
        /// timelines existed.
        case unavailable(String)
    }

    private(set) var availability: Availability = .unloaded
    private(set) var isPlaying = false
    /// Current position in beats, for the progress bar.
    private(set) var beat: Double = 0
    private(set) var highlightedMeasure: TimelineMeasure?
    private(set) var playhead: PlayheadOnset?

    private var timeline: Timeline?
    private var geometry: SheetGeometry?
    private var engine: SynthEngine?
    private var clock: TempoClock?

    private var originFrame: Int64 = 0
    private var windowStart: Double = 0
    private var windowEnd: Double = 0
    private var windowSeconds: Double = 0
    private var startSeconds: Double = 0
    private var ticker: Task<Void, Never>?

    private let jobID: String
    private let files: SheetFiles
    private static let frameInterval: Duration = .milliseconds(33)

    init(jobID: String, files: SheetFiles = SheetFiles()) {
        self.jobID = jobID
        self.files = files
    }

    var totalBeats: Double { timeline?.totalBeats ?? 0 }

    var measureLabel: String? {
        highlightedMeasure.map { "Measure \($0.label)" }
    }

    func load() async {
        switch availability {
        case .loading, .ready: return
        case .unloaded, .unavailable: break
        }
        availability = .loading
        do {
            let loaded = try await files.timeline(jobID: jobID)
            timeline = loaded
            geometry = SheetGeometry(timeline: loaded)
            availability = loaded.notes.isEmpty
                ? .unavailable("No notes were recognized for playback.")
                : .ready
        } catch {
            availability = .unavailable("Playback isn't available for this sheet.")
        }
    }

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            // The schedule restarts from the top when asked to begin at the end.
            play(from: beat)
        }
    }

    func play(fromMeasure index: Int) {
        guard let measure = timeline?.measure(withIndex: index) else { return }
        play(from: measure.startBeat)
    }

    func play(from startBeat: Double) {
        guard let timeline, let engine = startEngineIfNeeded() else { return }

        let clock = TempoClock(timeline: timeline)
        let schedule = PlaybackSchedule(timeline: timeline, clock: clock, fromBeat: startBeat)
        let rate = engine.sampleRate
        let origin = engine.currentFrame + Int64((schedule.leadSeconds * rate).rounded())

        engine.schedule(schedule.entries.map { entry in
            SynthNote(midi: entry.midi, velocity: entry.velocity,
                      startFrame: origin + Int64((entry.start * rate).rounded()),
                      endFrame: origin + Int64((entry.end * rate).rounded()))
        })

        self.clock = clock
        originFrame = origin
        windowStart = schedule.windowStart
        windowEnd = schedule.windowEnd
        windowSeconds = schedule.windowSeconds
        startSeconds = clock.seconds(atBeat: schedule.windowStart)
        beat = schedule.windowStart
        isPlaying = true
        startTicker()
    }

    func pause() {
        guard isPlaying else { return }
        engine?.silence()
        isPlaying = false
        ticker?.cancel()
        ticker = nil
    }

    /// Stops and forgets the position — used when leaving the screen.
    func stop() {
        pause()
        beat = 0
        publish(measure: nil, playhead: nil)
    }

    /// A tap on the page, in the page's own top-down point space.
    func handleTap(at point: CGPoint, page: Int) {
        guard let index = geometry?.measureIndex(at: point, page: page,
                                                 playingIndex: highlightedMeasure?.index,
                                                 beat: beat) else { return }
        play(fromMeasure: index)
    }

    // MARK: - Clock

    private func startEngineIfNeeded() -> SynthEngine? {
        if let engine { return engine }
        do {
            let started = try SynthEngine()
            engine = started
            return started
        } catch {
            availability = .unavailable("Couldn't start audio. \(error.localizedDescription)")
            return nil
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isPlaying else { return }
                self.tick()
                try? await Task.sleep(for: Self.frameInterval)
            }
        }
    }

    /// Reads the audio clock and moves the highlight and playhead to match.
    /// Timing comes from frames actually rendered, never from this loop's own
    /// cadence, so a late tick can make the picture stutter but never drift.
    private func tick() {
        guard let engine, let clock, let timeline else { return }
        let heard = engine.currentFrame - engine.outputLatencyFrames
        let elapsed = Double(heard - originFrame) / engine.sampleRate

        // The window includes trailing rests and every sustained voice.
        guard elapsed < windowSeconds else {
            isPlaying = false
            ticker?.cancel()
            ticker = nil
            beat = windowEnd
            publish(measure: nil, playhead: nil)
            return
        }

        let lead = clock.beat(atSeconds: startSeconds + elapsed)
        beat = min(windowEnd, max(windowStart, lead))
        guard lead >= windowStart else {
            publish(measure: nil, playhead: nil)  // still counting in
            return
        }
        let measure = timeline.measureIndex(atBeat: lead).flatMap { timeline.measure(withIndex: $0) }
        publish(measure: measure, playhead: geometry?.playhead(atBeat: lead))
    }

    /// Assigns only on change: the page rebuilds its annotations whenever
    /// these are set, and the clock ticks thirty times a second.
    private func publish(measure: TimelineMeasure?, playhead: PlayheadOnset?) {
        if highlightedMeasure != measure { highlightedMeasure = measure }
        if self.playhead != playhead { self.playhead = playhead }
    }
}
