import CoreGraphics
import Foundation

/// What the reader is doing to the sheet in the preview: moving or retyping
/// note names (retyping one fixes what plays too), drawing, highlighting,
/// adding text notes — one item at a time or a selected group. A port of the
/// web app's sheet-editor.tsx and annotation-layer.tsx, reshaped for touch:
/// a tap selects, a drag on a selected item moves it, touching and holding
/// empty space drags out a selection box, and one finger draws while two
/// scroll and zoom.
///
/// Everything here is in one page's PDF points, top-down; the view converts
/// touches before calling in, and passes how many screen points one PDF
/// point currently spans so pick radii stay the same size under a finger.
@MainActor
@Observable
final class SheetEditorModel {
    enum Tool: String, CaseIterable, Identifiable, Sendable {
        case select, pen, highlighter, text, eraser

        var id: Self { self }

        var title: String {
            switch self {
            case .select: "Select"
            case .pen: "Pen"
            case .highlighter: "Highlight"
            case .text: "Text"
            case .eraser: "Erase"
            }
        }

        /// One finger draws with these, so the sheet scrolls with two.
        var drawsWithOneFinger: Bool { self == .pen || self == .highlighter || self == .eraser }
    }

    /// The item being typed into, in the sheet that asks for its text.
    struct TextEditTarget: Identifiable, Equatable, Sendable {
        let item: SelectedItem
        let initialText: String
        /// A text note that exists only until it has text.
        let isNew: Bool

        var id: String { item.id }
    }

    struct DraftStroke: Equatable, Sendable {
        let page: Int
        let tool: SheetEdits.Stroke.Tool
        let color: String
        let width: Double
        var points: [Double]
    }

    struct Marquee: Equatable, Sendable {
        let page: Int
        let start: CGPoint
        var end: CGPoint

