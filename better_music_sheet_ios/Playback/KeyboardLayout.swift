import Foundation

/// Where the 88 keys sit.
///
/// Ported from the web app's app/play/keyboard-layout.ts, geometry and all.
/// Black keys are NOT centred on the boundary between two white keys: on a
/// real piano the twelve semitones are equally spaced where they enter the
/// action, so F♯ sits noticeably left of its boundary, G♯ close to centre and
/// A♯ right. Centring them is the single thing that makes a drawn keyboard
/// look wrong.
nonisolated struct KeyboardLayout: Sendable {
    static let firstMIDI = 21   // A0
    static let lastMIDI = 108   // C8

    /// A white key is one unit wide. Real ratios: 2.4cm vs 1.4cm wide, 15cm
    /// vs 9cm long.
    static let whiteWidth: Double = 1
    static let blackWidth: Double = 0.583
    /// The hairline between white keys.
    static let gap: Double = 0.055
    /// A black key's length as a fraction of a white key's.
    static let blackLength: Double = 0.6

    private static let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    static func pitchClass(_ midi: Int) -> Int { ((midi % 12) + 12) % 12 }

    static func isBlack(_ midi: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(pitchClass(midi))
    }

    static func noteName(_ midi: Int, withOctave: Bool = false) -> String {
        noteNames[pitchClass(midi)] + (withOctave ? String(midi / 12 - 1) : "")
    }

    /// A stretch of keyboard to draw, from the left edge of its lowest key to
    /// the right edge of its highest, in white-key units.
    struct KeyRange: Sendable, Hashable {
        let lowMIDI: Int
        let highMIDI: Int
        let left: Double
        let right: Double
        var width: Double { right - left }
    }

    /// Key centres, in white-key units from the left edge of the full board.
    let centers: [Int: Double]
    let whiteCount: Int

    init() {
        var centers: [Int: Double] = [:]
        var whiteIndex = 0
        for midi in Self.firstMIDI...Self.lastMIDI where !Self.isBlack(midi) {
            centers[midi] = Double(whiteIndex) + 0.5
            whiteIndex += 1
        }
        for midi in Self.firstMIDI...Self.lastMIDI where Self.isBlack(midi) {
            let below = centers[midi - 1]
            let above = centers[midi + 1]
            guard let below, let above else {
                // Only the ends of the board lack a neighbour.
                centers[midi] = (below ?? above ?? 0) + (below == nil ? -0.5 : 0.5)
                continue
            }
            // Twelve semitones equally spaced across an octave seven white keys
            // wide put semitone n at (n + 0.5) * 7/12; this is that position's
            // offset from the white-key boundary the black key sits over.
            let offset: Double = switch Self.pitchClass(midi) {
            case 1: -1.0 / 8
            case 3: 1.0 / 24
            case 6: -5.0 / 24
            case 8: -1.0 / 24
            case 10: 1.0 / 8
            default: 0
            }
            centers[midi] = (below + above) / 2 + offset
        }
        self.centers = centers
        self.whiteCount = whiteIndex
    }

    /// The whole instrument.
    var fullRange: KeyRange { range(from: Self.firstMIDI, to: Self.lastMIDI) }

    /// Just enough keyboard for a piece: whole octaves from the C below its
    /// lowest note to the B above its highest, widened to at least
    /// `minimumOctaves` so a narrow melody still reads as a keyboard, and never
    /// past either end of the instrument.
    func range(covering midis: [Int], minimumOctaves: Int = 3) -> KeyRange {
        guard let lowest = midis.min(), let highest = midis.max() else { return fullRange }
        var low = lowest - Self.pitchClass(lowest)
        var high = highest - Self.pitchClass(highest) + 11
        var widenBelow = true
        while high - low + 1 < minimumOctaves * 12 {
            if widenBelow { low -= 12 } else { high += 12 }
            widenBelow.toggle()
        }
        return range(from: max(Self.firstMIDI, low), to: min(Self.lastMIDI, high))
    }

    /// Where a key's drawn body starts, and how wide it is, in white-key units.
    func extent(of midi: Int) -> (x: Double, width: Double) {
        let width = Self.isBlack(midi) ? Self.blackWidth : Self.whiteWidth - Self.gap
        return ((centers[midi] ?? 0) - width / 2, width)
    }

    private func range(from low: Int, to high: Int) -> KeyRange {
        KeyRange(lowMIDI: low, highMIDI: high,
                 left: (centers[low] ?? 0) - halfSlot(low),
                 right: (centers[high] ?? 0) + halfSlot(high))
    }

    /// Half the space a key occupies on the board, gap included.
    private func halfSlot(_ midi: Int) -> Double {
        (Self.isBlack(midi) ? Self.blackWidth : Self.whiteWidth) / 2
    }
}
