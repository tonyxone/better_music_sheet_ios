import AuthenticationServices
import UIKit

/// Presents Cognito's hosted UI in a system browser sheet and resolves with
/// the callback URL it redirects to afterward. Google and Apple both need
/// their own real page to sign in on — unlike a password, typed straight
/// into this app, those credentials are typed on the provider's site, which
/// is why this can't be a direct network call the way CognitoAuth's other
/// calls are.
final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    @MainActor
    static func present(url: URL, callbackScheme: String) async throws -> URL {
        let presenter = WebAuthPresenter()
        return try await presenter.run(url: url, callbackScheme: callbackScheme)
    }

    @MainActor
    private func run(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let nsError = error as NSError?,
                          nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                          nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: AuthError.server(error?.localizedDescription ?? "Sign-in failed."))
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                continuation.resume(throwing: AuthError.invalidCallback)
            }
        }
    }

    /// Called by AuthenticationServices on the main thread, hence the
    /// synchronous main-actor access despite this method not being isolated
    /// itself — it satisfies an Objective-C protocol requirement that can't
    /// be marked `@MainActor` from this side.
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            // There's always a foreground window scene while this can be
            // called — it's only invoked while presenting UI on one.
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first { $0.isKeyWindow }
                ?? ASPresentationAnchor(windowScene: scenes[0])
        }
    }
}
