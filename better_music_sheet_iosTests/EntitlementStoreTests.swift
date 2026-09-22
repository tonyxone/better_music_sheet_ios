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
        let channel = StubProtocol.Channel([.init(status: 500, body: Data(#"{"detail": "boom"}"#.utf8))])
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(session())
        let entitlements = store(channel: channel, sessions: sessions, defaults: defaults)
        #expect(entitlements.isEntitled)  // seeded from the cache at init

        await entitlements.refresh()

        #expect(entitlements.isEntitled)
    }

    @Test func aFreeTierResponseClearsAPreviouslyCachedEntitlement() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: Self.cacheKey)
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
