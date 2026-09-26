import CoreGraphics
import Foundation

/// The note names of a sheet annotated before label export existed, read back
/// out of its annotated PDF. A port of the web app's readLabelsFromPdf and
/// linkByPosition (lib/labels.ts).
///
/// annotate.py draws every name twice at the same spot — a white outline, then
/// the fill — which nothing else on a score does, and that pairing is what
/// identifies them. PDFKit's own text extraction scrambles these tiny
/// overlapping runs, so this walks the page's content stream itself, keeping
/// just enough text state to know where each string starts.
///
/// Ids are built exactly as the web app builds them, from the same numbers,
/// so edits made to these names on one device find them on the other.
nonisolated enum PDFLabelReader {
    static func labels(in data: Data) -> [LabelItem] {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else { return [] }
        var items: [LabelItem] = []
        for number in 1...max(1, document.numberOfPages) {
            guard let page = document.page(at: number) else { continue }
            items += labels(on: page, number: number)
        }
        return items
    }

    private static func labels(on page: CGPDFPage, number: Int) -> [LabelItem] {
        let crop = page.getBoxRect(.cropBox)
        let runs = TextRunCollector.runs(on: page)
        var seen: [String: Int] = [:]
        var items: [LabelItem] = []
        for run in runs {
            let text = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, NoteNames.parse(text) != nil else { continue }
            // Top-down PDF points from the crop box's top-left — the space
            // bbox_pt uses, and pdf.js's viewport at scale 1.
            let x = run.origin.x - crop.minX
            let y = crop.maxY - run.origin.y
            let key = "\(text)@\(jsRound(x * 4)),\(jsRound(y * 4))"
            let count = (seen[key] ?? 0) + 1
            seen[key] = count
            guard count == 2 else { continue }
            let centre = x + run.width / 2
            let id = "pdf-\(number)-\(jsRound(centre * 10))-\(jsRound(y * 10))"
            items.append(LabelItem(id: id, group: id, page: number, x: centre, y: y,
                                   size: run.size, text: text, notes: []))
        }
        return items
    }

    /// Math.round: halves go up, not away from zero.
    static func jsRound(_ value: Double) -> Int {
        Int((value + 0.5).rounded(.down))
    }

    // MARK: - Linking to playback

    /// Ties labels read from a PDF to the timeline's notes by position: the
    /// nearest unclaimed notehead of the same pitch class just above or
    /// below. Approximate by nature — a label this can't place simply doesn't
    /// affect playback when retyped.
    static func linked(_ items: [LabelItem], to timeline: Timeline) -> [LabelItem] {
        struct Head { let page: Int; let cx: Double; let cy: Double; let pitchClass: Int; let id: String }
        var heads: [Head] = []
        var seenIDs: Set<String> = []
        for note in timeline.notes {
            guard let box = note.bboxPt, note.measureIndex >= 0, note.measureIndex < timeline.measures.count,
                  let page = timeline.measures[note.measureIndex].page,
                  let id = note.printedID ?? note.sourceID, !seenIDs.contains(id) else { continue }
            seenIDs.insert(id)
            heads.append(Head(page: page, cx: (box.x0 + box.x1) / 2, cy: (box.y0 + box.y1) / 2,
                              pitchClass: ((note.midi % 12) + 12) % 12, id: id))
        }
        var pairs: [(label: Int, head: Int, cost: Double)] = []
        for (i, label) in items.enumerated() {
            guard let spelled = NoteNames.parse(label.text) else { continue }
            let pitchClass = (((NoteNames.stepSemitones[spelled.step] + spelled.alter) % 12) + 12) % 12
            for (j, head) in heads.enumerated() where head.page == label.page && head.pitchClass == pitchClass {
                let dx = abs(head.cx - label.x)
                let dy = abs(head.cy - (label.y - label.size * 0.35))
                if dx > 16 || dy > 45 { continue }
                pairs.append((i, j, dx * 2 + dy))
            }
        }
        pairs.sort { $0.cost < $1.cost }
        var notes = items.map(\.notes)
        var claimed: Set<Int> = []
        for pair in pairs where notes[pair.label].isEmpty && !claimed.contains(pair.head) {
            notes[pair.label] = [heads[pair.head].id]
            claimed.insert(pair.head)
        }
        return zip(items, notes).map { item, ids in
            LabelItem(id: item.id, group: item.group, page: item.page, x: item.x, y: item.y,
                      size: item.size, text: item.text, notes: ids)
        }
    }
}

