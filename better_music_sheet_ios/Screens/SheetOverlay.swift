import CoreText
import PDFKit
import SwiftUI
import UIKit

/// Everything drawn over one page of the sheet: the note names, the reader's
/// freehand marks and their text notes — plus, while editing, what is
/// selected and what is being drawn. A value, so the page view can tell when
/// it has actually changed.
struct SheetOverlayContent: Equatable {
    var labelsByPage: [Int: [LabelItem]] = [:]
    var labelColor = "#000000"
    var showsNames = false
    var edits: SheetEdits = .empty
    var editing = false
    var selection: Set<SelectedItem> = []
    var draft: SheetEditorModel.DraftStroke?
    var marquee: SheetEditorModel.Marquee?

    var isBlank: Bool { !showsNames && edits.texts.isEmpty && edits.strokes.isEmpty && draft == nil && marquee == nil }

    @MainActor
    init(editor: SheetEditorModel, showsNames: Bool) {
        labelsByPage = editor.labelsByPage
        labelColor = editor.labels?.color ?? "#000000"
        self.showsNames = showsNames && editor.namesLive
        edits = editor.doc
        editing = editor.isEditing
        selection = Set(editor.selection)
        draft = editor.draft
        marquee = editor.marquee
    }

    /// Read-only: practice mode shows the names and marks but never edits.
    init(labels: LabelSet?, edits: SheetEdits, showsNames: Bool) {
        labelsByPage = Dictionary(grouping: labels?.items ?? [], by: \.page)
        labelColor = labels?.color ?? "#000000"
        self.showsNames = showsNames && labels != nil
        self.edits = edits
    }
}

/// Draws a SheetOverlayContent into a context already set up in one page's
/// PDF points, top-down. Shared by the page overlay and the Customized PDF,
/// so the export looks like the preview.
enum SheetOverlayRenderer {
    static func draw(_ content: SheetOverlayContent, page: Int, in ctx: CGContext) {
        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }

        let strokes = content.edits.strokes.filter { $0.page == page }
        for stroke in strokes where stroke.tool == .highlighter {
            draw(stroke, selected: content.selection.contains(SelectedItem(kind: .stroke, id: stroke.id)), in: ctx)
        }

        if content.showsNames {
            let color = UIColor(hex: content.labelColor)
            for item in content.labelsByPage[page] ?? [] {
                guard let label = content.edits.resolve(item) else { continue }
                if content.editing {
                    let selected = content.selection.contains(SelectedItem(kind: .label, id: label.id))
                    let box = SheetEditorModel.labelBox(label)
                    if selected {
                        fill(box, UIColor(Brand.accent).withAlphaComponent(0.1), in: ctx)
                        outline(box, UIColor(Brand.accent), width: 0.5, in: ctx)
                    } else if label.edited {
                        fill(box, UIColor(Brand.gold).withAlphaComponent(0.2), in: ctx)
                    }
                }
                drawLabel(label, color: label.color.map { UIColor(hex: $0) } ?? color)
            }
        }

        for stroke in strokes where stroke.tool == .pen {
            draw(stroke, selected: content.selection.contains(SelectedItem(kind: .stroke, id: stroke.id)), in: ctx)
        }

        for note in content.edits.texts where note.page == page {
            if content.editing, content.selection.contains(SelectedItem(kind: .text, id: note.id)) {
                let box = SheetEditorModel.textBox(note)
                fill(box, UIColor(Brand.accent).withAlphaComponent(0.08), in: ctx)
                outline(box, UIColor(Brand.accent), width: 0.5, in: ctx)
            }
            drawText(note)
        }

        if let draft = content.draft, draft.page == page {
            draw(SheetEdits.Stroke(id: "draft", page: page, tool: draft.tool, color: draft.color,
                                   width: draft.width, points: draft.points), selected: false, in: ctx)
        }

