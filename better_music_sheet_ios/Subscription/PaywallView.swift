import SwiftUI
import StoreKit

/// Presented in place of PracticeView wherever practice mode is gated (see
/// RootView and SheetDetailView) — the only place in the app that asks for
/// money.
struct PaywallView: View {
    @State private var manager = SubscriptionManager.shared
    @State private var selectedProductID: String?
    @State private var purchasing = false
    @State private var restoring = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.paper.ignoresSafeArea()
                content
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            await manager.loadProducts()
            if selectedProductID == nil {
                selectedProductID = manager.products.first { $0.id == SubscriptionProduct.yearlyID }?.id
                    ?? manager.products.first?.id
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if manager.isLoadingProducts && manager.products.isEmpty {
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
                            PlanCard(product: product, isSelected: product.id == selectedProductID) {
                                selectedProductID = product.id
                            }
                        }
                    }

                    purchaseButton
                    restoreButton

                    Text("A 7-day free trial, then the plan you choose. Cancel anytime in Settings.")
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
            Text("Practice without limits")
                .font(Brand.title(22))
                .foregroundStyle(Brand.ink)
            Text("Premium unlocks practice mode on every sheet, with a 7-day free trial.")
                .font(.system(size: 14))
                .foregroundStyle(Brand.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var purchaseButton: some View {
        Button(action: purchase) {
            Text(purchasing ? "Starting your trial…" : "Start free trial")
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
                dismiss()
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
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Brand.ink)
                    if hasFreeTrial {
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
