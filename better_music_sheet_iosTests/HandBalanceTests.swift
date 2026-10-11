import Foundation
import Testing
@testable import better_music_sheet_ios

@Suite struct HandBalanceTests {
    @Test func theMiddlePlaysBothHandsAsWritten() {
        #expect(HandBalance.velocityScale(balance: 0, role: 0) == 1)
        #expect(HandBalance.velocityScale(balance: 0, role: 1) == 1)
    }

    @Test func draggingTowardAHandQuietensOnlyTheOther() {
        // Toward the right hand: the left (role 1) gives way.
        #expect(HandBalance.velocityScale(balance: 0.75, role: 0) == 1)
        #expect(abs(HandBalance.velocityScale(balance: 0.75, role: 1) - 0.5) < 1e-12)
        #expect(HandBalance.velocityScale(balance: -0.75, role: 1) == 1)
        #expect(abs(HandBalance.velocityScale(balance: -0.75, role: 0) - 0.5) < 1e-12)
    }

    @Test func theEndsSilenceTheOtherHand() {
        #expect(HandBalance.velocityScale(balance: 1, role: 1) == 0)
        #expect(HandBalance.velocityScale(balance: -1, role: 0) == 0)
        // Out of range is no louder than the end.
        #expect(HandBalance.velocityScale(balance: 3, role: 1) == 0)
    }

    @Test func snapsToEvenNearTheMiddleAndStaysInRange() {
        #expect(HandBalance.normalized(0.05) == 0)
        #expect(HandBalance.normalized(-0.07) == 0)
        #expect(HandBalance.normalized(0.1) == 0.1)
        #expect(HandBalance.normalized(4) == 1)
        #expect(HandBalance.normalized(-4) == -1)
        #expect(HandBalance.normalized(.nan) == 0)
    }

    @Test func reportsEachHandsLevel() {
        #expect(HandBalance.levels(0.25) == (75, 100))
        #expect(HandBalance.levels(-1) == (100, 0))
    }

    @Test func isKeptPerSheet() throws {
        let name = "hand-balance-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        HandBalance.save(-0.5, jobID: "a", to: defaults)
        #expect(HandBalance.load(jobID: "a", from: defaults) == -0.5)
        #expect(HandBalance.load(jobID: "b", from: defaults) == 0)

        HandBalance.save(0, jobID: "a", to: defaults)
        #expect(defaults.object(forKey: "hand-balance:a") == nil)
    }
}