        if let marquee = content.marquee, marquee.page == page {
            fill(marquee.rect, UIColor(Brand.accent).withAlphaComponent(0.06), in: ctx)
            ctx.saveGState()
            ctx.setLineDash(phase: 0, lengths: [2, 1.5])
            outline(marquee.rect, UIColor(Brand.accent), width: 0.6, in: ctx)
            ctx.restoreGState()
        }
    }

    // MARK: - Pieces

    private static func path(_ points: [Double]) -> CGPath {
        let path = CGMutablePath()
        for segment in Ink.segments(points) {
            switch segment {
            case .move(let x, let y): path.move(to: CGPoint(x: x, y: y))
            case .line(let x, let y): path.addLine(to: CGPoint(x: x, y: y))
            case .quad(let cx, let cy, let x, let y): path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
            }
        }
        return path
    }

    private static func draw(_ stroke: SheetEdits.Stroke, selected: Bool, in ctx: CGContext) {
        let shape = path(stroke.points)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if selected {
            ctx.addPath(shape)
            ctx.setStrokeColor(UIColor(Brand.accent).withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(stroke.width + 2.4)
            ctx.strokePath()
        }
        ctx.addPath(shape)
        if stroke.tool == .highlighter {
            // Multiply, like a real highlighter: the notes stay black under it.
            ctx.setBlendMode(.multiply)
            ctx.setStrokeColor(UIColor(hex: stroke.color).withAlphaComponent(0.4).cgColor)
        } else {
            ctx.setStrokeColor(UIColor(hex: stroke.color).cgColor)
        }
        ctx.setLineWidth(stroke.width)
        ctx.strokePath()
    }

    /// Centred on x with its baseline on y, in a white outline under the
    /// fill — as annotate.py prints them, so a name stays readable where it
    /// crosses a staff line.
    private static func drawLabel(_ label: ResolvedLabel, color: UIColor) {
        let font = LabelFont.font(size: label.size)
        let text = LabelFont.printable(label.text)
        let outline = NSAttributedString(string: text, attributes: [
            .font: font, .strokeColor: UIColor.white,
            // Percent of the font size; centred on the glyph edge.
            .strokeWidth: 16,
        ])
        let fill = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let width = fill.size().width
        let origin = CGPoint(x: label.x - width / 2, y: label.y - font.ascender)
        outline.draw(at: origin)
        fill.draw(at: origin)
    }

    private static func drawText(_ note: SheetEdits.TextNote) {
        let font = UIFont.systemFont(ofSize: note.size)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(hex: note.color)]
        for (i, line) in note.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let baseline = note.y + Double(i) * note.size * 1.2
            NSAttributedString(string: String(line), attributes: attributes)
                .draw(at: CGPoint(x: note.x, y: baseline - font.ascender))
        }
    }

    private static func fill(_ rect: CGRect, _ color: UIColor, in ctx: CGContext) {
        ctx.setFillColor(color.cgColor)
        ctx.fill(rect)
    }

    private static func outline(_ rect: CGRect, _ color: UIColor, width: CGFloat, in ctx: CGContext) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.stroke(rect)
    }
}

