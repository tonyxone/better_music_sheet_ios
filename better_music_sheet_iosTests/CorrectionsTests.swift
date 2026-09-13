import Foundation
import Testing
@testable import better_music_sheet_ios

private func decode(_ json: String) throws -> Timeline {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Timeline.self, from: Data(json.utf8))
}

/// One 4-beat measure holding a single quarter note, played twice under the
/// same printed identity — enough to show that a correction reaches every
/// occurrence rather than just the one that was edited.
private func repeatedNote() throws -> Timeline {
    try decode("""
    {
      "version": 1, "tempo_bpm_default": 96, "total_beats": 8,
      "measures": [
        {"index": 0, "label": "1", "page": 1, "start_beat": 0, "length_beats": 4,
         "bbox_pt": null, "distinct_midis": [60]},
        {"index": 1, "label": "2", "page": 1, "start_beat": 4, "length_beats": 4,
         "bbox_pt": null, "distinct_midis": [60]}
      ],
      "notes": [
        {"source_id": "n1", "printed_id": "p1", "measure_index": 0, "role": 0,
         "midi": 60, "start_beat": 0, "duration_beats": 1, "is_grace": false, "bbox_pt": null},
        {"source_id": "n2", "printed_id": "p1", "measure_index": 1, "role": 0,
         "midi": 60, "start_beat": 4, "duration_beats": 1, "is_grace": false, "bbox_pt": null}
      ]
    }
    """)
}

struct CorrectionsTests {

    @Test func noCorrectionsChangesNothing() throws {
        let original = try repeatedNote()
        #expect(original.applying([:]) == original)
    }

    @Test func aCorrectionReachesEveryRepeatOfThePrintedNote() throws {
        // Both notes share printed_id "p1": fixing the printed note fixes the
        // reading of it everywhere, which is the whole point of the feature.
        let corrected = try repeatedNote().applying([
            "p1": NoteCorrection(midi: 62, hand: nil, offset: 0, duration: 1)
        ])

        #expect(corrected.notes.map(\.midi) == [62, 62])
        #expect(corrected.notes.allSatisfy { $0.pitchSource == "user" })
    }

    @Test func handChoiceDrivesTheColourRole() throws {
        let left = try repeatedNote().applying([
            "p1": NoteCorrection(midi: 60, hand: .left, offset: 0, duration: 1)
        ])
        #expect(left.notes.allSatisfy { $0.role == 1 && $0.hand == .left })

        let right = try repeatedNote().applying([
            "p1": NoteCorrection(midi: 60, hand: .right, offset: 0, duration: 1)
        ])
        #expect(right.notes.allSatisfy { $0.role == 0 && $0.hand == .right })
    }

    @Test func clearingTheHandFallsBackToTheStaff() throws {
        let timeline = try decode("""
        {"version": 1, "tempo_bpm_default": 96, "total_beats": 4,
         "measures": [{"index": 0, "label": "1", "page": 1, "start_beat": 0,
                       "length_beats": 4, "bbox_pt": null, "distinct_midis": [60]}],
         "notes": [{"source_id": "n1", "printed_id": "p1", "measure_index": 0, "role": 0,
                    "staff": 2, "midi": 60, "start_beat": 0, "duration_beats": 1,
                    "is_grace": false, "bbox_pt": null}]}
        """)

        let corrected = timeline.applying([
            "p1": NoteCorrection(midi: 60, hand: nil, offset: 0, duration: 1)
        ])
        // Staff 2 is the lower staff, which is role 1.
        #expect(corrected.notes[0].role == 1)
        #expect(corrected.notes[0].hand == nil)
    }

    @Test func durationIsClampedToWhatIsLeftInTheMeasure() throws {
        let corrected = try repeatedNote().applying([
            "p1": NoteCorrection(midi: 60, hand: nil, offset: 3, duration: 8)
        ])
        // Offset 3 in a 4-beat measure leaves exactly one beat.
        #expect(corrected.notes[0].durationBeats == 1)
        #expect(corrected.notes[0].startBeat == 3)
    }

    @Test func anOffsetPastTheMeasureIsRejected() throws {
        let corrected = try repeatedNote().applying([
            "p1": NoteCorrection(midi: 62, hand: nil, offset: 4, duration: 1)
        ])
        #expect(corrected.notes.map(\.midi) == [60, 60])
    }

