import Foundation
import Testing
@testable import better_music_sheet_ios

struct MultipartFormTests {

    @Test func encodesFieldsAndFilesInOrder() {
        var form = MultipartForm(boundary: "B")
        form.addField(name: "key", value: "uploads/abc.pdf")
        form.addFile(name: "file", filename: "score.pdf",
                     contentType: "application/pdf", data: Data("%PDF".utf8))

        let body = String(decoding: form.encoded(), as: UTF8.self)
        #expect(body == """
        --B\r
        Content-Disposition: form-data; name="key"\r
        \r
        uploads/abc.pdf\r
        --B\r
        Content-Disposition: form-data; name="file"; filename="score.pdf"\r
        Content-Type: application/pdf\r
        \r
        %PDF\r
        --B--\r

        """)
    }

    @Test func contentTypeCarriesTheBoundary() {
        let form = MultipartForm(boundary: "XYZ")
        #expect(form.contentType == "multipart/form-data; boundary=XYZ")
    }

    @Test func handlesBinaryDataWithoutMangling() {
        var form = MultipartForm(boundary: "B")
        let bytes = Data([0x00, 0xFF, 0x0D, 0x0A, 0x80])
        form.addFile(name: "file", filename: "a.png", contentType: "image/png", data: bytes)

        let encoded = form.encoded()
        #expect(encoded.range(of: bytes) != nil)
    }
}

@Suite(.serialized)
struct SheetUploaderTests {
    private let base = URL(string: "https://api.example.com")!

    private func client(_ channel: StubProtocol.Channel) -> APIClient {
        APIClient(baseURL: base,
                  urlSession: channel.session(),
                  sessions: SessionStore(store: InMemorySecretStore()),
                  guestID: GuestID(store: InMemorySecretStore()))
    }

    @Test func usesThePresignedFormAndPutsTheFileLast() async throws {
        let channel = StubProtocol.Channel([
            .init(status: 201, body: Data(#"""
            {"job_id": "job1", "upload": {"url": "https://s3.example.com/bucket",
             "fields": {"key": "uploads/job1", "policy": "abc"}}}
            """#.utf8)),
            .init(status: 204),                       // the S3 post
            .init(status: 202, body: Data("{}".utf8)) // complete
        ])

        let jobID = try await SheetUploader(client: client(channel))
            .upload(filename: "score.pdf", data: Data("%PDF-1.7".utf8), options: .standard)

        #expect(jobID == "job1")

        let requests = channel.recorded
        #expect(requests.map(\.url?.path) == ["/api/uploads", "/bucket", "/api/uploads/job1/complete"])

        // S3 ignores everything after the file part, so the file must be last
        // and every policy field must precede it.
        let s3Body = String(decoding: requests[1].httpBodyData ?? Data(), as: UTF8.self)
        let filePart = try #require(s3Body.range(of: #"name="file""#))
        #expect(s3Body.range(of: #"name="key""#)!.lowerBound < filePart.lowerBound)
        #expect(s3Body.range(of: #"name="policy""#)!.lowerBound < filePart.lowerBound)
        #expect(s3Body.contains("filename=\"score.pdf\""))
    }

    @Test func theS3PostCarriesNoneOfOurCredentials() async throws {
        let channel = StubProtocol.Channel([
            .init(status: 201, body: Data(#"{"job_id": "j", "upload": {"url": "https://s3.example.com/b", "fields": {}}}"#.utf8)),
            .init(status: 204),
            .init(status: 202, body: Data("{}".utf8)),
        ])

        _ = try await SheetUploader(client: client(channel))
            .upload(filename: "a.pdf", data: Data("x".utf8), options: .standard)

        let s3 = channel.recorded[1]
        #expect(s3.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(s3.value(forHTTPHeaderField: "X-Guest-Id") == nil)
    }

    @Test func fallsBackToTheLegacyEndpointWhenUploadsIsMissing() async throws {
        // An older backend has no /api/uploads; the app must not simply fail.
        let channel = StubProtocol.Channel([
            .init(status: 404, body: Data(#"{"detail": "Direct uploads are not enabled"}"#.utf8)),
            .init(status: 202, body: Data(#"{"job_id": "legacy1", "status": "queued"}"#.utf8)),
        ])

        let jobID = try await SheetUploader(client: client(channel))
            .upload(filename: "a.pdf", data: Data("x".utf8), options: .standard)

        #expect(jobID == "legacy1")
        #expect(channel.recorded.map(\.url?.path) == ["/api/uploads", "/api/sheets"])
    }

    @Test func aFailedCompletionDoesNotFailTheUpload() async throws {
        // S3's own notification owns delivery; this call is only a shortcut.
        let channel = StubProtocol.Channel([
            .init(status: 201, body: Data(#"{"job_id": "j2", "upload": {"url": "https://s3.example.com/b", "fields": {}}}"#.utf8)),
            .init(status: 204),
            .init(status: 500, body: Data(#"{"detail": "boom"}"#.utf8)),
        ])

        let jobID = try await SheetUploader(client: client(channel))
            .upload(filename: "a.pdf", data: Data("x".utf8), options: .standard)
        #expect(jobID == "j2")
    }

    @Test func explainsTheFifteenMinuteExpiryWhenS3Rejects() async throws {
        let channel = StubProtocol.Channel([
            .init(status: 201, body: Data(#"{"job_id": "j", "upload": {"url": "https://s3.example.com/b", "fields": {}}}"#.utf8)),
            .init(status: 403, body: Data("<Error>Policy expired</Error>".utf8)),
        ])

        do {
            _ = try await SheetUploader(client: client(channel))
                .upload(filename: "a.pdf", data: Data("x".utf8), options: .standard)
            Issue.record("expected the upload to throw")
        } catch let error as APIError {
            #expect(error.errorDescription?.contains("15 minutes") == true)
        }
    }

    @Test func refusesAFileLargerThanTheBackendAccepts() async throws {
        let channel = StubProtocol.Channel([])
        let tooBig = Data(count: AppConfig.maxUploadBytes + 1)

        await #expect(throws: APIError.self) {
            _ = try await SheetUploader(client: client(channel))
                .upload(filename: "a.pdf", data: tooBig, options: .standard)
        }
        // Nothing should have been sent.
        #expect(channel.recorded.isEmpty)
    }

    @Test func mapsFileTypesTheBackendAccepts() {
        #expect(SheetUploader.contentType(for: "a.pdf") == "application/pdf")
        #expect(SheetUploader.contentType(for: "a.JPG") == "image/jpeg")
        #expect(SheetUploader.contentType(for: "a.jpeg") == "image/jpeg")
        #expect(SheetUploader.contentType(for: "a.png") == "image/png")
        #expect(SheetUploader.isSupported(filename: "score.pdf"))
        #expect(!SheetUploader.isSupported(filename: "score.mxl"))
    }

    @Test func sendsEveryOptionIncludingTheLabelColor() async throws {
        let channel = StubProtocol.Channel([
            .init(status: 201, body: Data(#"{"job_id": "j", "upload": {"url": "https://s3.example.com/b", "fields": {}}}"#.utf8)),
            .init(status: 204),
            .init(status: 202, body: Data("{}".utf8)),
        ])
        var options = AnnotationOptions.standard
        options.style = .ascii
        options.octave = true
        options.fontSize = 8
        options.dpi = 250
        options.autoRetry = false
        options.labelColor = "#2F6FB5"

        _ = try await SheetUploader(client: client(channel))
            .upload(filename: "a.pdf", data: Data("x".utf8), options: options)

        let body = try #require(channel.recorded.first?.httpBodyData)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["style"] as? String == "ascii")
        #expect(json["octave"] as? Bool == true)
        #expect(json["font_size"] as? Double == 8)
        #expect(json["dpi"] as? Int == 250)
        #expect(json["auto_retry"] as? Bool == false)
        #expect(json["label_color"] as? String == "#2F6FB5")
    }

    @Test func theLegacyEndpointGetsTheLabelColorToo() async throws {
        let channel = StubProtocol.Channel([
            .init(status: 404, body: Data(#"{"detail": "Direct uploads are not enabled"}"#.utf8)),
            .init(status: 202, body: Data(#"{"job_id": "legacy1", "status": "queued"}"#.utf8)),
        ])
        var options = AnnotationOptions.standard
        options.labelColor = "#A83C34"

        _ = try await SheetUploader(client: client(channel))
            .upload(filename: "a.pdf", data: Data("x".utf8), options: options)

        let form = String(decoding: channel.recorded[1].httpBodyData ?? Data(), as: UTF8.self)
        #expect(form.contains(#"name="label_color""#))
        #expect(form.contains("#A83C34"))
    }
}

struct AnnotationOptionsTests {

    @Test func defaultsMatchTheBackend() {
        let options = AnnotationOptions.standard
        #expect(options.style == .unicode)
        #expect(options.fontSize == 6.5)
        #expect(options.dpi == nil)
        #expect(options.autoRetry)
        #expect(!options.octave)
    }

    @Test func roundTripsThroughStorage() throws {
        let defaults = try #require(UserDefaults(suiteName: "options-test-\(UUID().uuidString)"))
        var options = AnnotationOptions.largeLabels
        options.octave = true
        options.save(to: defaults)

        #expect(AnnotationOptions.load(from: defaults) == options)
    }

    @Test func fallsBackToStandardWhenNothingIsStored() throws {
        let defaults = try #require(UserDefaults(suiteName: "empty-\(UUID().uuidString)"))
        #expect(AnnotationOptions.load(from: defaults) == .standard)
    }

    @Test func keepsOlderSavedChoicesWhenANewOptionAppears() throws {
        // Saved before the label colour existed.
        let old = Data(#"{"style": "ascii", "octave": true, "fontSize": 9, "autoRetry": false}"#.utf8)
        let options = try JSONDecoder().decode(AnnotationOptions.self, from: old)
        #expect(options.style == .ascii)
        #expect(options.octave)
        #expect(options.fontSize == 9)
        #expect(!options.autoRetry)
        #expect(options.labelColor == "#000000")
    }

    @Test func ignoresAColorTheBackendWouldRefuse() throws {
        let saved = Data(#"{"labelColor": "red"}"#.utf8)
        #expect(try JSONDecoder().decode(AnnotationOptions.self, from: saved).labelColor == "#000000")
        #expect(AnnotationOptions.isValidColor("#a83c34"))
        #expect(!AnnotationOptions.isValidColor("#A83C3"))
        #expect(!AnnotationOptions.isValidColor("#A83C34F"))
    }
}
