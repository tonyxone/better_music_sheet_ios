import Foundation

/// The falling notes' arithmetic: which notes are in view, where each bar sits,
/// and when a note is being held or has just landed.
///
/// Ported from the web app's app/play/note-roll.tsx, and kept free of drawing
/// so it can be tested.
nonisolated struct NoteRollGeometry: Sendable {
    /// How much music is in view above the keys. The same as playback's
    /// count-in, so the first note starts at the top of the roll and arrives at
    /// the hit line exactly as it is due to sound.
    static let beatsAhead: Double = PlaybackSchedule.leadInBeats
    /// A sliver below the hit line, so a note stays visible for a moment after
    /// it lands instead of vanishing at the instant you need to see it.
    static let beatsBehind = 0.45
    /// Grace notes have no duration; this gives them a bar you can see.
    static let minimumBarBeats = 0.12
    /// How long the brighter strike flash at the hit line lasts.
    static let flashBeats = 0.35
    /// A long note that started well before the window can still reach into
    /// it, so the search backs off by this much rather than testing onsets alone.
    static let lookBackBeats = 8.0

    /// One note's bar. `y` grows downward as a note approaches, so the bottom
    /// edge is the onset and the top is where the note ends.
    struct Bar: Sendable, Hashable {
        let midi: Int
        let role: Int
        let top: Double
        let bottom: Double
    }

    /// A note whose key is held right now.
    struct Highlight: Sendable, Hashable {
        let midi: Int
        let top: Double
        let bottom: Double
        /// The landing flash, 1 at the moment of the strike fading to 0.
        let flash: Double
    }

    struct Frame: Sendable {
        var whiteKeyBars: [Bar] = []
        /// Kept apart because black-key lanes overlap their white neighbours,
        /// exactly as the keys do, so they are drawn in a second pass on top.
        var blackKeyBars: [Bar] = []
        var highlights: [Highlight] = []
    }

    /// Sorted by onset, which the search below relies on.
    let notes: [TimelineNote]

    init(notes: [TimelineNote]) {
        self.notes = notes
    }

    static func pointsPerBeat(height: Double) -> Double {
        height / (beatsAhead + beatsBehind)
    }

    /// Where notes land: just above the bottom edge, directly over the keys.
    static func hitY(height: Double) -> Double {
        height - beatsBehind * pointsPerBeat(height: height)
    }

    /// The index of the first note that could still be on screen. A binary
    /// search, so a 5,000-note piece costs the same per frame as a 50-note one.
    func firstVisibleIndex(windowStart: Double) -> Int {
        var low = 0
        var high = notes.count
        while low < high {
            let mid = (low + high) / 2
            if notes[mid].startBeat < windowStart - Self.lookBackBeats {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    func frame(atBeat beat: Double, height: Double) -> Frame {
        var frame = Frame()
        guard height > 0 else { return frame }
        let perBeat = Self.pointsPerBeat(height: height)
        let hit = Self.hitY(height: height)
        let windowStart = beat - Self.beatsBehind
        let windowEnd = beat + Self.beatsAhead

        for index in firstVisibleIndex(windowStart: windowStart)..<notes.count {
            let note = notes[index]
            if note.startBeat > windowEnd { break }

            let written = note.isGrace || note.durationBeats <= 0 ? 0 : note.durationBeats
            let beats = max(Self.minimumBarBeats, written)
            if note.startBeat + beats < windowStart { continue }

            let bottom = hit + (beat - note.startBeat) * perBeat
            let top = bottom - beats * perBeat
            if top > height || bottom < 0 { continue }

            let bar = Bar(midi: note.midi, role: note.role, top: top, bottom: bottom)
            if KeyboardLayout.isBlack(note.midi) {
                frame.blackKeyBars.append(bar)
            } else {
                frame.whiteKeyBars.append(bar)
            }

            // The overlay follows the key actually being held, not the written
            // length, so a staccato note stops lighting when its key comes up.
            let since = beat - note.startBeat
            let held = max(Self.minimumBarBeats, note.keyDurationBeats ?? written)
            if since >= 0, since < held {
                frame.highlights.append(Highlight(
                    midi: note.midi, top: top, bottom: bottom,
                    flash: since < Self.flashBeats ? 1 - since / Self.flashBeats : 0))
            }
        }
        return frame
    }
}
