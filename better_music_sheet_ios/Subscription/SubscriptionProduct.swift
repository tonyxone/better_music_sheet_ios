import Foundation

/// The two subscribable products, configured in App Store Connect with a
/// shared 7-day introductory (free trial) offer.
nonisolated enum SubscriptionProduct {
    static let monthlyID = "com.bettermusicsheet.premium.monthly"
    static let yearlyID = "com.bettermusicsheet.premium.yearly"
    static let allIDs = [monthlyID, yearlyID]
}
