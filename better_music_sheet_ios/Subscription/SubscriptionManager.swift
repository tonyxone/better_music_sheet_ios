import Foundation
import StoreKit

@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    private(set) var products: [Product] = []
    private(set) var introductoryEligibleIDs: Set<String> = []
    private(set) var isLoadingProducts = false
    private(set) var loadError: String?
    private(set) var syncError: String?

    private let client: APIClient
    private let entitlements: EntitlementStore
    private let sessions: SessionStore
    private var updatesTask: Task<Void, Never>?
    private var syncing = false

    init(client: APIClient = .shared, entitlements: EntitlementStore = .shared,
         sessions: SessionStore = .shared) {
        self.client = client
        self.entitlements = entitlements
        self.sessions = sessions
    }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                do { try await self.deliver(update) }
                catch { self.syncError = error.localizedDescription }
            }
        }
        Task { await loadProducts() }
        Task { await syncCurrentEntitlement() }
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        loadError = nil
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: SubscriptionProduct.allIDs)
                .sorted { $0.price < $1.price }
            if products.count != SubscriptionProduct.allIDs.count {
                loadError = "Some subscription plans are unavailable. Please try again later."
            }
            await refreshIntroductoryEligibility()
        } catch {
            loadError = "Couldn't load subscription options. \(error.localizedDescription)"
        }
    }

    func refreshIntroductoryEligibility() async {
        var eligible: Set<String> = []
        for product in products {
            if let info = product.subscription,
               info.introductoryOffer?.paymentMode == .freeTrial,
               await info.isEligibleForIntroOffer {
                eligible.insert(product.id)
            }
        }
        introductoryEligibleIDs = eligible
    }

    func purchase(_ product: Product) async throws {
        guard SubscriptionProduct.allIDs.contains(product.id),
              let session = await sessions.current(),
              let token = UUID(uuidString: session.user.userID) else {
            throw SubscriptionError.signInRequired
        }
        // Refuse a second charge based on a fresh server answer, not a cached paywall.
        let current: SubscriptionStatus = try await client.get("/api/me/subscription")
        if current.isPremium { throw SubscriptionError.alreadySubscribed }
        guard await sessions.current()?.user.userID == session.user.userID else {
            throw SubscriptionError.accountChanged
        }
        let result = try await product.purchase(options: [.appAccountToken(token)])
        switch result {
        case .success(let verification):
            try await deliver(verification, userID: session.user.userID)
        case .userCancelled:
            break
        case .pending:
            throw SubscriptionError.purchasePending
        @unknown default:
            break
        }
    }

    func restore() async throws {
        guard await sessions.current() != nil else { throw SubscriptionError.signInRequired }
        try await AppStore.sync()
        try await syncTransactions()
    }

    /// Retries unfinished delivery on launch, foreground, and after sign-in.
    func syncCurrentEntitlement() async {
        do { try await syncTransactions() }
        catch { syncError = error.localizedDescription }
    }

    private func syncTransactions() async throws {
        guard !syncing else { return }
        guard let userID = await sessions.current()?.user.userID else {
            await entitlements.refresh()
            return
        }
        syncing = true
        defer { syncing = false }
        syncError = nil
        var seen: Set<UInt64> = []
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result,
               SubscriptionProduct.allIDs.contains(transaction.productID) {
                try await deliver(result, userID: userID)
                seen.insert(transaction.id)
            }
        }
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               SubscriptionProduct.allIDs.contains(transaction.productID),
               !seen.contains(transaction.id) {
                try await deliver(result, userID: userID)
            }
        }
        await entitlements.refresh()
        await refreshIntroductoryEligibility()
    }

    private func deliver(_ result: VerificationResult<Transaction>, userID: String? = nil) async throws {
        guard case .verified(let transaction) = result else {
            throw SubscriptionError.failedVerification
        }
        guard SubscriptionProduct.allIDs.contains(transaction.productID) else { return }
        let signedInID = await sessions.current()?.user.userID
        guard let owner = userID ?? signedInID else {
            throw SubscriptionError.signInRequired
        }
        let reporter = ApplePurchaseReporter(client: client, sessions: sessions, entitlements: entitlements)
        try await reporter.report(result.jwsRepresentation, userID: owner)
        await transaction.finish()
        syncError = nil
    }
}
