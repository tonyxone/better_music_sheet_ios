import Foundation

nonisolated enum SubscriptionError: Error, LocalizedError, Sendable {
    /// StoreKit couldn't verify a transaction's signature — most often a
    /// jailbroken device or a tampered receipt, not something retrying fixes.
    case failedVerification
    case signInRequired
    case alreadySubscribed
    case accountChanged
    case purchasePending

    var errorDescription: String? {
        switch self {
        case .signInRequired:
            String(localized: "Sign in to your account before purchasing or restoring.", bundle: .app)
        case .alreadySubscribed:
            String(localized: "This account already has Premium. No additional purchase is needed.", bundle: .app)
        case .accountChanged:
            String(localized: "Your account changed during the purchase. Sign in to the original account and restore purchases.", bundle: .app)
        case .purchasePending:
            String(localized: "Your purchase is awaiting Apple's approval. Access will update when it is approved.", bundle: .app)
        case .failedVerification:
            String(localized: "Apple couldn't verify this purchase. Please try again.", bundle: .app)
        }
    }
}
