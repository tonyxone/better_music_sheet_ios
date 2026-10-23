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

#if DEBUG
    /// Launch with `--act-as-free` to try the free plan — ads, locked sheets,
    /// the practice preview — on an account that has Premium.
    private static let actsAsFree = ProcessInfo.processInfo.arguments.contains("--act-as-free")
#else
    private static let actsAsFree = false
#endif
    private(set) var status: SubscriptionStatus?

    private static let cacheKey = "bms_entitled"
    private static let ownerKey = "bms_entitled_owner"
    private static let statusKey = "bms_subscription_status"
    private var accountID: String?
    private let client: APIClient
    private let sessions: SessionStore
    private let defaults: UserDefaults
    private let now: () -> Date

    init(client: APIClient = .shared, sessions: SessionStore = .shared, defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init) {
        self.client = client
        self.sessions = sessions
        self.defaults = defaults
        self.now = now
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
               cached.master == true || cached.currentPeriodEnd == nil || cached.currentPeriodEnd! > now().timeIntervalSince1970 {
                status = cached
                isEntitled = cached.isPremium && !Self.actsAsFree
            }
        }
        // A previously valid snapshot may expire while this account stays
        // signed in. Failed refreshes must not extend its paid period.
        if let status, status.master != true, let end = status.currentPeriodEnd,
           end <= now().timeIntervalSince1970 {
            apply(entitled: false, status: nil)
        }
        do {
            let status: SubscriptionStatus = try await client.get("/api/me/subscription")
            guard await sessions.current()?.user.userID == userID else { return }
            apply(entitled: status.isPremium, status: status)
        } catch {
            // Keep the cached value.
        }
    }

    /// Applied only after the backend has verified and linked the Apple transaction.
    func acceptPurchase(_ status: SubscriptionStatus, userID: String) {
        accountID = userID
        apply(entitled: status.isPremium, status: status)
    }

    private func apply(entitled: Bool, status: SubscriptionStatus?) {
        isEntitled = entitled && !Self.actsAsFree
        self.status = status
        defaults.set(entitled, forKey: Self.cacheKey)
        defaults.set(accountID, forKey: Self.ownerKey)
        defaults.set(status.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.statusKey)
    }
}
