import SwiftUI

/// A few staff lines and a couple of noteheads — enough to read as sheet
/// music at 42×54 without pulling a real page render into a list row.
/// Noteheads are ellipses rotated -18°, the same idiom as the wordmark.
struct SheetThumbnail: View {
    var body: some View {
        Canvas { context, size in
            let lineGap = size.height / 8
            let top = lineGap * 1.6
            let inset = size.width * 0.14

            for line in 0..<5 {
                let y = top + Double(line) * lineGap
                var path = Path()
                path.move(to: CGPoint(x: inset, y: y))
                path.addLine(to: CGPoint(x: size.width - inset, y: y))
                context.stroke(path, with: .color(Brand.inkSoft.opacity(0.5)), lineWidth: 0.7)
            }

            for (index, step) in [3.0, 1.5].enumerated() {
                let x = inset + size.width * (index == 0 ? 0.22 : 0.52)
                let y = top + step * lineGap
                let head = CGRect(x: x - 2.6, y: y - 2.0, width: 5.2, height: 4.0)
                context.drawLayer { layer in
                    layer.rotate(by: .degrees(-18))
                    layer.fill(Path(ellipseIn: head), with: .color(Brand.ink))
                }
                var stem = Path()
                stem.move(to: CGPoint(x: x + 2.4, y: y))
                stem.addLine(to: CGPoint(x: x + 2.4, y: y - lineGap * 2.4))
                context.stroke(stem, with: .color(Brand.ink), lineWidth: 1)
            }
        }
        .frame(width: 42, height: 54)
        .background(Brand.paper)
        .clipShape(.rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.paperDeep, lineWidth: 1))
    }
}
