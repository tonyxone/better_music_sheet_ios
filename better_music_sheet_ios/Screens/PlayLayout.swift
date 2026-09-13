import SwiftUI

/// The Play screen's sections as the web app has them — sheet, controls,
/// falling notes, keyboard — with every one adjustable. The sheet and the
/// falling notes collapse to their headers, the falling-notes header drags to
/// divide the space between the two differently, and the keyboard's top edge
/// drags to make the keys taller or shorter.
///
/// Remembered between sessions: how much of each you want changes with how you
/// practise, not with which sheet happens to be open.
struct PlayLayout<Sheet: View, Controls: View, Roll: View, Keyboard: View>: View {
    /// The keyboard's natural height at a given width, before the user's scaling.
    let keyboardHeight: (CGFloat) -> CGFloat
    @ViewBuilder let sheet: () -> Sheet
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let roll: () -> Roll
    @ViewBuilder let keyboard: () -> Keyboard

    @AppStorage("play.sheetOpen") private var sheetOpen = true
    @AppStorage("play.rollOpen") private var rollOpen = true
    /// The sheet's share of the space the two panels divide when both are open.
    @AppStorage("play.sheetShare") private var sheetShare = 0.6
    @AppStorage("play.keyboardScale") private var keyboardScale = 1.0

    /// Measured, because the controls wrap onto two rows on narrow screens.
    @State private var controlsHeight: CGFloat = 110
    @State private var shareAtDragStart: Double?
    @State private var scaleAtDragStart: Double?

    // Computed rather than stored: a generic type cannot hold static stored
    // properties.
    private static var headerHeight: CGFloat { 32 }
    private static var shareRange: ClosedRange<Double> { 0.15...0.85 }
    private static var scaleRange: ClosedRange<Double> { 0.6...2.0 }
    private static var rollBackground: Color { Color(hex: 0x0F1113) }

    var body: some View {
        GeometryReader { proxy in
            let naturalKeyboard = keyboardHeight(proxy.size.width)
            let keysHeight = (naturalKeyboard * keyboardScale).rounded()
            let flexible = max(0, proxy.size.height - Self.headerHeight * 2 - controlsHeight - keysHeight)
            let heights = panelHeights(flexible: flexible)

            VStack(spacing: 0) {
                header("Sheet", open: sheetOpen, dark: false) { sheetOpen.toggle() }
                if sheetOpen {
                    sheet()
                        .frame(height: heights.sheet)
                        .clipped()
                }

                controls()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }

                // With both panels closed, the falling-notes header stays on
                // the keyboard rather than leaving a gap beneath the controls.
                if !sheetOpen && !rollOpen {
                    Spacer(minLength: 0)
                }

                rollHeader(flexible: flexible)
                if rollOpen {
                    roll()
                        .frame(height: heights.roll)
                        .clipped()
                }

                keyboard()
                    .frame(height: keysHeight)
                    .overlay(alignment: .top) {
                        keyboardHandle(naturalHeight: naturalKeyboard)
                    }
            }
        }
    }

    private func panelHeights(flexible: CGFloat) -> (sheet: CGFloat, roll: CGFloat) {
        switch (sheetOpen, rollOpen) {
        case (true, true):
            let sheet = (flexible * sheetShare).rounded()
            return (sheet, flexible - sheet)
        case (true, false):
            return (flexible, 0)
        case (false, true):
            return (0, flexible)
        case (false, false):
            return (0, 0)
        }
    }

    // MARK: - Headers

    private func header(_ title: String, open: Bool, dark: Bool,
                        toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .rotationEffect(.degrees(open ? 90 : 0))
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .tracking(0.25)
            Spacer()
        }
        .foregroundStyle(dark ? Color.white.opacity(0.55) : Brand.inkSoft)
        .padding(.horizontal, 14)
        .frame(height: Self.headerHeight)
        .background(dark ? Self.rollBackground : Brand.card)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.22)) { toggle() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(open ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(open ? "Collapses the section" : "Expands the section")
    }

    /// Doubles as the divider between the sheet and the falling notes.
    private func rollHeader(flexible: CGFloat) -> some View {
        let resizable = sheetOpen && rollOpen
        return header("Falling notes", open: rollOpen, dark: true) { rollOpen.toggle() }
            .overlay {
                if resizable {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 36, height: 4)
                        .allowsHitTesting(false)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        guard resizable, flexible > 0 else { return }
                        let start = shareAtDragStart ?? sheetShare
                        shareAtDragStart = start
                        sheetShare = Self.clamp(start + value.translation.height / flexible, to: Self.shareRange)
                    }
                    .onEnded { _ in shareAtDragStart = nil }
            )
            .accessibilityAdjustableAction { direction in
                guard resizable else { return }
                switch direction {
                case .increment: sheetShare = Self.clamp(sheetShare - 0.1, to: Self.shareRange)
                case .decrement: sheetShare = Self.clamp(sheetShare + 0.1, to: Self.shareRange)
                @unknown default: break
                }
            }
    }

    /// Straddles the boundary above the keys, so the falling notes still land
    /// on the keyboard itself rather than on a separating strip.
    private func keyboardHandle(naturalHeight: CGFloat) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.35))
            .frame(width: 36, height: 4)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .offset(y: -11)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard naturalHeight > 0 else { return }
                        let start = scaleAtDragStart ?? keyboardScale
                        scaleAtDragStart = start
                        // Dragging the top edge up makes the keys taller.
                        keyboardScale = Self.clamp(start - value.translation.height / naturalHeight,
                                                   to: Self.scaleRange)
                    }
                    .onEnded { _ in scaleAtDragStart = nil }
            )
            .accessibilityElement()
            .accessibilityLabel("Keyboard height")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: keyboardScale = Self.clamp(keyboardScale + 0.1, to: Self.scaleRange)
                case .decrement: keyboardScale = Self.clamp(keyboardScale - 0.1, to: Self.scaleRange)
                @unknown default: break
                }
            }
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
