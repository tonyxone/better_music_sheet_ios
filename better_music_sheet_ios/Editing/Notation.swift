import Foundation
import Observation

/// Numbered notation (jianpu, 簡譜): the note names shown as numbers,
/// 1 2 3 4 5 6 7, instead of letters. The labels stay letters underneath — in
/// labels.json, in the reader's saved edits, in what retyping compares — and
/// only what is drawn changes, so switching back and forth loses nothing.
///
/// "1" is always C, whatever the key signature ("1=C"): C D E F G A B read
/// 1 2 3 4 5 6 7, and a sharp or flat is written as the letter has it — F♯ is
/// ♯4, B♭ is ♭7. A double sharp or flat reads as the number it sounds as
/// (C𝄪 is 2).
///
/// The conversion itself is ported from the web app's lib/notation.ts, which
/// can count from any key; the app always counts from C.
nonisolated enum Notation: String, Codable, Sendable, CaseIterable, Identifiable {
    case letters, numbers

    var id: Self { self }

    /// What the switch says.
    var title: String {
        switch self {
        case .letters: "Letter"
        case .numbers: "簡"
        }
    }

    var spokenTitle: String {
        switch self {
        case .letters: "Letter names"
        case .numbers: "Jianpu, numbered notation"
        }
    }
}

/// A "1=G" mark: above the start of the first measure on each page and of any
/// measure where the key changes. Left-aligned on x, with its baseline on y,
/// in PDF points, top-down.
nonisolated struct KeyMark: Sendable, Hashable {
    let page: Int
    let x: Double
    let y: Double
    let size: Double
    let text: String
}

