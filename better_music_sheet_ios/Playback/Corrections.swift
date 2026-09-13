import Foundation

/// A user's fix for one printed note: what it really is, which hand plays it,
/// where in its measure it falls and how long it lasts.
///
/// Corrections address a PRINTED note, so every repeated occurrence of it
/// changes — that is the point. Ported from the web app's lib/corrections.ts.
nonisolated struct NoteCorrection: Codable, Sendable, Hashable {
    var midi: Int
    /// Nil means "keep following the staff colour".
    var hand: Hand?
    /// Beats from the start of its own measure.
    var offset: Double
    var duration: Double

    /// The same bounds the web app enforces: a real piano key, a non-negative
    /// offset, and a duration that is positive and not absurd.
    var isValid: Bool {
        (21...108).contains(midi)
            && offset.isFinite && offset >= 0
            && duration.isFinite && duration > 0 && duration <= 128
    }
}

typealias Corrections = [String: NoteCorrection]

extension Timeline {
    /// Apply saved corrections, returning a new timeline.
    ///
    /// Two behaviours here are easy to lose and hard to notice afterwards:
    /// a pitch fix on one segment of a tie propagates through the whole
    /// sounding chain, and a pedal release is an absolute moment in time
    /// rather than a tail that follows the note it was attached to.
    func applying(_ corrections: Corrections) -> Timeline {
        guard !corrections.isEmpty else { return self }

        var corrected: [TimelineNote] = notes.map { note in
            let key = note.printedID ?? note.sourceID ?? ""
            guard let correction = corrections[key], correction.isValid else { return note }
            // Measures are addressed by position, matching the web app.
            guard note.measureIndex >= 0, note.measureIndex < measures.count else { return note }
            let measure = measures[note.measureIndex]
            guard correction.offset < measure.lengthBeats else { return note }

            var edited = note
            let duration = min(correction.duration, measure.lengthBeats - correction.offset)
            // Preserve how much of its written length the note was actually
            // held for, so an edit doesn't turn a staccato into a legato.
            let gateRatio = note.durationBeats > 0
                ? (note.keyDurationBeats ?? note.durationBeats) / note.durationBeats
                : 1

            edited.midi = correction.midi
            edited.hand = correction.hand
            switch correction.hand {
            case .right: edited.role = 0
            case .left: edited.role = 1
            case nil: edited.role = max(0, (note.staff ?? note.role + 1) - 1)
            }
            edited.startBeat = measure.startBeat + correction.offset
            edited.durationBeats = duration
            edited.keyDurationBeats = duration * gateRatio
            edited.pitchSource = "user"
            return edited
        }

        var indexBySourceID: [String: Int] = [:]
        for (i, note) in corrected.enumerated() {
            if let id = note.sourceID { indexBySourceID[id] = i }
        }
        let originalsBySourceID = Dictionary(
            notes.compactMap { note in note.sourceID.map { ($0, note) } },
            uniquingKeysWith: { first, _ in first }
        )

        let correctedAudio: [AudioNote]? = audioNotes?.map { audio in
            let segmentIDs = audio.segmentIDs ?? [audio.sourceID].compactMap { $0 }
            let positions = segmentIDs.compactMap { indexBySourceID[$0] }
            guard !positions.isEmpty else { return audio }

            // A pitch fix anywhere in a tie chain governs the whole sounding
            // event, so push it back into every written segment as well.
            if let editedPitch = positions.first(where: { corrected[$0].pitchSource == "user" })
                .map({ corrected[$0].midi }) {
                for position in positions { corrected[position].midi = editedPitch }
            }

            let first = corrected[positions[0]]
            let oldEnd = positions.compactMap { position -> Double? in
                guard let id = corrected[position].sourceID,
                      let original = originalsBySourceID[id] else { return nil }
                return original.startBeat + (original.keyDurationBeats ?? original.durationBeats)
            }.max() ?? first.startBeat
            let newEnd = positions.map { position -> Double in
                let note = corrected[position]
                return note.startBeat + (note.keyDurationBeats ?? note.durationBeats)
            }.max() ?? first.startBeat

            // The pedal holds a note past its written end. That release is a
            // fixed moment, so it must not slide when the note is re-timed.
            let audioEnd = audio.startBeat + audio.durationBeats
            let pedalRelease = audioEnd > oldEnd + 1e-8 ? audioEnd : 0

            var edited = audio
            edited.midi = first.midi
            edited.role = first.role
            edited.startBeat = first.startBeat
            edited.durationBeats = max(newEnd, pedalRelease) - first.startBeat
            return edited
        }

        corrected.sort { left, right in
            left.startBeat != right.startBeat ? left.startBeat < right.startBeat : left.midi < right.midi
        }

        var result = self
        result.notes = corrected
        result.audioNotes = correctedAudio
        result.measures = measures.map { measure in
            var updated = measure
            updated.distinctMidis = Set(corrected.filter { $0.measureIndex == measure.index }.map(\.midi)).sorted()
            return updated
        }
        return result
    }
}
