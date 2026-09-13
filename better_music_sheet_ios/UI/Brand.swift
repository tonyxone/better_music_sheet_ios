import SwiftUI

/// The web app's paper/ink identity, carried over exactly (see the web app's
/// app/globals.css). These are literal values rather than an asset catalog
/// for now; the dark-surround treatment is still an open design decision, and
/// when it lands it belongs in a colour set, not here.
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum Brand {
    static let paper = Color(hex: 0xFAF3E6)
    static let paperDeep = Color(hex: 0xF0E4CE)
    static let card = Color(hex: 0xFFFDF8)
    static let ink = Color(hex: 0x2E2117)
    static let inkSoft = Color(hex: 0x7A6753)
    static let hairline = Color(hex: 0xC0B098)
    static let accent = Color(hex: 0xA83C34)
    static let accentDeep = Color(hex: 0x8C4A1F)
    static let gold = Color(hex: 0xD9A441)
    static let success = Color(hex: 0x5C7A4E)
    static let danger = Color(hex: 0xA83C34)

    /// Functional, not decorative: these two say which hand plays what, and
    /// they match the web app byte for byte so someone using both sees one
    /// colour language.
    static let rightHand = Color(hex: 0x2F6FB5)
    static let leftHand = Color(hex: 0x3E8E5A)

    /// Titles are set in Spectral on the web. Until that face is bundled,
    /// the system serif is the honest stand-in — same role, native metrics.
    static func title(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
