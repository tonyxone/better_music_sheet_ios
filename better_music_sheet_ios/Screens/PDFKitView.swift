import PDFKit
import SwiftUI

/// The annotated page itself.
///
/// PDFKit rather than a rendered image: it keeps the vector engraving crisp at
/// any zoom, and it hands back page bounds in PDF points — the same space the
/// timeline's geometry lives in — which is what the measure overlays and the
/// playhead will need.
struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.usePageViewController(false)
        view.backgroundColor = UIColor(Brand.paper)
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        // Rebuilding the document on every layout pass would throw away the
        // reader's scroll position and zoom.
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}