/// One shown string: where it starts, how big, how wide.
nonisolated struct TextRun {
    let text: String
    /// In default user space (PDF points, bottom-up).
    let origin: CGPoint
    let size: Double
    let width: Double
}

/// A minimal PDF text-state machine over CGPDFScanner: the graphics state's
/// transform, the text matrices, the font and its size. Enough to place a
/// string that starts a text object — which is how the labels are written —
/// not a general text extractor.
nonisolated private final class TextRunCollector {
    private var ctm = CGAffineTransform.identity
    private var stack: [(CGAffineTransform, PDFFont?, Double, Double)] = []
    private var textMatrix = CGAffineTransform.identity
    private var lineMatrix = CGAffineTransform.identity
    private var font: PDFFont?
    private var fontSize = 0.0
    private var leading = 0.0
    private var runs: [TextRun] = []
    private let fonts: CGPDFDictionaryRef?
    private var fontCache: [String: PDFFont] = [:]

    private init(page: CGPDFPage) {
        fonts = Self.fontDictionary(of: page)
    }

    static func runs(on page: CGPDFPage) -> [TextRun] {
        let state = TextRunCollector(page: page)
        guard let table = CGPDFOperatorTableCreate() else { return [] }
        func on(_ name: String, _ callback: @escaping CGPDFOperatorCallback) {
            CGPDFOperatorTableSetCallback(table, name, callback)
        }
        on("q") { _, info in TextRunCollector.from(info).save() }
        on("Q") { _, info in TextRunCollector.from(info).restore() }
        on("cm") { scanner, info in
            guard let m = TextRunCollector.popMatrix(scanner) else { return }
            let c = TextRunCollector.from(info)
            c.ctm = m.concatenating(c.ctm)
        }
        on("BT") { _, info in
            let c = TextRunCollector.from(info)
            c.textMatrix = .identity
            c.lineMatrix = .identity
        }
        on("Tf") { scanner, info in
            var size: CGPDFReal = 0
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopNumber(scanner, &size), CGPDFScannerPopName(scanner, &name), let name else { return }
            let c = TextRunCollector.from(info)
            c.fontSize = Double(size)
            c.font = c.loadFont(String(cString: name))
        }
        on("TL") { scanner, info in
            var value: CGPDFReal = 0
            if CGPDFScannerPopNumber(scanner, &value) { TextRunCollector.from(info).leading = Double(value) }
        }
        on("Tm") { scanner, info in
            guard let m = TextRunCollector.popMatrix(scanner) else { return }
            let c = TextRunCollector.from(info)
            c.textMatrix = m
            c.lineMatrix = m
        }
        on("Td") { scanner, info in
            guard let (tx, ty) = TextRunCollector.popPair(scanner) else { return }
            TextRunCollector.from(info).moveLine(tx, ty)
        }
        on("TD") { scanner, info in
            guard let (tx, ty) = TextRunCollector.popPair(scanner) else { return }
            let c = TextRunCollector.from(info)
            c.leading = -ty
            c.moveLine(tx, ty)
        }
        on("T*") { _, info in
            let c = TextRunCollector.from(info)
            c.moveLine(0, -c.leading)
        }
        on("Tj") { scanner, info in
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string else { return }
            TextRunCollector.from(info).show([string])
        }
        on("TJ") { scanner, info in
            var array: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &array), let array else { return }
            var strings: [CGPDFStringRef] = []
            for i in 0..<CGPDFArrayGetCount(array) {
                var string: CGPDFStringRef?
                if CGPDFArrayGetString(array, i, &string), let string { strings.append(string) }
            }
            TextRunCollector.from(info).show(strings)
        }
        let stream = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(state).toOpaque())
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(stream)
        CGPDFOperatorTableRelease(table)
        return state.runs
    }

    private static func from(_ info: UnsafeMutableRawPointer?) -> TextRunCollector {
        Unmanaged<TextRunCollector>.fromOpaque(info!).takeUnretainedValue()
    }

    private static func popPair(_ scanner: CGPDFScannerRef) -> (Double, Double)? {
        var ty: CGPDFReal = 0, tx: CGPDFReal = 0
        guard CGPDFScannerPopNumber(scanner, &ty), CGPDFScannerPopNumber(scanner, &tx) else { return nil }
        return (Double(tx), Double(ty))
    }

    private static func popMatrix(_ scanner: CGPDFScannerRef) -> CGAffineTransform? {
        var v = [CGPDFReal](repeating: 0, count: 6)
        for i in (0..<6).reversed() {
            guard CGPDFScannerPopNumber(scanner, &v[i]) else { return nil }
        }
        return CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
    }

    private func save() { stack.append((ctm, font, fontSize, leading)) }

    private func restore() {
        guard let saved = stack.popLast() else { return }
        (ctm, font, fontSize, leading) = saved
    }

    private func moveLine(_ tx: Double, _ ty: Double) {
        lineMatrix = CGAffineTransform(translationX: tx, y: ty).concatenating(lineMatrix)
        textMatrix = lineMatrix
    }

    private func show(_ strings: [CGPDFStringRef]) {
        guard let font else { return }
        var text = ""
        var advance = 0.0
        for string in strings {
            guard let bytes = CGPDFStringGetBytePtr(string) else { continue }
            let data = Data(bytes: bytes, count: CGPDFStringGetLength(string))
            let (decoded, width) = font.decode(data)
            text += decoded
            advance += width
        }
        let m = textMatrix.concatenating(ctm)
        let scale = Double(hypot(m.a, m.b))
        runs.append(TextRun(text: text, origin: CGPoint(x: m.tx, y: m.ty), size: fontSize * scale,
                            width: advance / 1000 * fontSize * scale))
        // The next string continues where this one ended.
        textMatrix = CGAffineTransform(translationX: advance / 1000 * fontSize, y: 0).concatenating(textMatrix)
    }

    private func loadFont(_ name: String) -> PDFFont? {
        if let cached = fontCache[name] { return cached }
        var dictionary: CGPDFDictionaryRef?
        guard let fonts, CGPDFDictionaryGetDictionary(fonts, name, &dictionary), let dictionary else { return nil }
        let font = PDFFont(dictionary)
        fontCache[name] = font
        return font
    }

    /// /Resources /Font, which a page may inherit from its parents.
    private static func fontDictionary(of page: CGPDFPage) -> CGPDFDictionaryRef? {
        var node = page.dictionary
        while let current = node {
            var resources: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(current, "Resources", &resources), let resources {
                var fonts: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(resources, "Font", &fonts) { return fonts }
            }
            var parent: CGPDFDictionaryRef?
            node = CGPDFDictionaryGetDictionary(current, "Parent", &parent) ? parent : nil
        }
        return nil
    }
}

