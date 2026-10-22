import Foundation
import Testing
@testable import better_music_sheet_ios

struct ServerTextTests {
    /// The web's Simplified Chinese for the messages these tests use.
    private static let chinese = [
        "Reading sheet music": "正在读谱",
        "(page {page} of {pages})": "（第 {page} 页，共 {pages} 页）",
        "about {count} minutes": "大约 {count} 分钟",
        "{count} notes to read": "需要识别 {count} 个音符",
        "{low}-{high} minutes": "{low}–{high} 分钟",
        "re-reading them should take {time}": "重新识别这些页面需要{time}",
        "File must be at most {mb} MB.": "文件不能超过 {mb} MB。",
    ]

    private func translate(_ text: String) -> String {
        ServerText.translate(text) { Self.chinese[$0] ?? $0 }
    }

    @Test func translatesAWholeMessageAndKeepsWhatFillsIt() {
        #expect(translate("File must be at most 20 MB.") == "文件不能超过 20 MB。")
    }

    @Test func translatesAStageLinePartByPart() {
        #expect(translate("Reading sheet music (page 2 of 5) · about 3 minutes · 1,234 notes to read")
                == "正在读谱（第 2 页，共 5 页） · 大约 3 分钟 · 需要识别 1,234 个音符")
    }

    @Test func aSlotCanHoldAMessageOfItsOwn() {
        // The most specific pattern wins, and "2-4 minutes" is then translated too.
        #expect(translate("re-reading them should take 2-4 minutes") == "重新识别这些页面需要2–4 分钟")
    }

    @Test func unknownTextIsShownAsItCame() {
        #expect(translate("Something new from the server") == "Something new from the server")
        #expect(translate("Reading sheet music · something new") == "正在读谱 · something new")
    }

    @Test func everyTemplateHasAnswerableSlots() {
        // A template whose own text is matched against itself fills back to itself.
        for template in ServerText.templates {
            #expect(ServerText.translate(template) { $0 } == template)
        }
    }
}

struct AppLanguageTests {
    @Test func matchesTagsLikeTheWeb() {
        #expect(AppLanguage.matching("en-US") == .english)
        #expect(AppLanguage.matching("ja") == .japanese)
        #expect(AppLanguage.matching("ko-KR") == .korean)
        #expect(AppLanguage.matching("zh-Hans") == .simplifiedChinese)
        #expect(AppLanguage.matching("zh-Hant") == .traditionalChinese)
        #expect(AppLanguage.matching("zh-TW") == .traditionalChinese)
        #expect(AppLanguage.matching("zh_HK") == .traditionalChinese)
        #expect(AppLanguage.matching("zh-Hans-HK") == .simplifiedChinese)
        #expect(AppLanguage.matching("zh-CN") == .simplifiedChinese)
        #expect(AppLanguage.matching("fr-FR") == nil)
        #expect(AppLanguage.matching(nil) == nil)
    }

    @Test func choosingStoresTheLanguageWhereIOSReadsIt() throws {
        let defaults = try #require(UserDefaults(suiteName: "AppLanguageTests"))
        defer { defaults.removePersistentDomain(forName: "AppLanguageTests") }
        let launch = AppLanguage.launch
        AppLanguage.choose(.korean, defaults: defaults)
        #expect(AppLanguage.current == .korean)
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["ko"])
        AppLanguage.choose(launch, defaults: defaults)
        #expect(AppLanguage.current == launch)
    }

    @Test func keepsTheRegionForFormatting() {
        let locale = AppLanguage.japanese.locale
        #expect(locale.language.languageCode == .japanese)
        #expect(locale.region == Locale.current.region)
        #expect(AppLanguage.simplifiedChinese.locale.language.script == .hanSimplified)
    }
}
