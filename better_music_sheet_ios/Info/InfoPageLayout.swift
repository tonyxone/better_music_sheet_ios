import SwiftUI

/// The layout the footer's pages and the privacy policy share: one readable
/// column on paper. Text given as a key is translated, and may carry Markdown
/// (bold, links); text given verbatim is shown as written — the privacy
/// policy and terms are English only, as on the web.
struct InfoPageLayout<Content: View>: View {
    let title: LocalizedStringKey
    /// For a page that is only in English, the notice saying so.
    var englishOnly = false
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if englishOnly, AppLanguage.current != .english {
                    Text("This page is available in English only. The English text is the version that applies.")
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.ink)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Brand.paperDeep.opacity(0.6), in: .rect(cornerRadius: 10))
                }
                content
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Brand.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The pieces of a page, translated or verbatim.
enum InfoText {
    static func note(_ key: LocalizedStringKey) -> some View { note(Text(key)) }
    static func note(verbatim text: String) -> some View { note(Text(verbatim: text)) }

    static func heading(_ key: LocalizedStringKey) -> some View { heading(Text(key)) }
    static func heading(verbatim text: String) -> some View { heading(Text(verbatim: text)) }

    static func paragraph(_ key: LocalizedStringKey) -> some View { paragraph(Text(key)) }
    static func paragraph(verbatim text: String) -> some View { paragraph(Text(verbatim: text)) }

    static func bullet(_ key: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "•").foregroundStyle(Brand.inkSoft)
            paragraph(key)
        }
    }

    private static func note(_ text: Text) -> some View {
        text
            .font(.footnote)
            .foregroundStyle(Brand.inkSoft)
    }

    private static func heading(_ text: Text) -> some View {
        text
            .font(Brand.title(21))
            .foregroundStyle(Brand.ink)
            .padding(.top, 10)
    }

    private static func paragraph(_ text: Text) -> some View {
        text
            .font(.system(size: 15))
            .foregroundStyle(Brand.ink)
            .tint(Brand.accent)
            .fixedSize(horizontal: false, vertical: true)
    }
}
