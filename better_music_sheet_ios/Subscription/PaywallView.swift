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
    @Environment(\.dismiss) private var dismiss

    private static let benefits = [
        "Upload your own sheets",
        "Every note labelled",
        "Practise on a keyboard",
        "Unlimited sheet storage",
        "Access anywhere — web and iPhone",
    ]

    /// True when pushed onto the app's navigation stack (in place of the
    /// practice page) rather than presented as a sheet. A pushed paywall must
    /// not bring its own NavigationStack: one nested inside the app's typed
    /// stack crashes SwiftUI when the path changes.
    var pushed = false

    var body: some View {
        Group {
            if pushed {
                page
            } else {
                NavigationStack {
                    page
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { dismiss() }
                            }
                        }
                }
            }
        }
        .task {
            await checkAccount()
            await manager.loadProducts()
            if selectedProductID == nil {
                selectedProductID = manager.products.first { $0.id == SubscriptionProduct.yearlyID }?.id
                    ?? manager.products.first?.id
            }
        }
        .sheet(isPresented: $showingAccount, onDismiss: { Task { await checkAccount() } }) {
            AccountView()
        }
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

    /// Only an account that has never subscribed gets the trial, whichever
    /// store it subscribed through — and StoreKit must agree for this Apple ID.
    private var offersTrial: Bool {
        guard entitlements.status?.offersTrial != false else { return false }
        return manager.products.contains { $0.subscription?.introductoryOffer?.paymentMode == .freeTrial }
    }

    @ViewBuilder
    private var content: some View {
        if entitlements.isEntitled, let status = entitlements.status {
            AlreadySubscribed(status: status) { dismiss() }
        } else if signedIn == nil || (manager.isLoadingProducts && manager.products.isEmpty) {
            ProgressView().tint(Brand.accent)
        } else if manager.products.isEmpty {
            RetryNotice(message: manager.loadError ?? "Couldn't load subscription options.") {
                Task { await manager.loadProducts() }
            }
        } else {
            ScrollView {
                VStack(spacing: 22) {
                    header

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(Brand.danger)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        ForEach(manager.products) { product in
                            PlanCard(product: product, isSelected: product.id == selectedProductID, offersTrial: offersTrial) {
                                selectedProductID = product.id
                            }
                        }
                    }

                    benefits

                    if signedIn == true {
                        purchaseButton
                        restoreButton
                    } else {
                        signInButton
                    }

                    Text(terms)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Brand.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "pianokeys")
                .font(.system(size: 30))
                .foregroundStyle(Brand.accent)
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
        return "\(start) Cancelling stops the next renewal: you keep access until the end of the period you've paid for, and payments already made aren't refunded. Manage it in Settings."
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
                .opacity(purchasing ? 0.6 : 1)
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

/// One plan's price card — the web app has no equivalent to mirror; this is
/// designed from scratch for iOS.
private struct PlanCard: View {
    let product: Product
    let isSelected: Bool
    var offersTrial = true
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
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Brand.accent : Brand.hairline)
            }
            .padding(16)
            .background(Brand.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Brand.accent : Brand.hairline, lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
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
            Text("You're subscribed")
                .font(Brand.title(22))
                .foregroundStyle(Brand.ink)
            Text(status.isBilledByApple
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
