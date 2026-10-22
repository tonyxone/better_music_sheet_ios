import Foundation
import os

/// The languages the app is written in — the web app's five — and which one
/// it is showing.
///
/// iOS picks the language at launch, from the device's languages or the
/// app's own Language setting. Choosing one in the app (the footer's picker)
/// is stored where that setting lives, so the two always agree, and takes
/// effect at once rather than at the next launch: the views read it from the
/// environment (see RootView), and strings made outside them come from
/// `Bundle.app`.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"

    var id: Self { self }

    /// Each language named in itself, for the language picker.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }

    /// The best of the app's languages for a language tag, as the web's
    /// matchLocale does: Chinese goes by script when the tag names one, then
    /// by region — Taiwan, Hong Kong and Macau read Traditional.
    static func matching(_ tag: String?) -> AppLanguage? {
        guard let tag = tag?.lowercased().replacingOccurrences(of: "_", with: "-") else { return nil }
        let parts = tag.split(separator: "-").map(String.init)
        switch parts.first {
        case "zh":
            if parts.contains("hans") { return .simplifiedChinese }
            if parts.contains("hant") || parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) {
                return .traditionalChinese
            }
            return .simplifiedChinese
        case "ja": return .japanese
        case "ko": return .korean
        case "en": return .english
        default: return nil
        }
    }

    /// The language iOS opened the app in.
    static let launch = matching(Bundle.main.preferredLocalizations.first) ?? .english

    private static let switched = OSAllocatedUnfairLock<AppLanguage?>(initialState: nil)

    /// The language the app is showing now.
    static var current: AppLanguage {
        switched.withLock { $0 } ?? launch
    }

    /// Switches now, and for every later launch.
    static func choose(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        switched.withLock { $0 = language == launch ? nil : language }
        // The per-app language iOS's Settings writes, and reads at launch.
        defaults.set([language.rawValue], forKey: "AppleLanguages")
    }

    /// The device's locale in this language, so dates and numbers keep the
    /// reader's region.
    var locale: Locale {
        var components = Locale.Components(locale: .current)
        var language = Locale.Language.Components(identifier: rawValue)
        language.region = Locale.current.region
        components.languageComponents = language
        return Locale(components: components)
    }

    /// The folder in the app holding this language's strings, when there is one.
    fileprivate var bundle: Bundle? {
        Bundle.main.path(forResource: rawValue, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}

extension Bundle {
    /// Where the app's strings are looked up: its own bundle, or — once the
    /// language has been switched in the app, until iOS applies it at the
    /// next launch — that language's folder in it. Pass it to
    /// `String(localized:bundle:)` for anything not shown through a view.
    nonisolated static var app: Bundle {
        let current = AppLanguage.current
        return current == AppLanguage.launch ? .main : current.bundle ?? .main
    }
}
