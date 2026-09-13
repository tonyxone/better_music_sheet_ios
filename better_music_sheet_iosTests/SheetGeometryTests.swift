import CoreGraphics
import Foundation
import Testing
@testable import better_music_sheet_ios

private func decode(_ json: String) throws -> Timeline {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Timeline.self, from: Data(json.utf8))
}

private func bbox(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) throws -> BBoxPoints {
    try JSONDecoder().decode(BBoxPoints.self, from: Data("[\(x0),\(y0),\(x1),\(y1)]".utf8))
}

struct SheetCoordinateTests {

    @Test func overlayRectsNeedNoFlip() throws {
        // bbox_pt is top-down and so are UIKit/SwiftUI, so a view overlay is
        // a straight proportional mapping.
        let rect = SheetGeometry.normalizedRect(for: try bbox(100, 50, 300, 150),
                                                pageWidth: 400, pageHeight: 200)
        #expect(rect.origin.x == 0.25)
        #expect(rect.origin.y == 0.25)
        #expect(rect.width == 0.5)
        #expect(rect.height == 0.5)
    }

    @Test func pdfKitRectsAreFlipped() throws {
        // PDFKit's page space starts at the BOTTOM-left, so the same box has
        // to be measured up from the bottom instead of down from the top.
        let rect = SheetGeometry.pdfRect(for: try bbox(100, 50, 300, 150), pageHeight: 200)
        #expect(rect.origin.x == 100)
        #expect(rect.origin.y == 50)   // 200 - 150
        #expect(rect.width == 200)
        #expect(rect.height == 100)
    }

    @Test func aBoxAtTheTopOfThePageLandsAtTheTopInBothSpaces() throws {
        let top = try bbox(0, 0, 100, 20)
        let overlay = SheetGeometry.normalizedRect(for: top, pageWidth: 100, pageHeight: 200)
        let pdf = SheetGeometry.pdfRect(for: top, pageHeight: 200)

        #expect(overlay.origin.y == 0)      // top of the view
        #expect(pdf.origin.y == 180)        // near the top in PDF space
        #expect(pdf.maxY == 200)
    }

    @Test func aZeroSizedPageDoesNotProduceInfinities() throws {
        let rect = SheetGeometry.normalizedRect(for: try bbox(0, 0, 10, 10), pageWidth: 0, pageHeight: 0)
        #expect(rect == .zero)
    }
}

/// Two measures on one system: measure 0 spans x 50...150, measure 1 spans
/// 150...250, both on page 1.
private func twoMeasures(notes: String) throws -> Timeline {
    try decode("""
    {
      "version": 1, "tempo_bpm_default": 96, "total_beats": 8,
      "measures": [
        {"index": 0, "label": "1", "page": 1, "start_beat": 0, "length_beats": 4,
         "bbox_pt": [50, 100, 150, 180], "distinct_midis": []},
        {"index": 1, "label": "2", "page": 1, "start_beat": 4, "length_beats": 4,
         "bbox_pt": [150, 100, 250, 180], "distinct_midis": []}
      ],
      "notes": [\(notes)]
    }
    """)
}

private func note(_ id: String, measure: Int, beat: Double, midi: Int = 60, box: String = "null") -> String {
    """
    {"source_id": "\(id)", "measure_index": \(measure), "role": 0, "midi": \(midi),
     "start_beat": \(beat), "duration_beats": 1, "is_grace": false, "bbox_pt": \(box)}
    """
}

struct PlayheadOnsetTests {

    @Test func aChordIsOneOnset() throws {
        // Three noteheads struck together must not draw three playheads.
        let geometry = SheetGeometry(timeline: try twoMeasures(notes: [
            note("a", measure: 0, beat: 0, midi: 60, box: "[60, 100, 70, 108]"),
            note("b", measure: 0, beat: 0, midi: 64, box: "[60, 110, 70, 118]"),
            note("c", measure: 0, beat: 0, midi: 67, box: "[60, 120, 70, 128]"),
        ].joined(separator: ",")))

        #expect(geometry.onsets.count == 1)
        #expect(geometry.onsets[0].x == 65)   // centre of the noteheads
        #expect(!geometry.onsets[0].approximate)
    }

    @Test func exactPositionsBeatInterpolatedOnes() throws {
        // One hand has real geometry, the other doesn't. Averaging the two
        // would drag the line away from the notehead that is actually known.
        let geometry = SheetGeometry(timeline: try twoMeasures(notes: [
            note("a", measure: 0, beat: 0, midi: 60, box: "[140, 100, 150, 108]"),
            note("b", measure: 0, beat: 0, midi: 48),
        ].joined(separator: ",")))

        #expect(geometry.onsets.count == 1)
        #expect(geometry.onsets[0].x == 145)
        #expect(!geometry.onsets[0].approximate)
    }

    @Test func missingGeometryInterpolatesAcrossTheMeasure() throws {
        let geometry = SheetGeometry(timeline: try twoMeasures(notes:
            note("a", measure: 0, beat: 2)))

        // Halfway through a 4-beat measure spanning x 50...150.
        #expect(geometry.onsets[0].x == 100)
        #expect(geometry.onsets[0].approximate)
    }

    @Test func interpolationStopsShortOfTheBarline() throws {
        // A note on the last fraction of the bar must not sit on the barline,
        // where it reads as belonging to the next measure.
        let geometry = SheetGeometry(timeline: try twoMeasures(notes:
            note("a", measure: 0, beat: 3.99)))

        #expect(geometry.onsets[0].x == 146)   // 50 + 0.96 * 100
    }

