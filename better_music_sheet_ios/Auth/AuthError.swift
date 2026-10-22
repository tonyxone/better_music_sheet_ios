import Foundation

nonisolated enum AuthError: LocalizedError, Sendable {
    case notConfigured
    case cancelled
    /// The hosted-UI redirect didn't carry what it was supposed to — no
    /// `code`, or a response this app doesn't know how to decode.
    case invalidCallback
    case transport(String)
    /// Cognito's or the backend's own explanation of why sign-in failed.
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: String(localized: "Sign-in isn't configured for this build.", bundle: .app)
        case .cancelled: String(localized: "Sign-in was cancelled.", bundle: .app)
        case .invalidCallback: String(localized: "Sign-in didn't return the expected response. Please try again.", bundle: .app)
        case .transport(let message): message
        case .server(let message): message
        }
    }
}
