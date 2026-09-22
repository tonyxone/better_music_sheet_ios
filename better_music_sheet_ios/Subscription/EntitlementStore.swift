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

    private func apply(entitled: Bool, status: SubscriptionStatus?) {
        isEntitled = entitled
        self.status = status
        defaults.set(entitled, forKey: Self.cacheKey)
    }
}
