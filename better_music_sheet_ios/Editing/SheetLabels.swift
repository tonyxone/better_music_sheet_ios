import Foundation

/// One printed note name, as data the app draws itself so a reader can move
/// and retype it. Written by the backend's label_export.py as labels.json,
/// next to timeline.json. Mirrors the web app's lib/labels.ts.
nonisolated struct LabelItem: Sendable, Hashable, Identifiable {
    let id: String
    /// Lines of one chord stack share a group, so they can be selected together.
    let group: String
    /// 1-based PDF page.
    let page: Int
    /// Horizontal centre and baseline, in PDF points, top-down.
    let x: Double
    let y: Double
    let size: Double
    let text: String
    /// Timeline ids (printed_id, else source_id) of the notes this names.
    let notes: [String]
}

nonisolated struct LabelSet: Sendable, Equatable {
    /// "#RRGGBB" — the colour the names were printed in.
    let color: String
    let items: [LabelItem]

    /// Parses labels.json, dropping any item too malformed to draw rather
    /// than losing the rest. Nil when nothing usable is left.
    static func decode(_ data: Data) -> LabelSet? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let raw = root["items"] as? [[String: Any]] ?? []
        let items: [LabelItem] = raw.compactMap { item in
            guard let id = item["id"] as? String, let text = item["text"] as? String,
                  let page = JSONValue.int(item["page"]), let x = JSONValue.double(item["x"]),
                  let y = JSONValue.double(item["y"]), let size = JSONValue.double(item["size"]) else { return nil }
            return LabelItem(id: id, group: item["group"] as? String ?? id, page: page,
                             x: x, y: y, size: size, text: text,
                             notes: (item["notes"] as? [Any])?.compactMap { $0 as? String } ?? [])
        }
        guard !items.isEmpty else { return nil }
        let color = root["color"] as? String
        return LabelSet(color: color.flatMap(SheetEdits.isColor) == true ? color! : "#000000", items: items)
    }

    /// Names read out of an annotated PDF (see PDFLabelReader), for a sheet
    /// with no labels.json. Nil when the PDF holds none.
    static func reading(pdf data: Data, timeline: Timeline?) -> LabelSet? {
        var items = PDFLabelReader.labels(in: data)
        guard !items.isEmpty else { return nil }
        if let timeline { items = PDFLabelReader.linked(items, to: timeline) }
        return LabelSet(color: "#000000", items: items)
    }

    /// Takes over the ids that saved edits use, for names read out of a PDF
    /// whose id came out slightly different on the web.
    ///
    /// Those ids are built from each name's position, and pdf.js sometimes
    /// counts an invisible trailing space into a name's width — when the next
    /// name sits further along the same line — which moves its centre a
    /// point or two right. An edit keyed that way finds no name here, so it
    /// is matched to the name on the same page and baseline just left of
    /// where it points, and that name answers to the web's id from then on.
    func adoptingIDs(of keys: some Sequence<String>) -> LabelSet {
        let known = Set(items.map(\.id))
        let wanted = Set(keys)
        var renamed: [Int: String] = [:]
        for key in wanted.sorted() where !known.contains(key) {
            let parts = key.split(separator: "-")
            guard parts.count == 4, parts[0] == "pdf", let page = Int(parts[1]),
                  let x = Int(parts[2]), let y = Int(parts[3]) else { continue }
            var best: (index: Int, gap: Int)?
            for (index, item) in items.enumerated() where renamed[index] == nil && item.page == page {
                let itemParts = item.id.split(separator: "-")
                guard itemParts.count == 4, itemParts[0] == "pdf", Int(itemParts[3]) == y,
                      let itemX = Int(itemParts[2]),
                      // A name whose own id has an edit is already found.
                      !wanted.contains(item.id) else { continue }
                let gap = x - itemX
                // A space in the label font is at most a few points wide.
                if gap > 0, gap <= 40, gap < (best?.gap ?? .max) { best = (index, gap) }
            }
            if let best { renamed[best.index] = key }
        }
        guard !renamed.isEmpty else { return self }
        return LabelSet(color: color, items: items.enumerated().map { index, item in
            guard let id = renamed[index] else { return item }
            return LabelItem(id: id, group: id, page: item.page, x: item.x, y: item.y,
                             size: item.size, text: item.text, notes: item.notes)
        })
    }
}