    @Test func thePlayheadNeverRetreatsWithinAMeasure() throws {
        // Recognition can hand a later onset an earlier x; the line must not
        // walk backwards while the music moves forward.
        let geometry = SheetGeometry(timeline: try twoMeasures(notes: [
            note("a", measure: 0, beat: 0, box: "[120, 100, 130, 108]"),
            note("b", measure: 0, beat: 1, box: "[60, 100, 70, 108]"),
        ].joined(separator: ",")))

        #expect(geometry.onsets.map(\.beat) == [0, 1])
        #expect(geometry.onsets[0].x == 125)
        #expect(geometry.onsets[1].x == 125)   // clamped, not 65
    }

    @Test func theClampDoesNotCrossIntoTheNextMeasure() throws {
        // A new measure legitimately starts further left — on a new system it
        // starts at the left margin — so the clamp must stop at the barline.
        let geometry = SheetGeometry(timeline: try twoMeasures(notes: [
            note("a", measure: 0, beat: 0, box: "[140, 100, 150, 108]"),
            note("b", measure: 1, beat: 4, box: "[155, 100, 165, 108]"),
        ].joined(separator: ",")))

        #expect(geometry.onsets[1].x == 160)
        #expect(geometry.onsets[1].measure == 1)
    }

    @Test func notesInMeasuresWithoutGeometryAreSkipped() throws {
        // Missing geometry must never be shifted onto another page.
        let timeline = try decode("""
        {"version": 1, "tempo_bpm_default": 96, "total_beats": 4,
         "measures": [{"index": 0, "label": "1", "page": null, "start_beat": 0,
                       "length_beats": 4, "bbox_pt": null, "distinct_midis": []}],
         "notes": [\(note("a", measure: 0, beat: 0))]}
        """)

        #expect(SheetGeometry(timeline: timeline).onsets.isEmpty)
    }

    @Test func findsTheLatestOnsetAtOrBeforeTheClock() throws {
        let geometry = SheetGeometry(timeline: try twoMeasures(notes: [
            note("a", measure: 0, beat: 0, box: "[60, 100, 70, 108]"),
            note("b", measure: 0, beat: 2, box: "[100, 100, 110, 108]"),
        ].joined(separator: ",")))

        #expect(geometry.playhead(atBeat: 0)?.beat == 0)
        #expect(geometry.playhead(atBeat: 1.9)?.beat == 0)
        #expect(geometry.playhead(atBeat: 2)?.beat == 2)
        #expect(geometry.playhead(atBeat: 3.5)?.beat == 2)
    }

    @Test func thePlayheadDropsRatherThanStrandItselfOnTheWrongBar() throws {
        // The clock has moved into measure 1, which has no onsets of its own.
        // Showing measure 0's line there would be worse than showing none.
        let geometry = SheetGeometry(timeline: try twoMeasures(notes:
            note("a", measure: 0, beat: 0, box: "[60, 100, 70, 108]")))

        #expect(geometry.playhead(atBeat: 0) != nil)
        #expect(geometry.playhead(atBeat: 5) == nil)
    }

    @Test func noOnsetBeforeTheFirstNote() throws {
        let geometry = SheetGeometry(timeline: try twoMeasures(notes:
            note("a", measure: 0, beat: 2, box: "[100, 100, 110, 108]")))

        #expect(geometry.playhead(atBeat: 0) == nil)
    }
}

struct MeasureHitTestingTests {

    private func geometry() throws -> SheetGeometry {
        SheetGeometry(timeline: try twoMeasures(notes: note("a", measure: 0, beat: 0)))
    }

    @Test func findsTheMeasureUnderAPoint() throws {
        let hit = try geometry().measureIndex(at: CGPoint(x: 100, y: 140), page: 1,
                                              playingIndex: nil, beat: 0)
        #expect(hit == 0)

        let second = try geometry().measureIndex(at: CGPoint(x: 200, y: 140), page: 1,
                                                 playingIndex: nil, beat: 0)
        #expect(second == 1)
    }

    @Test func missesOutsideAnyMeasure() throws {
        #expect(try geometry().measureIndex(at: CGPoint(x: 300, y: 140), page: 1,
                                            playingIndex: nil, beat: 0) == nil)
        // Above the system.
        #expect(try geometry().measureIndex(at: CGPoint(x: 100, y: 20), page: 1,
                                            playingIndex: nil, beat: 0) == nil)
    }

    @Test func ignoresOtherPages() throws {
        #expect(try geometry().measureIndex(at: CGPoint(x: 100, y: 140), page: 2,
                                            playingIndex: nil, beat: 0) == nil)
    }

    @Test func aTapOnTheBarlineBetweenTwoMeasuresPrefersWhatIsPlaying() throws {
        // x = 150 is the shared edge, so both measures contain the point.
        let hit = try geometry().measureIndex(at: CGPoint(x: 150, y: 140), page: 1,
                                              playingIndex: 1, beat: 0)
        #expect(hit == 1)
    }

    @Test func otherwiseThePointPrefersTheMeasureStillToCome() throws {
        let hit = try geometry().measureIndex(at: CGPoint(x: 150, y: 140), page: 1,
                                              playingIndex: nil, beat: 2)
        #expect(hit == 1)   // measure 1 starts at beat 4, which is still ahead
    }
}
