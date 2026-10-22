import SwiftUI

/// The web app's footer, at the end of the library: About, Privacy, Terms,
/// Support and Contact, the language, and a reminder that the names are read
/// by machine. Its pages are written for the app rather than the website.
struct AppFooter: View {
    @State private var page: InfoPage?
    @State private var language = LanguageChoice.shared

    var body: some View {
        VStack(spacing: 14) {
            // One row where it fits; a phone in a long language gets two.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    pageLink(.about); pageLink(.privacy); pageLink(.terms); pageLink(.support); contact
                }
                VStack(spacing: 10) {
                    HStack(spacing: 18) { pageLink(.about); pageLink(.privacy); pageLink(.terms) }
                    HStack(spacing: 18) { pageLink(.support); contact }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Brand.inkSoft)

            languagePicker

            Text("Note names are recognised automatically and are not always right — check against your original before you rely on them.")
                .font(.system(size: 11.5))
                .foregroundStyle(Brand.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(.top, 28)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        // Plain, so in a list row each one is tapped on its own rather than
        // the whole row setting them all off.
        .buttonStyle(.plain)
        .sheet(item: $page) { page in
            InfoPageSheet(page: page)
        }
    }

    private func pageLink(_ page: InfoPage) -> some View {
        Button(page.footerTitle) { self.page = page }
    }

    private var contact: some View {
        // Reachable from the library rather than only from inside a page: a
        // reader who wants to report a badly read sheet shouldn't have to go
        // looking for the address.
        Link("Contact", destination: InfoPage.email)
    }

    /// The web's picker: each language named in itself.
    private var languagePicker: some View {
        Menu {
            Picker("Language", selection: Binding(get: { language.current }, set: { language.choose($0) })) {
                ForEach(AppLanguage.allCases) { option in
                    Text(verbatim: option.nativeName).tag(option)
                }
            }
        } label: {
            Label {
                Text(verbatim: language.current.nativeName)
            } icon: {
                Image(systemName: "globe")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .overlay(Capsule().stroke(Brand.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .accessibilityLabel("Language")
        .accessibilityValue(Text(verbatim: language.current.nativeName))
    }
}

/// The footer's pages.
enum InfoPage: String, Identifiable {
    case about, privacy, terms, support

    static let email = URL(string: "mailto:bettermusicsheet@gmail.com")!

    var id: Self { self }

    var footerTitle: LocalizedStringKey {
        switch self {
        case .about: "About"
        case .privacy: "Privacy"
        case .terms: "Terms"
        case .support: "Support"
        }
    }
}

/// A footer page over the library, with its own way back.
private struct InfoPageSheet: View {
    let page: InfoPage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .about: AboutView()
                case .privacy: PrivacyPolicyView()
                case .terms: TermsView()
                case .support: SupportView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(Brand.accent)
    }
}

#Preview {
    ScrollView { AppFooter() }
        .background(Brand.paper)
}
