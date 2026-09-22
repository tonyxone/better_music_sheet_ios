import Foundation
import StoreKit

/// StoreKit 2 purchase flow and entitlement listener. Keeps no entitlement
/// state of its own — EntitlementStore is the single source of truth for
/// "can this account use practice mode," since it also has to agree with a
/// subscription bought on the web. This only drives StoreKit and tells the
/// backend what StoreKit said.
@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    private(set) var loadError: String?

    private let client: APIClient
    private let entitlements: EntitlementStore
    private var updatesTask: Task<Void, Never>?

    init(client: APIClient = .shared, entitlements: EntitlementStore = .shared) {
        self.client = client
        self.entitlements = entitlements
    }

    /// Called once, at app launch (see BetterMusicSheetApp). Starts
    /// listening for transactions StoreKit delivers outside of an explicit
    /// purchase() call — renewals, family sharing, a purchase made on
    /// another device — loads the product list, and reports whatever is
    /// currently entitled.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handleUpdate(update)
            }
        }
        Task { await loadProducts() }
        Task { await syncCurrentEntitlement() }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: SubscriptionProduct.allIDs)
                .sorted { $0.price < $1.price }
        } catch {
            loadError = "Couldn't load subscription options. \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            try await handlePurchase(verification)
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    /// Required by App Store review for any subscription app: re-links
    /// purchases StoreKit already knows about (a reinstall, a new device)
    /// without charging anything again.
    func restore() async throws {
        try await AppStore.sync()
        await syncCurrentEntitlement()
    }

    /// Walks current entitlements for the latest non-revoked, non-expired
    /// transaction and reports it to the backend and EntitlementStore.
    func syncCurrentEntitlement() async {
        var latest: (transaction: Transaction, jws: String)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  (transaction.expirationDate ?? .distantFuture) > Date() else { continue }
            if latest == nil || transaction.purchaseDate > latest!.transaction.purchaseDate {
                latest = (transaction, result.jwsRepresentation)
            }
        }
        if let latest {
            await report(latest.jws)
        }
        await entitlements.refresh()
    }

    // MARK: - Internals

    private func handlePurchase(_ result: VerificationResult<Transaction>) async throws {
        guard case .verified(let transaction) = result else {
            throw SubscriptionError.failedVerification
        }
        await report(result.jwsRepresentation)
        await transaction.finish()
        await entitlements.refresh()
    }

    /// The Transaction.updates listener's own handler: a transaction that
    /// fails verification here is quietly dropped rather than thrown, since
    /// there's no caller left to hand the error to.
    private func handleUpdate(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        await report(update.jwsRepresentation)
        await transaction.finish()
        await entitlements.refresh()
    }

    /// Posts the raw JWS so the backend can record the purchase against this
    /// account. POST /api/subscriptions/apple/transaction is shipping in
    /// parallel on the backend — a 404/501 (or any other failure) is silent
    /// and not retried; StoreKit's own verified transaction already grants
    /// the purchase locally, and the next launch or purchase/update tries
    /// the report again.
    private func report(_ jws: String) async {
        struct Body: Encodable { let transaction: String }
        guard let encoded = try? JSONEncoder().encode(Body(transaction: jws)) else { return }
        _ = try? await client.call("/api/subscriptions/apple/transaction", method: "POST",
                                   body: encoded, contentType: "application/json")
    }
}
