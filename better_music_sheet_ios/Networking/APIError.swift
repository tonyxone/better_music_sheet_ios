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
            "The app built an invalid request."
        case .transport(let message):
            message
        case .http(let status, let detail):
            detail ?? "The server returned an error (\(status))."
        case .decoding(let message):
            "The server sent something unexpected. \(message)"
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
