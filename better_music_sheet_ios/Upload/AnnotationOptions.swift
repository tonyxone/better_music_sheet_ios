import Foundation

/// How a sheet should be labelled: the web app's upload options, plus the
/// labels' colour. Remembered between uploads, since most people settle on
/// one way of reading their music.
nonisolated struct AnnotationOptions: Codable, Sendable, Hashable {
    enum LabelStyle: String, Codable, Sendable, CaseIterable {
        case unicode, ascii

        var title: String {
            switch self {
            case .unicode: "Unicode (B♭, C♯)"
            case .ascii: "ASCII (Bb, C#)"
            }
        }
    }

    var style: LabelStyle = .unicode
    /// Appends the scientific octave number, e.g. B♭4.
    var octave = false
    var fontSize: Double = 6.5
    /// Nil means "let the pipeline decide", which is right for most sheets.
    var dpi: Int?
    /// Re-scan an under-recognized page at higher resolution. Slower, but it
    /// rescues poor scans. Only applies while `dpi` is automatic.
    var autoRetry = true
    /// "#RRGGBB". Black is what the backend drew before it took a colour.
    var labelColor = "#000000"

    static let standard = AnnotationOptions()
    static let largeLabels = AnnotationOptions(fontSize: 9)

    /// The web app's font-size field. The backend accepts up to 20.
    static let fontSizeRange: ClosedRange<Double> = 3...12
    static let fontSizeStep = 0.5
    /// The web app's DPI field, 150 to 300 in steps of 50.
    static let dpiChoices = [150, 200, 250, 300]

    struct NamedColor: Sendable, Hashable {
        let name: String
        let hex: String
    }

    /// Dark enough to read over white paper through the labels' white halo.
    static let labelColorPresets = [
        NamedColor(name: "Black", hex: "#000000"),
        NamedColor(name: "Red", hex: "#A83C34"),
        NamedColor(name: "Blue", hex: "#2F6FB5"),
        NamedColor(name: "Green", hex: "#3E8E5A"),
        NamedColor(name: "Purple", hex: "#6B3FA0"),
    ]

    /// The form the backend validates: `#` and six hex digits.
    static func isValidColor(_ hex: String) -> Bool {
        hex.count == 7 && hex.first == "#" && hex.dropFirst().allSatisfy(\.isHexDigit)
    }

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

nonisolated extension AnnotationOptions {
    /// Fills in anything missing from options saved by an older version, so
    /// adding an option never resets the choices someone already made.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AnnotationOptions()
        style = try container.decodeIfPresent(LabelStyle.self, forKey: .style) ?? fallback.style
        octave = try container.decodeIfPresent(Bool.self, forKey: .octave) ?? fallback.octave
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? fallback.fontSize
        dpi = try container.decodeIfPresent(Int.self, forKey: .dpi)
        autoRetry = try container.decodeIfPresent(Bool.self, forKey: .autoRetry) ?? fallback.autoRetry
        let color = try container.decodeIfPresent(String.self, forKey: .labelColor) ?? fallback.labelColor
        labelColor = Self.isValidColor(color) ? color : fallback.labelColor
    }
}
