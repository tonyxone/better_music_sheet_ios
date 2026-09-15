import Foundation

/// The signed-in session: our own backend's JWT, plus Cognito's refresh token
/// so it can be re-minted without another sign-in. Cognito's ID token is
/// traded in once at `POST /api/auth/token` and never kept.
nonisolated struct Session: Codable, Sendable, Hashable {
    /// Our backend's JWT, not Cognito's.
    var token: String
    /// Epoch seconds, for the token above.
    var expiresAt: Double
    /// Cognito's, to re-mint without another sign-in. Nil when unavailable.
    var refreshToken: String?
    var user: User

    /// Refresh a little before the backend token actually expires, so a
    /// request in flight can't land on the far side of the boundary.
    static let refreshSkewSeconds: Double = 60

    var isFresh: Bool {
        expiresAt - Session.refreshSkewSeconds > Date().timeIntervalSince1970
    }
}

actor SessionStore {
    static let shared = SessionStore()

    private static let key = "bms_auth"
    private let store: SecretStore
    private var loaded = false
    private var session: Session?

    init(store: SecretStore = KeychainStore()) {
        self.store = store
    }

    func current() -> Session? {
        if !loaded {
            loaded = true
            session = store.string(for: Self.key)
                .flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
        }
        return session
    }

    func save(_ session: Session) {
        self.session = session
        loaded = true
        if let data = try? JSONEncoder().encode(session) {
            store.set(String(decoding: data, as: UTF8.self), for: Self.key)
        }
    }

    func clear() {
        session = nil
        loaded = true
        store.set(nil, for: Self.key)
    }

    /// A synchronous existence check — is there a saved session at all,
    /// valid or not — for the one place that can't afford to await an actor
    /// hop before its first render: RootView deciding whether a returning,
    /// signed-in visitor should see the welcome splash at all. Actual
    /// validity (and refreshing an expired token) stays `current()`'s job.
    nonisolated static func hasStoredSession(store: SecretStore = KeychainStore()) -> Bool {
        store.string(for: key) != nil
    }
}
