import Foundation
import Testing
@testable import better_music_sheet_ios

@MainActor
struct EntitlementStoreTests {
    private let base = URL(string: "https://api.example.com")!
    private static let cacheKey = "bms_entitled"

    private func session(_ user: User = User(userID: "u1", email: "a@example.com", displayName: "Ada", createdAt: 0)) -> Session {
        Session(token: "jwt", expiresAt: Date().timeIntervalSince1970 + 3600, refreshToken: nil, user: user)
    }

    /// A throwaway suite per test, so cached values never leak between tests
    /// (or into the real app's UserDefaults).
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    private func store(channel: StubProtocol.Channel, sessions: SessionStore, defaults: UserDefaults) -> EntitlementStore {
        let client = APIClient(baseURL: base, urlSession: channel.session(),
                               sessions: sessions, guestID: GuestID(store: InMemorySecretStore()))
        return EntitlementStore(client: client, sessions: sessions, defaults: defaults)
    }

    @Test func guestsAlwaysResolveToFreeWithoutANetworkCall() async {
        let channel = StubProtocol.Channel([])
        let entitlements = store(channel: channel, sessions: SessionStore(store: InMemorySecretStore()), defaults: freshDefaults())

        await entitlements.refresh()

        #expect(!entitlements.isEntitled)
        #expect(channel.recorded.isEmpty)
    }

