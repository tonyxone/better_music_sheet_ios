import Foundation

/// Whether this viewer has hidden the "Try a sample" entry from their
/// library. Only ever hides it for them — never touches the demo job itself.
///
/// A signed-in account keeps the choice on the server (GET/PUT
/// /api/me/demo-hidden), so it follows them to the web app and other
/// devices; a guest has no account to attach it to and keeps it on this
/// device. Mirrors the web app's lib/demo-hidden.ts.
@MainActor
@Observable
final class DemoVisibility {
    /// Nil until the first read settles, so the entry doesn't flash in and
    /// then vanish.
    private(set) var isHidden: Bool?

    private static let localKey = "bms-demo-hidden"
    private let client: APIClient
    private let sessions: SessionStore
    private let defaults: UserDefaults

    init(client: APIClient = .shared, sessions: SessionStore = .shared, defaults: UserDefaults = .standard) {
        self.client = client
        self.sessions = sessions
        self.defaults = defaults
    }

    private struct Body: Codable { let hidden: Bool }

    func load() async {
        guard await sessions.current() != nil else {
            isHidden = defaults.bool(forKey: Self.localKey)
            return
        }
        do {
            let body: Body = try await client.get("/api/me/demo-hidden")
            isHidden = body.hidden
        } catch {
            // Fail open, as the web app does: showing the sample is harmless.
            isHidden = isHidden ?? false
        }
    }

    func setHidden(_ hidden: Bool) async {
        isHidden = hidden
        guard await sessions.current() != nil else {
            defaults.set(hidden, forKey: Self.localKey)
            return
        }
        guard let body = try? JSONEncoder().encode(Body(hidden: hidden)) else { return }
        _ = try? await client.call("/api/me/demo-hidden", method: "PUT", body: body, contentType: "application/json")
    }
}
