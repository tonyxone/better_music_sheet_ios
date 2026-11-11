import Foundation

/// What a sheet is called. Its title is given when photos are uploaded — a
/// photo's filename says nothing about the music — and can be changed later.
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

    private struct RenameRequest: Encodable, Sendable {
        let title: String
    }

    /// Renames one of the signed-in account's own sheets, and returns the
    /// sheet as the backend now has it.
    static func rename(jobID: String, to title: String, client: APIClient = .shared) async throws -> AnnotationJob {
        try await client.put("/api/sheets/\(jobID)/title", body: RenameRequest(title: title))
    }
}
