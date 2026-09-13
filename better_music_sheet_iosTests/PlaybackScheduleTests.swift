import Foundation
import Testing
@testable import better_music_sheet_ios

private func decode(_ json: String) throws -> Timeline {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Timeline.self, from: Data(json.utf8))
}

/// 120bpm throughout, so one beat is exactly half a second and the arithmetic
/// below stays readable.
private func piece(notes: String, audio: String = "null", total: Double = 8) throws -> Timeline {
    try decode("""
    {
      "version": 1, "tempo_bpm_default": 120, "total_beats": \(total),
      "tempo_map": [{"start_beat": 0, "bpm": 120}],
      "measures": [{"index": 0, "label": "1", "page": 1, "start_beat": 0,
                    "length_beats": \(total), "bbox_pt": null, "distinct_midis": []}],
      "notes": [\(notes)],
      "audio_notes": \(audio)
    }
    """)
}

private func note(_ id: String, midi: Int, beat: Double, duration: Double,
                  keyDuration: String = "null", grace: Bool = false) -> String {
    """
    {"source_id": "\(id)", "measure_index": 0, "role": 0, "midi": \(midi),
     "start_beat": \(beat), "duration_beats": \(duration),
     "key_duration_beats": \(keyDuration), "is_grace": \(grace), "bbox_pt": null}
    """
}

private func schedule(_ timeline: Timeline, from: Double = 0, until: Double? = nil,
                      pedal: Bool = true, speed: Double = 1) -> PlaybackSchedule {
    PlaybackSchedule(timeline: timeline,
                     clock: TempoClock(timeline: timeline, speed: speed),
                     fromBeat: from, untilBeat: until, usesPianoPedal: pedal)
}

struct PlaybackScheduleTests {

    @Test func schedulesTheWholePieceByDefault() throws {
        let built = schedule(try piece(notes: [
            note("a", midi: 60, beat: 0, duration: 1),
            note("b", midi: 62, beat: 1, duration: 1),
        ].joined(separator: ",")))

        #expect(built.windowStart == 0)
        #expect(built.windowEnd == 8)
        #expect(built.windowSeconds == 4)        // 8 beats at 120bpm
        #expect(built.entries.count == 2)
        #expect(built.entries[0].start == 0)
        #expect(built.entries[0].end == 0.5)
        #expect(built.entries[1].start == 0.5)
    }

    @Test func timesAreRelativeToTheWindowNotThePiece() throws {
        // Starting at beat 4, the first note in view must be at zero seconds,
        // not two seconds into an imaginary full playthrough.
        let built = schedule(try piece(notes: note("a", midi: 60, beat: 4, duration: 1)), from: 4)

        #expect(built.entries.count == 1)
        #expect(built.entries[0].start == 0)
        #expect(built.entries[0].end == 0.5)
    }

    @Test func notesOutsideTheWindowAreDropped() throws {
        let built = schedule(try piece(notes: [
            note("a", midi: 60, beat: 0, duration: 1),
            note("b", midi: 62, beat: 6, duration: 1),
        ].joined(separator: ",")), from: 0, until: 4)

        #expect(built.entries.map(\.midi) == [60])
        #expect(built.windowEnd == 4)
    }

    @Test func aNoteAlreadyRingingIsClippedRatherThanStartedInThePast() throws {
        // Seeking into the middle of a held note should start it now; without
        // the clamp its start time would be negative and it would be skipped.
        let built = schedule(try piece(notes: note("a", midi: 60, beat: 0, duration: 4)), from: 2)

        #expect(built.entries.count == 1)
        #expect(built.entries[0].start == 0)
        #expect(built.entries[0].end == 1)   // the remaining two beats
    }

    @Test func aNoteRunningPastTheWindowIsClippedAtTheEnd() throws {
        let built = schedule(try piece(notes: note("a", midi: 60, beat: 0, duration: 8)),
                             from: 0, until: 2)
        #expect(built.entries[0].end == 1)   // two beats, not eight
    }

    @Test func startingAtOrPastTheEndRestartsFromTheTop() throws {
        // "Play" at the end of a piece means play it again.
        let built = schedule(try piece(notes: note("a", midi: 60, beat: 0, duration: 1)), from: 8)

        #expect(built.windowStart == 0)
        #expect(built.entries.count == 1)
    }

    @Test func entriesComeOutInPlayingOrder() throws {
        let built = schedule(try piece(notes: [
            note("c", midi: 64, beat: 3, duration: 1),
            note("a", midi: 60, beat: 0, duration: 1),
            note("b", midi: 62, beat: 1, duration: 1),
        ].joined(separator: ",")))

        #expect(built.entries.map(\.midi) == [60, 62, 64])
    }

    // MARK: - Sounding events vs written notes

