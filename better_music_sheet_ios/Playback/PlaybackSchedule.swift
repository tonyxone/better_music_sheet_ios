import Foundation

/// What sounds when, for one stretch of playback — the decision half of the
/// player, with no audio engine attached so it can be reasoned about and
/// tested on its own.
///
/// Ported from the web app's app/play/playback.ts. Times are seconds measured
/// from the window's own origin, so the caller only has to decide when the
/// origin is on its audio clock.
nonisolated struct PlaybackSchedule: Sendable {

    /// One sounding event, already resolved to wall-clock offsets.
    struct Entry: Sendable, Hashable {
        let midi: Int
        let velocity: Double
        let role: Int
        let start: TimeInterval
        let end: TimeInterval
    }

    /// Shared with the falling-note roll: the opening descent is exactly this
    /// long, so the first note starts at the top of the roll and arrives at
    /// the hit line as it is due to sound.
    static let leadInBeats: Double = 4

    /// A grace note is written with no duration; the player gives it a fixed
    /// short length instead of dropping it.
    static let graceSeconds: TimeInterval = 0.12
    private static let graceBeats = graceSeconds / 0.625

    /// How far ahead of the clock events are handed to the engine, and how
    /// often that happens.
    static let lookaheadSeconds: TimeInterval = 0.1
    static let tickInterval: Duration = .milliseconds(25)

    private static let defaultVelocity: Double = 80
    /// Enough to get the first notes scheduled when starting mid-piece,
    /// without a pause the user reads as lag.
    private static let midPieceLeadSeconds: TimeInterval = 0.06

    let entries: [Entry]
    /// The beat range actually played, after clamping.
    let windowStart: Double
    let windowEnd: Double
    /// Total length, including trailing rests and every sustained voice.
    let windowSeconds: TimeInterval
    /// How long to wait before the origin: a full count-in from the top, or a
    /// short settle when starting part-way through.
    let leadSeconds: TimeInterval

    init(timeline: Timeline,
         clock: TempoClock,
         fromBeat: Double = 0,
         untilBeat: Double? = nil,
         usesPianoPedal: Bool = true) {

        let requestedEnd = untilBeat ?? timeline.totalBeats
        let end = max(0, min(timeline.totalBeats, requestedEnd))
        let from = max(0, fromBeat)
        // Asking to start at or past the end means "play it again", not
        // "play nothing".
        let start = from >= end ? 0 : from

        self.windowStart = start
        self.windowEnd = end

        let startSeconds = clock.seconds(atBeat: start)
        self.windowSeconds = clock.seconds(atBeat: end) - startSeconds

        // Sounding events, which can span several written tie segments or
        // continue under the pedal. Fall back to the written notes for a
        // timeline built before audio events existed.
        var events: [AudioNote] = timeline.audioNotes ?? timeline.notes.map { note in
            AudioNote(segmentIDs: note.sourceID.map { [$0] },
                      sourceID: note.sourceID,
                      midi: note.midi,
                      role: note.role,
                      startBeat: note.startBeat,
                      durationBeats: note.durationBeats > 0 ? note.durationBeats
                                     : (note.isGrace ? Self.graceBeats : 0),
                      velocity: note.velocity)
        }

        // An organ has no sustain pedal: a note lasts exactly as long as it is
        // held, so the pedal tails that piano presets rely on are trimmed off.
        if !usesPianoPedal {
            let written = Dictionary(
                timeline.notes.compactMap { note in note.sourceID.map { ($0, note) } },
                uniquingKeysWith: { first, _ in first }
            )
            events = events.map { event in
                let ids = event.segmentIDs ?? [event.sourceID].compactMap { $0 }
                let segments = ids.compactMap { written[$0] }
                guard !segments.isEmpty else { return event }
                let heldEnd = segments
                    .map { $0.startBeat + ($0.keyDurationBeats ?? $0.durationBeats) }
                    .reduce(event.startBeat) { max($0, $1) }
                var trimmed = event
                trimmed.durationBeats = min(event.durationBeats, heldEnd - event.startBeat)
                return trimmed
            }
        }

        self.entries = events
            .filter { $0.startBeat < end - 1e-9 && $0.startBeat + $0.durationBeats > start + 1e-9 }
            .map { event in
                Entry(midi: event.midi,
                      velocity: event.velocity ?? Self.defaultVelocity,
                      role: event.role,
                      // Clipped to the window at both ends, so a note already
                      // ringing when you seek in starts now rather than in
                      // the past.
                      start: clock.seconds(atBeat: max(event.startBeat, start)) - startSeconds,
                      end: clock.seconds(atBeat: min(event.startBeat + event.durationBeats, end)) - startSeconds)
            }
            .sorted { $0.start < $1.start }

        // A count-in only makes sense from the top; seeking into the middle
        // of a piece should start promptly.
        self.leadSeconds = start <= 1e-9
            ? clock.seconds(atBeat: 0) - clock.seconds(atBeat: -Self.leadInBeats)
            : Self.midPieceLeadSeconds
    }
}
