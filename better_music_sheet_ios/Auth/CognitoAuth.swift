import Foundation

/// Talks to Cognito directly: the hosted-UI URL that starts a social sign-in,
/// and every direct user-pool API call the email/password flow needs.
/// Mirrors the web app's lib/cognito.ts.
///
/// No AWS SDK: the app client has no secret (it's a public client — see
/// infra/cognito.tf), so every call here is a plain, unauthenticated JSON
/// POST identified by an X-Amz-Target header rather than a signed request.
nonisolated enum CognitoAuth {
    struct Tokens: Sendable {
        let idToken: String
        let accessToken: String
        let refreshToken: String?
    }

    /// The hosted-UI URL that starts a social sign-in. Presented in
    /// ASWebAuthenticationSession — Google and Apple both need their own
    /// real page to sign in on, which a plain network request can't show.
    static func socialSignInURL(provider: SocialProvider, redirectURI: String) throws -> URL {
        guard AppConfig.isAuthConfigured, let clientID = AppConfig.cognitoClientID else {
            throw AuthError.notConfigured
        }
        guard var components = URLComponents(string: "\(AppConfig.cognitoDomain)/oauth2/authorize") else {
            throw AuthError.notConfigured
        }
        components.queryItems = [
            URLQueryItem(name: "identity_provider", value: provider.rawValue),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "scope", value: "openid email profile"),
        ]
        guard let url = components.url else { throw AuthError.notConfigured }
        return url
    }

    static func signInWithPassword(email: String, password: String, urlSession: URLSession) async throws -> Tokens {
        let result = try await call("InitiateAuth", body: [
            "AuthFlow": "USER_PASSWORD_AUTH",
            "AuthParameters": ["USERNAME": email, "PASSWORD": password],
        ], urlSession: urlSession)
        guard let authResult = result["AuthenticationResult"] as? [String: Any] else {
            // A challenge (MFA, forced password reset) rather than a completed
            // sign-in. The pool isn't configured for any of these today, so
            // rather than half-implement the flows, fail loudly.
            throw CognitoError(code: (result["ChallengeName"] as? String) ?? "ChallengeRequired",
                              message: "This account needs an extra sign-in step that isn't supported yet.")
        }
        return try tokens(from: authResult)
    }

    /// Trades a still-valid refresh token for a fresh Cognito ID token,
    /// without sending the visitor back through the hosted UI.
    static func refreshTokens(_ refreshToken: String, urlSession: URLSession) async throws -> Tokens {
        let result = try await call("InitiateAuth", body: [
            "AuthFlow": "REFRESH_TOKEN_AUTH",
            "AuthParameters": ["REFRESH_TOKEN": refreshToken],
        ], urlSession: urlSession)
        guard let authResult = result["AuthenticationResult"] as? [String: Any] else {
            throw CognitoError(code: "NoResult", message: "Could not refresh session.")
        }
        return try tokens(from: authResult)
    }

    /// Returns true when Cognito still needs the emailed code before this
    /// account can sign in (the normal case for self sign-up).
    static func signUp(email: String, password: String, name: String, urlSession: URLSession) async throws -> Bool {
        // The pool's `name` attribute can't be made required after creation
        // (Cognito schema attributes are immutable), so sign-up enforces it
        // here and always sends one.
        let result = try await call("SignUp", body: [
            "Username": email,
            "Password": password,
            "UserAttributes": [
                ["Name": "email", "Value": email],
                ["Name": "name", "Value": name.trimmingCharacters(in: .whitespacesAndNewlines)],
            ],
        ], urlSession: urlSession)
        return !((result["UserConfirmed"] as? Bool) ?? true)
    }

    static func confirmSignUp(email: String, code: String, urlSession: URLSession) async throws {
        _ = try await call("ConfirmSignUp", body: ["Username": email, "ConfirmationCode": code], urlSession: urlSession)
    }

    static func resendConfirmationCode(email: String, urlSession: URLSession) async throws {
        _ = try await call("ResendConfirmationCode", body: ["Username": email], urlSession: urlSession)
    }

    static func forgotPassword(email: String, urlSession: URLSession) async throws {
        _ = try await call("ForgotPassword", body: ["Username": email], urlSession: urlSession)
    }

    static func confirmForgotPassword(email: String, code: String, newPassword: String, urlSession: URLSession) async throws {
        _ = try await call("ConfirmForgotPassword", body: [
            "Username": email, "ConfirmationCode": code, "Password": newPassword,
        ], urlSession: urlSession)
    }

    // MARK: - Internals

    private static func tokens(from authenticationResult: [String: Any]) throws -> Tokens {
        guard let idToken = authenticationResult["IdToken"] as? String,
              let accessToken = authenticationResult["AccessToken"] as? String else {
            throw CognitoError(code: "NoResult", message: "Cognito completed the request without returning tokens.")
        }
        return Tokens(idToken: idToken, accessToken: accessToken,
                      refreshToken: authenticationResult["RefreshToken"] as? String)
    }

    private static func call(_ target: String, body: [String: Any], urlSession: URLSession) async throws -> [String: Any] {
        guard AppConfig.isAuthConfigured, let region = AppConfig.cognitoRegion,
              let clientID = AppConfig.cognitoClientID else {
            throw CognitoError(code: "NotConfigured", message: "Sign-in isn't configured for this build.")
        }
        var payload = body
        payload["ClientId"] = clientID

        var request = URLRequest(url: URL(string: "https://cognito-idp.\(region).amazonaws.com/")!)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSCognitoIdentityProviderService.\(target)", forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            // fetch/data(for:) only throws for transport-level failures, and
            // the system hides the reason behind a generic description. Name
            // what we were trying to reach instead.
            throw CognitoError(code: "NetworkError",
                              message: "Couldn't reach the sign-in service. Check your internet connection and try again.")
        }
        guard let http = response as? HTTPURLResponse else {
            throw CognitoError(code: "NetworkError", message: "The sign-in service sent no response.")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            // Errors come back as {__type: "NotAuthorizedException", message: "..."},
            // where __type may be namespace-prefixed.
            let type = (json["__type"] as? String)?.split(separator: "#").last.map(String.init)
            throw CognitoError(code: type ?? "UnknownError",
                              message: (json["message"] as? String) ?? (json["Message"] as? String)
                                ?? "Cognito request failed (\(http.statusCode)).")
        }
        return json
    }
}
