import Foundation
import Testing
@testable import better_music_sheet_ios

/// The conversion is the web app's lib/notation.ts, so its cases are kept here
/// for every key; the app itself always counts from C (1=C).
private func timeline(measures: String = "[]", notes: String) throws -> Timeline {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Timeline.self, from: Data("""
    {"version": 1, "tempo_bpm_default": 96, "total_beats": 100, "measures": \(measures), "notes": \(notes)}
    """.utf8))
}

private func measure(_ index: Int, page: Int? = nil, printed: Int? = nil, box: [Double]? = nil) -> String {
    """
    {"index": \(index), "printed_index": \(printed.map(String.init) ?? "null"), "label": "\(index + 1)",
     "page": \(page.map(String.init) ?? "null"), "start_beat": \(index * 4), "length_beats": 4,
     "bbox_pt": \(box.map { "\($0)" } ?? "null"), "distinct_midis": []}
    """
}

private func note(measure: Int = 0, midi: Int = 60, start: Double = 0, duration: Double = 1,
                  key: Int? = nil, extra: String = "") -> String {
    """
    {"measure_index": \(measure), "role": 0, "midi": \(midi), "start_beat": \(start),
     "duration_beats": \(duration), "is_grace": false, "key_fifths": \(key.map(String.init) ?? "null")\(extra)}
    """
}

