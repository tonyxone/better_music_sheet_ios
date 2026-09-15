import SwiftUI

/// The app's own loading spinner, ported from the web app's `.stage-spinner`
/// (see globals.css) rather than the system activity indicator: a paper-deep
/// ring with one accent-coloured arc, turning at the same 0.8s pace.
struct RingSpinner: View {
    var size: CGFloat = 20
    var lineWidth: CGFloat = 2.5

    @State private var rotation = 0.0

    var body: some View {
        Circle()
            .stroke(Brand.paperDeep, lineWidth: lineWidth)
            .overlay {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(Brand.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

#Preview {
    RingSpinner()
}
