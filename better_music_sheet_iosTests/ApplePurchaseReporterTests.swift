import Foundation
import Testing
@testable import better_music_sheet_ios

@MainActor
struct ApplePurchaseReporterTests {
    private let userID = "44444444-4444-4444-8444-444444444444"

    private func setup(_ responses: [StubProtocol.Exchange]) async -> (ApplePurchaseReporter, StubProtocol.Channel, EntitlementStore) {
        let channel = StubProtocol.Channel(responses)
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(Session(token: "jwt", expiresAt: Date().timeIntervalSince1970 + 3600,
                                    refreshToken: nil,
                                    user: User(userID: userID, email: nil, displayName: nil, createdAt: 0)))
        let client = APIClient(baseURL: URL(string: "https://api.example.com")!,
                               urlSession: channel.session(), sessions: sessions,
                               guestID: GuestID(store: InMemorySecretStore()))
        let entitlements = EntitlementStore(client: client, sessions: sessions,
                                             defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return (ApplePurchaseReporter(client: client, sessions: sessions, entitlements: entitlements), channel, entitlements)
    }

    @Test func failedDeliveryThrowsAndDoesNotUnlockPremium() async throws {
        let (reporter, channel, entitlements) = await setup([
            .init(status: 503, body: Data(#"{"detail":"Apple billing is not configured"}"#.utf8))
        ])
        await #expect(throws: APIError.self) {
            try await reporter.report("signed-transaction", userID: userID)
        }
        #expect(!entitlements.isEntitled)
        #expect(channel.recorded.count == 1)
    }

    @Test func acknowledgedPurchaseUnlocksWithoutASecondNetworkRequest() async throws {
        let (reporter, channel, entitlements) = await setup([
            .init(body: Data(#"{"tier":"premium","plan":"monthly","status":"active","platform":"apple","cancel_at_period_end":false}"#.utf8))
        ])
        try await reporter.report("signed-transaction", userID: userID)
        #expect(entitlements.isEntitled)
        #expect(entitlements.status?.platform == "apple")
        #expect(channel.recorded.count == 1)
        let request = try #require(channel.recorded.first)
        #expect(request.url?.path == "/api/subscriptions/apple/transaction")
    }

    @Test func accountMismatchStopsDeliveryBeforeSending() async {
        let (reporter, channel, entitlements) = await setup([])
        await #expect(throws: SubscriptionError.self) {
            try await reporter.report("signed-transaction", userID: "another-account")
        }
        #expect(channel.recorded.isEmpty)
        #expect(!entitlements.isEntitled)
    }
}
