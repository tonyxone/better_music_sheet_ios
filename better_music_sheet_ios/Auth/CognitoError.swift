import Foundation

/// Cognito's own error shape, surfaced so the UI can react to specific
/// failures (unconfirmed account, wrong password) rather than only showing a
/// message — mirrors the web app's lib/cognito.ts.
nonisolated struct CognitoError: LocalizedError, Sendable {
    let code: String
    let message: String

    var errorDescription: String? { message }
}
