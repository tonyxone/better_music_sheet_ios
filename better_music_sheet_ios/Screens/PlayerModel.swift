import CoreGraphics
import Foundation

/// Plays a sheet, and reports where in the music playback is: for the measure
/// highlight and playhead over the page, the falling notes, and the keys lit
/// on the keyboard.
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

    static let speedRange: ClosedRange<Double> = 0.1...2
    static let fullKeyRange = KeyboardLayout().fullRange

    private(set) var availability: Availability = .unloaded
    private(set) var isPlaying = false
    /// Current position in beats.
    private(set) var beat: Double = 0
    private(set) var highlightedMeasure: TimelineMeasure?
    private(set) var playhead: PlayheadOnset?
    /// Keys held right now, by MIDI note, valued by role: 0 right hand, 1 left.
    private(set) var litKeys: [Int: Int] = [:]
    /// The keys this piece uses, rounded out to whole octaves.
    private(set) var pieceKeyRange = KeyboardLayout().fullRange
    private(set) var timeline: Timeline?

    var showKeyNames = false
    private(set) var isMuted = false
    /// The speed multiplier the user asked for.
    private(set) var speed: Double = 1
    /// A tempo override in quarter notes per minute, or nil for the score's own.
    private(set) var baseBPM: Double?
    /// Whether anything has been played or stepped yet. Before that the
    /// falling notes stay empty, rather than showing the opening bars already
    /// sitting motionless at the keys.
    private(set) var hasStarted = false

    private var geometry: SheetGeometry?
    private var engine: SynthEngine?
    private var clock: TempoClock?
    /// Every distinct onset, in order: the stops the step buttons walk between.
    private var onsetBeats: [Double] = []
    private var hasStepped = false

    private var originFrame: Int64 = 0
    private var windowStart: Double = 0
    private var windowEnd: Double = 0
    private var windowSeconds: Double = 0
    private var startSeconds: Double = 0
    private var ticker: Task<Void, Never>?

    private let jobID: String
    private let files: SheetFiles
    private static let frameInterval: Duration = .milliseconds(33)
    private static let keyboardLayout = KeyboardLayout()

    init(jobID: String, files: SheetFiles = SheetFiles()) {
        self.jobID = jobID
        self.files = files
    }

    var totalBeats: Double { timeline?.totalBeats ?? 0 }

    var measureLabel: String? {
        highlightedMeasure.map { "Measure \($0.label)" }
    }

    /// Measures that actually take time: the denominator of the position.
    var playableMeasureCount: Int {
        timeline?.measures.filter { $0.lengthBeats > 0 }.count ?? 0
    }

    /// "Measure 12 · 14 / 36" — the printed label, then the performed
    /// position. Repeats make the two differ, which is useful to see.
    var positionLabel: String? {
        guard let timeline, let first = timeline.measures.first else { return nil }
        let index = timeline.measureIndex(atBeat: beat) ?? first.index
        guard let measure = timeline.measure(withIndex: index) else { return nil }
        let count = playableMeasureCount
        return "Measure \(measure.label) · \(min(index + 1, count)) / \(count)"
    }

    /// Whether the opening tempo was read from the score rather than assumed.
    var tempoFromScore: Bool {
        timeline?.tempoSource == "score"
    }

    /// What the speed control actually achieves after the tempo ceiling —
    /// lower than `speed` when a tempo override leaves no headroom for it.
    var effectiveSpeed: Double {
        guard let timeline else { return speed }
        return TempoClock(timeline: timeline, speed: speed, baseBPM: baseBPM).rate
    }

    /// The tempo as the score writes it, in the score's own beat unit.
    var tempoControl: TempoControl? {
        timeline.map { TempoControl(timeline: $0, quarterBPM: baseBPM) }
    }

    func load() async {
        switch availability {
        case .loading, .ready: return
        case .unloaded, .unavailable: break
        }
        availability = .loading
        do {
            var loaded = try await files.timeline(jobID: jobID)
            // Sorted once here: the falling notes binary-search them on every
            // frame, and nothing else depends on the order they arrived in.
            loaded.notes.sort { $0.startBeat < $1.startBeat }
            timeline = loaded
            geometry = SheetGeometry(timeline: loaded)
            onsetBeats = Array(Set(loaded.notes.map(\.startBeat))).sorted()
            pieceKeyRange = Self.keyboardLayout.range(covering: loaded.notes.map(\.midi))
            availability = loaded.notes.isEmpty
                ? .unavailable("No notes were recognized for playback.")
                : .ready
        } catch {
            availability = .unavailable("Playback isn't available for this sheet.")
        }
    }

    // MARK: - Transport

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

        let clock = TempoClock(timeline: timeline, speed: speed, baseBPM: baseBPM)
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
        hasStarted = true
        startTicker()
    }

    func pause() {
        guard isPlaying else { return }
        engine?.silence()
        isPlaying = false
        ticker?.cancel()
        ticker = nil
        // Leave the page and keyboard showing exactly where it stopped.
        show(beat: beat)
    }

    /// Stops and forgets the position — used when leaving the screen.
    func stop() {
        if isPlaying {
            engine?.silence()
            isPlaying = false
            ticker?.cancel()
            ticker = nil
        }
        beat = 0
        hasStepped = false
        hasStarted = false
        publish(measure: nil, playhead: nil, keys: [:])
    }

    /// Moves to `target` beats. While playing, playback carries on from there;
    /// while paused, the page and keyboard show what sounds at that moment.
    func seek(to target: Double) {
        guard timeline != nil else { return }
        let clamped = min(totalBeats, max(0, target))
        if isPlaying {
            play(from: clamped)
        } else {
            beat = clamped
            show(beat: clamped)
        }
    }

    /// Moves one onset and stops there, sounding only what is struck at it —
    /// for walking through a passage a note at a time.
    func step(_ direction: Int) {
        guard let timeline, let first = onsetBeats.first else { return }
        if isPlaying { pause() }

        let next: Double
        if direction > 0 {
            // The first press lands on the opening onset rather than past it,
            // and stepping beyond the last onset wraps to the start, so the
            // button never goes dead.
            if !hasStepped, beat <= first + 1e-6 {
                next = first
            } else {
                next = onsetBeats.first { $0 > beat + 1e-6 } ?? first
            }
        } else {
            // Strictly before the current position, so stopping part-way
            // through a note steps back to the onset you are inside. Clamps at
            // the start rather than wrapping: back at the top is a mis-tap far
            // more often than a request for the last bar.
            next = onsetBeats.last { $0 < beat - 1e-6 } ?? first
        }
        hasStepped = true
        hasStarted = true
        seek(to: next)
        sound(struckAt: next, in: timeline)
    }

    func setSpeed(_ value: Double) {
        speed = min(Self.speedRange.upperBound, max(Self.speedRange.lowerBound, value))
        if isPlaying { play(from: beat) }
    }

    /// `bpm` is in the score's own beat unit, as the tempo field shows it; nil
    /// returns to the score's own tempo.
    func setTempo(_ bpm: Double?) {
        if let bpm, bpm > 0, let control = tempoControl {
            baseBPM = control.toQuarterBPM(bpm)
        } else {
            baseBPM = nil
        }
        if isPlaying { play(from: beat) }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        engine?.setMuted(muted)
    }

    /// A tap on the page, in the page's own top-down point space.
    func handleTap(at point: CGPoint, page: Int) {
        guard let index = geometry?.measureIndex(at: point, page: page,
                                                 playingIndex: highlightedMeasure?.index,
                                                 beat: beat) else { return }
        play(fromMeasure: index)
    }

    // MARK: - Sound

    private func startEngineIfNeeded() -> SynthEngine? {
        if let engine { return engine }
        do {
            let started = try SynthEngine()
            started.setMuted(isMuted)
            engine = started
            return started
        } catch {
            availability = .unavailable("Couldn't start audio. \(error.localizedDescription)")
            return nil
        }
    }

    /// Only what is struck at this onset sounds; notes still ringing from an
    /// earlier one stay lit on the keyboard but are not re-hammered.
    private func sound(struckAt position: Double, in timeline: Timeline) {
        guard let engine = startEngineIfNeeded() else { return }
        let clock = TempoClock(timeline: timeline, speed: speed, baseBPM: baseBPM)
        let rate = engine.sampleRate
        let at = engine.currentFrame + Int64((0.02 * rate).rounded())

        let struck = timeline.notes.filter { $0.attack != false && abs($0.startBeat - position) < 1e-6 }
        // Replaces whatever was scheduled, so stepping quickly never piles
        // voices up.
        engine.schedule(struck.map { note in
            let beats = note.keyDurationBeats ?? note.durationBeats
            // Capped: a whole note held for its written length just drones
            // while you read the next one.
            let seconds = beats > 0
                ? min(1.5, clock.seconds(atBeat: note.startBeat + beats) - clock.seconds(atBeat: note.startBeat))
                : PlaybackSchedule.graceSeconds
            return SynthNote(midi: note.midi, velocity: note.velocity ?? 80,
                             startFrame: at,
                             endFrame: at + Int64((max(0.02, seconds) * rate).rounded()))
        })
    }

    // MARK: - Clock

    /// The position for the falling notes, read from the audio clock on every
    /// frame, so they move continuously rather than in the thirty-a-second
    /// steps the rest of the screen updates in. During the count-in it keeps
    /// counting up from below zero, which is what lets the first notes fall
    /// into place instead of appearing already at the keys. Nil before
    /// anything has played.
    func rollBeat() -> Double? {
        if isPlaying, let engine, let clock {
            let heard = engine.currentFrame - engine.outputLatencyFrames
            let elapsed = Double(heard - originFrame) / engine.sampleRate
            return clock.beat(atSeconds: startSeconds + elapsed)
        }
        return hasStarted ? beat : nil
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

    /// Reads the audio clock and moves the highlight, playhead and keys to
    /// match. Timing comes from frames actually rendered, never from this
    /// loop's own cadence, so a late tick can make the picture stutter but
    /// never drift.
    private func tick() {
        guard let engine, let clock else { return }
        let heard = engine.currentFrame - engine.outputLatencyFrames
        let elapsed = Double(heard - originFrame) / engine.sampleRate

        // The window includes trailing rests and every sustained voice.
        guard elapsed < windowSeconds else {
            isPlaying = false
            ticker?.cancel()
            ticker = nil
            beat = windowEnd
            publish(measure: nil, playhead: nil, keys: [:])
            return
        }

        let lead = clock.beat(atSeconds: startSeconds + elapsed)
        beat = min(windowEnd, max(windowStart, lead))
        guard lead >= windowStart else {
            publish(measure: nil, playhead: nil, keys: [:])  // still counting in
            return
        }
        show(beat: lead)
    }

    private func show(beat position: Double) {
        guard let timeline else { return }
        let measure = timeline.measureIndex(atBeat: position).flatMap { timeline.measure(withIndex: $0) }
        publish(measure: measure,
                playhead: geometry?.playhead(atBeat: position),
                keys: Self.roles(of: timeline.notes(atBeat: position)))
    }

    /// A pitch played by both hands at once takes the right hand's colour —
    /// picking one beats blending into a third colour that means neither.
    private static func roles(of notes: [TimelineNote]) -> [Int: Int] {
        var roles: [Int: Int] = [:]
        for note in notes where roles[note.midi] == nil || note.role == 0 {
            roles[note.midi] = note.role
        }
        return roles
    }

    /// Assigns only on change: the page rebuilds its annotations whenever
    /// these are set, and the clock ticks thirty times a second.
    private func publish(measure: TimelineMeasure?, playhead: PlayheadOnset?, keys: [Int: Int]) {
        if highlightedMeasure != measure { highlightedMeasure = measure }
        if self.playhead != playhead { self.playhead = playhead }
        if litKeys != keys { litKeys = keys }
    }
}