    @Test func signedInFetchesTheBackendsTier() async throws {
        let channel = StubProtocol.Channel([
            .init(body: Data(#"""
            {"tier": "premium", "plan": "yearly", "status": "active",
             "current_period_end": 1999999999, "cancel_at_period_end": false, "platform": "apple"}
            """#.utf8)),
        ])
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(session())
        let entitlements = store(channel: channel, sessions: sessions, defaults: freshDefaults())

        await entitlements.refresh()

        #expect(entitlements.isEntitled)
        #expect(entitlements.status?.plan == "yearly")
        let request = try #require(channel.recorded.first)
        #expect(request.url?.path == "/api/me/subscription")
    }

    @Test func aFailedFetchKeepsTheCachedValue() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: Self.cacheKey)
        defaults.set("u1", forKey: "bms_entitled_owner")
        let cached = SubscriptionStatus(tier: "premium", plan: "monthly", status: "active", currentPeriodEnd: 1999999999, cancelAtPeriodEnd: false, platform: "apple")
        defaults.set(try? JSONEncoder().encode(cached), forKey: "bms_subscription_status")
        let channel = StubProtocol.Channel([.init(status: 500, body: Data(#"{"detail": "boom"}"#.utf8))])
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(session())
        let entitlements = store(channel: channel, sessions: sessions, defaults: defaults)
        #expect(!entitlements.isEntitled)  // waits until the signed-in owner is known

        await entitlements.refresh()

        #expect(entitlements.isEntitled)
    }

    @Test func anOfflineAccountSwitchNeverKeepsThePreviousUsersPremium() async {
        let channel = StubProtocol.Channel([
            .init(body: Data(#"{"tier":"premium","plan":"monthly","status":"active","platform":"apple","cancel_at_period_end":false}"#.utf8)),
            .init(status: 500)
        ])
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(session())
        let entitlements = store(channel: channel, sessions: sessions, defaults: freshDefaults())
        await entitlements.refresh()
        #expect(entitlements.isEntitled)
        await sessions.save(session(User(userID: "u2", email: nil, displayName: nil, createdAt: 0)))
        await entitlements.refresh()
        #expect(!entitlements.isEntitled)
        #expect(entitlements.status == nil)
    }

    @Test func anOfflineSnapshotExpiresWithoutChangingAccounts() async {
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let channel = StubProtocol.Channel([.init(status: 503), .init(status: 503)])
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(session())
        let defaults = freshDefaults()
        let client = APIClient(baseURL: base, urlSession: channel.session(),
                               sessions: sessions, guestID: GuestID(store: InMemorySecretStore()))
        let entitlements = EntitlementStore(client: client, sessions: sessions, defaults: defaults,
                                            now: { clock })
        entitlements.acceptPurchase(SubscriptionStatus(tier: "premium", plan: "monthly", status: "active",
            currentPeriodEnd: 1_700_000_010, cancelAtPeriodEnd: false, platform: "apple"), userID: "u1")
        await entitlements.refresh()
        #expect(entitlements.isEntitled)
        clock = Date(timeIntervalSince1970: 1_700_000_011)
        await entitlements.refresh()
        #expect(!entitlements.isEntitled)
        #expect(entitlements.status == nil)
        #expect(!defaults.bool(forKey: Self.cacheKey))
    }

    @Test func anExpiredPaidPeriodDoesNotRemoveMasterAccessOffline() async {
        let channel = StubProtocol.Channel([.init(status: 503)])
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(session())
        let entitlements = store(channel: channel, sessions: sessions, defaults: freshDefaults())
        entitlements.acceptPurchase(SubscriptionStatus(tier: "premium", plan: "monthly", status: "active",
            currentPeriodEnd: 1, cancelAtPeriodEnd: false, platform: "apple", master: true), userID: "u1")
        await entitlements.refresh()
        #expect(entitlements.isEntitled)
        #expect(entitlements.status?.master == true)
    }

    @Test func aFreeTierResponseClearsAPreviouslyCachedEntitlement() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: Self.cacheKey)
        defaults.set("u1", forKey: "bms_entitled_owner")
        let cached = SubscriptionStatus(tier: "premium", plan: "monthly", status: "active", currentPeriodEnd: 1999999999, cancelAtPeriodEnd: false, platform: "apple")
        defaults.set(try? JSONEncoder().encode(cached), forKey: "bms_subscription_status")
        let channel = StubProtocol.Channel([
            .init(body: Data(#"""
            {"tier": "free", "plan": null, "status": null,
             "current_period_end": null, "cancel_at_period_end": null, "platform": null}
            """#.utf8)),
        ])
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(session())
        let entitlements = store(channel: channel, sessions: sessions, defaults: defaults)

        await entitlements.refresh()

        #expect(!entitlements.isEntitled)
        #expect(defaults.bool(forKey: Self.cacheKey) == false)
    }
    @Test func aMasterAccountIsEntitledWithNoPlanToManage() async throws {
        // The backend's shape for a master user with no subscription of its own.
        let channel = StubProtocol.Channel([
            .init(body: Data(#"""
            {"tier": "premium", "plan": null, "status": null, "started_at": null,
             "current_period_end": null, "cancel_at_period_end": false, "platform": null,
             "master": true, "trial_eligible": true}
            """#.utf8)),
        ])
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(session())
        let entitlements = store(channel: channel, sessions: sessions, defaults: freshDefaults())

        await entitlements.refresh()

        #expect(entitlements.isEntitled)
        #expect(entitlements.status?.isMasterOnly == true)
    }

    @Test func aMasterWhoAlsoSubscribedStillShowsThatSubscription() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let status = try decoder.decode(SubscriptionStatus.self, from: Data(#"""
        {"tier": "premium", "plan": "yearly", "status": "active", "current_period_end": 1999999999,
         "cancel_at_period_end": false, "platform": "apple", "master": true}
        """#.utf8))
        #expect(status.isPremium)
        #expect(!status.isMasterOnly)

        // Older backends send no `master` at all.
        let older = try decoder.decode(SubscriptionStatus.self, from: Data(#"""
        {"tier": "free", "plan": null, "status": null, "current_period_end": null,
         "cancel_at_period_end": false, "platform": null}
        """#.utf8))
        #expect(older.master == nil && !older.isMasterOnly)
    }

    @Test func readsTrialEligibilityAndCancelsAWebSubscriptionByPlatform() async throws {
        let channel = StubProtocol.Channel([
            .init(body: Data(#"""
            {"tier": "premium", "plan": "monthly", "status": "trialing", "started_at": 1700000000,
             "current_period_end": 1999999999, "cancel_at_period_end": false, "platform": "stripe",
             "trial_eligible": false}
            """#.utf8)),
            .init(body: Data(#"""
            {"tier": "premium", "plan": "monthly", "status": "trialing", "started_at": 1700000000,
             "current_period_end": 1999999999, "cancel_at_period_end": true, "platform": "stripe"}
            """#.utf8)),
        ])
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(session())
        let entitlements = store(channel: channel, sessions: sessions, defaults: freshDefaults())

        await entitlements.refresh()
        #expect(entitlements.status?.offersTrial == false)
        #expect(entitlements.status?.startedAt == 1700000000)
        #expect(entitlements.status?.isBilledByApple == false)

        try await entitlements.cancelWebSubscription()
        #expect(entitlements.isEntitled)
        #expect(entitlements.status?.cancelAtPeriodEnd == true)
        // The cancel answer has no trial field; what was known is kept.
        #expect(entitlements.status?.offersTrial == false)
        let cancel = try #require(channel.recorded.last)
        #expect(cancel.url?.path == "/api/subscriptions/cancel")
        #expect(cancel.httpMethod == "POST")
    }
}

struct SubscriptionStatusDecodingTests {
    private func decode(_ json: String) throws -> SubscriptionStatus {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SubscriptionStatus.self, from: Data(json.utf8))
    }

    @Test func decodesAPremiumSubscription() throws {
        let status = try decode("""
        {"tier": "premium", "plan": "monthly", "status": "active",
         "current_period_end": 1999999999, "cancel_at_period_end": true, "platform": "apple"}
        """)

        #expect(status.isPremium)
        #expect(status.plan == "monthly")
        #expect(status.cancelAtPeriodEnd == true)
    }

    @Test func decodesAFreeTierWithNullOptionalFields() throws {
        let status = try decode("""
        {"tier": "free", "plan": null, "status": null,
         "current_period_end": null, "cancel_at_period_end": null, "platform": null}
        """)

        #expect(!status.isPremium)
        #expect(status.plan == nil)
    }

}
