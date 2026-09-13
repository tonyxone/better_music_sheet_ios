import Foundation

/// The playback timeline served by `GET /api/sheets/{job_id}/timeline`,
/// built by the backend's timeline.py. Ported field-for-field from the web
/// app's lib/timeline.ts — this is shared correctness, not UI, so it stays
/// faithful rather than idiomatic.
///
/// Beats are quarter-note units. Score/PDF tempo events form a tempo map; a
/// default BPM remains available when recognition has no trustworthy marking.

/// [x0, y0, x1, y1] in PDF points, top-down (PyMuPDF convention). Kept as a
/// named type because the y-axis flip on the way to PDFKit is the single
/// easiest thing to get wrong here.
nonisolated struct BBoxPoints: Codable, Sendable, Hashable {
    let x0, y0, x1, y1: Double

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x0 = try c.decode(Double.self)
        y0 = try c.decode(Double.self)
        x1 = try c.decode(Double.self)
        y1 = try c.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(contentsOf: [x0, y0, x1, y1])
    }

    var width: Double { x1 - x0 }
    var height: Double { y1 - y0 }
}

nonisolated enum Hand: String, Codable, Sendable, Hashable {
    case left, right
}

nonisolated struct TimelineNote: Codable, Sendable, Hashable, Identifiable {
    var sourceID: String?
    var printedID: String?
    var printedMeasureIndex: Int?
    var part: Int?
    var staff: Int?
    var voice: String?
    var hand: Hand?
    var attack: Bool?
    var velocity: Double?
    var keyDurationBeats: Double?
    var pitchSource: String?
    var confidence: Double?
    var fingering: String?
    var tieStart: Bool?
    var tieStop: Bool?
    var measureIndex: Int
    /// 0 = top staff (right hand), 1 = bottom staff.
    var role: Int
    var midi: Int
    var startBeat: Double
    /// 0 for grace notes; the player gives those a fixed short length.
    var durationBeats: Double
    var isGrace: Bool
    /// The notehead's own box, when the two OMR sources agreed on this
    /// measure. Nil otherwise — the player falls back to a position
    /// interpolated across the measure.
    var bboxPt: BBoxPoints?

    /// `sourceID`/`printedID` need spelling out: the snake_case strategy
    /// produces "sourceId", which does not match a key synthesised from
    /// "sourceID". Everything else matches by default.
    private enum CodingKeys: String, CodingKey {
        case sourceID = "sourceId"
        case printedID = "printedId"
        case printedMeasureIndex, part, staff, voice, hand, attack, velocity
        case keyDurationBeats, pitchSource, confidence, fingering
        case tieStart, tieStop, measureIndex, role, midi
        case startBeat, durationBeats, isGrace, bboxPt
    }

    /// Stable identity for diffing and for the correction store. Falls back
    /// the same way the web app does when the backend sent no ids.
    var id: String { printedID ?? sourceID ?? "\(measureIndex):\(midi):\(startBeat)" }

    /// How long the key is physically held: excludes pedal-only sustain, and
    /// gives a grace note the fixed short length the player uses.
    var heldDurationBeats: Double {
        if let keyDurationBeats { return keyDurationBeats }
        if durationBeats > 0 { return durationBeats }
        return isGrace ? 0.25 : 0
    }
}

nonisolated struct TimelineMeasure: Codable, Sendable, Hashable, Identifiable {
    var printedIndex: Int?
    var system: Int?
    var warnings: [String]?
    var index: Int
    var label: String
    /// 1-based PDF page, or nil if this measure has no page geometry.
    var page: Int?
    var startBeat: Double
    var lengthBeats: Double
    var bboxPt: BBoxPoints?
    var distinctMidis: [Int]

    var id: Int { index }
    var endBeat: Double { startBeat + lengthBeats }
}

nonisolated struct AudioNote: Codable, Sendable, Hashable {
    var segmentIDs: [String]?
    var sourceID: String?
    var midi: Int
    var role: Int
    var startBeat: Double
    var durationBeats: Double
    var velocity: Double?

    private enum CodingKeys: String, CodingKey {
        case segmentIDs = "segmentIds"
        case sourceID = "sourceId"
        case midi, role, startBeat, durationBeats, velocity
    }
}

nonisolated struct TempoEvent: Codable, Sendable, Hashable {
    var startBeat: Double
    var bpm: Double
    var beatUnitQuarters: Double?
}

nonisolated struct TimelineEvent: Codable, Sendable, Hashable {
    var kind: String
    var startBeat: Double
    /// The backend sends either a string or a number here depending on `kind`.
    var value: String
    var part: Int
    var staff: Int

    private enum CodingKeys: String, CodingKey {
        case kind, startBeat, value, part, staff
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        startBeat = try c.decode(Double.self, forKey: .startBeat)
        part = try c.decode(Int.self, forKey: .part)
        staff = try c.decode(Int.self, forKey: .staff)
        if let text = try? c.decode(String.self, forKey: .value) {
            value = text
        } else if let number = try? c.decode(Double.self, forKey: .value) {
            value = String(number)
        } else {
            value = ""
        }
    }
}

nonisolated struct Timeline: Codable, Sendable, Hashable {
    var version: Int
    var tempoBpmDefault: Double
    var totalBeats: Double
    var measures: [TimelineMeasure]
    var notes: [TimelineNote]
    var audioNotes: [AudioNote]?
    var tempoMap: [TempoEvent]?
    var tempoSource: String?
    var events: [TimelineEvent]?
    var stats: [String: Double]?
    var warnings: [String]?

    /// Held keys exclude pedal-only sustain; written tie segments stay visible.
    func notes(atBeat beat: Double) -> [TimelineNote] {
        notes.filter { note in
            let duration = note.heldDurationBeats
            return beat >= note.startBeat - 1e-9 && beat < note.startBeat + duration - 1e-9
        }
    }

    func measureIndex(atBeat beat: Double) -> Int? {
        measures.first { beat >= $0.startBeat && beat < $0.endBeat }?.index
    }

    func measure(withIndex index: Int) -> TimelineMeasure? {
        measures.first { $0.index == index }
    }
}
