import Foundation

/// Text that reaches the app in English from the server — a sheet's stage
/// and errors — shown in the app's language when it is recognised, and as it
/// came when it isn't. The web app's lib/i18n/known-text.ts, ported.
///
/// The patterns are the server's English messages themselves: a {name} in one
/// matches whatever stands there, which is then carried into the translation.
/// ServerText.xcstrings holds the translations, keyed by the English, so
/// wording changed on the server only needs changing here, and something new
/// simply shows in English until it is added.
nonisolated enum ServerText {
    /// The server's messages (the web's `en.known`), in English.
    static let templates = [
        // A sheet's stage (processor.py), built up from parts joined by " · ".
        "Uploading sheet",
        "Waiting for a recognition worker",
        "Reading sheet music",
        "Re-reading unclear pages",
        "Matching pitches to notes",
        "Building playback timeline",
        "Drawing the annotated sheet",
        "Complete",
        "Processing failed",
        "Recovering interrupted processing",
        "Retrying interrupted processing",
        "(page {page} of {pages})",
        "less than a minute",
        "about a minute",
        "about {count} minutes",
        "{low}-{high} minutes",
        "{count} notes to read",
        "thanks for your patience",
        "re-reading the scan should take {time}",
        "re-reading them should take {time}",
        "{measures} measures, {notes} notes",
        // Errors (server.py).
        "We couldn't read the music on this sheet. We've been notified and will look into it - you can try again later.",
        "This sheet took too long to read. Uploading fewer pages at a time usually helps.",
        "We couldn't start reading this sheet. Please try again in a few minutes.",
        "Upload a valid, unencrypted PDF or image with at most {pages} pages.",
        "Uploaded file size does not match the selected file.",
        "Could not prepare upload.",
        "Upload failed.",
        "No music notation was detected in this PDF. Make sure it's actually a sheet music score (with staff lines and notes) and not a scan of something else, a blank page, or a non-music document.",
        "The free plan keeps 1 sheet at a time. Delete your current sheet to upload another, or go Premium for unlimited sheets.",
        "This upload didn't finish, so there is nothing to read again. Please upload the file again.",
        "Only PDF, JPG and PNG files are supported.",
        "You already have a sheet processing. Wait for it to finish.",
        "You've started {count} sheets today, the most your plan allows in a day. You can start another {when}. {upgrade}",
        "You've started {count} sheets today, the most your plan allows in a day. You can start another {when}.",
        "in about {count} hours",
        "in about 1 hour",
        "within the hour",
        "Premium allows {monthly} a day, or {yearly} on the yearly plan.",
        "The yearly plan allows {count} a day.",
        "Sign in to upload a sheet.",
        "File must be at most {mb} MB.",
        "Invalid file or annotation options.",
        "The sheet is not ready yet.",
        "Wait for this sheet to finish processing before deleting it.",
        "Wait for your current upload to finish before deleting your account.",
        "This sheet changed; refresh and try again.",
        "The demo sheet can't be deleted.",
        "This sheet isn't waiting to be tried again.",
        "Too many drawings on this sheet to save. Erase some and try again.",
        "No active subscription found.",
        "This subscription is billed through a different store. Reload and try again.",
        "This subscription was bought through Apple, so it's cancelled in your Apple ID settings. Open Subscriptions there and choose Cancel Subscription.",
    ]

    /// `text` in the app's language, as far as it is recognised.
    static func translate(_ text: String) -> String {
        guard AppLanguage.current != .english else { return text }
        return translate(text) { Bundle.app.localizedString(forKey: $0, value: $0, table: "ServerText") }
    }

    /// `text` with each recognised message replaced by `translation(template)`,
    /// its {names} filled in.
    static func translate(_ text: String, translation: (String) -> String) -> String {
        if let whole = translateOne(text, translation) { return whole }
        // A stage is built up from parts: "Reading sheet music (page 2 of 5)
        // · about 3 minutes · 1,234 notes to read".
        return text.components(separatedBy: " · ").map { part in
            if let match = pagePattern.firstMatch(in: part, range: NSRange(part.startIndex..., in: part)),
               let stage = Range(match.range(at: 1), in: part), let page = Range(match.range(at: 2), in: part) {
                // No space between: each language's "page" message brings its own.
                let stageText = String(part[stage]), pageText = String(part[page])
                return (translateOne(stageText, translation) ?? stageText)
                    + (translateOne(pageText, translation) ?? " " + pageText)
            }
            return translateOne(part, translation) ?? part
        }.joined(separator: " · ")
    }

    private struct Pattern: @unchecked Sendable {
        let template: String
        let regex: NSRegularExpression
        let names: [String]
        /// How much of it is fixed text: the most specific is tried first.
        let literal: Int
    }

    private static let pagePattern = try! NSRegularExpression(pattern: #"^(.*?) (\(page \d+ of \d+\))$"#)
    private static let placeholder = try! NSRegularExpression(pattern: #"\{(\w+)\}"#)

    /// The most specific first: "re-reading them should take {time}" also
    /// fits "{low}-{high} minutes" when the time is "2-4 minutes".
    private static let patterns: [Pattern] = templates.map { template in
        var names: [String] = []
        var source = ""
        var rest = template[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            source += NSRegularExpression.escapedPattern(for: String(rest[..<open]))
            names.append(String(rest[rest.index(after: open)..<close]))
            // Never across a " · ": a stage line is several messages joined by it.
            source += "([^·]+?)"
            rest = rest[rest.index(after: close)...]
        }
        source += NSRegularExpression.escapedPattern(for: String(rest))
        let literal = placeholder.stringByReplacingMatches(
            in: template, range: NSRange(template.startIndex..., in: template), withTemplate: "").count
        return Pattern(template: template, regex: try! NSRegularExpression(pattern: "^\(source)$"),
                       names: names, literal: literal)
    }.sorted { $0.literal > $1.literal }

    private static func translateOne(_ text: String, _ translation: (String) -> String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for pattern in patterns {
            guard let match = pattern.regex.firstMatch(in: trimmed, range: range) else { continue }
            var result = translation(pattern.template)
            for (i, name) in pattern.names.enumerated() {
                guard let value = Range(match.range(at: i + 1), in: trimmed) else { continue }
                // What fills a slot can be a message of its own ("about 3 minutes").
                let filled = translateOne(String(trimmed[value]), translation) ?? String(trimmed[value])
                result = result.replacingOccurrences(of: "{\(name)}", with: filled)
            }
            return result
        }
        return nil
    }
}
