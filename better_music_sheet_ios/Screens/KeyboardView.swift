import SwiftUI

/// The keyboard under the sheet, lighting each key while it is held.
///
/// Drawn in 2D rather than the web app's three.js scene, but on the same
/// geometry (see KeyboardLayout) and the same colour rules: blue for the right
/// hand, green for the left, the hand colour blended into the key so the key
/// stays visible underneath, and a lit key drawn pressed.
struct KeyboardView: View {
    let range: KeyboardLayout.KeyRange
    /// Keys to light, by MIDI note, valued by role: 0 right hand, 1 left.
    let litKeys: [Int: Int]
    let showNames: Bool

    private static let layout = KeyboardLayout()

    /// How much hand colour to mix in: enough to read at a glance while the
    /// key itself stays visible. Black keys take more, because the same
    /// fraction over near-black reads far darker than over ivory.
    private static let whiteMix = 0.7
    private static let blackMix = 0.875

    private static let ivory: UInt32 = 0xFBF9F4
    private static let keyLip: UInt32 = 0xE6DDCD
    private static let ebony: UInt32 = 0x1C1613
    private static let felt: UInt32 = 0x2E2117
    private static let rightHand: UInt32 = 0x2F6FB5
    private static let leftHand: UInt32 = 0x3E8E5A

    var body: some View {
        Canvas { context, size in
            let unit = size.width / range.width
            // Every white key is named whenever asked, however narrow the keys.
            // Hiding them below a width left a phone with a wide piece showing
            // none. Sized to the key instead, so even "C4" stays inside its own
            // key rather than running into the next name.
            let labelSize = min(11, max(5, unit * 0.6))

            for midi in range.lowMIDI...range.highMIDI where !KeyboardLayout.isBlack(midi) {
                let extent = Self.layout.extent(of: midi)
                let rect = CGRect(x: (extent.x - range.left) * unit, y: 0,
                                  width: extent.width * unit, height: size.height)
                let role = litKeys[midi]
                let radius = unit * 0.12
                context.fill(Path(roundedRect: rect,
                                  cornerRadii: RectangleCornerRadii(bottomLeading: radius, bottomTrailing: radius)),
                             with: .color(Self.color(base: Self.ivory, role: role, mix: Self.whiteMix)))

                if role == nil {
                    // The front lip of a key at rest. A sounding key has
                    // dropped below it, which reads as "this one" faster than
                    // colour alone.
                    let lipHeight = max(3, unit * 0.22)
                    let lip = CGRect(x: rect.minX, y: rect.maxY - lipHeight, width: rect.width, height: lipHeight)
                    context.fill(Path(roundedRect: lip,
                                      cornerRadii: RectangleCornerRadii(bottomLeading: radius, bottomTrailing: radius)),
                                 with: .color(Color(hex: Self.keyLip)))
                }

                if showNames {
                    let name = KeyboardLayout.noteName(midi, withOctave: KeyboardLayout.pitchClass(midi) == 0)
                    context.draw(Text(name)
                                    .font(.system(size: labelSize, weight: .semibold))
                                    .foregroundStyle(role == nil ? Brand.inkSoft : .white),
                                 at: CGPoint(x: rect.midX, y: rect.maxY - max(6, unit * 0.45)),
                                 anchor: .bottom)
                }
            }

            let blackHeight = size.height * KeyboardLayout.blackLength
            for midi in range.lowMIDI...range.highMIDI where KeyboardLayout.isBlack(midi) {
                let extent = Self.layout.extent(of: midi)
                let rect = CGRect(x: (extent.x - range.left) * unit, y: 0,
                                  width: extent.width * unit, height: blackHeight)
                let role = litKeys[midi]
                let radius = unit * 0.08
                context.fill(Path(roundedRect: rect,
                                  cornerRadii: RectangleCornerRadii(bottomLeading: radius, bottomTrailing: radius)),
                             with: .color(Self.color(base: Self.ebony, role: role, mix: Self.blackMix)))
                // Unlabelled: a black key is a sharp or a flat depending on
                // the key signature, and a name here would be wrong half the
                // time.
            }
        }
        // Shows through the hairlines between white keys.
        .background(Color(hex: Self.felt))
        .accessibilityElement()
        .accessibilityLabel(accessibilityDescription)
    }

    /// A height that keeps the keys in proportion at this width: where the
    /// keyboard's drag handle scales from.
    static func naturalHeight(width: CGFloat, range: KeyboardLayout.KeyRange) -> CGFloat {
        guard range.width > 0 else { return 0 }
        return min(170, max(56, width / range.width * 5.2))
    }

    private var accessibilityDescription: String {
        let names = litKeys.keys.sorted().map(KeyboardLayout.spokenName)
        return names.isEmpty ? "Keyboard, nothing sounding" : "Keyboard, sounding " + names.joined(separator: ", ")
    }

    private static func color(base: UInt32, role: Int?, mix: Double) -> Color {
        guard let role else { return Color(hex: base) }
        return blend(base, role == 1 ? leftHand : rightHand, mix)
    }

    private static func blend(_ from: UInt32, _ to: UInt32, _ amount: Double) -> Color {
        func channel(_ value: UInt32, _ shift: UInt32) -> Double {
            Double((value >> shift) & 0xFF) / 255
        }
        func mixed(_ shift: UInt32) -> Double {
            channel(from, shift) * (1 - amount) + channel(to, shift) * amount
        }
        return Color(.sRGB, red: mixed(16), green: mixed(8), blue: mixed(0), opacity: 1)
    }
}
