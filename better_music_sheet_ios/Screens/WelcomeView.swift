import SwiftUI

/// Shown each time the app starts: the welcome artwork, with a real,
/// SwiftUI-drawn Get Started button laid over it — sized, positioned and
/// coloured to match the button already painted into the artwork (colours
/// sampled from Welcome.png itself), rather than just an invisible tap zone
/// over static art.
struct WelcomeView: View {
    let getStarted: () -> Void

    /// The artwork's size, cropped to the screen inside its drawn phone.
    private static let aspectRatio: CGFloat = 750.0 / 1472.0
    /// Where the artwork's Get Started button sits, as fractions of the image.
    private static let buttonFrame = CGRect(x: 50.0 / 750, y: 1207.0 / 1472,
                                            width: 646.0 / 750, height: 109.0 / 1472)
    /// The artwork button's own gradient, top-leading to bottom-trailing.
    private static let buttonGradient = [Color(hex: 0xFCE3AF), Color(hex: 0xA37239)]

    var body: some View {
        GeometryReader { proxy in
            // Fitted rather than filled, so nothing at the sides is cut off;
            // any space left above and below is the artwork's own cream.
            let width = min(proxy.size.width, proxy.size.height * Self.aspectRatio)
            let height = width / Self.aspectRatio
            let buttonHeight = height * Self.buttonFrame.height

            Image("Welcome")
                .resizable()
                .frame(width: width, height: height)
                .accessibilityLabel("Better Music Sheet. Upload, annotate, and practice your sheet music.")
                .overlay(alignment: .topLeading) {
                    Button(action: getStarted) {
                        HStack(spacing: buttonHeight * 0.18) {
                            Text("Get Started")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: buttonHeight * 0.37, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: buttonHeight)
                        .background(
                            LinearGradient(colors: Self.buttonGradient,
                                          startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: .capsule
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: width * Self.buttonFrame.width, height: buttonHeight)
                    .offset(x: width * Self.buttonFrame.minX, y: height * Self.buttonFrame.minY)
                    .accessibilityLabel("Get Started")
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(
            LinearGradient(colors: [Color(hex: 0xFDFCF9), Color(hex: 0xFDFDF7)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

#Preview {
    WelcomeView {}
}
