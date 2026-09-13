import Foundation

/// An anonymous per-install id, generated once and kept in the secret store.
///
/// The web app keeps the equivalent in a cookie on its own origin and sends
/// it as a header, because the API is on a different origin (see the web
/// app's lib/guest-id.ts). Here there is no cookie jar to worry about: it is
/// simply attached as `X-Guest-Id` whenever there is no signed-in token.
///
/// It lets the backend separate one visitor's uploads, history and quota from
/// another's with no real sign-in.
nonisolated struct GuestID: Sendable {
    static let key = "guest_id"

    private let store: SecretStore

    init(store: SecretStore = KeychainStore()) {
        self.store = store
    }

    func current() -> String {
        if let existing = store.string(for: Self.key), !existing.isEmpty { return existing }
        let fresh = UUID().uuidString
        store.set(fresh, for: Self.key)
        return fresh
    }
}
