import Foundation

/// Mirrors the backend's GET /api/me/subscription — the single source of
/// truth for entitlement, whichever platform (iOS or web) the purchase
/// happened on. Field names match the backend's snake_case response via
/// APIClient's `.convertFromSnakeCase` decoder, so no CodingKeys are needed.
nonisolated struct SubscriptionStatus: Codable, Sendable, Equatable {
    let tier: String
    let plan: String?
    let status: String?
    /// When the current subscription began, trial included (epoch seconds).
    var startedAt: Double? = nil
    let currentPeriodEnd: Double?
    let cancelAtPeriodEnd: Bool?
    /// "apple" or "stripe": which store bills it, and so where it's cancelled.
    let platform: String?
    /// Whether a new subscription would start with the 7-day free trial —
    /// only an account that has never subscribed before gets one. Absent
    /// from older backends, which gave everyone the trial.
    var trialEligible: Bool? = nil
    /// A master account: premium because it's listed in the backend's master
    /// users table, not because it pays. Absent from older backends.
    var master: Bool? = nil

    var isPremium: Bool { tier == "premium" }
    /// Premium with no subscription of its own behind it — nothing to show
    /// as a plan and nothing to cancel. A master account that also bought a
    /// subscription keeps showing (and can cancel) that subscription.
    var isMasterOnly: Bool { master == true && platform == nil }
    var isTrialing: Bool { status == "trialing" }
    var isBilledByApple: Bool { platform == "apple" }
    var offersTrial: Bool { trialEligible != false }
}
