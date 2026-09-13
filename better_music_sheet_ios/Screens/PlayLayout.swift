import SwiftUI

/// The Practice page's sections as the web app has them — sheet, controls,
/// falling notes, keyboard. The sheet and the falling notes collapse to their
/// headers, and the falling-notes header drags to divide the space between the
/// two differently. The keyboard stays at its natural height.
///
/// Remembered between sessions: how much of each you want changes with how you
/// practise, not with which sheet happens to be open.
struct PlayLayout<Sheet: View, Controls: View, Roll: View, Keyboard: View>: View {
    /// The keyboard's natural height at a given width.
    let keyboardHeight: (CGFloat) -> CGFloat
    @ViewBuilder let sheet: () -> Sheet
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let roll: () -> Roll
    @ViewBuilder let keyboard: () -> Keyboard

    @AppStorage("play.sheetOpen") private var sheetOpen = true
    @AppStorage("play.rollOpen") private var rollOpen = true
    /// The sheet's share of the space the two panels divide when both are open.
    @AppStorage("play.sheetShare") private var storedSheetShare = 0.6

    /// The live value while a drag is under way, saved once the finger lifts.
    /// Writing preferences on every frame of a drag made resizing stutter.
    @State private var liveShare: Double?
    @State private var shareAtDragStart = 0.6
    /// Measured, because the controls wrap onto two rows on narrow screens.
    @State private var controlsHeight: CGFloat = 110

    // Computed rather than stored: a generic type cannot hold static stored
    // properties.
    private static var headerHeight: CGFloat { 32 }
    private static var shareRange: ClosedRange<Double> { 0.15...0.85 }
    /// Room the panels keep on a short screen, such as a phone in landscape.
    private static var minimumPanelSpace: CGFloat { 120 }
    private static var rollBackground: Color { Color(hex: 0x0F1113) }

    private var sheetShare: Double { liveShare ?? storedSheetShare }

    var body: some View {
        GeometryReader { proxy in
            let naturalKeyboard = keyboardHeight(proxy.size.width)
            let fixed = Self.headerHeight * 2 + controlsHeight
            // Natural height, giving way only where a short screen would
            // otherwise squeeze the panels above it to nothing.
            let keysHeight = min(naturalKeyboard,
                                 max(naturalKeyboard * 0.6, proxy.size.height - fixed - Self.minimumPanelSpace))
            let flexible = max(0, proxy.size.height - fixed - keysHeight)
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
            }
        }
    }

    private func panelHeights(flexible: CGFloat) -> (sheet: CGFloat, roll: CGFloat) {
        switch (sheetOpen, rollOpen) {
        case (true, true):
            // Not rounded, so a drag moves the divider continuously instead of
            // in whole-point steps.
            let sheet = flexible * sheetShare
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
            // Measured in screen coordinates. The header moves as it resizes
            // the panels, and a translation measured against the header itself
            // shrank back every frame and fought the finger.
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        guard resizable, flexible > 0 else { return }
                        if liveShare == nil { shareAtDragStart = storedSheetShare }
                        liveShare = Self.clamp(shareAtDragStart + value.translation.height / flexible,
                                               to: Self.shareRange)
                    }
                    .onEnded { _ in
                        if let liveShare { storedSheetShare = liveShare }
                        liveShare = nil
                    }
            )
            .accessibilityAdjustableAction { direction in
                guard resizable else { return }
                switch direction {
                case .increment: storedSheetShare = Self.clamp(storedSheetShare - 0.1, to: Self.shareRange)
                case .decrement: storedSheetShare = Self.clamp(storedSheetShare + 0.1, to: Self.shareRange)
                @unknown default: break
                }
            }
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
