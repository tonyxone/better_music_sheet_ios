import Foundation

/// A Cognito identity provider the hosted UI can redirect to. Raw values are
/// Cognito's own provider names — Cognito matches these exactly, and they're
/// also what goes in the hosted UI's `identity_provider` query parameter
/// (mirrors the web app's lib/cognito.ts).
nonisolated enum SocialProvider: String, CaseIterable, Sendable, Hashable {
    case google = "Google"
    case signInWithApple = "SignInWithApple"

    var displayLabel: String {
        switch self {
        case .google: "Continue with Google"
        case .signInWithApple: "Continue with Apple"
        }
    }
}
