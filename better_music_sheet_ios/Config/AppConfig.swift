import Foundation

/// Where the app points and what it is allowed to do there.
///
/// The backend (`server.py`) and Cognito identifiers are public values, not
/// secrets — they ship in the web app's JS bundle by design. They live here
/// rather than in an xcconfig for now so the project file needs no surgery;
/// moving them to Debug/Release xcconfig is a later, mechanical change.
nonisolated enum AppConfig {
    /// Overridable at runtime so a debug build can be pointed at a local
    /// `server.py` without a rebuild. Note that plain-HTTP localhost also
    /// needs an ATS exception before it will load.
    private static let apiBaseOverrideKey = "api_base_override"

    static var apiBase: URL {
        if let raw = UserDefaults.standard.string(forKey: apiBaseOverrideKey),
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://api.bettermusicsheet.com")!
    }

    static func setAPIBaseOverride(_ raw: String?) {
        UserDefaults.standard.set(raw, forKey: apiBaseOverrideKey)
    }

    /// Sign-in is optional everywhere. With no user pool configured the app
    /// still uploads, annotates and plays the free lines as a guest — the
    /// sign-in affordance simply doesn't appear (mirrors lib/cognito.ts).
    ///
    /// Same user pool and app client as the web app (see infra/cognito.tf in
    /// the BetterMusicSheet repo) — an account created on one is the same
    /// account on the other, since both trade a Cognito ID token in at the
    /// same `POST /api/auth/token`.
    static let cognitoRegion: String? = "us-west-1"
    static let cognitoClientID: String? = "2qfqlrplc15p0nnhpeaumi9vbt"
    static let cognitoDomain = "https://better-music-sheet.auth.us-west-1.amazoncognito.com"

    static var isAuthConfigured: Bool { cognitoRegion != nil && cognitoClientID != nil }

    /// Which social buttons to show — mirrors NEXT_PUBLIC_COGNITO_SOCIAL_PROVIDERS.
    /// Facebook is configured on the pool but not offered here or on the web.
    static let configuredSocialProviders: [SocialProvider] = [.google, .signInWithApple]

    /// Where Cognito's hosted UI redirects after a social sign-in. A custom
    /// scheme rather than the web app's `https://.../auth/callback/`: there's
    /// no page here to receive it, and ASWebAuthenticationSession intercepts
    /// whatever scheme it's told to watch for without it needing to be
    /// declared in Info.plist. Must appear verbatim in the Cognito app
    /// client's callback_urls (see infra/cognito.tf) or the exchange fails.
    static let authCallbackScheme = "bettermusicsheet"
    static let authCallbackURL = "bettermusicsheet://auth/callback"

    /// Matches the backend's own cap (`MAX_UPLOAD_BYTES`).
    static let maxUploadBytes = 32 * 1024 * 1024
}
