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

    /// Where a note's name goes: the middle of the whole held note, tied
    /// pieces and all, falling with it.
    struct NameTag: Sendable, Hashable {
        /// Into `notes`, and so into the name lists.
        let index: Int
        let midi: Int
        let top: Double
        let bottom: Double
    }

    struct Frame: Sendable {
        var whiteKeyBars: [Bar] = []
        /// Kept apart because black-key lanes overlap their white neighbours,
        /// exactly as the keys do, so they are drawn in a second pass on top.
        var blackKeyBars: [Bar] = []
        var highlights: [Highlight] = []
        /// Empty unless names were asked for.
        var names: [NameTag] = []
    }

    /// Every note's name as letters and as jianpu, and where each name's
    /// span ends (see `nameEnds`), in the order of the notes they were made
    /// from.
    struct Names: Sendable {
        let letters: [String]
        let numbers: [String]
        let ends: [Double]

        static let none = Names(letters: [], numbers: [], ends: [])

        /// `notes` sorted by onset.
        static func of(_ notes: [TimelineNote]) -> Names {
            Names(letters: notes.map { Jianpu.name(of: $0, in: .letters) },
                  numbers: notes.map { Jianpu.name(of: $0, in: .numbers) },
                  ends: NoteRollGeometry.nameEnds(notes))
        }

        func list(_ notation: Notation) -> [String] {
            notation == .numbers ? numbers : letters
        }
    }

    /// Sorted by onset, which the search below relies on.
    let notes: [TimelineNote]
    /// From `nameEnds`, when names are drawn.
    let nameEnds: [Double]?

    init(notes: [TimelineNote], nameEnds: [Double]? = nil) {
        self.notes = notes
        self.nameEnds = nameEnds.flatMap { $0.count == notes.count ? $0 : nil }
    }

    /// Where each note's name ends, in beats, for notes sorted by onset: one
    /// name per struck note, spanning its tied continuations — which get -1,
    /// as does a second copy of a note two voices strike together.
    static func nameEnds(_ notes: [TimelineNote]) -> [Double] {
        var ends = [Double](repeating: 0, count: notes.count)
        // Per key, the note whose name the next tied piece would extend.
        var heads: [Int: (index: Int, start: Double, end: Double)] = [:]
        for (i, note) in notes.enumerated() {
            let written = note.isGrace || note.durationBeats <= 0 ? 0 : note.durationBeats
            let end = note.startBeat + max(minimumBarBeats, written)
            if var head = heads[note.midi],
               abs(head.start - note.startBeat) < 1e-6
                || (note.tieStop == true && abs(head.end - note.startBeat) < 1e-6) {
                ends[i] = -1
                if end > head.end {
                    head.end = end
                    ends[head.index] = end
                    heads[note.midi] = head
                }
                continue
            }
            ends[i] = end
            heads[note.midi] = (i, note.startBeat, end)
        }
        return ends
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

            if let nameEnds, nameEnds[index] >= 0, nameEnds[index] >= windowStart {
                let bottom = hit + (beat - note.startBeat) * perBeat
                let top = bottom - (nameEnds[index] - note.startBeat) * perBeat
                if top <= height, bottom >= 0 {
                    frame.names.append(NameTag(index: index, midi: note.midi, top: top, bottom: bottom))
                }
            }

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
