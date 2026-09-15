import Foundation
import Testing
@testable import better_music_sheet_ios

struct CognitoAuthTests {
    @Test func socialSignInURLCarriesTheRightQueryParameters() throws {
        let url = try CognitoAuth.socialSignInURL(provider: .google, redirectURI: "bettermusicsheet://auth/callback")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.host == "better-music-sheet.auth.us-west-1.amazoncognito.com")
        #expect(components.path == "/oauth2/authorize")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["identity_provider"] == "Google")
        #expect(items["redirect_uri"] == "bettermusicsheet://auth/callback")
        #expect(items["response_type"] == "code")
        #expect(items["client_id"] == AppConfig.cognitoClientID)
    }

    @Test func signInWithPasswordReturnsTheTokens() async throws {
        let channel = StubProtocol.Channel([
            .init(body: Data(#"{"AuthenticationResult": {"IdToken": "id", "AccessToken": "at", "RefreshToken": "rt"}}"#.utf8)),
        ])

        let tokens = try await CognitoAuth.signInWithPassword(email: "a@example.com", password: "pw", urlSession: channel.session())

        #expect(tokens.idToken == "id")
        #expect(tokens.refreshToken == "rt")
        let request = try #require(channel.recorded.first)
        #expect(request.value(forHTTPHeaderField: "X-Amz-Target") == "AWSCognitoIdentityProviderService.InitiateAuth")
    }

    @Test func signInWithPasswordSurfacesCognitosOwnErrorCode() async throws {
        let channel = StubProtocol.Channel([
            .init(status: 400, body: Data(#"{"__type": "NotAuthorizedException", "message": "Incorrect username or password."}"#.utf8)),
        ])

        await #expect(throws: CognitoError.self) {
            _ = try await CognitoAuth.signInWithPassword(email: "a@example.com", password: "wrong", urlSession: channel.session())
        }
    }

    @Test func signUpReturnsTrueWhenTheAccountStillNeedsConfirmation() async throws {
        let channel = StubProtocol.Channel([.init(body: Data(#"{"UserConfirmed": false}"#.utf8))])

        let needsCode = try await CognitoAuth.signUp(email: "a@example.com", password: "pw", name: "Ada", urlSession: channel.session())

        #expect(needsCode)
    }
}

struct AuthServiceTests {
    private func user(_ id: String = "u1") -> User {
        User(userID: id, email: nil, displayName: nil, createdAt: 0)
    }

    @Test func freshSessionReturnsTheStoredTokenWithoutANetworkCall() async throws {
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(Session(token: "fresh-jwt", expiresAt: Date().timeIntervalSince1970 + 3600,
                                    refreshToken: "refresh-1", user: user()))
        let channel = StubProtocol.Channel([])
        let auth = AuthService(sessions: sessions, urlSession: channel.session())

        let token = await auth.validAccessToken()

        #expect(token == "fresh-jwt")
        #expect(channel.recorded.isEmpty)
    }

    @Test func expiredSessionWithNoRefreshTokenIsCleared() async throws {
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(Session(token: "stale", expiresAt: Date().timeIntervalSince1970 - 10,
                                    refreshToken: nil, user: user()))
        let auth = AuthService(sessions: sessions, urlSession: StubProtocol.Channel([]).session())

        let token = await auth.validAccessToken()

        #expect(token == nil)
        let stored = await sessions.current()
        #expect(stored == nil)
    }

    @Test func expiredSessionWithARefreshTokenReMintsTheBackendToken() async throws {
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(Session(token: "stale", expiresAt: Date().timeIntervalSince1970 - 10,
                                    refreshToken: "refresh-1", user: user()))
        let channel = StubProtocol.Channel([
            .init(body: Data(#"{"AuthenticationResult": {"IdToken": "id-2", "AccessToken": "at", "ExpiresIn": 3600}}"#.utf8)),
            .init(body: Data(#"""
            {"access_token": "new-jwt", "expires_in": 3600,
             "user": {"user_id": "u1", "email": "a@example.com", "display_name": "Ada", "created_at": 0}}
            """#.utf8)),
        ])
        let auth = AuthService(sessions: sessions, urlSession: channel.session())

        let token = await auth.validAccessToken()

        #expect(token == "new-jwt")
        let stored = await sessions.current()
        // Cognito doesn't reissue a refresh token on this grant — the old one is kept.
        #expect(stored?.refreshToken == "refresh-1")
        #expect(stored?.user.displayName == "Ada")
        #expect(channel.recorded.count == 2)
        #expect(channel.recorded[0].url?.host == "cognito-idp.us-west-1.amazonaws.com")
        #expect(channel.recorded[1].url?.path == "/api/auth/token")
    }

    @Test func aFailedRefreshClearsTheSessionRatherThanTrappingTheVisitor() async throws {
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(Session(token: "stale", expiresAt: Date().timeIntervalSince1970 - 10,
                                    refreshToken: "expired-refresh", user: user()))
        let channel = StubProtocol.Channel([
            .init(status: 400, body: Data(#"{"__type": "NotAuthorizedException", "message": "Refresh Token has expired"}"#.utf8)),
        ])
        let auth = AuthService(sessions: sessions, urlSession: channel.session())

        let token = await auth.validAccessToken()

        #expect(token == nil)
        let stored = await sessions.current()
        #expect(stored == nil)
    }

    @Test func passwordSignInSavesASessionWithCognitosRefreshToken() async throws {
        let sessions = SessionStore(store: InMemorySecretStore())
        let channel = StubProtocol.Channel([
            .init(body: Data(#"{"AuthenticationResult": {"IdToken": "id", "AccessToken": "at", "RefreshToken": "rt"}}"#.utf8)),
            .init(body: Data(#"""
            {"access_token": "backend-jwt", "expires_in": 3600,
             "user": {"user_id": "u1", "email": "a@example.com", "display_name": "Ada", "created_at": 0}}
            """#.utf8)),
        ])
        let auth = AuthService(sessions: sessions, urlSession: channel.session())

        let session = try await auth.signIn(email: "a@example.com", password: "pw")

        #expect(session.token == "backend-jwt")
        #expect(session.refreshToken == "rt")
        let stored = await sessions.current()
        #expect(stored?.user.email == "a@example.com")
    }

    @Test func signOutClearsTheSession() async throws {
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(Session(token: "t", expiresAt: Date().timeIntervalSince1970 + 3600,
                                    refreshToken: nil, user: user()))
        let auth = AuthService(sessions: sessions, urlSession: StubProtocol.Channel([]).session())

        await auth.signOut()

        let stored = await sessions.current()
        #expect(stored == nil)
    }
}
