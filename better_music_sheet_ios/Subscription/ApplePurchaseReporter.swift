import Foundation

/// The server must acknowledge delivery before a StoreKit transaction is finished.
/// Keeping this outside StoreKit makes failed delivery and account changes testable.
@MainActor
struct ApplePurchaseReporter {
    let client: APIClient
    let sessions: SessionStore
    let entitlements: EntitlementStore

    func report(_ transaction: String, userID: String) async throws {
        guard await sessions.current()?.user.userID == userID else {
            throw SubscriptionError.accountChanged
        }
        struct Body: Encodable { let transaction: String }
        let status: SubscriptionStatus = try await client.post(
            "/api/subscriptions/apple/transaction", body: Body(transaction: transaction))
        guard await sessions.current()?.user.userID == userID else {
            throw SubscriptionError.accountChanged
        }
        entitlements.acceptPurchase(status, userID: userID)
    }
}