/// Reading loosely-typed JSON numbers. JSONSerialization hands back NSNumber,
/// which also bridges from booleans — those are refused, as the web app's
/// `Number.isFinite` refuses them.
nonisolated enum JSONValue {
    static func double(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, !isBool(number) else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    static func int(_ value: Any?) -> Int? {
        double(value).flatMap { $0 == $0.rounded() && abs($0) < 1e9 ? Int($0) : nil }
    }

    static func isBool(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}

// MARK: - Note names

/// A note name as a reader might type it: its letter, accidental and
/// (optional) octave.
nonisolated struct SpelledPitch: Sendable, Equatable {
    /// 0 = C through 6 = B.
    let step: Int
    let alter: Int
    let octave: Int?
}

nonisolated enum NoteNames {
    private static let steps: [Character] = ["C", "D", "E", "F", "G", "A", "B"]
    static let stepSemitones = [0, 2, 4, 5, 7, 9, 11]
    /// In the web app's regex alternation order, so the same text parses the
    /// same way: longer spellings are tried before their prefixes.
    private static let accidentals: [(String, Int)] = [
        ("𝄫", -2), ("𝄪", 2), ("♭♭", -2), ("♯♯", 2), ("##", 2), ("bb", -2),
        ("♮", 0), ("♯", 1), ("♭", -1), ("#", 1), ("b", -1), ("x", 2),
    ]

    /// "B♭", "C#4", "f" -> its spelling, or nil for anything that isn't a
    /// note name.
    static func parse(_ text: String) -> SpelledPitch? {
        let trimmed = text.drop { $0.isWhitespace }
        guard let letter = trimmed.first?.uppercased().first,
              let step = steps.firstIndex(of: letter) else { return nil }
        let rest = trimmed.dropFirst()
        // A regex alternation backtracks into shorter alternatives when the
        // rest fails to match; trying each in order does the same.
        for (spelling, alter) in accidentals where rest.hasPrefix(spelling) {
            if case .some(let octave) = tail(rest.dropFirst(spelling.count)) {
                return SpelledPitch(step: step, alter: alter, octave: octave)
            }
        }
        if case .some(let octave) = tail(rest) {
            return SpelledPitch(step: step, alter: 0, octave: octave)
        }
        return nil
    }

    /// `(-?\d)?\s*\??\s*$`: an optional octave digit, then at most a question
    /// mark (the backend's mark for a doubtful reading) and whitespace.
    /// Nil when the text doesn't fit; `.some(nil)` when it fits with no octave.
    private static func tail(_ text: Substring) -> Int?? {
        var rest = text
        var octave: Int?
        let negative = rest.first == "-"
        let digits = negative ? rest.dropFirst() : rest
        if let digit = digits.first, digit.isASCII, let value = digit.wholeNumberValue {
            octave = negative ? -value : value
            rest = digits.dropFirst()
        } else if negative {
            return nil
        }
        rest = rest.drop { $0.isWhitespace }
        if rest.first == "?" { rest = rest.dropFirst() }
        rest = rest.drop { $0.isWhitespace }
        return rest.isEmpty ? .some(octave) : nil
    }

    /// The MIDI number a retyped label means, judged against what it said
    /// before and the note it belonged to: an explicit octave is taken as
    /// written, otherwise the new letter lands on the nearest staff position —
    /// so a "B" retyped as "C" goes up a step, not down a seventh.
    static func retypedMIDI(newText: String, oldText: String, oldMIDI: Int) -> Int? {
        guard let next = parse(newText) else { return nil }
        let midi: Int
        if let octave = next.octave {
            midi = (octave + 1) * 12 + stepSemitones[next.step] + next.alter
        } else {
            let old = parse(oldText)
            let oldStep = old?.step ?? nearestStep(oldMIDI)
            let oldAlter = old?.alter ?? (oldMIDI % 12 - stepSemitones[oldStep])
            // Math.round, which rounds halves up, not away from zero.
            let oldOctave = Int((Double(oldMIDI - oldAlter - stepSemitones[oldStep]) / 12 + 0.5).rounded(.down)) - 1
            let oldIndex = oldOctave * 7 + oldStep
            var best = 0
            var bestDistance = Int.max
            for octave in (oldOctave - 1)...(oldOctave + 1) {
                let distance = abs(octave * 7 + next.step - oldIndex)
                if distance < bestDistance {
                    bestDistance = distance
                    best = octave
                }
            }
            midi = (best + 1) * 12 + stepSemitones[next.step] + next.alter
        }
        return (21...108).contains(midi) ? midi : nil
    }

    private static func nearestStep(_ midi: Int) -> Int {
        let pitchClass = ((midi % 12) + 12) % 12
        var best = 0
        for i in 0..<7 where abs(stepSemitones[i] - pitchClass) < abs(stepSemitones[best] - pitchClass) {
            best = i
        }
        return best
    }
}