    @Test func invalidCorrectionsAreIgnored() throws {
        for bad in [
            NoteCorrection(midi: 12, hand: nil, offset: 0, duration: 1),      // below A0
            NoteCorrection(midi: 200, hand: nil, offset: 0, duration: 1),     // above C8
            NoteCorrection(midi: 60, hand: nil, offset: -1, duration: 1),     // negative offset
            NoteCorrection(midi: 60, hand: nil, offset: 0, duration: 0),      // zero length
            NoteCorrection(midi: 60, hand: nil, offset: 0, duration: 999),    // absurd length
        ] {
            let corrected = try repeatedNote().applying(["p1": bad])
            #expect(corrected.notes.allSatisfy { $0.pitchSource != "user" },
                    "correction \(bad) should have been rejected")
        }
    }

    @Test func articulationSurvivesARetiming() throws {
        // A note written as 2 beats but held for 1 is staccato; re-timing it
        // to 4 beats should keep it staccato, not make it legato.
        let timeline = try decode("""
        {"version": 1, "tempo_bpm_default": 96, "total_beats": 4,
         "measures": [{"index": 0, "label": "1", "page": 1, "start_beat": 0,
                       "length_beats": 4, "bbox_pt": null, "distinct_midis": [60]}],
         "notes": [{"source_id": "n1", "printed_id": "p1", "measure_index": 0, "role": 0,
                    "midi": 60, "start_beat": 0, "duration_beats": 2, "key_duration_beats": 1,
                    "is_grace": false, "bbox_pt": null}]}
        """)

        let corrected = timeline.applying([
            "p1": NoteCorrection(midi: 60, hand: nil, offset: 0, duration: 4)
        ])
        #expect(corrected.notes[0].durationBeats == 4)
        #expect(corrected.notes[0].keyDurationBeats == 2)  // the 0.5 gate ratio is preserved
    }

    @Test func notesAreReorderedAfterRetiming() throws {
        let timeline = try decode("""
        {"version": 1, "tempo_bpm_default": 96, "total_beats": 4,
         "measures": [{"index": 0, "label": "1", "page": 1, "start_beat": 0,
                       "length_beats": 4, "bbox_pt": null, "distinct_midis": [60, 64]}],
         "notes": [
           {"source_id": "n1", "printed_id": "p1", "measure_index": 0, "role": 0,
            "midi": 60, "start_beat": 0, "duration_beats": 1, "is_grace": false, "bbox_pt": null},
           {"source_id": "n2", "printed_id": "p2", "measure_index": 0, "role": 0,
            "midi": 64, "start_beat": 1, "duration_beats": 1, "is_grace": false, "bbox_pt": null}]}
        """)

        // Push the first note after the second.
        let corrected = timeline.applying([
            "p1": NoteCorrection(midi: 60, hand: nil, offset: 3, duration: 1)
        ])
        #expect(corrected.notes.map(\.sourceID) == ["n2", "n1"])
        #expect(corrected.measures[0].distinctMidis == [60, 64])
    }

    @Test func recomputesTheMeasuresDistinctPitches() throws {
        let corrected = try repeatedNote().applying([
            "p1": NoteCorrection(midi: 67, hand: nil, offset: 0, duration: 1)
        ])
        #expect(corrected.measures[0].distinctMidis == [67])
        #expect(corrected.measures[1].distinctMidis == [67])
    }

    // MARK: - Tied notes and the pedal

    /// Two written segments tied into one sounding event.
    private func tied(audioDuration: Double) throws -> Timeline {
        try decode("""
        {
          "version": 1, "tempo_bpm_default": 96, "total_beats": 8,
          "measures": [{"index": 0, "label": "1", "page": 1, "start_beat": 0,
                        "length_beats": 8, "bbox_pt": null, "distinct_midis": [60]}],
          "notes": [
            {"source_id": "n1", "printed_id": "p1", "measure_index": 0, "role": 0, "midi": 60,
             "start_beat": 0, "duration_beats": 2, "is_grace": false, "bbox_pt": null, "tie_start": true},
            {"source_id": "n2", "printed_id": "p2", "measure_index": 0, "role": 0, "midi": 60,
             "start_beat": 2, "duration_beats": 2, "is_grace": false, "bbox_pt": null, "tie_stop": true}
          ],
          "audio_notes": [
            {"segment_ids": ["n1", "n2"], "source_id": "n1", "midi": 60, "role": 0,
             "start_beat": 0, "duration_beats": \(audioDuration)}
          ]
        }
        """)
    }

    @Test func aPitchFixPropagatesThroughTheWholeTieChain() throws {
        // Only the first segment is corrected, but a tie is one sounding
        // note: the second segment must follow, or the note changes pitch
        // halfway through while it is still ringing.
        let corrected = try tied(audioDuration: 4).applying([
            "p1": NoteCorrection(midi: 62, hand: nil, offset: 0, duration: 2)
        ])

        #expect(corrected.notes.map(\.midi) == [62, 62])
        #expect(corrected.audioNotes?.first?.midi == 62)
    }

    @Test func aShortenedNoteShortensItsSound() throws {
        // No pedal: the sounding event ends exactly where the writing does,
        // so shrinking the note shrinks the sound with it.
        let corrected = try tied(audioDuration: 4).applying([
            "p2": NoteCorrection(midi: 60, hand: nil, offset: 2, duration: 1)
        ])

        #expect(corrected.audioNotes?.first?.durationBeats == 3)
    }

    @Test func aPedalReleaseStaysWhereItWas() throws {
        // The pedal holds this chord to beat 6, well past the written end at
        // beat 4. Shortening the note must not drag the release earlier —
        // the release is an absolute event in the performance.
        let corrected = try tied(audioDuration: 6).applying([
            "p2": NoteCorrection(midi: 60, hand: nil, offset: 2, duration: 1)
        ])

        let audio = try #require(corrected.audioNotes?.first)
        #expect(audio.startBeat == 0)
        #expect(audio.durationBeats == 6)  // still released at beat 6
    }

    @Test func audioFollowsTheNoteWhenItIsMoved() throws {
        let corrected = try tied(audioDuration: 4).applying([
            "p1": NoteCorrection(midi: 60, hand: nil, offset: 1, duration: 2)
        ])

        let audio = try #require(corrected.audioNotes?.first)
        #expect(audio.startBeat == 1)
        #expect(audio.durationBeats == 3)  // from beat 1 to the tied end at 4
    }
}
