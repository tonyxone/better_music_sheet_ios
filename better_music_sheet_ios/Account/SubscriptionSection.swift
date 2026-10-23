import StoreKit
import SwiftUI

/// The account's subscription at a glance, and where to change it — the web
/// app's /subscription page, reshaped as a card on the account screen.
///
/// One subscription covers both apps, so it may have been bought on the web:
/// an App Store subscription is managed in Apple's own sheet, and a web
/// (Stripe) one is cancelled on the website — the app only says where.
struct SubscriptionSection: View {
    @State private var entitlements = EntitlementStore.shared
    @State private var showingPaywall = false
    @State private var managingWithApple = false
    @State private var explainingWebCancel = false

    var body: some View {
        Group {
            if let status = entitlements.status, status.isMasterOnly {
                masterAccount
            } else if let status = entitlements.status, status.isPremium {
                subscribed(status)
            } else {
                VStack(spacing: 10) {
                    Text("You're on the Free plan: 1 sheet at a time, with ads.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Brand.inkSoft)
                        .multilineTextAlignment(.center)
                    Button("See Premium Plans") { showingPaywall = true }
                        .buttonStyle(.premium)
                }
                .padding(.horizontal, 32)
            }
        }
        .task { await entitlements.refresh() }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .manageSubscriptionsSheet(isPresented: $managingWithApple)
        .onChange(of: managingWithApple) { _, open in
            if !open { Task { await SubscriptionManager.shared.syncCurrentEntitlement() } }
        }
    }

    /// Full access without a subscription (the backend's master users
    /// table): no plan, no renewal date, nothing to cancel — as on the web.
    private var masterAccount: some View {
        VStack(spacing: 6) {
            row("Plan", Text("Master account"))
            row("Status", Text("Full access, no subscription needed"))
        }
        .padding(14)
        .background(Brand.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.paperDeep, lineWidth: 1))
        .padding(.horizontal, 32)
    }

    private func subscribed(_ status: SubscriptionStatus) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                row("Plan", Text(status.plan == "yearly" ? "Yearly" : "Monthly"))
                row("Status", Text(status.cancelAtPeriodEnd == true ? "Cancels at period end"
                    : status.isTrialing ? "Trial active" : "Active"))
                row(status.cancelAtPeriodEnd == true ? "Access ends" : "Renews", Text(verbatim: date(status.currentPeriodEnd)))
                row("Billed through", Text(status.isBilledByApple ? "App Store" : "Website"))
            }
            .padding(14)
            .background(Brand.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.paperDeep, lineWidth: 1))

            if status.cancelAtPeriodEnd == true {
                Text("Premium continues until \(date(status.currentPeriodEnd)), then ends. You won't be charged again.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.inkSoft)
                    .multilineTextAlignment(.center)
            } else if status.isBilledByApple {
                Button("Manage Subscription") { managingWithApple = true }
                    .buttonStyle(.account(.filled))
            } else {
                Button("Cancel Subscription") { explainingWebCancel = true }
                    .buttonStyle(.account(tint: Brand.danger))
            }
        }
        .padding(.horizontal, 32)
        .alert("Cancel on bettermusicsheet.com", isPresented: $explainingWebCancel) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This subscription was bought on bettermusicsheet.com, so it can only be cancelled there. Please go to bettermusicsheet.com, sign in with this account and cancel it from the Subscription page.")
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Text(label).foregroundStyle(Brand.inkSoft)
            Spacer()
            value.foregroundStyle(Brand.ink)
        }
        .font(.system(size: 13.5))
    }

    private func date(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        return Date(timeIntervalSince1970: seconds)
            .formatted(Date.FormatStyle(date: .long, time: .omitted, locale: AppLanguage.current.locale))
    }
}
