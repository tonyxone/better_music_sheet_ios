import Foundation

/// Every API call goes through here so identity is attached consistently:
/// the signed-in user's backend token when there is one, and the anonymous
/// per-install guest id otherwise. Only ever one of the two — the backend
/// prefers the token and would ignore the guest id anyway (see auth.py).
actor APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let urlSession: URLSession
    private let sessions: SessionStore
    private let guestID: GuestID
    private let authService: AuthService
    private let decoder: JSONDecoder

    init(baseURL: URL = AppConfig.apiBase,
         urlSession: URLSession = .shared,
         sessions: SessionStore = .shared,
         guestID: GuestID = GuestID(),
         authService: AuthService? = nil) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.sessions = sessions
        self.guestID = guestID
        self.authService = authService ?? AuthService(sessions: sessions, urlSession: urlSession)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    // MARK: - Typed helpers

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await call(path)
        return try decode(data)
    }

    func post<Body: Encodable, T: Decodable>(_ path: String,
                                             body: Body,
                                             as type: T.Type = T.self) async throws -> T {
        let encoded = try JSONEncoder().encode(body)
        let (data, _) = try await call(path, method: "POST", body: encoded, contentType: "application/json")
        return try decode(data)
    }

    /// For endpoints whose success carries no body worth reading — a 204, or
    /// the fire-and-forget upload completion.
    func send(_ path: String, method: String) async throws {
        _ = try await call(path, method: method)
    }

    // MARK: - Core

    /// A request against our own API, with identity attached. Non-2xx becomes
    /// an `APIError.http` carrying the backend's own `detail` string when it
    /// sent one.
    @discardableResult
    func call(_ path: String,
              method: String = "GET",
              body: Data? = nil,
              contentType: String? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        await attachIdentity(to: &request)

        var (data, http) = try await perform(request)

        // A rejected token means the session is gone, not that the user is
        // blocked: drop it and let the request land as a guest rather than
        // trapping them on a broken session.
        if http.statusCode == 401, await sessions.current() != nil {
            await sessions.clear()
            var retry = request
            retry.setValue(nil, forHTTPHeaderField: "Authorization")
            await attachIdentity(to: &retry)
            (data, http) = try await perform(retry)
        }

        try check(http, data)
        return (data, http)
    }

    /// A POST to another origin — an S3 presigned upload — which likewise
    /// must not carry our identity. S3 authorises the request from the signed
    /// policy fields in the body, not from any header of ours.
    @discardableResult
    func postExternal(_ url: URL, body: Data, contentType: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (data, http) = try await perform(request)
        try check(http, data)
        return (data, http)
    }

    /// A fetch that must NOT carry our identity — a presigned S3 URL lives on
    /// another origin, where our credentials would only leak.
    func fetchExternal(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, http) = try await perform(request)
        try check(http, data)
        return data
    }

    // MARK: - Internals

    private func attachIdentity(to request: inout URLRequest) async {
        if let token = await authService.validAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(guestID.current(), forHTTPHeaderField: "X-Guest-Id")
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let error as URLError {
            // "Could not connect to the server" tells the user nothing about
            // which server. Name it, the way the web app does.
            throw APIError.transport("Couldn't reach \(request.url?.host() ?? "the server"). \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("The server sent no response.")
        }
        return (data, http)
    }

    private func check(_ response: HTTPURLResponse, _ data: Data) throws {
        guard !(200..<300).contains(response.statusCode) else { return }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        throw APIError.http(status: response.statusCode, detail: body?["detail"] as? String)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