        var rect: CGRect {
            CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                   width: abs(end.x - start.x), height: abs(end.y - start.y))
        }
    }

    enum ResetScope: Sendable { case names, everything }

    static let penColors = ["#2e2117", "#c0392b", "#1f5fbf", "#2f7d32"]
    static let highlightColors = ["#ffd84d", "#8ee07a", "#ff9ec7", "#7cc8ff"]
    static let penWidth = 1.2
    static let highlighterWidth = 7.0
    static let textSize = 10.0
    /// How far from a name or note a touch still picks it up, in screen
    /// points — a fingertip's worth, where the web app allows a cursor's.
    static let pickRadius = 22.0

    let store: SheetEditsStore
    /// The names as data. Nil when this sheet can't show them that way — no
    /// stored original, a photo upload, or one annotated before label export —
    /// and then only marks and notes can be added, over the annotated copy.
    let labels: LabelSet?
    private let timeline: Timeline?
    private let labelsByID: [String: LabelItem]
    let labelsByPage: [Int: [LabelItem]]
    /// Where "1=C" goes on each page, for names shown as numbers.
    let keyMarksByPage: [Int: [KeyMark]]

    var isEditing = false {
        didSet { if !isEditing { finishEditing() } }
    }
    var tool: Tool = .select {
        didSet { if tool != oldValue { marquee = nil } }
    }
    var penColor = SheetEditorModel.penColors[1]
    var highlightColor = SheetEditorModel.highlightColors[0]
    /// Whether names are on the page being edited — false on the Original
    /// view, where only marks and notes show.
    var showsNames = true {
        didSet { if !showsNames { selection.removeAll { $0.kind == .label } } }
    }
    private(set) var selection: [SelectedItem] = []
    var textEditor: TextEditTarget?
    private(set) var draft: DraftStroke?
    private(set) var marquee: Marquee?
    /// Set with a notice after a reset, so that notice can offer its own undo.
    private(set) var resetNotice: String?

    private var drag: (items: [SelectedItem], start: CGPoint, before: SheetEdits, moved: Bool)?
    private var erasing: (before: SheetEdits, removed: Bool)?
    /// The document without a new text note, so keeping it is one undo step.
    private var textBefore: SheetEdits?

    /// Where the letters/jianpu choice is read from: the shared one, except
    /// in tests, which mustn't depend on what was last chosen on the device.
    private let notationPreference: NotationPreference

    init(store: SheetEditsStore, labels: LabelSet?, timeline: Timeline?,
         notationPreference: NotationPreference = .shared) {
        self.store = store
        self.notationPreference = notationPreference
        self.labels = labels
        self.timeline = timeline
        self.labelsByID = Dictionary((labels?.items ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.labelsByPage = Dictionary(grouping: labels?.items ?? [], by: \.page)
        self.keyMarksByPage = Dictionary(grouping: Jianpu.keyMarks(timeline), by: \.page)
    }

    var doc: SheetEdits { store.doc ?? .empty }
    var namesLive: Bool { labels != nil }

    /// Letters or jianpu: the reader's choice, shared with every other page,
    /// or the notation the sheet was made with until they make one.
    var notation: Notation { notationPreference.notation(fallback: labels?.notation) }

    /// A name as it's drawn right now, in the notation being shown.
    func resolved(_ item: LabelItem) -> ResolvedLabel? {
        doc.resolve(item, notation: notation)
    }

    var notice: String? { store.notice }

    func setNotice(_ message: String?) {
        store.notice = message
        if message != resetNotice { resetNotice = nil }
    }

    func dismissNotice() { setNotice(nil) }

    private func finishEditing() {
        selection = []
        draft = nil
        marquee = nil
        drag = nil
        erasing = nil
    }

    // MARK: - What's where

    /// Rough width of a label, for hit boxes and selection outlines only —
    /// the same estimate the web app uses, so a box drawn there fits here.
    static func approxWidth(_ text: String, size: Double) -> Double {
        Double(max(1, text.count)) * size * 0.62
    }

    func resolvedLabels(page: Int) -> [ResolvedLabel] {
        guard showsNames else { return [] }
        return (labelsByPage[page] ?? []).compactMap(resolved)
    }

    static func labelBox(_ l: ResolvedLabel) -> CGRect {
        let width = approxWidth(l.text, size: l.size)
        return CGRect(x: l.x - width / 2 - 0.8, y: l.y - l.size * 0.9, width: width + 1.6, height: l.size * 1.15)
    }

    static func textBox(_ t: SheetEdits.TextNote) -> CGRect {
        let lines = t.text.split(separator: "\n", omittingEmptySubsequences: false)
        let width = lines.map { approxWidth(String($0), size: t.size * 0.9) }.max() ?? 0
        return CGRect(x: t.x - 1, y: t.y - t.size, width: max(width, t.size) + 2,
                      height: t.size * 1.2 * Double(max(1, lines.count)) + 1)
    }

    /// The item under a touch: a name or note whose box holds it, else the
    /// nearest one within reach, else a drawing passing close by.
    func item(at point: CGPoint, page: Int, pxPerPt: Double, kinds: Set<SelectedItem.Kind> = [.label, .text, .stroke]) -> SelectedItem? {
        let radius = Self.pickRadius / max(pxPerPt, 0.01)
        let labels = kinds.contains(.label) ? resolvedLabels(page: page) : []
        let texts = kinds.contains(.text) ? doc.texts.filter { $0.page == page } : []

        // Latest drawn first, as on screen: notes sit over names.
        if let t = texts.last(where: { Self.textBox($0).contains(point) }) { return SelectedItem(kind: .text, id: t.id) }
        if let l = labels.last(where: { Self.labelBox($0).contains(point) }) { return SelectedItem(kind: .label, id: l.id) }

        var best: SelectedItem?
        var bestDistance = radius
        for l in labels {
            let d = hypot(l.x - point.x, l.y - l.size * 0.35 - point.y)
            if d < bestDistance { bestDistance = d; best = SelectedItem(kind: .label, id: l.id) }
        }
        for t in texts {
            let box = Self.textBox(t)
            let d = hypot(box.midX - point.x, box.midY - point.y)
            if d < bestDistance { bestDistance = d; best = SelectedItem(kind: .text, id: t.id) }
        }
        if let best { return best }

        guard kinds.contains(.stroke) else { return nil }
        for stroke in doc.strokes.reversed() where stroke.page == page {
            if Self.distance(from: point, to: stroke.points) <= radius * 0.6 + stroke.width / 2 {
                return SelectedItem(kind: .stroke, id: stroke.id)
            }
        }
        return nil
    }

    static func distance(from p: CGPoint, to points: [Double]) -> Double {
        let n = points.count / 2
        guard n > 0 else { return .infinity }
        if n == 1 { return hypot(points[0] - p.x, points[1] - p.y) }
        var best = Double.infinity
        for i in 0..<(n - 1) {
            let ax = points[i * 2], ay = points[i * 2 + 1], bx = points[i * 2 + 2], by = points[i * 2 + 3]
            let dx = bx - ax, dy = by - ay
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0 ? max(0, min(1, ((p.x - ax) * dx + (p.y - ay) * dy) / lengthSquared)) : 0
            best = min(best, hypot(ax + t * dx - p.x, ay + t * dy - p.y))
        }
        return best
    }

    /// Items whose centre lies inside the box.
    func items(in rect: CGRect, page: Int) -> [SelectedItem] {
        var found: [SelectedItem] = []
        for l in resolvedLabels(page: page) where rect.contains(CGPoint(x: l.x, y: l.y - l.size * 0.35)) {
            found.append(SelectedItem(kind: .label, id: l.id))
        }
        for t in doc.texts where t.page == page {
            let box = Self.textBox(t)
            if rect.contains(CGPoint(x: box.midX, y: box.midY)) { found.append(SelectedItem(kind: .text, id: t.id)) }
        }
        for s in doc.strokes where s.page == page {
            let xs = stride(from: 0, to: s.points.count, by: 2).map { s.points[$0] }
            let ys = stride(from: 1, to: s.points.count, by: 2).map { s.points[$0] }
            let centre = CGPoint(x: ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2, y: ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2)
            if rect.contains(centre) { found.append(SelectedItem(kind: .stroke, id: s.id)) }
        }
        return found
    }

    func isSelected(_ item: SelectedItem) -> Bool { selection.contains(item) }

    func select(_ items: [SelectedItem]) {
        selection = items.filter { showsNames || $0.kind != .label }
    }

    // MARK: - Touches

    func tap(at point: CGPoint, page: Int, pxPerPt: Double) {
        guard isEditing, store.doc != nil else { return }
        switch tool {
        case .select:
            guard let hit = item(at: point, page: page, pxPerPt: pxPerPt) else {
                selection = []
                return
            }
            // Tapping the one selected name or note again types into it.
            if selection == [hit], hit.kind != .stroke {
                openTextEditor(for: hit)
            } else {
                select([hit])
            }
        case .text:
            if let hit = item(at: point, page: page, pxPerPt: pxPerPt, kinds: [.text]) {
                select([hit])
                openTextEditor(for: hit)
            } else {
                addText(at: point, page: page)
            }
        case .eraser:
            if let hit = item(at: point, page: page, pxPerPt: pxPerPt, kinds: [.text, .stroke]) {
                store.update { $0.removing([hit]) }
                selection.removeAll { $0 == hit }
            }
        case .pen, .highlighter:
            // A dot: the shortest stroke there is.
            beginPan(at: point, page: page, pxPerPt: pxPerPt)
            endPan(at: point)
        }
    }

    /// Whether a one-finger drag starting here belongs to the editor rather
    /// than scrolling the sheet: always for the drawing tools, and for the
    /// others only when it starts on something that can be moved.
    func claimsPan(at point: CGPoint, page: Int, pxPerPt: Double) -> Bool {
        guard isEditing, store.doc != nil else { return false }
        if tool.drawsWithOneFinger { return true }
        return item(at: point, page: page, pxPerPt: pxPerPt) != nil
    }

    func beginPan(at point: CGPoint, page: Int, pxPerPt: Double) {
        guard isEditing, let current = store.doc else { return }
        switch tool {
        case .pen, .highlighter:
            let highlighter = tool == .highlighter
            draft = DraftStroke(page: page, tool: highlighter ? .highlighter : .pen,
                                color: highlighter ? highlightColor : penColor,
                                width: highlighter ? Self.highlighterWidth : Self.penWidth,
                                points: [point.x, point.y])
        case .eraser:
            erasing = (current, false)
            erase(at: point, page: page, pxPerPt: pxPerPt)
        case .select, .text:
            guard let hit = item(at: point, page: page, pxPerPt: pxPerPt) else { return }
            // Pressing on part of the selection moves all of it; on anything
            // else, that item becomes the selection.
            let items = selection.contains(hit) ? selection : [hit]
            select(items)
            drag = (items, point, current, false)
        }
    }

    func movePan(to point: CGPoint, page: Int, pxPerPt: Double) {
        if var stroke = draft {
            let lx = stroke.points[stroke.points.count - 2], ly = stroke.points[stroke.points.count - 1]
            guard hypot(point.x - lx, point.y - ly) >= 0.3 else { return }
            stroke.points += [point.x, point.y]
            draft = stroke
        } else if erasing != nil {
            erase(at: point, page: page, pxPerPt: pxPerPt)
        } else if var d = drag {
            let dx = point.x - d.start.x, dy = point.y - d.start.y
            if !d.moved && hypot(dx, dy) * pxPerPt < 3 { return }
            d.moved = true
            drag = d
            let before = d.before, items = d.items
            store.update(transient: true) { _ in before.moving(items, dx: dx, dy: dy) }
        }
    }

    func endPan(at point: CGPoint) {
        if let stroke = draft {
            draft = nil
            let points = Ink.simplify(stroke.points)
            store.update { d in
                var next = d
                next.strokes.append(SheetEdits.Stroke(id: EditIDs.make("stroke"), page: stroke.page, tool: stroke.tool,
                                                      color: stroke.color, width: stroke.width, points: points))
                return next
            }
        } else if let sweep = erasing {
            erasing = nil
            // One undo step for the whole sweep.
            if sweep.removed { store.update(before: sweep.before) { $0 } }
        } else if let d = drag {
            drag = nil
            guard d.moved else { return }
            store.update(before: d.before) { _ in d.before.moving(d.items, dx: point.x - d.start.x, dy: point.y - d.start.y) }
        }
    }

    func cancelPan() {
        draft = nil
        if let sweep = erasing {
            erasing = nil
            if sweep.removed { store.update(transient: true) { _ in sweep.before } }
        }
        if let d = drag {
            drag = nil
            store.update(transient: true) { _ in d.before }
        }
    }

    private func erase(at point: CGPoint, page: Int, pxPerPt: Double) {
        guard erasing != nil,
              let hit = item(at: point, page: page, pxPerPt: pxPerPt, kinds: [.text, .stroke]) else { return }
        store.update(transient: true) { $0.removing([hit]) }
        selection.removeAll { $0 == hit }
        erasing?.removed = true
    }

    // MARK: Selection box

    /// Touch and hold on empty space starts a box; anything inside it when
    /// the finger lifts is selected. Only in the select tool.
    func beginMarquee(at point: CGPoint, page: Int, pxPerPt: Double) -> Bool {
        guard isEditing, tool == .select, item(at: point, page: page, pxPerPt: pxPerPt) == nil else { return false }
        marquee = Marquee(page: page, start: point, end: point)
        return true
    }

    func moveMarquee(to point: CGPoint) {
        marquee?.end = point
    }

    func endMarquee() {
        guard let box = marquee else { return }
        marquee = nil
        select(items(in: box.rect, page: box.page))
    }

    // MARK: - Text

    private func addText(at point: CGPoint, page: Int) {
        guard let now = store.doc else { return }
        let note = SheetEdits.TextNote(id: EditIDs.make("text"), page: page, x: point.x,
                                       y: point.y + Self.textSize * 0.35, text: "", size: Self.textSize,
                                       color: penColor)
        textBefore = now
        // Not an undo step yet: an empty note is dropped when its editor
        // closes, and a filled one is recorded then.
        store.update(transient: true) { d in
            var next = d
            next.texts.append(note)
            return next
        }
        let item = SelectedItem(kind: .text, id: note.id)
        select([item])
        textEditor = TextEditTarget(item: item, initialText: "", isNew: true)
    }

    func openTextEditor(for item: SelectedItem) {
        switch item.kind {
        case .label:
            guard let label = labelsByID[item.id], let shown = resolved(label) else { return }
            textEditor = TextEditTarget(item: item, initialText: shown.text, isNew: false)
        case .text:
            guard let note = doc.texts.first(where: { $0.id == item.id }) else { return }
            textEditor = TextEditTarget(item: item, initialText: note.text, isNew: false)
        case .stroke:
            return
        }
    }

    /// The text sheet closed: with what was typed, or nil when cancelled.
    func closeTextEditor(_ value: String?) {
        guard let target = textEditor else { return }
        textEditor = nil
        if target.item.kind == .label {
            if let value { retypeLabel(target.item.id, value) }
            return
        }
        let before = textBefore
        textBefore = nil
        let id = target.item.id
        let text = value.map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
        if target.isNew {
            guard let text, !text.isEmpty else {
                store.update(transient: true) { d in
                    var next = d
                    next.texts.removeAll { $0.id == id }
                    return next
                }
                selection = []
                return
            }
            store.update(before: before) { d in Self.settingText(d, id: id, text: text) }
            return
        }
        guard let text else { return }
        if text.isEmpty {
            store.update { $0.removing([target.item]) }
            selection = []
        } else {
            store.update { d in Self.settingText(d, id: id, text: text) }
        }
    }

    private static func settingText(_ d: SheetEdits, id: String, text: String) -> SheetEdits {
        var next = d
        if let i = next.texts.firstIndex(where: { $0.id == id }) { next.texts[i].text = text }
        return next
    }

    // MARK: - Names

    func label(_ id: String) -> LabelItem? { labelsByID[id] }

    /// Lines of the same chord stack as `id`, itself included.
    func chord(of id: String) -> [LabelItem] {
        guard let label = labelsByID[id] else { return [] }
        return (labelsByPage[label.page] ?? []).filter { $0.group == label.group }
    }

    func selectChord(of id: String) {
        select(chord(of: id).map { SelectedItem(kind: .label, id: $0.id) })
    }

    func retypeLabel(_ id: String, _ raw: String) {
        guard let item = labelsByID[id], let now = store.doc else { return }
        // A scale degree typed while names read as numbers is stored as the
        // letter it means, like every other name.
        let typed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let numbered = notation == .numbers
            ? Jianpu.letter(fromNumbered: typed, fifths: Jianpu.fixedFifths, original: item.text)
            : nil
        let text = numbered ?? typed
        var edit = now.labels[id] ?? SheetEdits.LabelEdit()
        if text.isEmpty {
            edit.hidden = true
            store.update { $0.settingLabel(id, edit) }
            setNotice("Name hidden. Undo brings it back.")
            return
        }
        if text == (edit.text ?? item.text) { return }
        edit.text = text == item.text ? nil : text
        var corrections = now.corrections
        let message: String
        if let timeline {
            if let result = SheetEdits.correctionsForRetype(item, to: text, original: timeline, corrections: now.corrections) {
                if !result.linked {
                    message = "This name isn't linked to a note, so only the page changes."
                } else {
                    corrections = result.corrections
                    message = text == item.text
                        ? "Back to the printed name; playback restored."
                        : "Playback now plays \(typed)\(result.changed > 1 ? " for \(result.changed) notes" : "")."
                }
            } else {
                message = "\"\(typed)\" isn't a note name, so playback stays the same."
            }
        } else {
            message = "Playback isn't available for this sheet, so only the page changes."
        }
        store.update { d in
            var next = d.settingLabel(id, edit)
            next.corrections = corrections
            return next
        }
        setNotice(message)
    }

    /// Names back where and as they were printed, with their playback.
    func resetLabels(_ ids: [String]) {
        guard let now = store.doc else { return }
        var corrections = now.corrections
        if let timeline {
            for id in ids {
                guard let item = labelsByID[id] else { continue }
                corrections = SheetEdits.correctionsForRetype(item, to: item.text, original: timeline,
                                                              corrections: corrections)?.corrections ?? corrections
            }
        }
        store.update { d in
            var next = d
            for id in ids { next.labels[id] = nil }
            next.corrections = corrections
            return next
        }
    }

    /// The palette that fits what's selected: highlighter colours when it's
    /// only highlighting, the pen's otherwise — names included.
    var selectionPalette: [String] {
        let strokes = doc.strokes.filter { selection.contains(SelectedItem(kind: .stroke, id: $0.id)) }
        let onlyHighlights = !strokes.isEmpty && strokes.count == selection.count && strokes.allSatisfy { $0.tool == .highlighter }
        return onlyHighlights ? Self.highlightColors : [labels?.color ?? "#000000"] + Self.penColors.filter {
            $0.caseInsensitiveCompare(labels?.color ?? "#000000") != .orderedSame
        }
    }

    /// The colour everything selected already shares, if it does.
    var selectionColor: String? {
        let colors: [String] = selection.compactMap { item in
            switch item.kind {
            case .label: doc.labels[item.id]?.color ?? labels?.color ?? "#000000"
            case .text: doc.texts.first { $0.id == item.id }?.color
            case .stroke: doc.strokes.first { $0.id == item.id }?.color
            }
        }
        guard let first = colors.first, colors.allSatisfy({ $0.caseInsensitiveCompare(first) == .orderedSame }) else { return nil }
        return first
    }

    func recolorSelection(_ color: String) {
        guard !selection.isEmpty else { return }
        let items = selection
        let labelDefault = labels?.color ?? "#000000"
        store.update { $0.recoloring(items, to: color, labelDefault: labelDefault) }
    }

    /// Hides selected names; deletes selected marks and notes.
    func deleteSelection() {
        guard !selection.isEmpty else { return }
        let items = selection
        store.update { $0.removing(items) }
        selection = []
    }

    func reset(_ scope: ResetScope) {
        store.update { d in
            if scope == .everything { return .empty }
            var next = d
            next.labels = [:]
            next.corrections = [:]
            return next
        }
        selection = []
        let message = scope == .everything
            ? "Reset to the annotated version: your names, playback fixes, drawings and notes are removed."
            : "Note names and playback reset to the annotated version. Your drawings and notes are kept."
        setNotice(message)
        resetNotice = message
    }

    func undoReset() {
        store.undo()
        setNotice(nil)
    }

    var hasNameChanges: Bool { !doc.labels.isEmpty || !doc.corrections.isEmpty }
    var hasMarks: Bool { !doc.texts.isEmpty || !doc.strokes.isEmpty }
}
