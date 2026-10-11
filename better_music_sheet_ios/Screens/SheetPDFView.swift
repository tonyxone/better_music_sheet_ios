import PDFKit
import SwiftUI

/// How the reading page lays a sheet out: every page down one column, or one
/// at a time, turned with a flick. The web app's page_mode.
enum SheetPageMode: String, CaseIterable, Identifiable {
    case scroll, swipe

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

/// Which page a sheet is showing, and a way to turn it from outside the page:
/// the link between the pager buttons and the PDF view.
@Observable
final class SheetPager {
    private(set) var page = 1
    private(set) var count = 1
    @ObservationIgnored fileprivate var onTurn: ((Int) -> Void)?

    func turn(by delta: Int) { onTurn?(delta) }

    fileprivate func report(page: Int, count: Int) {
        if self.page != page { self.page = page }
        if self.count != count { self.count = count }
    }
}

/// The sheet, with the measure being played outlined and a playhead drawn
/// over it, and the note names and the reader's own marks on top.
///
/// The measure outline is a PDF annotation placed in the page's own
/// coordinate space, so PDFKit keeps it attached to the engraving through
/// every scroll and zoom with no tracking code here. The names, the reader's
/// marks and the playhead are drawn by a per-page overlay view (see
/// SheetOverlay.swift), which PDFKit also keeps over its page — the playhead
/// on top of everything, so notes and names never hide it.
///
/// With an `editor`, touches go to it while it is editing: a tap selects or
/// places, one finger draws or drags what it lands on, touch-and-hold on empty
/// space drags out a selection box, and two fingers still scroll and zoom.
struct SheetPDFView: UIViewRepresentable {
    let data: Data
    var highlightedMeasure: TimelineMeasure? = nil
    var playhead: PlayheadOnset? = nil
    /// The names and marks to draw over each page.
    var overlay: SheetOverlayContent? = nil
    var editor: SheetEditorModel? = nil
    var pageMode: SheetPageMode = .scroll
    /// Told which page is showing, and asked to turn it.
    var pager: SheetPager? = nil
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
        // Before the document: PDFKit asks for overlays as pages load.
        view.pageOverlayViewProvider = context.coordinator
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
        context.coordinator.installEditingGestures(on: view)
        context.coordinator.installPageTurning(on: view)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scaleChanged),
                                               name: .PDFViewScaleChanged, object: view)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged),
                                               name: .PDFViewPageChanged, object: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        // This view is also used to compare the annotated PDF with the
        // uploaded original. UIViewRepresentable retains its PDFView when
        // `data` changes, so replace the document explicitly.
        if context.coordinator.loadedData != data {
            context.coordinator.loadedData = data
            // One page at a time, the other copy opens on the page being read.
            let reading = context.coordinator.isSwiping
                ? view.currentPage.flatMap { view.document?.index(for: $0) } : nil
            let document = PDFDocument(data: data)
            view.document = document
            if let reading, let document, reading < document.pageCount, let page = document.page(at: reading) {
                view.go(to: page)
            }
            context.coordinator.clearMarks()
            context.coordinator.pageChanged()
        }
        context.coordinator.onTap = onTap
        context.coordinator.editor = editor
        context.coordinator.setEditing(editor?.isEditing == true)
        context.coordinator.pager = pager
        context.coordinator.setPageMode(pageMode)
        context.coordinator.overlay = overlay
        context.coordinator.show(measure: highlightedMeasure, playhead: playhead)
    }

    private static func doubleTapRecognizers(in view: UIView) -> [UIGestureRecognizer] {
        let own = (view.gestureRecognizers ?? []).filter {
            ($0 as? UITapGestureRecognizer)?.numberOfTapsRequired == 2
        }
        return own + view.subviews.flatMap { doubleTapRecognizers(in: $0) }
    }

    final class Coordinator: NSObject, PDFPageOverlayViewProvider, UIGestureRecognizerDelegate {
        weak var view: PDFView?
        var onTap: (@MainActor (CGPoint, Int) -> Void)?
        var loadedData: Data?
        var editor: SheetEditorModel?
        var overlay: SheetOverlayContent? {
            didSet {
                guard overlay != oldValue else { return }
                for view in overlays.values { view.content = overlay }
            }
        }

        private var overlays: [Int: SheetOverlayView] = [:]
        private var pan: UIPanGestureRecognizer?
        private var hold: UILongPressGestureRecognizer?
        /// Where the current touch came down, before a recognizer's own
        /// movement threshold moved it on.
        private var touchStart: CGPoint?
        /// The page a drag started on; its points stay in that page's space
        /// even if the finger wanders onto the next.
        private var gesturePage: PDFPage?
        private var editing = false

        var pager: SheetPager? {
            didSet {
                guard pager !== oldValue else { return }
                oldValue?.onTurn = nil
                pager?.onTurn = { [weak self] delta in self?.turnPage(by: delta) }
                pageChanged()
            }
        }
        /// One page at a time. False for a one-page sheet, which has nothing
        /// to turn to.
        private(set) var isSwiping = false
        private var swipes: [UISwipeGestureRecognizer] = []
        /// How far across the sheet was scrolled when the current touch came
        /// down.
        private var swipeStartOffset: CGFloat?
        private var backSwipeYields = false

        private var measureMark: PDFAnnotation?
        private var shownMeasure: TimelineMeasure?
        private var shownPlayhead: PlayheadOnset?

        func clearMarks() {
            measureMark = nil
            shownMeasure = nil
            shownPlayhead = nil
        }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let view, let document = view.document else { return }
            let location = recognizer.location(in: view)
            if editing, let editor {
                guard let page = view.page(for: location, nearest: true) else { return }
                editor.tap(at: topDown(location, on: page), page: document.index(for: page) + 1,
                           pxPerPt: view.scaleFactor)
                return
            }
            guard let page = view.page(for: location, nearest: false) else { return }
            onTap?(topDown(location, on: page), document.index(for: page) + 1)
        }

        /// A point in the view, in `page`'s top-down PDF points. PDFKit's page
        /// space is bottom-up; the timeline's and the edits' are top-down.
        private func topDown(_ location: CGPoint, on page: PDFPage) -> CGPoint {
            guard let view else { return .zero }
            let crop = page.bounds(for: .cropBox)
            let inPage = view.convert(location, to: page)
            return CGPoint(x: inPage.x - crop.minX, y: crop.maxY - inPage.y)
        }

        private func pageNumber(_ page: PDFPage) -> Int {
            (view?.document?.index(for: page) ?? 0) + 1
        }

        // MARK: Overlays

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            let number = (view.document?.index(for: page) ?? 0) + 1
            let overlay = SheetOverlayView(pageNumber: number, pageSize: page.bounds(for: .cropBox).size)
            overlay.content = self.overlay
            overlay.playhead = shownPlayhead
            overlays[number] = overlay
            return overlay
        }

        func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
            // Laid out only after this returns; match the current zoom then.
            DispatchQueue.main.async { [weak self] in self?.scaleChanged() }
        }

        func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
            guard let overlay = overlayView as? SheetOverlayView, overlays[overlay.pageNumber] === overlay else { return }
            overlays[overlay.pageNumber] = nil
        }

        @objc func scaleChanged() {
            guard let view else { return }
            let screenScale = view.window?.screen.scale ?? view.traitCollection.displayScale
            for overlay in overlays.values {
                overlay.matchScale(pointsPerPDFPoint: view.scaleFactor, screenScale: screenScale)
            }
        }

        // MARK: Editing gestures

        func installEditingGestures(on view: PDFView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            view.addGestureRecognizer(pan)
            self.pan = pan

            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.minimumPressDuration = 0.35
            hold.delegate = self
            view.addGestureRecognizer(hold)
            self.hold = hold

            // The sheet scrolls only once the editor has turned a drag down —
            // which, outside editing, it does at once.
            if let scroll = Self.scrollView(in: view) {
                scroll.panGestureRecognizer.require(toFail: pan)
            }
        }

        func setEditing(_ value: Bool) {
            guard value != editing, let view else { return }
            editing = value
            if !value { gesturePage = nil }
            // PDFKit's own touch-and-hold selects text, which would fight
            // the selection box.
            for recognizer in Self.recognizers(in: view) where recognizer is UILongPressGestureRecognizer && recognizer !== hold {
                recognizer.isEnabled = !value
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if let view {
                touchStart = touch.location(in: view)
                swipeStartOffset = Self.scrollView(in: view)?.contentOffset.x
                // By now the sheet is on screen, if it wasn't when the mode was set.
                if isSwiping { makeBackSwipeYield() }
            }
            return true
        }

        /// A flick turns the page while the sheet's own scrolling carries on;
        /// left to themselves the scroll would always claim the touch first.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UISwipeGestureRecognizer
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if let swipe = gestureRecognizer as? UISwipeGestureRecognizer {
                return hasNoRoomToPan(toward: swipe.direction)
            }
            guard gestureRecognizer === pan || gestureRecognizer === hold else { return true }
            guard editing, let editor, let view, let document = view.document else { return false }
            let location = touchStart ?? gestureRecognizer.location(in: view)
            guard let page = view.page(for: location, nearest: true) else { return false }
            let point = topDown(location, on: page)
            let number = document.index(for: page) + 1
            if gestureRecognizer === pan {
                return editor.claimsPan(at: point, page: number, pxPerPt: view.scaleFactor)
            }
            return editor.tool == .select
                && editor.item(at: point, page: number, pxPerPt: view.scaleFactor) == nil
        }

        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            guard let editor, let view else { return }
            switch recognizer.state {
            case .began:
                let location = touchStart ?? recognizer.location(in: view)
                guard let page = view.page(for: location, nearest: true) else { return }
                gesturePage = page
                editor.beginPan(at: topDown(location, on: page), page: pageNumber(page), pxPerPt: view.scaleFactor)
                editor.movePan(to: topDown(recognizer.location(in: view), on: page), page: pageNumber(page),
                               pxPerPt: view.scaleFactor)
            case .changed:
                guard let page = gesturePage else { return }
                editor.movePan(to: topDown(recognizer.location(in: view), on: page), page: pageNumber(page),
                               pxPerPt: view.scaleFactor)
            case .ended:
                guard let page = gesturePage else { return }
                editor.endPan(at: topDown(recognizer.location(in: view), on: page))
                gesturePage = nil
            case .cancelled, .failed:
                editor.cancelPan()
                gesturePage = nil
            default:
                break
            }
        }

        @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
            guard let editor, let view else { return }
            switch recognizer.state {
            case .began:
                let location = recognizer.location(in: view)
                guard let page = view.page(for: location, nearest: true),
                      editor.beginMarquee(at: topDown(location, on: page), page: pageNumber(page),
                                          pxPerPt: view.scaleFactor) else { return }
                gesturePage = page
                UISelectionFeedbackGenerator().selectionChanged()
            case .changed:
                guard let page = gesturePage else { return }
                editor.moveMarquee(to: topDown(recognizer.location(in: view), on: page))
            case .ended, .cancelled, .failed:
                editor.endMarquee()
                gesturePage = nil
            default:
                break
            }
        }

        // MARK: Turning pages

        func installPageTurning(on view: PDFView) {
            for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
                swipe.direction = direction
                swipe.delegate = self
                swipe.isEnabled = false
                view.addGestureRecognizer(swipe)
                swipes.append(swipe)
            }
        }

        func setPageMode(_ mode: SheetPageMode) {
            guard let view else { return }
            let swiping = mode == .swipe && (view.document?.pageCount ?? 0) > 1
            // An edit draws with the same drag, so there the pager turns pages.
            for swipe in swipes { swipe.isEnabled = swiping && !editing }
            if swiping { makeBackSwipeYield() }
            guard swiping != isSwiping else { return }
            isSwiping = swiping
            let reading = view.currentPage
            view.displayMode = swiping ? .singlePage : .singlePageContinuous
            view.autoScales = true
            if let reading { view.go(to: reading) }
        }

        /// A swipe to the right turns back a page; without this the navigation
        /// stack takes the same swipe as "back" and leaves the sheet. Its
        /// gestures wait for ours, which fails at once whenever pages aren't
        /// being swiped, so going back works as usual everywhere else.
        private func makeBackSwipeYield() {
            guard !backSwipeYields, let view,
                  let back = swipes.first(where: { $0.direction == .right }) else { return }
            var responder = view.next
            while let current = responder, !(current is UIViewController) { responder = current.next }
            guard let navigation = (responder as? UIViewController)?.navigationController else { return }
            navigation.interactivePopGestureRecognizer?.require(toFail: back)
            // iOS 26 also goes back on a swipe anywhere over the content.
            if #available(iOS 26.0, *) {
                navigation.interactiveContentPopGestureRecognizer?.require(toFail: back)
            }
            backSwipeYields = true
        }

        @objc private func swiped(_ recognizer: UISwipeGestureRecognizer) {
            turnPage(by: recognizer.direction == .left ? 1 : -1)
        }

        func turnPage(by delta: Int) {
            guard let view, let document = view.document, let current = view.currentPage else { return }
            let index = document.index(for: current) + delta
            guard (0..<document.pageCount).contains(index), let page = document.page(at: index) else { return }
            // The new page slides in from the side it was swiped from.
            if isSwiping, !UIAccessibility.isReduceMotionEnabled {
                let slide = CATransition()
                slide.type = .push
                slide.subtype = delta > 0 ? .fromRight : .fromLeft
                slide.duration = 0.22
                slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
                view.layer.add(slide, forKey: "pageTurn")
            }
            view.go(to: page)
        }

        /// Zoomed in, the sheet pans until it reaches an edge first.
        private func hasNoRoomToPan(toward direction: UISwipeGestureRecognizer.Direction) -> Bool {
            guard let view, let scroll = Self.scrollView(in: view) else { return true }
            let leading = -scroll.adjustedContentInset.left
            let trailing = scroll.contentSize.width - scroll.bounds.width + scroll.adjustedContentInset.right
            guard trailing - leading > 1 else { return true }
            let offset = swipeStartOffset ?? scroll.contentOffset.x
            return direction == .left ? offset >= trailing - 1 : offset <= leading + 1
        }

        @objc func pageChanged() {
            guard let view, let document = view.document else { return }
            let page = view.currentPage.map { document.index(for: $0) + 1 } ?? 1
            let count = document.pageCount
            // Not during a SwiftUI update, which is when a document first loads.
            DispatchQueue.main.async { [pager] in pager?.report(page: page, count: count) }
        }

        private static func scrollView(in view: UIView) -> UIScrollView? {
            for subview in view.subviews {
                if let scroll = subview as? UIScrollView { return scroll }
                if let nested = scrollView(in: subview) { return nested }
            }
            return nil
        }

        private static func recognizers(in view: UIView) -> [UIGestureRecognizer] {
            (view.gestureRecognizers ?? []) + view.subviews.flatMap { recognizers(in: $0) }
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
                // Drawn by the page overlays, above the note names and the
                // reader's marks — a PDF annotation would sit under them.
                for overlay in overlays.values { overlay.playhead = playhead }
            }
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
