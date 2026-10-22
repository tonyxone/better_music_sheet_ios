import Foundation

nonisolated enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case transport(String)
    /// The backend explains itself in a `detail` string; pass that through
    /// rather than only the status code.
    case http(status: Int, detail: String?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "The app built an invalid request.", bundle: .app)
        case .transport(let message):
            message
        case .http(let status, let detail):
            // The server explains itself in English; shown in the app's language
            // when it's one of the messages ServerText knows.
            detail.map(ServerText.translate) ?? String(localized: "The server returned an error (\(status)).", bundle: .app)
        case .decoding(let message):
            String(localized: "The server sent something unexpected. \(message)", bundle: .app)
        }
    }

    /// A busy backend (one sheet at a time) is a normal state, not a failure.
    var isAlreadyProcessing: Bool {
        if case .http(let status, _) = self { return status == 409 }
        return false
    }

    var isNotFound: Bool {
        if case .http(let status, _) = self { return status == 404 }
        return false
    }
}
