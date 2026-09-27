import StoreKit
import SwiftUI

/// The account's subscription at a glance, and where to change it — the web
/// app's /subscription page, reshaped as a card on the account screen.
///
/// One subscription covers both apps, so it may have been bought on the web:
/// an App Store subscription is managed in Apple's own sheet (no server can
/// cancel one), and a web one is cancelled here through the backend.
struct SubscriptionSection: View {
    @State private var entitlements = EntitlementStore.shared
    @State private var showingPaywall = false
    @State private var managingWithApple = false
    @State private var confirmingCancel = false
    @State private var cancelling = false
    @State private var error: String?

    var body: some View {
        Group {
            if let status = entitlements.status, status.isMasterOnly {
                masterAccount
            } else if let status = entitlements.status, status.isPremium {
                subscribed(status)
            } else {
                Button("See Premium plans") { showingPaywall = true }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.accent)
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
            row("Plan", "Master account")
            row("Status", "Full access, no subscription needed")
        }
        .padding(14)
        .background(Brand.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.paperDeep, lineWidth: 1))
        .padding(.horizontal, 32)
    }

    private func subscribed(_ status: SubscriptionStatus) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                row("Plan", status.plan == "yearly" ? "Yearly" : "Monthly")
                row("Status", status.cancelAtPeriodEnd == true ? "Cancels at period end"
                    : status.isTrialing ? "Trial active" : "Active")
                row(status.cancelAtPeriodEnd == true ? "Access ends" : "Renews", date(status.currentPeriodEnd))
                row("Billed through", status.isBilledByApple ? "App Store" : "Website")
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.accent)
            } else {
                Button(cancelling ? "Cancelling…" : "Cancel Subscription") { confirmingCancel = true }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.danger)
                    .disabled(cancelling)
            }

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .alert(status.isTrialing ? "Cancel your free trial?" : "Cancel your subscription?",
               isPresented: $confirmingCancel) {
            Button("Keep Subscription", role: .cancel) {}
            Button("Confirm Cancellation", role: .destructive) { Task { await cancel() } }
        } message: {
            Text(status.isTrialing
                 ? "You keep Premium until \(date(status.currentPeriodEnd)), and you won't be charged."
                 : "It stays active until \(date(status.currentPeriodEnd)), then ends. You won't be charged again, but no refund is issued for the time remaining.")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Brand.inkSoft)
            Spacer()
            Text(value).foregroundStyle(Brand.ink)
        }
        .font(.system(size: 13.5))
    }

    private func date(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        return Date(timeIntervalSince1970: seconds).formatted(date: .long, time: .omitted)
    }

    private func cancel() async {
        cancelling = true
        error = nil
        defer { cancelling = false }
        do {
            try await entitlements.cancelWebSubscription()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