/// The font the names are printed in: the same DejaVu Sans subset the web
/// app and the backend use, bundled so a retyped ♭ looks like a printed one.
enum LabelFont {
    private static let descriptor: UIFontDescriptor? = {
        guard let url = Bundle.main.url(forResource: "DejaVuSans-labels", withExtension: "ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first else { return nil }
        return first as UIFontDescriptor
    }()

    static func font(size: Double) -> UIFont {
        descriptor.map { UIFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
    }

    /// The bundled subset has ♭ ♮ ♯ but not the double accidentals, which
    /// are written as two glyphs instead (as the web app's export does).
    static func printable(_ text: String) -> String {
        text.replacingOccurrences(of: "𝄫", with: "♭♭").replacingOccurrences(of: "𝄪", with: "×")
    }
}

/// One page's overlay inside the PDF view, laid over the page by PDFKit
/// (PDFPageOverlayViewProvider) so it follows every scroll and zoom.
final class SheetOverlayView: UIView {
    let pageNumber: Int
    private let pageSize: CGSize
    private let playheadLayer = CAShapeLayer()

    var content: SheetOverlayContent? {
        didSet { if content != oldValue { setNeedsDisplay() } }
    }

    /// Practice mode's playhead: a light red dashed line over the notes and
    /// names. Its own layer, so moving it never redraws the page's names.
    var playhead: PlayheadOnset? {
        didSet { if playhead != oldValue { layoutPlayhead() } }
    }

    init(pageNumber: Int, pageSize: CGSize) {
        self.pageNumber = pageNumber
        self.pageSize = pageSize
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        // Touches go to the PDF view, which converts them into page space.
        isUserInteractionEnabled = false
        contentMode = .redraw
        playheadLayer.fillColor = nil
        playheadLayer.strokeColor = UIColor(red: 1, green: 0.42, blue: 0.42, alpha: 0.85).cgColor
        playheadLayer.lineCap = .butt
        layer.addSublayer(playheadLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutPlayhead()
    }

    private func layoutPlayhead() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        playheadLayer.frame = bounds
        guard let playhead, playhead.page == pageNumber, bounds.width > 0, pageSize.width > 0 else {
            playheadLayer.path = nil
            return
        }
        // Page points to this view's points; the 2pt dashes of the web app's
        // `.playhead` rule, in page points so they scale with the sheet.
        let scale = bounds.width / pageSize.width
        let path = CGMutablePath()
        path.move(to: CGPoint(x: playhead.x * scale, y: playhead.y0 * scale))
        path.addLine(to: CGPoint(x: playhead.x * scale, y: playhead.y1 * scale))
        playheadLayer.path = path
        playheadLayer.lineWidth = 2 * scale
        playheadLayer.lineDashPattern = [NSNumber(value: 5 * scale), NSNumber(value: 4 * scale)]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Re-rasterized at the zoom it is shown at, so names stay crisp when
    /// zoomed in — within a pixel budget, since a page at 4× on a 3× screen
    /// would otherwise need a bitmap of several hundred megabytes.
    func matchScale(pointsPerPDFPoint: CGFloat, screenScale: CGFloat) {
        guard bounds.width > 0, pageSize.width > 0 else { return }
        let base = bounds.width / pageSize.width
        var scale = screenScale * max(1, pointsPerPDFPoint / base)
        let pixels = bounds.width * bounds.height * scale * scale
        let budget: CGFloat = 16_000_000
        if pixels > budget { scale *= (budget / pixels).squareRoot() }
        scale = max(screenScale, scale)
        if abs(contentScaleFactor - scale) > 0.05 {
            contentScaleFactor = scale
            playheadLayer.contentsScale = scale
        }
    }

    override func draw(_ rect: CGRect) {
        guard let content, !content.isBlank, let ctx = UIGraphicsGetCurrentContext(),
              pageSize.width > 0, pageSize.height > 0 else { return }
        ctx.scaleBy(x: bounds.width / pageSize.width, y: bounds.height / pageSize.height)
        SheetOverlayRenderer.draw(content, page: pageNumber, in: ctx)
    }
}

/// The Customized download: the sheet as the preview shows it, names and
/// marks drawn as vector text and paths into a new PDF.
enum SheetExport {
    static func customizedPDF(base: Data, content: SheetOverlayContent) -> Data? {
        guard let document = PDFDocument(data: base), document.pageCount > 0 else { return nil }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let crop = page.bounds(for: .cropBox)
                context.beginPage(withBounds: CGRect(origin: .zero, size: crop.size), pageInfo: [:])
                let ctx = context.cgContext
                ctx.saveGState()
                // PDFKit draws bottom-up; the renderer's context is top-down.
                ctx.translateBy(x: 0, y: crop.height)
                ctx.scaleBy(x: 1, y: -1)
                page.draw(with: .cropBox, to: ctx)
                ctx.restoreGState()
                var printed = content
                printed.editing = false
                printed.selection = []
                printed.draft = nil
                printed.marquee = nil
                SheetOverlayRenderer.draw(printed, page: index + 1, in: ctx)
            }
        }
    }
}

extension UIColor {
    /// From "#RRGGBB"; black if it isn't one.
    convenience init(hex: String) {
        let value = SheetEdits.isColor(hex) ? UInt32(hex.dropFirst(), radix: 16) ?? 0 : 0
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
