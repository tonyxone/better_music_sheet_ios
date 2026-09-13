import Foundation
import Testing
@testable import better_music_sheet_ios

private func notes(_ json: String) throws -> [TimelineNote] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let timeline = try decoder.decode(Timeline.self, from: Data("""
    {"version": 1, "tempo_bpm_default": 96, "total_beats": 100, "measures": [], "notes": [\(json)]}
    """.utf8))
    return timeline.notes
}

private func note(_ midi: Int, at start: Double, for duration: Double,
                  held: Double? = nil, grace: Bool = false) -> String {
    """
    {"source_id": "n\(midi)-\(start)", "measure_index": 0, "role": 0, "midi": \(midi),
     "start_beat": \(start), "duration_beats": \(duration), "is_grace": \(grace),
     "key_duration_beats": \(held.map { String($0) } ?? "null"), "bbox_pt": null}
    """
}

struct NoteRollGeometryTests {
    /// 4 beats ahead plus 0.45 behind: at 445pt that is 100pt a beat, with the
    /// hit line at 400.
    private let height = 445.0

    @Test func theHitLineSitsJustAboveTheBottom() {
        #expect(abs(NoteRollGeometry.pointsPerBeat(height: height) - 100) < 1e-9)
        #expect(abs(NoteRollGeometry.hitY(height: height) - 400) < 1e-9)
    }

    @Test func aNoteReachesTheHitLineExactlyAsItSounds() throws {
        let geometry = NoteRollGeometry(notes: try notes(note(60, at: 2, for: 1)))
        let bar = try #require(geometry.frame(atBeat: 2, height: height).whiteKeyBars.first)
        #expect(abs(bar.bottom - 400) < 1e-9)
        #expect(abs(bar.top - 300) < 1e-9)
    }

    @Test func anUpcomingNoteFallsFromAbove() throws {
        let geometry = NoteRollGeometry(notes: try notes(note(60, at: 3, for: 1)))
        let bar = try #require(geometry.frame(atBeat: 1, height: height).whiteKeyBars.first)
        // Two beats early: two beats' height above the hit line.
        #expect(abs(bar.bottom - 200) < 1e-9)
        #expect(abs(bar.top - 100) < 1e-9)
    }

    @Test func notesFallDuringTheCountIn() throws {
        // Below beat zero the roll keeps moving, so the first note starts high
        // and falls into place rather than waiting at the keys.
        let geometry = NoteRollGeometry(notes: try notes(note(60, at: 0, for: 1)))
        let bar = try #require(geometry.frame(atBeat: -2, height: height).whiteKeyBars.first)
        #expect(abs(bar.bottom - 200) < 1e-9)
    }

    @Test func notesBeyondTheLookAheadAreNotDrawn() throws {
        let geometry = NoteRollGeometry(notes: try notes(note(60, at: 5.5, for: 1)))
        #expect(geometry.frame(atBeat: 1, height: height).whiteKeyBars.isEmpty)
    }

    @Test func aNoteThatHasPassedIsNotDrawn() throws {
        let geometry = NoteRollGeometry(notes: try notes(note(60, at: 0, for: 1)))
        #expect(geometry.frame(atBeat: 2, height: height).whiteKeyBars.isEmpty)
    }

    @Test func aLongNoteThatStartedWellBeforeTheWindowStillShows() throws {
        let geometry = NoteRollGeometry(notes: try notes(note(48, at: 0, for: 10)))
        #expect(geometry.frame(atBeat: 6, height: height).whiteKeyBars.count == 1)
    }

    @Test func graceNotesGetABarYouCanSee() throws {
        let geometry = NoteRollGeometry(notes: try notes(note(62, at: 1, for: 0, grace: true)))
        let bar = try #require(geometry.frame(atBeat: 1, height: height).whiteKeyBars.first)
        #expect(abs((bar.bottom - bar.top) - 12) < 1e-9)   // 0.12 beats at 100pt a beat
    }

    @Test func blackKeyNotesAreKeptApartToDrawOnTop() throws {
        let geometry = NoteRollGeometry(notes: try notes(
            [note(60, at: 1, for: 1), note(61, at: 1, for: 1)].joined(separator: ",")))
        let frame = geometry.frame(atBeat: 1, height: height)
        #expect(frame.whiteKeyBars.map(\.midi) == [60])
        #expect(frame.blackKeyBars.map(\.midi) == [61])
    }

    @Test func aNoteIsHighlightedOnlyWhileItsKeyIsHeld() throws {
        // Written as two beats but held for one: staccato.
        let geometry = NoteRollGeometry(notes: try notes(note(60, at: 1, for: 2, held: 1)))
        #expect(geometry.frame(atBeat: 0.9, height: height).highlights.isEmpty)
        #expect(geometry.frame(atBeat: 1.5, height: height).highlights.count == 1)
        #expect(geometry.frame(atBeat: 2.5, height: height).highlights.isEmpty)
    }

    @Test func theLandingFlashFadesAfterTheStrike() throws {
        let geometry = NoteRollGeometry(notes: try notes(note(60, at: 1, for: 2)))
        let atStrike = try #require(geometry.frame(atBeat: 1, height: height).highlights.first)
        let halfway = try #require(geometry.frame(atBeat: 1.175, height: height).highlights.first)
        let later = try #require(geometry.frame(atBeat: 1.5, height: height).highlights.first)
        #expect(atStrike.flash == 1)
        #expect(abs(halfway.flash - 0.5) < 1e-9)
        #expect(later.flash == 0)
    }

    @Test func findsTheFirstVisibleNoteBySearching() throws {
        let many = try notes((0..<100).map { note(60, at: Double($0), for: 0.5) }.joined(separator: ","))
        let geometry = NoteRollGeometry(notes: many)
        // Anything starting up to eight beats before the window may reach it.
        #expect(geometry.firstVisibleIndex(windowStart: 50) == 42)
        #expect(geometry.firstVisibleIndex(windowStart: -3) == 0)
        #expect(geometry.firstVisibleIndex(windowStart: 500) == 100)
    }

    @Test func nothingIsDrawnWithNoRoom() throws {
        let geometry = NoteRollGeometry(notes: try notes(note(60, at: 0, for: 1)))
        let frame = geometry.frame(atBeat: 0, height: 0)
        #expect(frame.whiteKeyBars.isEmpty)
        #expect(frame.highlights.isEmpty)
    }
}
