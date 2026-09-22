import Foundation

nonisolated enum SubscriptionError: Error, LocalizedError, Sendable {
    /// StoreKit couldn't verify a transaction's signature — most often a
    /// jailbroken device or a tampered receipt, not something retrying fixes.
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            "Apple couldn't verify this purchase. Please try again."
        }
    }
}
