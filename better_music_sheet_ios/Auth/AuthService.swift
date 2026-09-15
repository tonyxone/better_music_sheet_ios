import Foundation

/// Bridges Cognito's hosted UI and this backend's own token exchange into a
/// signed-in Session, and keeps that session fresh. Mirrors the web app's
/// lib/auth.ts, adapted for a native OAuth redirect
/// (ASWebAuthenticationSession) in place of a page navigation to
/// /auth/callback.
///
/// Two tokens are in play, deliberately: Cognito's ID token, obtained here
/// and immediately traded in at POST /api/auth/token or /api/auth/social,
/// and never sent to this app's backend again; and this backend's own JWT,
/// which every other API call carries (see SessionStore, APIClient).
actor AuthService {
    static let shared = AuthService()

    private let sessions: SessionStore
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(sessions: SessionStore = .shared, urlSession: URLSession = .shared) {
        self.sessions = sessions
        self.urlSession = urlSession
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    /// Starts the hosted-UI flow for `provider` in a system browser sheet,
    /// exchanges the authorization code it comes back with for a backend
    /// session, and saves it.
    func signIn(provider: SocialProvider) async throws -> Session {
        guard AppConfig.configuredSocialProviders.contains(provider) else { throw AuthError.notConfigured }
        let redirectURI = AppConfig.authCallbackURL
        let authorizeURL = try CognitoAuth.socialSignInURL(provider: provider, redirectURI: redirectURI)
        let callbackURL = try await WebAuthPresenter.present(url: authorizeURL, callbackScheme: AppConfig.authCallbackScheme)
        let code = try Self.code(from: callbackURL)

        let response: SocialResponse = try await postForSession("/api/auth/social", body: [
            "code": code,
            "redirect_uri": redirectURI,
        ])
        let session = Session(token: response.accessToken,
                              expiresAt: Date().timeIntervalSince1970 + (response.expiresIn ?? 3600),
                              refreshToken: response.refreshToken,
                              user: response.user)
        await sessions.save(session)
        return session
    }

    /// Signs in with email + password and establishes a session. The
    /// password itself never reaches this app's own backend — CognitoAuth
    /// sends it straight to Cognito over TLS, and only the resulting ID
    /// token is traded in here, at POST /api/auth/token.
    func signIn(email: String, password: String) async throws -> Session {
        let tokens = try await CognitoAuth.signInWithPassword(email: email, password: password, urlSession: urlSession)
        let response: TokenResponse = try await postForSession("/api/auth/token", body: ["id_token": tokens.idToken])
        let session = Session(token: response.accessToken,
                              expiresAt: Date().timeIntervalSince1970 + (response.expiresIn ?? 3600),
                              refreshToken: tokens.refreshToken,
                              user: response.user)
        await sessions.save(session)
        return session
    }

    /// The current backend token, refreshed if it's expired or about to be.
    /// nil means "not signed in" — callers fall back to the guest id.
    func validAccessToken() async -> String? {
        guard let session = await sessions.current() else { return nil }
        if session.isFresh { return session.token }

        guard let refreshToken = session.refreshToken else {
            await sessions.clear()
            return nil
        }
        do {
            let tokens = try await CognitoAuth.refreshTokens(refreshToken, urlSession: urlSession)
            let response: TokenResponse = try await postForSession("/api/auth/token", body: ["id_token": tokens.idToken])
            // Cognito doesn't return a new refresh token on this grant — keep ours.
            let refreshed = Session(token: response.accessToken,
                                    expiresAt: Date().timeIntervalSince1970 + (response.expiresIn ?? 3600),
                                    refreshToken: refreshToken,
                                    user: response.user)
            await sessions.save(refreshed)
            return refreshed.token
        } catch {
            // Refresh token expired or revoked: drop back to guest rather
            // than trapping the visitor on a session that can't be renewed.
            await sessions.clear()
            return nil
        }
    }

    func signOut() async {
        await sessions.clear()
    }

    // MARK: - Internals

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Double?
        let user: User
    }

    private struct SocialResponse: Decodable {
        let accessToken: String
        let expiresIn: Double?
        let refreshToken: String?
        let user: User
    }

    private func postForSession<T: Decodable>(_ path: String, body: [String: String]) async throws -> T {
        guard let url = URL(string: path, relativeTo: AppConfig.apiBase) else { throw AuthError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AuthError.transport("Couldn't reach the app backend. \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.transport("The server sent no response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AuthError.server((body?["detail"] as? String) ?? "Sign-in failed (\(http.statusCode)).")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AuthError.invalidCallback
        }
    }

    /// The hosted-UI redirect can carry an authorization code, or the
    /// provider's/Cognito's own error instead — most commonly someone
    /// dismissing the provider's login sheet.
    private static func code(from callbackURL: URL) throws -> String {
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value {
            throw AuthError.server(error == "access_denied" ? "Sign-in was cancelled." : "Sign-in failed (\(error)).")
        }
        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.invalidCallback
        }
        return code
    }
}
