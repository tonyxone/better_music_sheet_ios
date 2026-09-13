import SwiftUI

/// The mark for practising a sheet: a keyboard in line art, ported from the web
/// app's app/keyboard-icon.tsx on its 24×16 grid. Drawn in the current
/// foreground style, so it takes whatever colour its button gives it.
struct KeyboardIcon: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 24, size.height / 16)
            let originX = (size.width - 24 * scale) / 2
            let originY = (size.height - 16 * scale) / 2

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: originX + x * scale, y: originY + y * scale)
            }
            func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
                CGRect(x: originX + x * scale, y: originY + y * scale,
                       width: width * scale, height: height * scale)
            }

            let line = StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round, lineJoin: .round)
            context.stroke(Path(roundedRect: rect(1, 1, 22, 14), cornerRadius: 2.5 * scale),
                           with: .foreground, style: line)

            // White-key divisions only reach the front half, so the filled
            // black keys above them read as sitting between them.
            var divisions = Path()
            for x: CGFloat in [6.5, 12, 17.5] {
                divisions.move(to: point(x, 8.6))
                divisions.addLine(to: point(x, 15))
            }
            context.stroke(divisions, with: .foreground, style: line)

            for x: CGFloat in [4.5, 10, 15.5] {
                context.fill(Path(roundedRect: rect(x, 1, 4, 7.6), cornerRadius: scale),
                             with: .foreground)
            }
        }
        .aspectRatio(24.0 / 16.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
