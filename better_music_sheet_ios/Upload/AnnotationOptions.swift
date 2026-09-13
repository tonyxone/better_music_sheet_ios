import Foundation

/// How a sheet should be labelled. These are defaults the user sets once
/// rather than a form to fill in on the way in — the web app asks every time,
/// which is a web habit, not a requirement.
nonisolated struct AnnotationOptions: Codable, Sendable, Hashable {
    enum LabelStyle: String, Codable, Sendable, CaseIterable {
        case unicode, ascii

        var title: String {
            switch self {
            case .unicode: "Unicode ♭ ♯"
            case .ascii: "ASCII (Bb, C#)"
            }
        }
    }

    var style: LabelStyle = .unicode
    /// Appends the scientific octave number, e.g. B♭4.
    var octave = false
    /// Backend accepts 3...20; the two presets the UI offers sit inside that.
    var fontSize: Double = 6.5
    /// Nil means "let the pipeline decide", which is right for most sheets.
    var dpi: Int?
    /// Re-scan an under-recognized page at higher resolution. Slower, but it
    /// rescues poor scans.
    var autoRetry = true

    static let standard = AnnotationOptions()
    static let largeLabels = AnnotationOptions(style: .unicode, octave: false, fontSize: 9, dpi: nil, autoRetry: true)

    // MARK: - Persistence

    private static let key = "annotation_options"

    static func load(from defaults: UserDefaults = .standard) -> AnnotationOptions {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AnnotationOptions.self, from: data)
        else { return .standard }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