/// What a string's bytes say, and how far they advance: a font's ToUnicode
/// map and glyph widths (in thousandths of the font size).
nonisolated private struct PDFFont {
    private let twoByte: Bool
    private var unicode: [UInt32: String] = [:]
    private var widths: [UInt32: Double] = [:]
    private var defaultWidth = 0.0

    init(_ font: CGPDFDictionaryRef) {
        var subtype: UnsafePointer<CChar>?
        CGPDFDictionaryGetName(font, "Subtype", &subtype)
        twoByte = subtype.map { String(cString: $0) } == "Type0"

        var toUnicode: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(font, "ToUnicode", &toUnicode), let toUnicode,
           let data = Self.streamData(toUnicode) {
            unicode = Self.parseCMap(String(decoding: data, as: UTF8.self))
        }

        if twoByte {
            defaultWidth = 1000
            var descendants: CGPDFArrayRef?
            var descendant: CGPDFDictionaryRef?
            if CGPDFDictionaryGetArray(font, "DescendantFonts", &descendants), let descendants,
               CGPDFArrayGetDictionary(descendants, 0, &descendant), let descendant {
                var dw: CGPDFReal = 0
                if CGPDFDictionaryGetNumber(descendant, "DW", &dw) { defaultWidth = Double(dw) }
                var w: CGPDFArrayRef?
                if CGPDFDictionaryGetArray(descendant, "W", &w), let w { widths = Self.parseCIDWidths(w) }
            }
        } else {
            var first: CGPDFInteger = 0
            var w: CGPDFArrayRef?
            if CGPDFDictionaryGetInteger(font, "FirstChar", &first),
               CGPDFDictionaryGetArray(font, "Widths", &w), let w {
                for i in 0..<CGPDFArrayGetCount(w) {
                    var value: CGPDFReal = 0
                    if CGPDFArrayGetNumber(w, i, &value) { widths[UInt32(first + i)] = Double(value) }
                }
            }
        }
    }

    private static func streamData(_ stream: CGPDFStreamRef) -> Data? {
        var format = CGPDFDataFormat.raw
        return CGPDFStreamCopyData(stream, &format) as Data?
    }

    func decode(_ bytes: Data) -> (String, Double) {
        var codes: [UInt32] = []
        if twoByte {
            var i = bytes.startIndex
            while i + 1 < bytes.endIndex {
                codes.append(UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1]))
                i += 2
            }
        } else {
            codes = bytes.map(UInt32.init)
        }
        var text = ""
        var advance = 0.0
        for code in codes {
            text += unicode[code] ?? (twoByte ? "" : String(UnicodeScalar(UInt8(truncatingIfNeeded: code))))
            advance += widths[code] ?? defaultWidth
        }
        return (text, advance)
    }

    /// bfchar and bfrange entries of a ToUnicode CMap.
    private static func parseCMap(_ source: String) -> [UInt32: String] {
        var map: [UInt32: String] = [:]
        func hex(_ s: Substring) -> UInt32? { UInt32(s, radix: 16) }
        func utf16(_ s: Substring) -> String {
            var units: [UInt16] = []
            var index = s.startIndex
            while let end = s.index(index, offsetBy: 4, limitedBy: s.endIndex), index < s.endIndex {
                if let unit = UInt16(s[index..<end], radix: 16) { units.append(unit) }
                index = end
            }
            return String(decoding: units, as: UTF16.self)
        }
        for section in sections(source, "beginbfchar", "endbfchar") {
            let t = hexTokens(section)
            stride(from: 0, to: t.count - 1, by: 2).forEach { i in
                if let code = hex(t[i]) { map[code] = utf16(t[i + 1]) }
            }
        }
        for section in sections(source, "beginbfrange", "endbfrange") {
            let t = hexTokens(section)
            stride(from: 0, to: t.count - 2, by: 3).forEach { i in
                guard let low = hex(t[i]), let high = hex(t[i + 1]), let base = hex(t[i + 2]), high >= low,
                      high - low < 65536 else { return }
                for code in low...high {
                    if let scalar = UnicodeScalar(base + (code - low)) { map[code] = String(Character(scalar)) }
                }
            }
        }
        return map
    }

    private static func sections(_ source: String, _ begin: String, _ end: String) -> [Substring] {
        var out: [Substring] = []
        var rest = source[...]
        while let start = rest.range(of: begin), let stop = rest.range(of: end, range: start.upperBound..<rest.endIndex) {
            out.append(rest[start.upperBound..<stop.lowerBound])
            rest = rest[stop.upperBound...]
        }
        return out
    }

    private static func hexTokens(_ source: some StringProtocol) -> [Substring] {
        var tokens: [Substring] = []
        let text = Substring(source)
        var index = text.startIndex
        while let open = text[index...].firstIndex(of: "<"), let close = text[open...].firstIndex(of: ">") {
            tokens.append(text[text.index(after: open)..<close])
            index = text.index(after: close)
        }
        return tokens
    }

    /// /W: `c [w1 w2 ...]` or `c_first c_last w`.
    private static func parseCIDWidths(_ array: CGPDFArrayRef) -> [UInt32: Double] {
        var widths: [UInt32: Double] = [:]
        var i = 0
        let count = CGPDFArrayGetCount(array)
        while i < count {
            var first: CGPDFInteger = 0
            guard CGPDFArrayGetInteger(array, i, &first) else { break }
            var list: CGPDFArrayRef?
            if CGPDFArrayGetArray(array, i + 1, &list), let list {
                for j in 0..<CGPDFArrayGetCount(list) {
                    var value: CGPDFReal = 0
                    if CGPDFArrayGetNumber(list, j, &value) { widths[UInt32(first + j)] = Double(value) }
                }
                i += 2
            } else {
                var last: CGPDFInteger = 0
                var value: CGPDFReal = 0
                guard CGPDFArrayGetInteger(array, i + 1, &last), CGPDFArrayGetNumber(array, i + 2, &value),
                      last >= first, last - first < 65536 else { break }
                for code in first...last { widths[UInt32(code)] = Double(value) }
                i += 3
            }
        }
        return widths
    }
}
