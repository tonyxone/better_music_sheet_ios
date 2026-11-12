import Foundation

/// What a sheet is called. Its title is given when uploading — offered as the
/// file's own name, or "Scan <date>" for the camera — and can be changed later.
/// Only the title changes: the backend keeps the uploaded filename, which the
/// file's type comes from. Mirrors the web app's lib/sheet-title.ts and the
/// backend's server.py (clean_title, PUT /api/sheets/{id}/title).
nonisolated enum SheetTitle {
    /// The backend's cap (server.py TITLE_MAX_LENGTH).
    static let maxLength = 255

    /// A title as the backend stores it: runs of whitespace, newlines among
    /// them, become one space, other control characters go, and the ends are
    /// trimmed. Empty when nothing is left.
    static func cleaned(_ text: String) -> String {
        let kept = text.unicodeScalars.filter {
            $0.properties.isWhitespace || $0.properties.generalCategory != .control
        }
        return String(String.UnicodeScalarView(kept))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// The name offered for photographed pages: "Scan" and the date and time
    /// to the minute, so two scans on one day still have names of their own.
    static func scan(at date: Date = .now, locale: Locale = AppLanguage.current.locale) -> String {
        let when = date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
        return String(localized: "Scan \(when)", bundle: .app,
                      comment: "The name offered for a sheet of photos; the date and time it was taken")
    }

    /// A file's name as a title: without its extension, cleaned like a
    /// title. Nil when that says nothing about the music — what the system
    /// calls a photo it hands over ("image", a timestamp, an identifier) —
    /// so "Scan <date>" is offered instead. "IMG_2041" is kept: it at least
    /// finds the photo again in the library.
    static func fromFilename(_ filename: String?) -> String? {
        guard let filename else { return nil }
        // The extension as the web app strips it, so ".jpg" leaves nothing.
        let stem = cleaned(filename.replacing(/\.[^.\/\\]+$/, with: ""))
        let generic = /(?i)^(?:image|photo|picture|page|camera|capture|scan)?[\s_-]*(?:\(\d+\)|\d+)?$/
        let identifier = /(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
        if stem.wholeMatch(of: generic) != nil || stem.wholeMatch(of: identifier) != nil
            || stem.contains("=") { return nil }
        return String(stem.prefix(maxLength))
    }

    /// The name offered for an upload: the file's own (fromFilename), else
    /// "Scan" and the date and time (scan).
    static func suggested(for filename: String?, at date: Date = .now,
                          locale: Locale = AppLanguage.current.locale) -> String {
        fromFilename(filename) ?? scan(at: date, locale: locale)
    }

    private struct RenameRequest: Encodable, Sendable {
        let title: String
    }

    /// Renames one of the signed-in account's own sheets, and returns the
    /// sheet as the backend now has it.
    static func rename(jobID: String, to title: String, client: APIClient = .shared) async throws -> AnnotationJob {
        try await client.put("/api/sheets/\(jobID)/title", body: RenameRequest(title: title))
    }
}