struct NotationTests {
    @Test func numbersCountFromTheMajorTonicOfTheKeySignature() {
        // No sharps or flats: 1 = C, and F sharp is the raised fourth.
        #expect(["G", "A", "B", "C", "D", "E", "F♯"].map { Jianpu.numbered($0, fifths: 0) }
                == ["5", "6", "7", "1", "2", "3", "♯4"])
        // In G major F sharp belongs to the key and F natural is lowered.
        #expect(Jianpu.numbered("F♯", fifths: 1) == "7")
        #expect(Jianpu.numbered("F", fifths: 1) == "♭7")
        #expect(Jianpu.numbered("G", fifths: 1) == "1")
        // Flat keys, and a minor piece read from its relative major (A minor: 6).
        #expect(Jianpu.numbered("E♭", fifths: -3) == "1")
        #expect(Jianpu.numbered("B♭", fifths: -3) == "5")
        #expect(Jianpu.numbered("B", fifths: -3) == "♯5")
        #expect(Jianpu.numbered("A", fifths: 0) == "6")
        #expect(Jianpu.numbered("G♯", fifths: 0) == "♯5")
        // Spelling decides the degree: E sharp in C sharp major is 3, not 4.
        #expect(Jianpu.numbered("E♯", fifths: 7) == "3")
        // A double sharp or flat relative to the key reads as the degree it sounds.
        #expect(Jianpu.numbered("C𝄪", fifths: 0) == "2")
        #expect(Jianpu.numbered("D♯", fifths: -4) == "5")
        #expect(Jianpu.numbered("A♯", fifths: -4) == "2")
        #expect(Jianpu.numbered("A♭", fifths: 5) == "6")
        #expect(Jianpu.numbered("F𝄫", fifths: 0) == "♭3")
        // ASCII labels stay ASCII; octaves drop; the uncertainty mark stays.
        #expect(Jianpu.numbered("Bb4", fifths: 0) == "b7")
        #expect(Jianpu.numbered("C#?", fifths: 0) == "#1?")
        // Anything that isn't a note name is left as it is.
        #expect(Jianpu.numbered("rit.", fifths: 0) == "rit.")
    }

    @Test func keyNamesCoverEveryKeySignature() {
        #expect((-7...7).map { Jianpu.keyName($0) }
                == ["C♭", "G♭", "D♭", "A♭", "E♭", "B♭", "F", "C", "G", "D", "A", "E", "B", "F♯", "C♯"])
        #expect(Jianpu.keyName(-2, ascii: true) == "Bb")
    }

    @Test func everyLetterRoundTripsThroughItsScaleDegreeInEveryKey() throws {
        func pitchClass(_ text: String) throws -> Int {
            let p = try #require(NoteNames.parse(text))
            return ((NoteNames.stepSemitones[p.step] + p.alter) % 12 + 12) % 12
        }
        for fifths in -7...7 {
            for letter in ["C", "D", "E", "F", "G", "A", "B"] {
                for accidental in ["♭", "", "♯"] {
                    let name = letter + accidental
                    let number = Jianpu.numbered(name, fifths: fifths)
                    let back = try #require(Jianpu.letter(fromNumbered: number, fifths: fifths, original: "X"),
                                            "\(name) in \(fifths)")
                    #expect(!number.contains("𝄪") && !number.contains("𝄫"), "\(name) in \(fifths)")
                    #expect(Jianpu.numbered(back, fifths: fifths) == number, "\(name) in \(fifths)")
                    // The same key on the piano, whether or not it was respelled.
                    #expect(try pitchClass(back) == pitchClass(name), "\(name) in \(fifths)")
                }
            }
        }
    }

    @Test func aTypedScaleDegreeBecomesTheLetterItMeans() {
        #expect(Jianpu.letter(fromNumbered: "#4", fifths: 0, original: "G") == "F♯")
        #expect(Jianpu.letter(fromNumbered: "b7", fifths: 1, original: "G") == "F")
        #expect(Jianpu.letter(fromNumbered: "7", fifths: 1, original: "Bb") == "F#")
        // The printed note keeps its printed text, octave and all.
        #expect(Jianpu.letter(fromNumbered: "5", fifths: 0, original: "G4") == "G4")
        #expect(Jianpu.letter(fromNumbered: "F#", fifths: 0, original: "G") == nil)
    }

    @Test func namesReadAsNumbersWithCAsOneWhateverTheKeyAndEditsStayLetters() {
        let item = LabelItem(id: "L1", group: "g", page: 1, x: 0, y: 0, size: 6, text: "F♯", notes: [])
        var doc = SheetEdits.empty
        doc.labels["L1"] = SheetEdits.LabelEdit(text: "B♭")
        #expect(SheetEdits.empty.resolve(item, notation: .numbers)?.text == "♯4")
        #expect(doc.resolve(item, notation: .numbers)?.text == "♭7")
        #expect(doc.resolve(item, notation: .letters)?.text == "B♭")
        #expect(["C", "D", "E", "F", "G", "A", "B", "C#4", "Eb?"].map { Jianpu.display($0, in: .numbers) }
                == ["1", "2", "3", "4", "5", "6", "7", "#1", "b3?"])
    }

    @Test func keyMarksSay1EqualsCOncePerPageOverItsFirstMeasure() throws {
        func m(_ index: Int, _ page: Int, _ printed: Int, _ x: Double, box: Bool = true) -> String {
            measure(index, page: page, printed: printed, box: box ? [x, 100, x + 50, 190] : nil)
        }
        // A repeat replays measure 1 on page 1; page 3's first measure has no box.
        let t = try timeline(
            measures: "[\(m(0, 1, 0, 40)), \(m(1, 1, 1, 90)), \(m(2, 2, 2, 40)), \(m(3, 1, 1, 90)), \(m(4, 3, 4, 40, box: false)), \(m(5, 3, 5, 90))]",
            notes: "[\(note(key: -3))]")
        #expect(Jianpu.keyMarks(t).map { "\($0.page)@\(Int($0.x)) \($0.text)" } == ["1@40 1=C", "2@40 1=C", "3@90 1=C"])
        #expect(Jianpu.keyMarks(nil).isEmpty)
    }

    @Test func whiteKeysReadAsJianpuWithCAsOne() {
        #expect((60...71).map { KeyboardLayout.keyLabel($0, notation: .numbers) }
                == ["1", "", "2", "", "3", "4", "", "5", "", "6", "", "7"])
        #expect(KeyboardLayout.keyLabel(60, notation: .letters) == "C4")
        #expect(KeyboardLayout.keyLabel(62, notation: .letters) == "D")
    }

    @Test func fallingNotesAreNamedAsWrittenOrFromThePitchOnceCorrected() throws {
        let notes = try timeline(notes: """
            [\(note(midi: 66, key: 1, extra: #", "step": "F", "alter": 1, "octave": 4"#)),
             \(note(midi: 63, key: -4, extra: #", "step": "D", "alter": 1"#)),
             \(note(midi: 68, key: -4, extra: #", "step": "F", "alter": 1, "octave": 4"#)),
             \(note(midi: 68, key: 1, extra: #", "step": "F", "alter": 1, "octave": 4"#)),
             \(note(midi: 60))]
            """).notes
        #expect(Jianpu.name(of: notes[0], in: .letters) == "F♯")
        #expect(Jianpu.name(of: notes[0], in: .numbers) == "♯4")
        // Spelled as written even where the pitch has another name.
        #expect(Jianpu.name(of: notes[1], in: .letters) == "D♯")
        #expect(Jianpu.name(of: notes[1], in: .numbers) == "♯2")
        // A reader's correction changes the pitch but not the old spelling:
        // then the pitch decides, with flats in a flat key.
        #expect(Jianpu.name(of: notes[2], in: .letters) == "A♭")
        #expect(Jianpu.name(of: notes[3], in: .letters) == "G♯")
        #expect(Jianpu.name(of: notes[4], in: .numbers) == "1")
    }

    @Test func aFallingNoteIsNamedOnceAcrossItsTiedPieces() throws {
        let notes = try timeline(notes: """
            [\(note(midi: 75, start: 0, duration: 2)),
             \(note(midi: 63, start: 0, duration: 0.5)),
             \(note(midi: 63, start: 0, duration: 0.5)),
             \(note(midi: 63, start: 1, duration: 0.5)),
             \(note(midi: 75, start: 2, duration: 2, extra: #", "tie_stop": true"#)),
             \(note(midi: 75, start: 4, duration: 1, extra: #", "tie_stop": true"#)),
             \(note(midi: 75, start: 5, duration: 1))]
            """).notes
        // A second voice on the same key, a repeated strike named again, a
        // tie carried on, and a new strike right after the tie ends.
        #expect(NoteRollGeometry.nameEnds(notes) == [5, 0.5, -1, 1.5, -1, -1, 6])
    }

    @Test func aNameSitsInTheMiddleOfItsWholeHeldNote() throws {
        let notes = try timeline(notes: """
            [\(note(midi: 60, start: 2, duration: 1)),
             \(note(midi: 60, start: 3, duration: 1, extra: #", "tie_stop": true"#))]
            """).notes
        let geometry = NoteRollGeometry(notes: notes, nameEnds: NoteRollGeometry.nameEnds(notes))
        // 100pt a beat with the hit line at 400 (see NoteRollGeometryTests).
        let names = geometry.frame(atBeat: 2, height: 445).names
        #expect(names.count == 1)
        #expect(names.first.map { abs($0.bottom - 400) < 1e-9 && abs($0.top - 200) < 1e-9 } == true)
        #expect(NoteRollGeometry(notes: notes).frame(atBeat: 2, height: 445).names.isEmpty)
    }

    @Test func labelsJSONCarriesTheSheetsNotation() throws {
        let set = try #require(LabelSet.decode(Data("""
            {"color": "#000000", "notation": "numbers", "items": [
              {"id": "1-0-0", "group": "1-0", "page": 1, "x": 10, "y": 20, "size": 6.5, "text": "F♯", "notes": [], "key": 1},
              {"id": "1-0-1", "group": "1-0", "page": 1, "x": 10, "y": 28, "size": 6.5, "text": "D", "notes": []}]}
            """.utf8)))
        #expect(set.notation == .numbers)
        #expect(set.items.count == 2)
        #expect(LabelSet.decode(Data(#"{"items": [{"id": "a", "page": 1, "x": 0, "y": 0, "size": 6, "text": "C"}]}"#.utf8))?
            .notation == .letters)
    }

    @Test @MainActor func theReadersChoiceWinsOverTheSheetsOwnAndIsRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "NotationTests"))
        defaults.removePersistentDomain(forName: "NotationTests")
        let preference = NotationPreference(defaults: defaults)
        #expect(preference.notation(fallback: .numbers) == .numbers)
        #expect(preference.notation(fallback: nil) == .letters)
        preference.choose(.letters)
        #expect(preference.notation(fallback: .numbers) == .letters)
        #expect(NotationPreference(defaults: defaults).chosen == .letters)
        defaults.removePersistentDomain(forName: "NotationTests")
    }
}
