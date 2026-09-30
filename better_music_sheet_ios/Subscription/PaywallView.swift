import SwiftUI
import StoreKit

/// Presented in place of PracticeView wherever practice mode is gated (see
/// RootView and SheetDetailView), and in place of the upload panel — the only
/// place in the app that asks for money.
///
/// One subscription covers the web app and this one, recorded against the
/// signed-in account — so buying needs an account first, and an account
/// already subscribed (on either) is told so instead of being billed twice.
struct PaywallView: View {
    @State private var manager = SubscriptionManager.shared
    @State private var entitlements = EntitlementStore.shared
    @State private var selectedProductID: String?
    @State private var purchasing = false
    @State private var restoring = false
    @State private var errorMessage: String?
    /// Nil until the session check settles.
    @State private var signedIn: Bool?
    @State private var showingAccount = false
    @State private var showingPrivacyPolicy = false
    @Environment(\.dismiss) private var dismiss

    private static let benefits = [
        "Upload your own sheets",
        "Every note labelled",
        "Practise on a keyboard",
        "Unlimited sheet storage",
        "No ads",
        "Access anywhere — web, iPhone and iPad",
    ]

    /// True when pushed onto the app's navigation stack (in place of the
    /// practice page) rather than presented as a sheet. A pushed paywall must
    /// not bring its own NavigationStack: one nested inside the app's typed
    /// stack crashes SwiftUI when the path changes.
    var pushed = false

    /// Shows the plans and prices only — no buying, restoring or signing in.
    /// For a signed-out visitor who just wants to see what Premium costs.
    var previewOnly = false

