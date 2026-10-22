import SwiftUI

/// The terms of use, for the app. English in every language, like the web's
/// terms and the privacy policy: the English text is the one that applies.
struct TermsView: View {
    var body: some View {
        InfoPageLayout(title: "Terms of Use", englishOnly: true) {
            InfoText.note(verbatim: "Last updated 20 October 2026")

            InfoText.paragraph(verbatim: "By using BetterMusicSheet you accept these terms. They are short on purpose.")

            InfoText.heading(verbatim: "What the app does")
            InfoText.paragraph(verbatim: "You add sheet music; BetterMusicSheet reads it with optical music recognition and returns a copy with note names printed on it, plus data for playing it back on an on-screen keyboard.")

            InfoText.heading(verbatim: "Copyright in what you upload")
            InfoText.paragraph(verbatim: "Most sheet music is copyrighted, and a great deal of it is explicitly marked against copying. By uploading a file you confirm you have the right to do so — because you own it, because it is out of copyright, because it is licensed to you, or because your use is otherwise permitted. You keep whatever rights you already held; uploading grants BetterMusicSheet no ownership, and the only use made of your file is producing your annotated copy.")
            InfoText.paragraph(verbatim: "Please do not upload material you have no right to, and do not use BetterMusicSheet to redistribute copyrighted music. If you believe something here infringes your copyright, email bettermusicsheet@gmail.com with enough detail to identify the work and it will be removed.")

            InfoText.heading(verbatim: "Accuracy")
            InfoText.paragraph(verbatim: "Optical music recognition is imperfect. Notes are misread, ornaments and unusual notation are missed, and rhythm in the playback is an approximation. Check the output against the original before relying on it, particularly for performance, teaching, or examination. It is a reading aid, not an authority.")

            InfoText.heading(verbatim: "Subscriptions")
            InfoText.paragraph(verbatim: "Premium is a subscription that renews automatically. Bought in the app, it is billed to your Apple Account and renews unless cancelled at least 24 hours before the current period ends; manage or cancel it in your Apple Account settings, and Apple handles refund requests. Purchases in the app are also governed by Apple's Standard Licensed Application End User License Agreement. A subscription bought on bettermusicsheet.com is managed and cancelled on the website.")
            Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                Text(verbatim: "Apple's Standard License Agreement")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Brand.accent)

            InfoText.heading(verbatim: "Availability")
            InfoText.paragraph(verbatim: "BetterMusicSheet is offered as-is, with no guarantee of uptime, of your files being retained, or of it continuing to exist. Keep your own copy of anything you care about. Processing capacity is limited, so uploads may queue at busy times, and abusive or automated use may be blocked.")

            InfoText.heading(verbatim: "Liability")
            InfoText.paragraph(verbatim: "To the extent the law allows, BetterMusicSheet and its author are not liable for losses arising from using it — including misread notation, lost uploads, or interruptions. Nothing here removes rights you have that cannot be waived under the law where you live.")

            InfoText.heading(verbatim: "Changes")
            InfoText.paragraph(verbatim: "These terms may change; the date above will say when. Continuing to use the app after a change means accepting it.")
        }
    }
}

#Preview {
    NavigationStack { TermsView() }
}
