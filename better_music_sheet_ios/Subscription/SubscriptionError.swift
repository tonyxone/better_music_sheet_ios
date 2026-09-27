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
            "Sign in to your account before purchasing or restoring."
        case .alreadySubscribed:
            "This account already has Premium. No additional purchase is needed."
        case .accountChanged:
            "Your account changed during the purchase. Sign in to the original account and restore purchases."
        case .purchasePending:
            "Your purchase is awaiting Apple's approval. Access will update when it is approved."
        case .failedVerification:
            "Apple couldn't verify this purchase. Please try again."
        }
    }
}
