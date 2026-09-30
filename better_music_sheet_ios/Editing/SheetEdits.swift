import Foundation

/// A reader's own changes to a sheet: note names moved, retyped or hidden,
/// freehand marks, text notes, and the playback corrections a retyped name
/// implies. Stored per reader per sheet on the server (PUT
/// /api/sheets/{id}/edits), shared with the web app — so the same JSON shape,
/// and the same limits, as its lib/edits.ts.
///
/// Everything is in PDF points, top-down: the space the labels and the
/// timeline's boxes already use, so it lines up at any zoom.
nonisolated struct SheetEdits: Sendable, Equatable {
    nonisolated struct LabelEdit: Sendable, Equatable {
        var dx: Double?
        var dy: Double?
        var text: String?
        var hidden = false
        /// "#RRGGBB" when the reader recoloured this name; nil keeps the
        /// sheet's own label colour.
        var color: String?

        var isEmpty: Bool { dx == nil && dy == nil && text == nil && !hidden && color == nil }
    }

    nonisolated struct TextNote: Sendable, Equatable, Identifiable {
        let id: String
        var page: Int
        var x: Double
        var y: Double
        var text: String
        var size: Double
        var color: String
    }

    nonisolated struct Stroke: Sendable, Equatable, Identifiable {
        enum Tool: String, Sendable { case pen, highlighter }

        let id: String
        var page: Int
        var tool: Tool
        var color: String
        var width: Double
        /// Flat [x0, y0, x1, y1, ...].
        var points: [Double]
    }

    var labels: [String: LabelEdit] = [:]
    var texts: [TextNote] = []
    var strokes: [Stroke] = []
    var corrections: Corrections = [:]

    static let empty = SheetEdits()

    var isEmpty: Bool { labels.isEmpty && texts.isEmpty && strokes.isEmpty && corrections.isEmpty }

    static func isColor(_ value: String) -> Bool {
        value.count == 7 && value.first == "#" && value.dropFirst().allSatisfy(\.isHexDigit)
    }

    // MARK: - JSON

    /// Whatever came back from storage, reduced to what this version can
    /// draw. A malformed entry is dropped on its own rather than costing the
    /// rest — the web app may have written something newer.
    init(json value: Any?) {
        let raw = value as? [String: Any] ?? [:]
        for (id, entry) in raw["labels"] as? [String: Any] ?? [:] {
            guard let entry = entry as? [String: Any] else { continue }
            var edit = LabelEdit()
            edit.dx = JSONValue.double(entry["dx"])
            edit.dy = JSONValue.double(entry["dy"])
            edit.text = (entry["text"] as? String).map { String($0.prefix(40)) }
            edit.hidden = (entry["hidden"] as? NSNumber).map { JSONValue.isBool($0) && $0.boolValue } ?? false
            edit.color = (entry["color"] as? String).flatMap { Self.isColor($0) ? $0 : nil }
            if !edit.isEmpty { labels[id] = edit }
        }
        texts = (raw["texts"] as? [Any] ?? []).compactMap { entry in
            guard let t = entry as? [String: Any], let id = t["id"] as? String,
                  let page = JSONValue.int(t["page"]), let x = JSONValue.double(t["x"]),
                  let y = JSONValue.double(t["y"]), let text = t["text"] as? String,
                  let size = JSONValue.double(t["size"]), let color = t["color"] as? String,
                  Self.isColor(color) else { return nil }
            return TextNote(id: id, page: page, x: x, y: y, text: text, size: size, color: color)
        }
        strokes = (raw["strokes"] as? [Any] ?? []).compactMap { entry in
            guard let s = entry as? [String: Any], let id = s["id"] as? String,
                  let page = JSONValue.int(s["page"]),
                  let tool = (s["tool"] as? String).flatMap(Stroke.Tool.init(rawValue:)),
                  let color = s["color"] as? String, Self.isColor(color),
                  let width = JSONValue.double(s["width"]),
                  let rawPoints = s["points"] as? [Any], rawPoints.count >= 2 else { return nil }
            let points = rawPoints.compactMap(JSONValue.double)
            guard points.count == rawPoints.count else { return nil }
            return Stroke(id: id, page: page, tool: tool, color: color, width: width, points: points)
        }
        for (id, entry) in raw["corrections"] as? [String: Any] ?? [:] {
            guard let c = entry as? [String: Any], let midi = JSONValue.int(c["midi"]),
                  let offset = JSONValue.double(c["offset"]), let duration = JSONValue.double(c["duration"]),
                  c.keys.contains("hand") else { continue }
            // null keeps following the staff; anything else must be a hand.
            let hand: Hand?
            if c["hand"] is NSNull {
                hand = nil
            } else if let named = (c["hand"] as? String).flatMap(Hand.init(rawValue:)) {
                hand = named
            } else {
                continue
            }
            let correction = NoteCorrection(midi: midi, hand: hand, offset: offset, duration: duration)
            if correction.isValid { corrections[id] = correction }
        }
    }

    init() {}

    /// The document as the server and the web app expect it. Built by hand
    /// rather than through Codable: a correction's `hand` has to be an
    /// explicit null when absent — the web app rejects a missing one.
    var jsonObject: [String: Any] {
        [
            "version": 1,
            "labels": labels.mapValues { edit -> [String: Any] in
                var out: [String: Any] = [:]
                if let dx = edit.dx { out["dx"] = dx }
                if let dy = edit.dy { out["dy"] = dy }
                if let text = edit.text { out["text"] = text }
                if edit.hidden { out["hidden"] = true }
                if let color = edit.color { out["color"] = color }
                return out
            },
            "texts": texts.map { t -> [String: Any] in
                ["id": t.id, "page": t.page, "x": t.x, "y": t.y, "text": t.text, "size": t.size, "color": t.color]
            },
            "strokes": strokes.map { s -> [String: Any] in
                ["id": s.id, "page": s.page, "tool": s.tool.rawValue, "color": s.color,
                 "width": s.width, "points": s.points]
            },
            "corrections": corrections.mapValues { c -> [String: Any] in
                ["midi": c.midi, "hand": c.hand?.rawValue ?? NSNull(), "offset": c.offset, "duration": c.duration]
            },
        ]
    }

    // MARK: - Labels

    /// A label as it should be drawn now: moved, retyped, or nil if hidden —
    /// its text in `notation` (edits themselves are always stored as letters).
    func resolve(_ item: LabelItem, notation: Notation = .letters) -> ResolvedLabel? {
        let edit = labels[item.id]
        if edit?.hidden == true { return nil }
        return ResolvedLabel(id: item.id, page: item.page,
                             x: item.x + (edit?.dx ?? 0), y: item.y + (edit?.dy ?? 0),
                             size: item.size,
                             text: Jianpu.display(edit?.text ?? item.text, in: notation),
                             edited: edit != nil, color: edit?.color)
    }

    /// `edit` stored for `id`, or the entry removed when there is nothing
    /// left in it.
    func settingLabel(_ id: String, _ edit: LabelEdit) -> SheetEdits {
        var next = self
        next.labels[id] = edit.isEmpty ? nil : edit
        return next
    }

    // MARK: - Selections

    /// Every selected item moved by (dx, dy) points, from this state.
    func moving(_ items: [SelectedItem], dx: Double, dy: Double) -> SheetEdits {
        func r(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        let keys = Set(items)
        var next = self
        for item in items where item.kind == .label {
            var edit = next.labels[item.id] ?? LabelEdit()
            edit.dx = r((edit.dx ?? 0) + dx)
            edit.dy = r((edit.dy ?? 0) + dy)
            next.labels[item.id] = edit
        }
        next.texts = texts.map { t in
            guard keys.contains(SelectedItem(kind: .text, id: t.id)) else { return t }
            var moved = t
            moved.x = r(t.x + dx)
            moved.y = r(t.y + dy)
            return moved
        }
        next.strokes = strokes.map { s in
            guard keys.contains(SelectedItem(kind: .stroke, id: s.id)) else { return s }
            var moved = s
            moved.points = s.points.enumerated().map { i, v in r(v + (i % 2 == 1 ? dy : dx)) }
            return moved
        }
        return next
    }

    /// Hides selected names and deletes selected marks and notes.
    func removing(_ items: [SelectedItem]) -> SheetEdits {
        let keys = Set(items)
        var next = self
        for item in items where item.kind == .label {
            var edit = next.labels[item.id] ?? LabelEdit()
            edit.hidden = true
            next.labels[item.id] = edit
        }
        next.texts.removeAll { keys.contains(SelectedItem(kind: .text, id: $0.id)) }
        next.strokes.removeAll { keys.contains(SelectedItem(kind: .stroke, id: $0.id)) }
        return next
    }

    /// Selected names, text notes and drawings in a new colour. Names take
    /// it as their own colour; the sheet's label colour clears it again.
    func recoloring(_ items: [SelectedItem], to color: String, labelDefault: String) -> SheetEdits {
        let keys = Set(items)
        var next = self
        for item in items where item.kind == .label {
            var edit = next.labels[item.id] ?? LabelEdit()
            edit.color = color.caseInsensitiveCompare(labelDefault) == .orderedSame ? nil : color
            next.labels[item.id] = edit.isEmpty ? nil : edit
        }
        for i in next.texts.indices where keys.contains(SelectedItem(kind: .text, id: next.texts[i].id)) {
            next.texts[i].color = color
        }
        for i in next.strokes.indices where keys.contains(SelectedItem(kind: .stroke, id: next.strokes[i].id)) {
            next.strokes[i].color = color
        }
        return next
    }

    // MARK: - Retyped names -> playback

    nonisolated struct RetypeResult: Sendable, Equatable {
        let corrections: Corrections
        let changed: Int
        /// False when the label names no note, so only the page changes.
        let linked: Bool
    }

    /// The corrections implied by retyping `item` to `text`: every note it
    /// names moves to the new pitch, keeping its timing and hand. Retyping
    /// back to the printed name drops those corrections again. Nil when
    /// `text` isn't a note name (the label then changes on the page only).
    static func correctionsForRetype(_ item: LabelItem, to text: String, original: Timeline,
                                     corrections: Corrections) -> RetypeResult? {
        guard !item.notes.isEmpty else { return RetypeResult(corrections: corrections, changed: 0, linked: false) }
        var next = corrections
        var changed = 0
        var byID: [String: TimelineNote] = [:]
        for note in original.notes {
            if let id = note.printedID ?? note.sourceID, byID[id] == nil { byID[id] = note }
        }
        let backToPrinted = text.trimmingCharacters(in: .whitespacesAndNewlines)
            == item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        for id in item.notes {
            guard let note = byID[id], note.measureIndex >= 0, note.measureIndex < original.measures.count else { continue }
            let measure = original.measures[note.measureIndex]
            if backToPrinted {
                if next.removeValue(forKey: id) != nil { changed += 1 }
                continue
            }
            guard let midi = NoteNames.retypedMIDI(newText: text, oldText: item.text, oldMIDI: note.midi) else { return nil }
            if var existing = next[id] {
                existing.midi = midi
                next[id] = existing
            } else {
                next[id] = NoteCorrection(midi: midi, hand: note.hand, offset: note.startBeat - measure.startBeat,
                                          duration: note.durationBeats > 0 ? note.durationBeats : 0.125)
            }
            changed += 1
        }
        return RetypeResult(corrections: next, changed: changed, linked: true)
    }
}

/// A label with the reader's edits applied, ready to draw.
nonisolated struct ResolvedLabel: Sendable, Equatable {
    let id: String
    let page: Int
    let x: Double
    let y: Double
    let size: Double
    let text: String
    let edited: Bool
    /// The reader's colour for this name, if they chose one.
    var color: String? = nil
}

nonisolated struct SelectedItem: Sendable, Hashable {
    enum Kind: String, Sendable { case label, text, stroke }

    let kind: Kind
    let id: String
}

nonisolated enum EditIDs {
    /// Unique enough across devices: a time stamp and a random tail, in the
    /// web app's format.
    static func make(_ prefix: String, now: Date = Date()) -> String {
        let time = String(Int64(now.timeIntervalSince1970 * 1000), radix: 36)
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let tail = String((0..<5).map { _ in alphabet.randomElement()! })
        return "\(prefix)-\(time)-\(tail)"
    }
}

// MARK: - Ink

/// Freehand strokes: thinning the raw touch samples, and the smooth curve
/// both the page and the exported PDF draw them with. Ported from the web
/// app's lib/ink.ts so a stroke looks the same wherever it was drawn.
nonisolated enum Ink {
    /// Ramer–Douglas–Peucker on a flat [x0, y0, x1, y1, ...] list. Keeps a
    /// stroke's shape while dropping most of the samples a finger produces,
    /// which is what keeps a page of handwriting small enough to save.
    static func simplify(_ points: [Double], tolerance: Double = 0.35) -> [Double] {
        let n = points.count / 2
        guard n > 2 else { return points }
        var keep = [Bool](repeating: false, count: n)
        keep[0] = true
        keep[n - 1] = true
        var stack = [(0, n - 1)]
        while let (a, b) = stack.popLast() {
            let ax = points[a * 2], ay = points[a * 2 + 1], bx = points[b * 2], by = points[b * 2 + 1]
            let dx = bx - ax, dy = by - ay
            let length = (dx * dx + dy * dy).squareRoot()
            var worst = -1
            var worstDistance = tolerance
            for i in (a + 1)..<b {
                let px = points[i * 2], py = points[i * 2 + 1]
                let distance = length > 0
                    ? abs(dy * px - dx * py + bx * ay - by * ax) / length
                    : ((px - ax) * (px - ax) + (py - ay) * (py - ay)).squareRoot()
                if distance > worstDistance {
                    worst = i
                    worstDistance = distance
                }
            }
            if worst >= 0 {
                keep[worst] = true
                stack.append((a, worst))
                stack.append((worst, b))
            }
        }
        var out: [Double] = []
        for i in 0..<n where keep[i] {
            out.append(round(points[i * 2]))
            out.append(round(points[i * 2 + 1]))
        }
        return out
    }

    private static func round(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    enum Segment: Equatable {
        case move(Double, Double)
        case line(Double, Double)
        case quad(cx: Double, cy: Double, x: Double, y: Double)
    }

    /// Quadratic curves through the midpoints between samples — smooth, and
    /// passing close enough to every kept sample to read as what was drawn.
    static func segments(_ points: [Double]) -> [Segment] {
        let n = points.count / 2
        guard n > 0 else { return [] }
        let x = { (i: Int) in points[i * 2] }
        let y = { (i: Int) in points[i * 2 + 1] }
        if n == 1 { return [.move(x(0), y(0)), .line(x(0) + 0.01, y(0))] }
        var out: [Segment] = [.move(x(0), y(0))]
        if n == 2 { return out + [.line(x(1), y(1))] }
        for i in 1..<(n - 1) {
            out.append(.quad(cx: x(i), cy: y(i), x: (x(i) + x(i + 1)) / 2, y: (y(i) + y(i + 1)) / 2))
        }
        out.append(.line(x(n - 1), y(n - 1)))
        return out
    }
}