    @Test func soundingEventsWinOverWrittenNotes() throws {
        // Two tied segments are one sounding note; scheduling the written
        // pair would re-strike the key halfway through.
        let built = schedule(try piece(notes: [
            note("a", midi: 60, beat: 0, duration: 2),
            note("b", midi: 60, beat: 2, duration: 2),
        ].joined(separator: ","), audio: """
        [{"segment_ids": ["a", "b"], "source_id": "a", "midi": 60, "role": 0,
          "start_beat": 0, "duration_beats": 4}]
        """))

        #expect(built.entries.count == 1)
        #expect(built.entries[0].end == 2)   // four beats at 120bpm
    }

    @Test func fallsBackToWrittenNotesWhenThereAreNoAudioEvents() throws {
        // Sheets processed before audio events existed must still play.
        let built = schedule(try piece(notes: note("a", midi: 60, beat: 0, duration: 2)))
        #expect(built.entries.count == 1)
        #expect(built.entries[0].end == 1)
    }

    @Test func graceNotesGetAFixedShortLengthInsteadOfBeingDropped() throws {
        let built = schedule(try piece(notes:
            note("g", midi: 61, beat: 0, duration: 0, grace: true)))

        #expect(built.entries.count == 1)
        // 0.12s / 0.625 = 0.192 beats, which at 120bpm is 0.096s.
        #expect(abs(built.entries[0].end - 0.096) < 1e-9)
    }

    @Test func aZeroLengthNonGraceNoteMakesNoSound() throws {
        let built = schedule(try piece(notes: note("a", midi: 60, beat: 0, duration: 0)))
        #expect(built.entries.isEmpty)
    }

    @Test func velocityFallsBackToADefault() throws {
        let built = schedule(try piece(notes: note("a", midi: 60, beat: 0, duration: 1)))
        #expect(built.entries[0].velocity == 80)
    }

    // MARK: - The pedal

    @Test func pianoKeepsThePedalTail() throws {
        // The written note is held for one beat but rings for four under the
        // pedal; a piano should let it ring.
        let timeline = try piece(notes: note("a", midi: 60, beat: 0, duration: 1, keyDuration: "1"),
                                 audio: """
        [{"segment_ids": ["a"], "source_id": "a", "midi": 60, "role": 0,
          "start_beat": 0, "duration_beats": 4}]
        """)

        #expect(schedule(timeline, pedal: true).entries[0].end == 2)
    }

    @Test func anOrganStopsWhenTheKeyIsReleased() throws {
        // An organ has no sustain pedal: the same event must be cut back to
        // how long the key was actually held.
        let timeline = try piece(notes: note("a", midi: 60, beat: 0, duration: 1, keyDuration: "1"),
                                 audio: """
        [{"segment_ids": ["a"], "source_id": "a", "midi": 60, "role": 0,
          "start_beat": 0, "duration_beats": 4}]
        """)

        #expect(schedule(timeline, pedal: false).entries[0].end == 0.5)
    }

    @Test func anOrganStillFollowsTiesToTheirEnd() throws {
        // Trimming must follow the whole tie chain, not stop at the first
        // segment, or a tied note is cut off mid-ring.
        let timeline = try piece(notes: [
            note("a", midi: 60, beat: 0, duration: 2, keyDuration: "2"),
            note("b", midi: 60, beat: 2, duration: 2, keyDuration: "2"),
        ].joined(separator: ","), audio: """
        [{"segment_ids": ["a", "b"], "source_id": "a", "midi": 60, "role": 0,
          "start_beat": 0, "duration_beats": 6}]
        """)

        #expect(schedule(timeline, pedal: false).entries[0].end == 2)   // four beats
    }

    @Test func organTrimmingLeavesUnmatchedEventsAlone() throws {
        // An event whose segments are not in the written notes has nothing to
        // trim against; it must not collapse to zero.
        let timeline = try piece(notes: note("a", midi: 60, beat: 0, duration: 1),
                                 audio: """
        [{"segment_ids": ["missing"], "source_id": "missing", "midi": 60, "role": 0,
          "start_beat": 0, "duration_beats": 2}]
        """)

        #expect(schedule(timeline, pedal: false).entries[0].end == 1)
    }

    // MARK: - The count-in

    @Test func startingFromTheTopGetsAFullCountIn() throws {
        let built = schedule(try piece(notes: note("a", midi: 60, beat: 0, duration: 1)))
        // Four beats at 120bpm.
        #expect(abs(built.leadSeconds - 2) < 1e-9)
    }

    @Test func seekingIntoThePieceStartsPromptly() throws {
        let built = schedule(try piece(notes: note("a", midi: 60, beat: 4, duration: 1)), from: 4)
        #expect(abs(built.leadSeconds - 0.06) < 1e-9)
    }

    @Test func theCountInFollowsTheSpeedControl() throws {
        // At double speed the count-in is half as long, so it still counts
        // four beats of the music you are about to hear.
        let built = schedule(try piece(notes: note("a", midi: 60, beat: 0, duration: 1)), speed: 2)
        #expect(abs(built.leadSeconds - 1) < 1e-9)
    }
}
