import PDFKit
import SwiftUI

/// The annotated page, with the measure being played outlined and a playhead
/// drawn over it.
///
/// Both marks are PDF annotations placed in the page's own coordinate space,
/// so PDFKit keeps them attached to the engraving through every scroll and
/// zoom with no tracking code here.
struct SheetPDFView: UIViewRepresentable {
    let data: Data
    var highlightedMeasure: TimelineMeasure? = nil
    var playhead: PlayheadOnset? = nil
    /// A tap on the page, in the page's top-down point space, with its 1-based
    /// page number. Nil on the reading page, where a tap does nothing.
    var onTap: (@MainActor (CGPoint, Int) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.usePageViewController(false)
        view.backgroundColor = UIColor(Brand.paper)
        // Loaded once. Comparing documents on every update would re-serialize
        // the whole PDF thirty times a second while playing.
        view.document = PDFDocument(data: data)
        context.coordinator.loadedData = data

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped(_:)))
        // PDFKit's own double-tap zoom wins, so zooming doesn't also start
        // playback from wherever the first tap landed.
        for recognizer in Self.doubleTapRecognizers(in: view) {
            tap.require(toFail: recognizer)
        }
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        // This view is also used to compare the annotated PDF with the
        // uploaded original. UIViewRepresentable retains its PDFView when
        // `data` changes, so replace the document explicitly.
        if context.coordinator.loadedData != data {
            context.coordinator.loadedData = data
            view.document = PDFDocument(data: data)
            context.coordinator.clearMarks()
        }
        context.coordinator.onTap = onTap
        context.coordinator.show(measure: highlightedMeasure, playhead: playhead)
    }

    private static func doubleTapRecognizers(in view: UIView) -> [UIGestureRecognizer] {
        let own = (view.gestureRecognizers ?? []).filter {
            ($0 as? UITapGestureRecognizer)?.numberOfTapsRequired == 2
        }
        return own + view.subviews.flatMap { doubleTapRecognizers(in: $0) }
    }

    final class Coordinator: NSObject {
        weak var view: PDFView?
        var onTap: (@MainActor (CGPoint, Int) -> Void)?
        var loadedData: Data?

        private var measureMark: PDFAnnotation?
        private var playheadMarks: [PDFAnnotation] = []
        private var shownMeasure: TimelineMeasure?
        private var shownPlayhead: PlayheadOnset?

        func clearMarks() {
            measureMark = nil
            playheadMark = nil
            shownMeasure = nil
            shownPlayhead = nil
        }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let view, let document = view.document else { return }
            let location = recognizer.location(in: view)
            guard let page = view.page(for: location, nearest: false) else { return }
            let crop = page.bounds(for: .cropBox)
            let inPage = view.convert(location, to: page)
            // PDFKit's page space is bottom-up; the timeline's is top-down.
            let topDown = CGPoint(x: inPage.x - crop.minX, y: crop.maxY - inPage.y)
            onTap?(topDown, document.index(for: page) + 1)
        }

        func show(measure: TimelineMeasure?, playhead: PlayheadOnset?) {
            guard let view, let document = view.document else { return }

            if measure != shownMeasure {
                shownMeasure = measure
                if let old = measureMark {
                    old.page?.removeAnnotation(old)
                    measureMark = nil
                }
                if let measure, let box = measure.bboxPt, let number = measure.page,
                   let page = document.page(at: number - 1) {
                    let rect = Self.pageRect(for: box, on: page)
                    let mark = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
                    mark.color = UIColor(Brand.accent)
                    mark.interiorColor = UIColor(Brand.accent).withAlphaComponent(0.16)
                    let border = PDFBorder()
                    border.lineWidth = 1
                    mark.border = border
                    page.addAnnotation(mark)
                    measureMark = mark
                    Self.reveal(rect, on: page, in: view)
                }
            }

            if playhead != shownPlayhead {
                shownPlayhead = playhead
                for old in playheadMarks {
                    old.page?.removeAnnotation(old)
                }
                playheadMarks = []
                if let playhead, let page = document.page(at: playhead.page - 1) {
                    let crop = page.bounds(for: .cropBox)
                    let x = crop.minX + playhead.x
                    let bottom = crop.minY + crop.height - playhead.y1
                    let top = crop.minY + crop.height - playhead.y0
                    // Matches the web app's `.playhead` rule in globals.css: a 2px
                    // dashed border-left in the accent colour. Built from filled
                    // segments, like the measure box, rather than a PDFKit Line
                    // annotation — Line annotations don't reliably get an
                    // appearance stream generated on iOS.
                    playheadMarks = Self.dashSegments(x: x, bottom: bottom, top: top)
                        .map { segment in
                            let mark = PDFAnnotation(bounds: segment, forType: .square, withProperties: nil)
                            mark.color = .clear
                            mark.interiorColor = UIColor(Brand.accent)
                            let border = PDFBorder()
                            border.lineWidth = 0
                            mark.border = border
                            return mark
                        }
                    for mark in playheadMarks {
                        page.addAnnotation(mark)
                    }
                }
            }
        }

        /// Rects for a vertical dashed line's filled segments, in the page's
        /// bottom-up space, spanning from `bottom` up to `top` at `x`.
        private static func dashSegments(x: CGFloat, bottom: CGFloat, top: CGFloat) -> [CGRect] {
            let width: CGFloat = 2
            let dash: CGFloat = 5
            let gap: CGFloat = 4
            var segments: [CGRect] = []
            var y = bottom
            while y < top {
                let height = min(dash, top - y)
                segments.append(CGRect(x: x - width / 2, y: y, width: width, height: height))
                y += dash + gap
            }
            return segments
        }

        /// The timeline's top-down box in this page's bottom-up space,
        /// allowing for a crop box that doesn't start at the origin.
        private static func pageRect(for box: BBoxPoints, on page: PDFPage) -> CGRect {
            let crop = page.bounds(for: .cropBox)
            return SheetGeometry.pdfRect(for: box, pageHeight: crop.height)
                .offsetBy(dx: crop.minX, dy: crop.minY)
        }

        /// Scrolls only when the measure isn't already fully in view, so
        /// playback doesn't yank the page around on every bar.
        private static func reveal(_ rect: CGRect, on page: PDFPage, in view: PDFView) {
            let onScreen = view.convert(rect, from: page)
            guard !view.bounds.contains(onScreen) else { return }
            view.go(to: rect.insetBy(dx: 0, dy: -40), on: page)
        }
    }
}
