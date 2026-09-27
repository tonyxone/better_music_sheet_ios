import Foundation

/// Whether this account can use practice mode — cached locally (so the app
/// never flashes a paywall before the backend answers) and re-checked
/// against GET /api/me/subscription, so a subscription bought on the web
/// unlocks iOS without a separate purchase.
///
/// Guests always resolve to free: the subscription record is per backend
/// account, and there is nothing to check without one.
@MainActor
@Observable
final class EntitlementStore {
    static let shared = EntitlementStore()

    private(set) var isEntitled: Bool
    private(set) var status: SubscriptionStatus?

    private static let cacheKey = "bms_entitled"
    private static let ownerKey = "bms_entitled_owner"
    private static let statusKey = "bms_subscription_status"
    private var accountID: String?
    private let client: APIClient
    private let sessions: SessionStore
    private let defaults: UserDefaults

    init(client: APIClient = .shared, sessions: SessionStore = .shared, defaults: UserDefaults = .standard) {
        self.client = client
        self.sessions = sessions
        self.defaults = defaults
        self.isEntitled = false
    }

    /// Re-checks entitlement against the backend. Called on launch
    /// (SubscriptionManager.syncCurrentEntitlement) and whenever the
    /// signed-in account changes (see LibraryModel.load(), which already
    /// refreshes `currentUser` at the same moments). A failed fetch keeps
    /// whatever was cached rather than locking out someone with an active
    /// subscription over a flaky connection.
    func refresh() async {
        guard let userID = await sessions.current()?.user.userID else {
            accountID = nil
            apply(entitled: false, status: nil)
            return
        }
        if accountID != userID {
            accountID = userID
            status = nil
            isEntitled = false
            if defaults.string(forKey: Self.ownerKey) == userID,
               let data = defaults.data(forKey: Self.statusKey),
               let cached = try? JSONDecoder().decode(SubscriptionStatus.self, from: data),
               cached.currentPeriodEnd == nil || cached.currentPeriodEnd! > Date().timeIntervalSince1970 {
                status = cached
                isEntitled = cached.isPremium
            }
        }
        do {
            let status: SubscriptionStatus = try await client.get("/api/me/subscription")
            guard await sessions.current()?.user.userID == userID else { return }
            apply(entitled: status.isPremium, status: status)
        } catch {
            // Keep the cached value.
        }
    }

    /// Cancels at period end, through whichever store billed it. Only a web
    /// (Stripe) subscription can be cancelled by the server; an App Store one
    /// is cancelled in Settings, which the account screen opens instead. The
    /// platform is named so the server refuses if this view is out of date.
    func cancelWebSubscription() async throws {
        guard let platform = status?.platform else { return }
        struct Body: Encodable { let platform: String }
        let updated: SubscriptionStatus = try await client.post("/api/subscriptions/cancel", body: Body(platform: platform))
        apply(entitled: updated.isPremium, status: SubscriptionStatus(
            tier: updated.tier, plan: updated.plan, status: updated.status, startedAt: updated.startedAt,
            currentPeriodEnd: updated.currentPeriodEnd, cancelAtPeriodEnd: updated.cancelAtPeriodEnd,
            platform: updated.platform, trialEligible: status?.trialEligible ?? updated.trialEligible,
            master: updated.master ?? status?.master))
    }

    /// Applied only after the backend has verified and linked the Apple transaction.
    func acceptPurchase(_ status: SubscriptionStatus, userID: String) {
        accountID = userID
        apply(entitled: status.isPremium, status: status)
    }

    private func apply(entitled: Bool, status: SubscriptionStatus?) {
        isEntitled = entitled
        self.status = status
        defaults.set(entitled, forKey: Self.cacheKey)
        defaults.set(accountID, forKey: Self.ownerKey)
        defaults.set(status.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.statusKey)
    }
}
