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
    static let cognitoRegion: String? = nil
    static let cognitoClientID: String? = nil

    static var isAuthConfigured: Bool { cognitoRegion != nil && cognitoClientID != nil }

    /// Matches the backend's own cap (`MAX_UPLOAD_BYTES`).
    static let maxUploadBytes = 32 * 1024 * 1024
}
