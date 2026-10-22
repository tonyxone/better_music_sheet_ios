import SwiftUI

/// Help with the app: the plans, billing, getting good results, and deleting
/// data — the web's Support page, for the app.
struct SupportView: View {
    var body: some View {
        InfoPageLayout(title: "Support") {
            InfoText.note("Last updated 20 October 2026")

            InfoText.heading("Contact us")
            InfoText.paragraph("Questions, bug reports, and sheets that came out wrong are all welcome at [bettermusicsheet@gmail.com](mailto:bettermusicsheet@gmail.com). Please say which iPhone or iPad and which version of iOS you use, and attach the sheet if it was read badly.")

            InfoText.heading("Free and Premium")
            InfoText.paragraph("The free plan keeps as many sheets as you like: your first is free, and each one after it takes a short ad. It adds up to 15 sheets a day and shows ads. Premium adds more each day and has no ads. One subscription covers this app and the website.")

            InfoText.heading("Managing or cancelling a subscription")
            InfoText.paragraph("A subscription bought in this app is billed by Apple: manage or cancel it with Manage Subscription on the Account screen, or in Settings under your name, then Subscriptions.")
            InfoText.paragraph("A subscription bought on bettermusicsheet.com can only be cancelled there: sign in on the website and cancel it from your Subscription page.")
            InfoText.paragraph("Either way, cancelling keeps Premium until the end of the period you paid for.")

            InfoText.heading("Premium isn't showing after I paid")
            InfoText.paragraph("A subscription belongs to the account that bought it, so make sure you are signed in to that account. If you bought it in this app, tap Restore Purchases on the Account screen. If it still doesn't show, email us.")

            InfoText.heading("Getting the best results")
            InfoText.paragraph("Choose a PDF where you can: note names are read far more reliably from a PDF than from a photo, and some photos can't be read at all. For a photo, lay the page flat in even light and fill the frame with it. Note names are recognised automatically, so check them against your original; you can correct a name with the pencil button on the sheet.")

            InfoText.heading("Deleting your data")
            InfoText.paragraph("To delete a sheet, swipe left on it in the Library and tap Delete. To delete your account, choose Delete Account on the Account screen. Deleting your account doesn't cancel a subscription, so cancel it first. The privacy policy explains what is kept and how to ask for anything else to be removed.")

            VStack(alignment: .leading, spacing: 10) {
                NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                NavigationLink("Terms of Use") { TermsView() }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Brand.accent)
            .padding(.top, 8)
        }
    }
}

#Preview {
    NavigationStack { SupportView() }
}
