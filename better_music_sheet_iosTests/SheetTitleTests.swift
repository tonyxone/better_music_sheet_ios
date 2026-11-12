import Foundation
import Testing
@testable import better_music_sheet_ios

struct SheetTitleTests {
    @Test func cleansATitleTheWayTheBackendStoresIt() {
        #expect(SheetTitle.cleaned("  Clair   de\nLune\t") == "Clair de Lune")
        #expect(SheetTitle.cleaned("Bell\u{07} song\u{00}") == "Bell song")
        #expect(SheetTitle.cleaned("Line one\r\nLine two") == "Line one Line two")
        #expect(SheetTitle.cleaned("夏日漱石 🎹") == "夏日漱石 🎹")
        #expect(SheetTitle.cleaned(" \n\t\u{3000} ").isEmpty)
    }

    @Test func offersAFilesOwnNameWithoutItsExtension() {
        #expect(SheetTitle.fromFilename("Menuet in G.pdf") == "Menuet in G")
        #expect(SheetTitle.fromFilename("IMG_2041.png") == "IMG_2041")
        #expect(SheetTitle.fromFilename("IMG_2041.HEIC") == "IMG_2041")
        #expect(SheetTitle.fromFilename("Op. 2 No. 1.pdf") == "Op. 2 No. 1")
        #expect(SheetTitle.fromFilename("  Clair\tde  Lune .jpeg") == "Clair de Lune")
        #expect(SheetTitle.fromFilename(String(repeating: "x", count: 300) + ".pdf")?.count == SheetTitle.maxLength)
    }

    @Test func aNameThatSaysNothingIsNotOffered() {
        for name in ["image.jpg", "image (2).jpg", "IMAGE.JPEG", "Photo.jpg", "1731340000000.jpg", ".jpg", "",
                     "3F2504E0-4F89-11D3-9A0C-0305E82C3301.jpeg", "version=1&uuid=3F25.jpeg"] {
            #expect(SheetTitle.fromFilename(name) == nil, "\(name)")
        }
        #expect(SheetTitle.fromFilename(nil) == nil)
    }

    @Test func fallsBackToScanAndTheDate() {
        let locale = Locale(identifier: "en_US")
        let date = Date(timeIntervalSince1970: 1_794_400_000)
        #expect(SheetTitle.suggested(for: "Menuet in G.pdf", at: date, locale: locale) == "Menuet in G")
        #expect(SheetTitle.suggested(for: "image.jpg", at: date, locale: locale)
                == SheetTitle.scan(at: date, locale: locale))
        #expect(SheetTitle.suggested(for: nil, at: date, locale: locale) == SheetTitle.scan(at: date, locale: locale))
    }

    @Test func offersScanAndTheDateAndTime() {
        let locale = Locale(identifier: "en_US")
        let date = Date(timeIntervalSince1970: 1_794_400_000)
        let when = date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
        #expect(SheetTitle.scan(at: date, locale: locale).hasSuffix(when))
        // A minute later is a name of its own.
        #expect(SheetTitle.scan(at: date, locale: locale) != SheetTitle.scan(at: date + 60, locale: locale))
    }
}

@Suite(.serialized)
struct RenameSheetTests {
    private func client(_ channel: StubProtocol.Channel) -> APIClient {
        APIClient(baseURL: URL(string: "https://api.example.com")!,
                  urlSession: channel.session(),
                  sessions: SessionStore(store: InMemorySecretStore()),
                  guestID: GuestID(store: InMemorySecretStore()))
    }

    @Test func putsTheNewTitleAndReadsBackTheSheet() async throws {
        let channel = StubProtocol.Channel([.init(body: Data("""
        {"job_id": "job1", "music_sheet_id": "job1", "status": "done",
         "sheet_name": "Photo.jpg", "title": "Gymnopédie No. 1", "error": null,
         "stage": "Complete", "labeled_groups": 3, "style": "unicode", "octave": false,
         "font_size": 6.5, "dpi": null, "created_at": 1, "updated_at": 2}
        """.utf8))])

        let job = try await SheetTitle.rename(jobID: "job1", to: "Gymnopédie No. 1", client: client(channel))

        #expect(job.displayName == "Gymnopédie No. 1")
        let request = try #require(channel.recorded.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/sheets/job1/title")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBodyData)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["title"] as? String == "Gymnopédie No. 1")
    }

    @Test func passesOnWhyTheBackendRefused() async throws {
        let channel = StubProtocol.Channel([
            .init(status: 404, body: Data(#"{"detail": "no such job"}"#.utf8)),
        ])

        do {
            _ = try await SheetTitle.rename(jobID: "theirs", to: "Mine now", client: client(channel))
            Issue.record("expected the rename to throw")
        } catch let error as APIError {
            #expect(error.isNotFound)
            #expect(error.errorDescription == "no such job")
        }
    }
}
