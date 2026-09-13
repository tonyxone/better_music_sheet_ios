import Foundation

nonisolated struct MusicSheet: Codable, Sendable, Identifiable, Hashable {
    let musicSheetID: String
    let sheetName: String
    let createdAt: Double

    var id: String { musicSheetID }

    private enum CodingKeys: String, CodingKey {
        case musicSheetID = "musicSheetId"
        case sheetName, createdAt
    }
}

nonisolated struct User: Codable, Sendable, Identifiable, Hashable {
    let userID: String
    let email: String?
    /// Null for accounts created before names were required.
    let displayName: String?
    let createdAt: Double

    var id: String { userID }

    private enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case email, displayName, createdAt
    }
}
