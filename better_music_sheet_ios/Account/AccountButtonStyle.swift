import SwiftUI

/// The Account screen's actions as full-width capsules, matching the paywall's
/// buttons: `filled` for the one thing to do next, `outlined` for the rest.
struct AccountButtonStyle: ButtonStyle {
    enum Kind { case filled, outlined }

    var kind: Kind = .outlined
    var tint: Color = Brand.accent

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(kind == .filled ? .white : tint)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(kind == .filled ? tint : Brand.card, in: .capsule)
            .overlay(Capsule().stroke(kind == .filled ? .clear : tint, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == AccountButtonStyle {
    static func account(_ kind: AccountButtonStyle.Kind = .outlined,
                        tint: Color = Brand.accent) -> AccountButtonStyle {
        AccountButtonStyle(kind: kind, tint: tint)
    }

}

/// The way into Premium, styled as the welcome screen's Get Started button:
/// a gold gradient capsule with white text.
struct PremiumButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(LinearGradient(colors: Brand.goldGradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .capsule)
        .opacity(configuration.isPressed ? 0.8 : 1)
        .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == PremiumButtonStyle {
    static var premium: PremiumButtonStyle { PremiumButtonStyle() }
}
