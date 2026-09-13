import Foundation
import Testing
@testable import better_music_sheet_ios

/// Intercepts requests so the client can be exercised without a backend.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Exchange: Sendable {
        var status: Int = 200
        var body: Data = Data("{}".utf8)
    }

    nonisolated(unsafe) private static var queue: [Exchange] = []
    nonisolated(unsafe) private(set) static var seen: [URLRequest] = []
    private static let lock = NSLock()

    static func reset(_ exchanges: [Exchange]) {
        lock.withLock {
            queue = exchanges
            seen = []
        }
    }

    static func recorded() -> [URLRequest] { lock.withLock { seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let exchange: Exchange = Self.lock.withLock {
            Self.seen.append(request)
            return Self.queue.isEmpty ? Exchange() : Self.queue.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: exchange.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: exchange.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }
}

@Suite(.serialized)
struct APIClientTests {
    private let base = URL(string: "https://api.example.com")!

    private func client() -> APIClient {
        APIClient(baseURL: base,
                  urlSession: StubProtocol.session(),
                  sessions: SessionStore(store: InMemorySecretStore()),
                  guestID: GuestID(store: InMemorySecretStore()))
    }

    @Test func signedOutCallsCarryTheGuestIDAndNoToken() async throws {
        StubProtocol.reset([.init(body: Data("[]".utf8))])
        let jobs: [AnnotationJob] = try await client().get("/api/sheets")

        #expect(jobs.isEmpty)
        let request = try #require(StubProtocol.recorded().first)
        #expect(request.url?.absoluteString == "https://api.example.com/api/sheets")
        // Exactly one identity, never both: the backend prefers the token and
        // would ignore the guest id anyway.
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let guest = try #require(request.value(forHTTPHeaderField: "X-Guest-Id"))
        #expect(!guest.isEmpty)
    }

    @Test func signedInCallsCarryTheTokenAndNoGuestID() async throws {
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(Session(
            token: "backend-jwt",
            expiresAt: Date().timeIntervalSince1970 + 3600,
            refreshToken: nil,
            user: User(userID: "u1", email: "a@example.com", displayName: "Ada", createdAt: 0)
        ))
        StubProtocol.reset([.init(body: Data("[]".utf8))])

        let client = APIClient(baseURL: base,
                               urlSession: StubProtocol.session(),
                               sessions: sessions,
                               guestID: GuestID(store: InMemorySecretStore()))
        let _: [AnnotationJob] = try await client.get("/api/sheets")

        let request = try #require(StubProtocol.recorded().first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer backend-jwt")
        #expect(request.value(forHTTPHeaderField: "X-Guest-Id") == nil)
    }

    @Test func anExpiredTokenIsNotSent() async throws {
        let sessions = SessionStore(store: InMemorySecretStore())
        await sessions.save(Session(
            token: "stale",
            expiresAt: Date().timeIntervalSince1970 - 10,
            refreshToken: nil,
            user: User(userID: "u1", email: nil, displayName: nil, createdAt: 0)
        ))
        StubProtocol.reset([.init(body: Data("[]".utf8))])

        let client = APIClient(baseURL: base,
                               urlSession: StubProtocol.session(),
                               sessions: sessions,
                               guestID: GuestID(store: InMemorySecretStore()))
        let _: [AnnotationJob] = try await client.get("/api/sheets")

        let request = try #require(StubProtocol.recorded().first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Guest-Id") != nil)
    }

    @Test func surfacesTheBackendsOwnDetailString() async throws {
        StubProtocol.reset([
            .init(status: 409, body: Data(#"{"detail": "You already have a sheet processing."}"#.utf8))
        ])

        await #expect(throws: APIError.self) {
            let _: [AnnotationJob] = try await client().get("/api/sheets")
        }

        StubProtocol.reset([
            .init(status: 409, body: Data(#"{"detail": "You already have a sheet processing."}"#.utf8))
        ])
        do {
            let _: [AnnotationJob] = try await client().get("/api/sheets")
            Issue.record("expected the call to throw")
        } catch let error as APIError {
            #expect(error.errorDescription == "You already have a sheet processing.")
            #expect(error.isAlreadyProcessing)
        }
    }

    @Test func fallsBackToTheStreamingEndpointWhenAssetsIsMissing() async throws {
        // A backend deployed before /assets existed answers 404; the app must
        // fall through to the older streaming route rather than give up.
        StubProtocol.reset([
            .init(status: 404, body: Data(#"{"detail": "not found"}"#.utf8)),
            .init(status: 200, body: Data("%PDF-1.7 fake".utf8)),
        ])

        let files = SheetFiles(client: client())
        let data = try await files.data(jobID: "job123", artifact: .pdf)

        #expect(String(decoding: data, as: UTF8.self) == "%PDF-1.7 fake")
        let paths = StubProtocol.recorded().compactMap(\.url?.path)
        #expect(paths == ["/api/sheets/job123/assets", "/api/sheets/job123/download"])
    }

    @Test func presignedFetchesDropOurCredentials() async throws {
        StubProtocol.reset([
            .init(body: Data(#"{"direct": true, "pdf": "https://s3.example.com/x.pdf", "timeline": null}"#.utf8)),
            .init(body: Data("%PDF-1.7 fake".utf8)),
        ])

        let files = SheetFiles(client: client())
        _ = try await files.data(jobID: "job123", artifact: .pdf)

        let s3 = try #require(StubProtocol.recorded().last)
        #expect(s3.url?.host() == "s3.example.com")
        // Neither identity may travel to another origin.
        #expect(s3.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(s3.value(forHTTPHeaderField: "X-Guest-Id") == nil)
    }
}

struct AnnotationJobTests {
    private func decode(_ json: String) throws -> AnnotationJob {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AnnotationJob.self, from: Data(json.utf8))
    }

    @Test func decodesAFinishedJob() throws {
        let job = try decode("""
        {"job_id": "abc", "music_sheet_id": "sheet-1", "status": "done",
         "sheet_name": "Menuet in G.pdf", "error": null, "stage": "Complete",
         "labeled_groups": 214, "style": "unicode", "octave": false,
         "font_size": 6.5, "dpi": null, "created_at": 1757600000, "updated_at": 1757600100}
        """)

        #expect(job.jobID == "abc")
        #expect(job.musicSheetID == "sheet-1")
        #expect(job.status == .done)
        #expect(job.labeledGroups == 214)
        #expect(job.dpi == nil)
        #expect(job.displayName == "Menuet in G.pdf")
        #expect(!job.status.isInProgress)
    }

    @Test func treatsAnUnfamiliarStatusAsUnknownRatherThanFailing() throws {
        // A status added to the API later must not fail the whole decode and
        // empty someone's library.
        let job = try decode("""
        {"job_id": "abc", "music_sheet_id": "s", "status": "transcoding",
         "error": null, "stage": null, "labeled_groups": null, "style": "unicode",
         "octave": false, "font_size": 6.5, "dpi": null,
         "created_at": 1, "updated_at": 2}
        """)

        #expect(job.status == .unknown)
        #expect(!job.status.isInProgress)
        #expect(job.displayName == "s")  // falls back to the sheet id
    }

    @Test func inProgressStatesAreTheOnesWorthPolling() throws {
        #expect(AnnotationJob.Status.uploading.isInProgress)
        #expect(AnnotationJob.Status.queued.isInProgress)
        #expect(AnnotationJob.Status.processing.isInProgress)
        #expect(!AnnotationJob.Status.done.isInProgress)
        #expect(!AnnotationJob.Status.failed.isInProgress)
    }
}
