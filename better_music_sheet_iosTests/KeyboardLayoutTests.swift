import Foundation
import Testing
@testable import better_music_sheet_ios

struct KeyboardLayoutTests {
    private let layout = KeyboardLayout()

    @Test func hasTheEightyEightKeysOfAPiano() {
        let midis = KeyboardLayout.firstMIDI...KeyboardLayout.lastMIDI
        #expect(midis.count == 88)
        #expect(layout.whiteCount == 52)
        #expect(midis.filter(KeyboardLayout.isBlack).count == 36)
    }

    @Test func whiteKeysTileEvenly() {
        #expect(layout.centers[21] == 0.5)    // A0
        #expect(layout.centers[23] == 1.5)    // B0
        #expect(layout.centers[60] == 23.5)   // middle C
        #expect(layout.centers[108] == 51.5)  // C8
    }

    @Test func blackKeysSitWhereTheyDoOnARealPiano() throws {
        // Boundaries around middle C's octave: C4|D4 at 24, D4|E4 at 25,
        // F4|G4 at 27, G4|A4 at 28, A4|B4 at 29.
        #expect(abs(try #require(layout.centers[61]) - (24 - 1.0 / 8)) < 1e-12)   // C♯ left
        #expect(abs(try #require(layout.centers[63]) - (25 + 1.0 / 24)) < 1e-12)  // D♯ right
        #expect(abs(try #require(layout.centers[66]) - (27 - 5.0 / 24)) < 1e-12)  // F♯ well left
        #expect(abs(try #require(layout.centers[68]) - (28 - 1.0 / 24)) < 1e-12)  // G♯ nearly centred
        #expect(abs(try #require(layout.centers[70]) - (29 + 1.0 / 8)) < 1e-12)   // A♯ right
    }

    @Test func theLowestBlackKeyFollowsTheSameRule() throws {
        // A♯0 sits between A0 and B0 like any other A♯.
        #expect(abs(try #require(layout.centers[22]) - (1 + 1.0 / 8)) < 1e-12)
    }

    @Test func namesKeys() {
        #expect(KeyboardLayout.noteName(60, withOctave: true) == "C4")
        #expect(KeyboardLayout.noteName(61) == "C♯")
        #expect(KeyboardLayout.noteName(21, withOctave: true) == "A0")
        #expect(KeyboardLayout.noteName(108, withOctave: true) == "C8")
        #expect(KeyboardLayout.isBlack(70))
        #expect(!KeyboardLayout.isBlack(71))
    }

    @Test func fullRangeIsTheWholeBoard() {
        let full = layout.fullRange
        #expect(full.lowMIDI == 21)
        #expect(full.highMIDI == 108)
        #expect(full.left == 0)
        #expect(full.width == 52)
    }

    @Test func aPieceGetsWholeOctavesAroundItsNotes() {
        // D3 to B5 already spans three octaves once rounded out to C3...B5.
        let range = layout.range(covering: [50, 71, 83])
        #expect(range.lowMIDI == 48)
        #expect(range.highMIDI == 83)
        #expect(range.width == 21)
    }

    @Test func aNarrowMelodyIsWidenedToThreeOctaves() {
        let range = layout.range(covering: [60, 64, 67])
        #expect(range.lowMIDI == 48)   // one octave down
        #expect(range.highMIDI == 83)  // and one up
    }

    @Test func widensWithoutRunningPastTheBottom() {
        let range = layout.range(covering: [21, 23])
        #expect(range.lowMIDI == 21)
        #expect(range.left == 0)
    }

    @Test func orPastTheTop() {
        let range = layout.range(covering: [108])
        #expect(range.highMIDI == 108)
        #expect(range.right == 52)
    }

    @Test func noNotesMeansTheWholeKeyboard() {
        #expect(layout.range(covering: []) == layout.fullRange)
    }

    @Test func keyExtentsMatchTheirWidths() {
        let white = layout.extent(of: 60)
        #expect(abs(white.width - (1 - 0.055)) < 1e-12)
        #expect(abs(white.x - (23.5 - (1 - 0.055) / 2)) < 1e-12)
        #expect(abs(layout.extent(of: 61).width - 0.583) < 1e-12)
    }
}
