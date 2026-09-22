import Foundation

/// Mirrors the backend's GET /api/me/subscription — the single source of
/// truth for entitlement, whichever platform (iOS or web) the purchase
/// happened on. Field names match the backend's snake_case response via
/// APIClient's `.convertFromSnakeCase` decoder, so no CodingKeys are needed.
nonisolated struct SubscriptionStatus: Codable, Sendable, Equatable {
    let tier: String
    let plan: String?
    let status: String?
    let currentPeriodEnd: Double?
    let cancelAtPeriodEnd: Bool?
    let platform: String?

    var isPremium: Bool { tier == "premium" }
}