    var body: some View {
        Group {
            if pushed {
                page
            } else if #available(iOS 18.0, *) {
                presentedPage.presentationSizing(.page)
            } else {
                presentedPage
            }
        }
        .task {
            await checkAccount()
            await manager.loadProducts()
            if !previewOnly { await manager.syncCurrentEntitlement() }
        }
        .sheet(isPresented: $showingAccount, onDismiss: { Task { await checkAccount() } }) {
            AccountView()
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            NavigationStack {
                PrivacyPolicyView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingPrivacyPolicy = false }
                        }
                    }
            }
        }
    }

    private var presentedPage: some View {
        NavigationStack {
            page
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
    }

    private var page: some View {
        ZStack {
            Brand.paper.ignoresSafeArea()
            content
        }
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func checkAccount() async {
        signedIn = await SessionStore.shared.current() != nil
        await entitlements.refresh()
    }

    /// Apple determines introductory eligibility for this Apple Account and
    /// group. No plan is chosen up front, so until one is, it's whether any
    /// plan offers the trial.
    private var offersTrial: Bool {
        guard let selectedProductID else { return !manager.introductoryEligibleIDs.isEmpty }
        return manager.introductoryEligibleIDs.contains(selectedProductID)
    }

    @ViewBuilder
    private var content: some View {
        if entitlements.isEntitled, let status = entitlements.status {
            AlreadySubscribed(status: status) { dismiss() }
        } else if signedIn == nil || (manager.isLoadingProducts && manager.products.isEmpty) {
            ProgressView().tint(Brand.accent)
        } else if manager.products.isEmpty {
            VStack(spacing: 16) {
                RetryNotice(message: manager.loadError ?? "Couldn't load subscription options.") {
                    Task { await manager.loadProducts() }
                }
                if !previewOnly {
                    if signedIn == true { restoreButton } else { signInButton }
                }
                legalLinks
                if let message = errorMessage ?? manager.syncError {
                    Text(message).font(.footnote).foregroundStyle(Brand.danger)
                }
            }
            .padding(28)
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        header

                        if let errorMessage = errorMessage ?? manager.syncError {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(Brand.danger)
                                .multilineTextAlignment(.center)
                        }

                        VStack(spacing: 12) {
                            ForEach(manager.products) { product in
                                PlanCard(product: product, isSelected: !previewOnly && product.id == selectedProductID,
                                         offersTrial: manager.introductoryEligibleIDs.contains(product.id),
                                         selectable: !previewOnly) {
                                    selectedProductID = product.id
                                }
                            }
                        }

                        benefits

                        if previewOnly {
                            Text("Sign in to subscribe. Your subscription belongs to your account, so it works on the web too.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Brand.inkSoft)
                                .multilineTextAlignment(.center)
                        } else if signedIn == true {
                            purchaseButton
                            restoreButton
                        } else {
                            signInButton
                        }

                        FreePlanCard()

                        Text(terms)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Brand.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                }

                legalLinks
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Brand.paper)
            }
        }
    }

    private var legalLinks: some View {
        HStack(spacing: 20) {
            Button("Privacy Policy") { showingPrivacyPolicy = true }
            Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
        }
        .font(.system(size: 12))
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "pianokeys")
                .font(.system(size: 30))
                .foregroundStyle(Brand.ink)
            Text("Your own sheet music, labelled")
                .font(Brand.title(22))
                .foregroundStyle(Brand.ink)
            Text("Upload your piano music and get it back with the letter name above every note, then practise it on a keyboard that lights up each note\(offersTrial ? ". Starts with a 7-day free trial." : ".")")
                .font(.system(size: 14))
                .foregroundStyle(Brand.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Self.benefits, id: \.self) { benefit in
                Label {
                    Text(benefit).foregroundStyle(Brand.ink)
                } icon: {
                    Image(systemName: "checkmark").foregroundStyle(Brand.success)
                }
                .font(.system(size: 14))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    /// The cancellation and refund terms, stated before buying — as the web
    /// app's checkout asks the visitor to agree to them.
    private var terms: String {
        let start = offersTrial
            ? "7-day free trial for new subscribers, then the plan you choose. Cancel during the trial and you won't be charged."
            : "Billed from today for the plan you choose."
        return "\(start) Payment is charged to your Apple Account. The subscription renews automatically unless cancelled at least 24 hours before the current period ends. Your account is charged for renewal within 24 hours before the period ends. Manage or cancel in Apple Account Settings. Refund requests are handled by Apple."
    }

    private var signInButton: some View {
        VStack(spacing: 8) {
            Button {
                showingAccount = true
            } label: {
                Text("Sign in to subscribe")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Brand.accent, in: .capsule)
            }
            Text("Your subscription belongs to your account, so it works on the web too.")
                .font(.system(size: 12.5))
                .foregroundStyle(Brand.inkSoft)
                .multilineTextAlignment(.center)
        }
    }

    private var purchaseButton: some View {
        Button(action: purchase) {
            Text(purchasing ? "Starting…" : offersTrial ? "Start 7-day free trial" : "Subscribe")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Brand.accent, in: .capsule)
                .opacity(purchasing || selectedProductID == nil ? 0.5 : 1)
        }
        .disabled(purchasing || selectedProductID == nil)
    }

    private var restoreButton: some View {
        Button(restoring ? "Restoring…" : "Restore Purchases") {
            restore()
        }
        .font(.system(size: 13.5, weight: .semibold))
        .foregroundStyle(Brand.accent)
        .disabled(restoring)
    }

    private func purchase() {
        guard let product = manager.products.first(where: { $0.id == selectedProductID }) else { return }
        errorMessage = nil
        purchasing = true
        Task {
            defer { purchasing = false }
            do {
                try await manager.purchase(product)
                if entitlements.isEntitled { dismiss() }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func restore() {
        errorMessage = nil
        restoring = true
        Task {
            defer { restoring = false }
            do {
                try await manager.restore()
                if EntitlementStore.shared.isEntitled {
                    dismiss()
                } else {
                    errorMessage = "No active subscription found for this Apple ID."
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

/// What the free plan includes, beside Premium's plans for comparison. Not a
/// choice: it's what an account has without subscribing.
private struct FreePlanCard: View {
    private static let points: [(included: Bool, text: String)] = [
        (true, "Every note labelled"),
        (true, "Practise on a keyboard"),
        (false, "1 music sheet at a time"),
        (false, "Shows ads"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Free")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.ink)
                Spacer()
                Text("Your plan without Premium")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.inkSoft)
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Self.points, id: \.text) { point in
                    Label {
                        Text(point.text).foregroundStyle(Brand.ink)
                    } icon: {
                        Image(systemName: point.included ? "checkmark" : "minus")
                            .foregroundStyle(point.included ? Brand.success : Brand.danger)
                    }
                    .font(.system(size: 14))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.paperDeep.opacity(0.5), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .accessibilityElement(children: .combine)
    }
}

/// One plan's price card — the web app has no equivalent to mirror; this is
/// designed from scratch for iOS.
private struct PlanCard: View {
    let product: Product
    let isSelected: Bool
    var offersTrial = true
    /// False shows the plan without a selection circle, and taps do nothing.
    var selectable = true
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Brand.ink)
                    if hasFreeTrial && offersTrial {
                        Text("7-day free trial")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Brand.success)
                    }
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.ink)
                if selectable {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Brand.accent : Brand.hairline)
                }
            }
            .padding(16)
            .background(Brand.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Brand.accent : Brand.hairline, lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(selectable)
    }

    private var title: String {
        product.id == SubscriptionProduct.yearlyID ? "Yearly" : "Monthly"
    }

    private var hasFreeTrial: Bool {
        product.subscription?.introductoryOffer?.paymentMode == .freeTrial
    }
}

/// An account already subscribed — possibly on the web — has nothing to buy
/// here; a second subscription would only bill them twice.
private struct AlreadySubscribed: View {
    let status: SubscriptionStatus
    let done: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34))
                .foregroundStyle(Brand.success)
            Text(status.isMasterOnly ? "You have full access" : "You're subscribed")
                .font(Brand.title(22))
                .foregroundStyle(Brand.ink)
            Text(status.isMasterOnly
                 ? "This is a master account, with full access to everything — no subscription needed."
                 : status.isBilledByApple
                 ? "Premium is active on this account."
                 : "Premium is active on this account through the website, so it works here too — there's nothing more to buy.")
                .font(.system(size: 14))
                .foregroundStyle(Brand.inkSoft)
                .multilineTextAlignment(.center)
            Button("Continue", action: done)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .frame(height: 46)
                .background(Brand.accent, in: .capsule)
        }
        .padding(.horizontal, 32)
    }
}

private struct RetryNotice: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Couldn't load Premium")
                .font(Brand.title(19))
                .foregroundStyle(Brand.ink)
            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(Brand.inkSoft)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 44)
                .background(Brand.accent, in: .capsule)
        }
        .padding(.horizontal, 32)
    }
}

#Preview {
    PaywallView()
}
