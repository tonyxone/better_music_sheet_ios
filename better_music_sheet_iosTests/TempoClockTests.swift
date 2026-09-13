import Foundation
import Testing
@testable import better_music_sheet_ios

private func timeline(_ json: String) throws -> Timeline {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Timeline.self, from: Data(json.utf8))
}

private func bare(tempoMap: String = "null", defaultBPM: Double = 96) throws -> Timeline {
    try timeline("""
    {"version": 1, "tempo_bpm_default": \(defaultBPM), "total_beats": 16,
     "measures": [], "notes": [], "tempo_map": \(tempoMap)}
    """)
}

struct TempoClockTests {

    @Test func constantTempoIsLinear() throws {
        // 120 bpm = half a second per quarter.
        let clock = TempoClock(timeline: try bare(tempoMap: #"[{"start_beat": 0, "bpm": 120}]"#))

        #expect(clock.seconds(atBeat: 0) == 0)
        #expect(abs(clock.seconds(atBeat: 1) - 0.5) < 1e-9)
        #expect(abs(clock.seconds(atBeat: 8) - 4.0) < 1e-9)
    }

    @Test func beatAndSecondsAreInverses() throws {
        let clock = TempoClock(timeline: try bare(tempoMap:
            #"[{"start_beat": 0, "bpm": 72}, {"start_beat": 8, "bpm": 144}]"#))

        for beat in [0.0, 0.5, 3.25, 8.0, 8.75, 15.0] {
            let roundTrip = clock.beat(atSeconds: clock.seconds(atBeat: beat))
            #expect(abs(roundTrip - beat) < 1e-9, "round trip failed at beat \(beat)")
        }
    }

    @Test func integratesAcrossATempoChange() throws {
        // 8 beats at 60bpm = 8s, then 4 beats at 120bpm = 2s.
        let clock = TempoClock(timeline: try bare(tempoMap:
            #"[{"start_beat": 0, "bpm": 60}, {"start_beat": 8, "bpm": 120}]"#))

        #expect(abs(clock.seconds(atBeat: 8) - 8.0) < 1e-9)
        #expect(abs(clock.seconds(atBeat: 12) - 10.0) < 1e-9)
    }

    @Test func speedScalesTime() throws {
        let base = TempoClock(timeline: try bare(tempoMap: #"[{"start_beat": 0, "bpm": 100}]"#))
        let double = TempoClock(timeline: try bare(tempoMap: #"[{"start_beat": 0, "bpm": 100}]"#), speed: 2)

        #expect(abs(double.seconds(atBeat: 4) - base.seconds(atBeat: 4) / 2) < 1e-9)
        #expect(double.rate == 2)
    }

    @Test func baseBPMOverrideRescalesTheWholeMap() throws {
        // Override the opening 60 to 120: everything runs twice as fast,
        // including the later marking, because the map is scaled, not replaced.
        let clock = TempoClock(timeline: try bare(tempoMap:
            #"[{"start_beat": 0, "bpm": 60}, {"start_beat": 4, "bpm": 90}]"#), baseBPM: 120)

        #expect(abs(clock.seconds(atBeat: 4) - 2.0) < 1e-9)
    }

    @Test func speedIsCappedByTheFastestTempoAnywhere() throws {
        // The opening is slow, but a Presto section later would blow past the
        // ceiling — the cap has to consider the whole piece.
        let clock = TempoClock(timeline: try bare(tempoMap:
            #"[{"start_beat": 0, "bpm": 60}, {"start_beat": 8, "bpm": 200}]"#), speed: 2)

        // 200 * 2 = 400, over the 300 ceiling, so the rate is pulled back.
        #expect(abs(clock.rate - 1.5) < 1e-9)
    }

    @Test func theBPMOverrideWinsOverTheSpeedControl() throws {
        // A typed override is explicit; the speed multiplier is casual, so
        // the multiplier is what gives way.
        let clock = TempoClock(timeline: try bare(tempoMap: #"[{"start_beat": 0, "bpm": 100}]"#),
                               speed: 2, baseBPM: 200)
        #expect(abs(clock.rate - 1.5) < 1e-9)  // 200 * 1.5 = 300, exactly the ceiling
    }

    @Test func fallsBackToTheDefaultWhenThereIsNoMap() throws {
        let clock = TempoClock(timeline: try bare(defaultBPM: 120))
        #expect(abs(clock.seconds(atBeat: 2) - 1.0) < 1e-9)
    }

    @Test func prependsTheDefaultWhenTheMapStartsLate() throws {
        // A marking at beat 4 says nothing about beats 0-4.
        let clock = TempoClock(timeline: try bare(tempoMap: #"[{"start_beat": 4, "bpm": 120}]"#,
                                                  defaultBPM: 60))
        #expect(abs(clock.seconds(atBeat: 4) - 4.0) < 1e-9)   // 4 beats at 60
        #expect(abs(clock.seconds(atBeat: 6) - 5.0) < 1e-9)   // then 2 at 120
    }

    @Test func ignoresNonsenseTempoEntries() throws {
        let clock = TempoClock(timeline: try bare(tempoMap:
            #"[{"start_beat": 0, "bpm": 0}, {"start_beat": 0, "bpm": 120}]"#))
        #expect(abs(clock.seconds(atBeat: 2) - 1.0) < 1e-9)
    }

    @Test func extrapolatesBeforeZeroForTheCountIn() throws {
        // The four-beat lead-in lives at negative beats; without extrapolation
        // the first note would sound immediately instead of after the count.
        let clock = TempoClock(timeline: try bare(tempoMap: #"[{"start_beat": 0, "bpm": 120}]"#))
        #expect(abs(clock.seconds(atBeat: -4) - -2.0) < 1e-9)
    }

    @Test func invalidSpeedFallsBackToNormal() throws {
        let clock = TempoClock(timeline: try bare(tempoMap: #"[{"start_beat": 0, "bpm": 120}]"#), speed: 0)
        #expect(clock.rate == 1)
    }
}

struct TempoControlTests {

    @Test func plainQuarterNoteTempo() throws {
        let control = TempoControl(timeline: try bare(tempoMap: #"[{"start_beat": 0, "bpm": 72}]"#))
        #expect(control.bpm == 72)
        #expect(control.unit == "quarter note")
        #expect(control.toQuarterBPM(80) == 80)
    }

    @Test func showsCompoundMetreInItsOwnBeatUnit() throws {
        // 6/8 marked "dotted quarter = 60" is 90 quarter-beats per minute;
        // the field must say 60, and hand 90 back to the clock.
        let control = TempoControl(timeline: try bare(tempoMap:
            #"[{"start_beat": 0, "bpm": 90, "beat_unit_quarters": 1.5}]"#))

        #expect(control.bpm == 60)
        #expect(control.unit == "dotted quarter note")
        #expect(control.toQuarterBPM(60) == 90)
    }

    @Test func usesTheDefaultWhenThereIsNoMarking() throws {
        let control = TempoControl(timeline: try bare(defaultBPM: 108))
        #expect(control.bpm == 108)
        #expect(control.unit == "quarter note")
    }
}
