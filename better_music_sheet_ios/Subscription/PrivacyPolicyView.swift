import SwiftUI

/// The iOS app's privacy notice. Keep its data-handling statements in sync
/// with the app, its backend, and the public policy URL in App Store Connect.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last updated 29 September 2026")
                    .font(.footnote)
                    .foregroundStyle(Brand.inkSoft)

                paragraph("BetterMusicSheet for iPhone and iPad lets you upload sheet music, add note labels, edit sheets, and practise playing them. This policy explains the information the app uses to provide those features.")

                heading("Information we collect")
                subheading("Account and sign-in")
                paragraph("You can use the app as a guest or create an account. If you create an account, we collect your email address, display name, and account identifier. Amazon Cognito handles email sign-in. If you choose Sign in with Apple or Google, that provider and Cognito handle the sign-in process. We use your account information to sign you in and connect your sheets and Premium access across devices. Sign-in tokens are stored in the device Keychain.")

                subheading("Guest use")
                paragraph("For guests, the app creates a random identifier and stores it in the device Keychain. It sends this identifier to our service to keep your sheets and usage separate from other guests. It is not based on your name or email address. If you lose this identifier, you may lose access to sheets saved as a guest.")

                subheading("Sheet music and edits")
                paragraph("When you choose a PDF, image, or camera photo, the app uploads only the file or photo you selected. We store the original, generated annotated sheets, playback data, your edits, the filename, processing options, job status, and related dates to provide your library, editing, and practice features. The app asks for camera access only when you choose to take a photo; the system photo and file pickers let you choose what to share. Our service stores uploads and processing records in Amazon Web Services in the United States.")

                subheading("Subscriptions")
                paragraph("Apple processes purchases made in the app. We receive and store the subscription provider, plan, transaction or subscription identifier, status, and dates against your account so Premium access works in the app and on the website. We do not receive your full payment card details from Apple.")

                subheading("Ads and device information")
                paragraph("The Free plan may show banner ads from Google AdMob; Premium does not show ads. The app requests non-personalized ads and does not request Apple's permission to track you across other companies' apps and websites. Google's advertising tools may still collect data such as your IP address, approximate location inferred from it, device identifiers, ad views and interactions, app interactions, crash logs, and performance data to provide and measure ads, prevent fraud, and improve their services. We do not give your uploaded sheets to AdMob. Where required, Google's consent form asks for your choices before ads load. You can change available choices through Ad Privacy Choices on the Account screen.")
                Link("Google's Privacy Policy", destination: URL(string: "https://policies.google.com/privacy")!)

                heading("How we use and protect information")
                paragraph("We use this information to authenticate users, process sheet music, save and sync sheets and edits, enable practice and Premium features, show ads to Free users, and keep the service working. Our service uses Amazon Web Services for authentication, storage, and processing; Apple for in-app purchases; and Google for optional sign-in and ads. These providers process information for those purposes under their own privacy and security commitments. We do not sell or publish your sheet music or use it to train AI models. We do not send uploaded files to AdMob or to a separate AI service for recognition.")

                heading("Storage and retention")
                paragraph("The app keeps sign-in tokens, a guest identifier, preferences, subscription status, and cached sheets, playback data, instrument sounds, and edits on your device. Unsaved edits may be kept locally until they can sync. Our service keeps uploaded sheets and results until you delete them; there is no automatic expiry. Deleting a sheet from the Library removes its upload and generated results from the service.")

                heading("Your choices and deletion")
                paragraph("You can delete individual sheets from the Library and delete your account from the Account screen. Account deletion removes the sign-in account and sheet history, but it may not erase every retained file. Delete individual sheets first if you want their uploaded files removed. To ask what data we hold or request removal of retained files, email us below. Deleting your account does not cancel a subscription billed by Apple; manage or cancel it in Apple Account Settings. You can change available ad consent choices from the Account screen.")
                Link("Email bettermusicsheet@gmail.com", destination: URL(string: "mailto:bettermusicsheet@gmail.com")!)

                heading("Changes")
                paragraph("If this policy changes, we will update the date at the top of this page.")
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Brand.paper)
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(Brand.title(21))
            .foregroundStyle(Brand.ink)
            .padding(.top, 10)
    }

    private func subheading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Brand.ink)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Brand.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}
