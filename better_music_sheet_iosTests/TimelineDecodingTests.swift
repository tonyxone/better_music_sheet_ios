import Foundation
import Testing
@testable import better_music_sheet_ios

/// The timeline is the one payload where a decoding slip is invisible until
/// it looks wrong on a real score, so these pin the shape: sparse optional
/// fields, the bbox array, and the held-duration rule that drives which keys
/// light up.
struct TimelineDecodingTests {

    private func decode(_ json: String) throws -> Timeline {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Timeline.self, from: Data(json.utf8))
    }

    /// Only the fields timeline.py always writes. Everything else is optional
    /// and a sheet processed by an older backend simply won't have it.
    private let minimal = """
    {
      "version": 1,
      "tempo_bpm_default": 96,
      "total_beats": 6,
      "measures": [
        {"index": 0, "label": "1", "page": 1, "start_beat": 0, "length_beats": 3,
         "bbox_pt": [72.5, 110.25, 300.0, 190.5], "distinct_midis": [55, 74]},
        {"index": 1, "label": "2", "page": null, "start_beat": 3, "length_beats": 3,
         "bbox_pt": null, "distinct_midis": []}
      ],
      "notes": [
        {"measure_index": 0, "role": 0, "midi": 74, "start_beat": 0,
         "duration_beats": 1, "is_grace": false, "bbox_pt": [80.0, 120.0, 88.0, 128.0]},
        {"measure_index": 0, "role": 1, "midi": 55, "start_beat": 0,
         "duration_beats": 3, "is_grace": false, "bbox_pt": null}
      ]
    }
    """

    @Test func decodesTheMinimalTimeline() throws {
        let timeline = try decode(minimal)

        #expect(timeline.totalBeats == 6)
        #expect(timeline.measures.count == 2)
        #expect(timeline.notes.count == 2)
        // Absent optionals must stay absent rather than defaulting to zero.
        #expect(timeline.audioNotes == nil)
        #expect(timeline.tempoMap == nil)
    }

    @Test func decodesBoundingBoxesInOrder() throws {
        let timeline = try decode(minimal)
        let box = try #require(timeline.measures[0].bboxPt)

        #expect(box.x0 == 72.5)
        #expect(box.y0 == 110.25)
        #expect(box.x1 == 300.0)
        #expect(box.y1 == 190.5)
        #expect(box.width == 227.5)
        #expect(box.height == 80.25)
    }

    @Test func keepsNullGeometryNull() throws {
        let timeline = try decode(minimal)
        // A measure with no page geometry must not be shifted onto another
        // page — it has to stay nil so the player interpolates instead.
        #expect(timeline.measures[1].page == nil)
        #expect(timeline.measures[1].bboxPt == nil)
        #expect(timeline.notes[1].bboxPt == nil)
    }

    @Test func readsRicherFieldsWhenPresent() throws {
        let timeline = try decode("""
        {
          "version": 1, "tempo_bpm_default": 96, "total_beats": 4,
          "tempo_source": "score",
          "tempo_map": [{"start_beat": 0, "bpm": 72, "beat_unit_quarters": 1.5}],
          "stats": {"notes_matched": 214, "notes_unmatched": 3},
          "warnings": ["Time signature in measure 4 was unreadable"],
          "measures": [{"index": 0, "label": "1", "page": 1, "start_beat": 0,
                        "length_beats": 4, "bbox_pt": null, "distinct_midis": [60],
                        "system": 2, "warnings": ["interpolated"]}],
          "notes": [{"source_id": "n1", "printed_id": "p1", "measure_index": 0,
                     "role": 0, "midi": 60, "start_beat": 0, "duration_beats": 2,
                     "key_duration_beats": 1.5, "is_grace": false, "bbox_pt": null,
                     "hand": "left", "staff": 2, "velocity": 88.5, "tie_start": true}],
          "audio_notes": [{"segment_ids": ["n1"], "source_id": "n1", "midi": 60,
                           "role": 0, "start_beat": 0, "duration_beats": 2.5}]
        }
        """)

        #expect(timeline.tempoSource == "score")
        #expect(timeline.tempoMap?.first?.beatUnitQuarters == 1.5)
        #expect(timeline.stats?["notes_matched"] == 214)
        #expect(timeline.warnings?.count == 1)
        #expect(timeline.measures[0].system == 2)

        let note = timeline.notes[0]
        #expect(note.hand == .left)
        #expect(note.staff == 2)
        #expect(note.velocity == 88.5)
        #expect(note.tieStart == true)
        #expect(note.id == "p1")  // printed id wins, so repeats share identity

        // The sounding event outlasts the written one under the pedal.
        #expect(timeline.audioNotes?.first?.durationBeats == 2.5)
        #expect(timeline.audioNotes?.first?.segmentIDs == ["n1"])
    }

    @Test func heldDurationPrefersTheKeyDuration() throws {
        let timeline = try decode("""
        {
          "version": 1, "tempo_bpm_default": 96, "total_beats": 4, "measures": [],
          "notes": [
            {"measure_index": 0, "role": 0, "midi": 60, "start_beat": 0,
             "duration_beats": 2, "key_duration_beats": 1.5, "is_grace": false, "bbox_pt": null},
            {"measure_index": 0, "role": 0, "midi": 62, "start_beat": 0,
             "duration_beats": 0, "is_grace": true, "bbox_pt": null},
            {"measure_index": 0, "role": 0, "midi": 64, "start_beat": 0,
             "duration_beats": 0, "is_grace": false, "bbox_pt": null}
          ]
        }
        """)

        #expect(timeline.notes[0].heldDurationBeats == 1.5)
        #expect(timeline.notes[1].heldDurationBeats == 0.25)  // grace gets a fixed short length
        #expect(timeline.notes[2].heldDurationBeats == 0)
    }

    @Test func findsWhatIsSoundingAtABeat() throws {
        let timeline = try decode(minimal)

        #expect(timeline.notes(atBeat: 0).map(\.midi) == [74, 55])
        // The quarter has ended; the half in the left hand is still held.
        #expect(timeline.notes(atBeat: 1.5).map(\.midi) == [55])
        #expect(timeline.notes(atBeat: 3).isEmpty)
    }

    @Test func mapsBeatsToMeasures() throws {
        let timeline = try decode(minimal)

        #expect(timeline.measureIndex(atBeat: 0) == 0)
        #expect(timeline.measureIndex(atBeat: 2.999) == 0)
        // A measure's end beat belongs to the next measure, not this one.
        #expect(timeline.measureIndex(atBeat: 3) == 1)
        #expect(timeline.measureIndex(atBeat: 6) == nil)
    }

    @Test func readsEventValuesOfEitherType() throws {
        let timeline = try decode("""
        {
          "version": 1, "tempo_bpm_default": 96, "total_beats": 4,
          "measures": [], "notes": [],
          "events": [
            {"kind": "dynamic", "start_beat": 0, "value": "mf", "part": 0, "staff": 1},
            {"kind": "pedal", "start_beat": 2, "value": 1, "part": 0, "staff": 2}
          ]
        }
        """)

        #expect(timeline.events?.count == 2)
        #expect(timeline.events?[0].value == "mf")
        #expect(timeline.events?[1].kind == "pedal")
    }
}
