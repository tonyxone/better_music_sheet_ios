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
    private let client: APIClient
    private let sessions: SessionStore
    private let defaults: UserDefaults

    init(client: APIClient = .shared, sessions: SessionStore = .shared, defaults: UserDefaults = .standard) {
        self.client = client
        self.sessions = sessions
        self.defaults = defaults
        self.isEntitled = defaults.bool(forKey: Self.cacheKey)
    }

    /// Re-checks entitlement against the backend. Called on launch
    /// (SubscriptionManager.syncCurrentEntitlement) and whenever the
    /// signed-in account changes (see LibraryModel.load(), which already
    /// refreshes `currentUser` at the same moments). A failed fetch keeps
    /// whatever was cached rather than locking out someone with an active
    /// subscription over a flaky connection.
    func refresh() async {
        guard await sessions.current() != nil else {
            apply(entitled: false, status: nil)
            return
        }
        do {
            let status: SubscriptionStatus = try await client.get("/api/me/subscription")
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

    private func apply(entitled: Bool, status: SubscriptionStatus?) {
        isEntitled = entitled
        self.status = status
        defaults.set(entitled, forKey: Self.cacheKey)
    }
}
