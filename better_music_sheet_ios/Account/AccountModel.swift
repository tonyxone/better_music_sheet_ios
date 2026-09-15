import Foundation

@MainActor
@Observable
final class AccountModel {
    enum State: Sendable {
        case checking
        case signedOut
        case signedIn(User)
    }

    private(set) var state: State = .checking
    /// One shared flag for whichever request is in flight — only one of the
    /// actions below can run at a time from the sign-in form.
    private(set) var busy = false
    private(set) var busyProvider: SocialProvider?
    /// Flips true exactly once, when an active sign-in completes — not when
    /// `load()` merely finds an already-signed-in session. AccountView
    /// watches this (rather than `state` itself) to auto-dismiss only after
    /// something the visitor just did, never when they open the screen to
    /// look at an account they were already signed into.
    private(set) var justSignedIn = false

    private let sessions: SessionStore
    private let authService: AuthService
    private let client: APIClient

    init(sessions: SessionStore = .shared, authService: AuthService = .shared, client: APIClient = .shared) {
        self.sessions = sessions
        self.authService = authService
        self.client = client
    }

    var isAuthConfigured: Bool { AppConfig.isAuthConfigured }
    var availableProviders: [SocialProvider] { AppConfig.configuredSocialProviders }

    func load() async {
        if let session = await sessions.current() {
            state = .signedIn(session.user)
        } else {
            state = .signedOut
        }
    }

    // MARK: - Social sign-in

    func signIn(with provider: SocialProvider) async throws {
        busyProvider = provider
        defer { busyProvider = nil }
        let session = try await authService.signIn(provider: provider)
        state = .signedIn(session.user)
        justSignedIn = true
    }

    // MARK: - Email + password

    func signIn(email: String, password: String) async throws {
        busy = true
        defer { busy = false }
        let session = try await authService.signIn(email: email, password: password)
        state = .signedIn(session.user)
        justSignedIn = true
    }

    /// Returns true when Cognito still needs the emailed code before the new
    /// account can sign in.
    func signUp(email: String, password: String, name: String) async throws -> Bool {
        busy = true
        defer { busy = false }
        return try await CognitoAuth.signUp(email: email, password: password, name: name, urlSession: .shared)
    }

    func confirmSignUp(email: String, code: String) async throws {
        busy = true
        defer { busy = false }
        try await CognitoAuth.confirmSignUp(email: email, code: code, urlSession: .shared)
    }

    func resendConfirmationCode(email: String) async throws {
        try await CognitoAuth.resendConfirmationCode(email: email, urlSession: .shared)
    }

    func forgotPassword(email: String) async throws {
        busy = true
        defer { busy = false }
        try await CognitoAuth.forgotPassword(email: email, urlSession: .shared)
    }

    func confirmForgotPassword(email: String, code: String, newPassword: String) async throws {
        busy = true
        defer { busy = false }
        try await CognitoAuth.confirmForgotPassword(email: email, code: code, newPassword: newPassword, urlSession: .shared)
    }

    func signOut() async {
        await authService.signOut()
        state = .signedOut
    }

    /// Permanently deletes the signed-in account — required by Apple's App
    /// Store guideline 5.1.1(v) for any app that supports account creation.
    /// The backend deletes the Cognito identity and this account's history
    /// itself; there's nothing left to undo locally afterward beyond the
    /// same cleanup a sign-out already does.
    func deleteAccount() async throws {
        try await client.send("/api/me", method: "DELETE")
        await signOut()
    }
}
