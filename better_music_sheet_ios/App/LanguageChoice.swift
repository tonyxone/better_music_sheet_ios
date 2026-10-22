import Observation

/// The app's language as the views see it: AppLanguage, made observable, so
/// choosing one in the footer redraws the app in it straight away (see
/// BetterMusicSheetApp and RootView).
@Observable
final class LanguageChoice {
    static let shared = LanguageChoice()

    private(set) var current = AppLanguage.current

    func choose(_ language: AppLanguage) {
        guard language != current else { return }
        AppLanguage.choose(language)
        current = language
    }
}