nonisolated enum Jianpu {
    private static let letters: [Character] = ["C", "D", "E", "F", "G", "A", "B"]
    private static let stepSemitones = NoteNames.stepSemitones
    private static let unicodeAccidentals = [-2: "𝄫", -1: "♭", 0: "", 1: "♯", 2: "𝄪"]
    private static let asciiAccidentals = [-2: "bb", -1: "b", 0: "", 1: "#", 2: "##"]
    /// In the web app's regex alternation order: longer spellings first.
    private static let typedAccidentals: [(String, Int)] = [
        ("𝄫", -2), ("𝄪", 2), ("♭♭", -2), ("♯♯", 2), ("##", 2), ("bb", -2),
        ("♮", 0), ("♯", 1), ("♭", -1), ("#", 1), ("b", -1), ("x", 2),
    ]

    private static func mod(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }

    /// Whether a label spells its accidentals in plain ASCII (Bb, C#).
    private static func usesASCII(_ text: String) -> Bool {
        let trimmed = text.drop { $0.isWhitespace }
        guard let first = trimmed.first, "ABCDEFGabcdefg".contains(first),
              let second = trimmed.dropFirst().first else { return false }
        return second == "#" || second == "b" || second == "x"
    }

    private static func accidental(_ alter: Int, ascii: Bool) -> String? {
        (ascii ? asciiAccidentals : unicodeAccidentals)[alter]
    }

    /// The major tonic of a key signature: letter index (C = 0) and pitch class.
    private static func tonic(_ fifths: Int) -> (step: Int, pc: Int) {
        (mod(4 * fifths, 7), mod(7 * fifths, 12))
    }

    /// "G", "E♭", "F♯" — the name after "1=" for a key signature.
    static func keyName(_ fifths: Int, ascii: Bool = false) -> String {
        let t = tonic(fifths)
        let alter = mod(t.pc - stepSemitones[t.step] + 6, 12) - 6
        return String(letters[t.step]) + (accidental(alter, ascii: ascii) ?? "")
    }

    /// A letter label ("F♯", "Bb4", "C?") as a scale degree of the key given by
    /// `fifths` ("#4", "♭7", "1?"). Anything that isn't a note name comes back
    /// unchanged. The octave, when the label has one, is dropped.
    static func numbered(_ text: String, fifths: Int) -> String {
        guard let p = NoteNames.parse(text) else { return text }
        let t = tonic(fifths)
        var degree = mod(p.step - t.step, 7)
        let expected = mod(t.pc + stepSemitones[degree], 12)
        let actual = mod(stepSemitones[p.step] + p.alter, 12)
        var alter = mod(actual - expected + 6, 12) - 6
        if abs(alter) > 1 {
            // By sound instead: the degree itself, or the one a semitone away
            // in the direction the note was altered.
            let offset = mod(actual - t.pc, 12)
            if let plain = stepSemitones.firstIndex(of: offset) {
                degree = plain
                alter = 0
            } else {
                alter = alter > 0 ? 1 : -1
                degree = stepSemitones.firstIndex(of: mod(offset - alter, 12)) ?? degree
            }
        }
        let doubtful = text.trimmingCharacters(in: .whitespaces).hasSuffix("?")
        return (accidental(alter, ascii: usesASCII(text)) ?? "") + String(degree + 1) + (doubtful ? "?" : "")
    }

    /// A scale degree typed by the reader ("#4", "b7", "5") back as the letter
    /// it means in the key, spelled like `original` (the label's printed
    /// text). When it names the printed note, the printed text itself comes
    /// back, octave and all. Nil when `text` isn't a scale degree.
    static func letter(fromNumbered text: String, fifths: Int, original: String) -> String? {
        guard let typed = parseDegree(text) else { return nil }
        let t = tonic(fifths)
        let step = mod(t.step + typed.degree, 7)
        let pc = mod(t.pc + stepSemitones[typed.degree] + typed.alter, 12)
        let alter = mod(pc - stepSemitones[step] + 6, 12) - 6
        if let printed = NoteNames.parse(original), printed.step == step, printed.alter == alter {
            return original.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let acc = accidental(alter, ascii: usesASCII(original)) else { return nil }
        return String(letters[step]) + acc + (typed.doubtful ? "?" : "")
    }

    /// `^\s*(accidental)?([1-7])\s*(\?)?\s*$`
    private static func parseDegree(_ text: String) -> (degree: Int, alter: Int, doubtful: Bool)? {
        var rest = text.drop { $0.isWhitespace }
        var alter = 0
        if let (spelling, value) = typedAccidentals.first(where: { rest.hasPrefix($0.0) }) {
            alter = value
            rest = rest.dropFirst(spelling.count)
        }
        guard let digit = rest.first, digit.isASCII, let value = digit.wholeNumberValue,
              (1...7).contains(value) else { return nil }
        rest = rest.dropFirst().drop { $0.isWhitespace }
        let doubtful = rest.first == "?"
        if doubtful { rest = rest.dropFirst().drop { $0.isWhitespace } }
        return rest.isEmpty ? (value - 1, alter, doubtful) : nil
    }

    private static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
    private static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    /// A timeline note's name in `notation`, as written on the sheet: its own
    /// spelling when that still matches what it plays, otherwise — a pitch
    /// the reader corrected — spelled from the pitch, with flats in flat keys.
    static func name(of note: TimelineNote, in notation: Notation) -> String {
        let fifths = note.keyFifths ?? 0
        let pc = mod(note.midi, 12)
        let step = note.step.flatMap { $0.first }.flatMap { letters.firstIndex(of: $0) }
        let letter: String
        if let step, mod(stepSemitones[step] + (note.alter ?? 0), 12) == pc {
            letter = String(letters[step]) + (unicodeAccidentals[note.alter ?? 0] ?? "")
        } else {
            letter = (fifths < 0 ? flatNames : sharpNames)[pc]
        }
        return display(letter, in: notation)
    }

    /// The key "1" is counted from: C, always.
    static let fixedFifths = 0

    /// What a label reads as in `notation`.
    static func display(_ text: String, in notation: Notation) -> String {
        notation == .numbers ? numbered(text, fifths: fixedFifths) : text
    }

    // MARK: - Key marks

    /// Where "1=C" goes: above the start of the first measure on each page, as
    /// printed jianpu marks it.
    static func keyMarks(_ timeline: Timeline?, size: Double = 7) -> [KeyMark] {
        guard let timeline else { return [] }
        // Each printed measure once, in reading order — repeats replay measures.
        var printed: [Int: TimelineMeasure] = [:]
        for m in timeline.measures where printed[m.printedIndex ?? m.index] == nil {
            printed[m.printedIndex ?? m.index] = m
        }
        var marks: [KeyMark] = []
        var marked: Set<Int> = []
        for (_, m) in printed.sorted(by: { $0.key < $1.key }) {
            guard let page = m.page, let box = m.bboxPt, !marked.contains(page) else { continue }
            // Above the top staff line, clear of a treble clef's curl.
            marks.append(KeyMark(page: page, x: box.x0, y: box.y0 - size * 1.3, size: size,
                                 text: "1=\(keyName(fixedFifths))"))
            marked.insert(page)
        }
        return marks
    }
}

/// The reader's letters/numbers choice, remembered on this device and shared
/// by every page that shows names, so switching on one switches them all.
/// Until they choose, each sheet shows the notation it was made with.
@MainActor
@Observable
final class NotationPreference {
    static let shared = NotationPreference()

    private static let key = "label_notation"
    private let defaults: UserDefaults
    private(set) var chosen: Notation?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        chosen = defaults.string(forKey: Self.key).flatMap(Notation.init(rawValue:))
    }

    func notation(fallback: Notation?) -> Notation {
        chosen ?? fallback ?? .letters
    }

    func choose(_ notation: Notation) {
        chosen = notation
        defaults.set(notation.rawValue, forKey: Self.key)
    }
}
