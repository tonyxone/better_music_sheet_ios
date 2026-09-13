import CoreGraphics
import Foundation

/// Where the playhead sits for one moment in the music. A chord — and both
/// hands striking together — collapse into a single onset, so the line is
/// drawn once rather than several times at nearly the same place.
nonisolated struct PlayheadOnset: Sendable, Hashable {
    let beat: Double
    /// 1-based PDF page.
    let page: Int
    /// Vertical extent of the system, in PDF points, top-down.
    let y0: Double
    let y1: Double
    let x: Double
    /// True when no notehead in this group had real geometry and the position
    /// was interpolated across the measure. The UI marks these, because an
    /// interpolated playhead is a guess and should look like one.
    let approximate: Bool
    let measure: Int
}

/// Turning timeline geometry into positions on the page.
///
/// **The coordinate trap.** `bbox_pt` is top-down — PyMuPDF's convention,
/// written by the backend's annotate.py. UIKit and SwiftUI are also top-down,
/// so drawing an overlay needs no flip at all. PDFKit's own page space is
/// bottom-up, so anything handed to a PDFKit API (an annotation's bounds, a
/// selection) does need one. Mixing the two silently flips everything
/// vertically, which is why the two conversions below are named for the space
/// they produce rather than left to the call site to remember.
nonisolated struct SheetGeometry: Sendable {
    let onsets: [PlayheadOnset]
    private let measures: [TimelineMeasure]

    init(timeline: Timeline) {
        self.measures = timeline.measures
        self.onsets = Self.buildOnsets(measures: timeline.measures, notes: timeline.notes)
    }

    // MARK: - Coordinate conversion

    /// A fraction-of-the-page rect (0...1), y measured from the top — ready
    /// to lay out an overlay over a rendered page at any size.
    static func normalizedRect(for bbox: BBoxPoints, pageWidth: Double, pageHeight: Double) -> CGRect {
        guard pageWidth > 0, pageHeight > 0 else { return .zero }
        return CGRect(x: bbox.x0 / pageWidth,
                      y: bbox.y0 / pageHeight,
                      width: bbox.width / pageWidth,
                      height: bbox.height / pageHeight)
    }

    /// The same box in PDFKit's page space, whose origin is the BOTTOM-left.
    static func pdfRect(for bbox: BBoxPoints, pageHeight: Double) -> CGRect {
        CGRect(x: bbox.x0,
               y: pageHeight - bbox.y1,
               width: bbox.width,
               height: bbox.height)
    }

    // MARK: - Hit testing

    /// Which measure a tap landed on. `point` is in the page's own top-down
    /// point space — the caller converts from view coordinates by scaling,
    /// never via PDFKit's bottom-up conversion helpers.
    ///
    /// Overlapping boxes are resolved the way the web app resolves them:
    /// whatever is playing wins, then the next measure due to play, then
    /// simply the first.
    func measureIndex(at point: CGPoint, page: Int, playingIndex: Int?, beat: Double) -> Int? {
        let hits = measures.filter { measure in
            guard measure.page == page, let box = measure.bboxPt else { return false }
            return point.x >= box.x0 && point.x <= box.x1 && point.y >= box.y0 && point.y <= box.y1
        }
        guard !hits.isEmpty else { return nil }
        if let playing = playingIndex, let hit = hits.first(where: { $0.index == playing }) { return hit.index }
        return (hits.first { $0.startBeat >= beat } ?? hits[0]).index
    }

    // MARK: - Playhead

    /// The latest onset at or before the clock, or nil when the clock has
    /// moved into a measure that onset does not belong to — better to drop
    /// the line than to leave it stranded on the wrong bar.
    func playhead(atBeat beat: Double) -> PlayheadOnset? {
        var low = 0
        var high = onsets.count - 1
        var found = -1
        while low <= high {
            let mid = (low + high) / 2
            if onsets[mid].beat <= beat + 1e-9 {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard found >= 0 else { return nil }
        let current = measures.first { beat >= $0.startBeat && beat < $0.endBeat }
        return onsets[found].measure == current?.index ? onsets[found] : nil
    }

    // MARK: - Building

    private struct Group {
        var beat: Double
        var page: Int
        var y0: Double
        var y1: Double
        var exactXs: [Double] = []
        var fallbackXs: [Double] = []
        var measure: Int
    }

    private static func buildOnsets(measures: [TimelineMeasure], notes: [TimelineNote]) -> [PlayheadOnset] {
        let byIndex = Dictionary(measures.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        var groups: [String: Group] = [:]
        var order: [String] = []

        for note in notes {
            guard let measure = byIndex[note.measureIndex],
                  let measureBox = measure.bboxPt,
                  let page = measure.page else { continue }

            let x: Double
            if let noteBox = note.bboxPt {
                x = (noteBox.x0 + noteBox.x1) / 2
            } else if measure.lengthBeats > 0 {
                // Interpolate across the bar. Stopping at 0.96 keeps the last
                // onset off the barline, where it would read as the next bar.
                let fraction = min(0.96, max(0, (note.startBeat - measure.startBeat) / measure.lengthBeats))
                x = measureBox.x0 + fraction * (measureBox.x1 - measureBox.x0)
            } else {
                continue
            }

            let key = "\(measure.index):\(note.startBeat)"
            if groups[key] == nil {
                groups[key] = Group(beat: note.startBeat, page: page,
                                    y0: measureBox.y0, y1: measureBox.y1,
                                    measure: measure.index)
                order.append(key)
            }
            // Exact notehead positions take priority over interpolated ones:
            // averaging the two together can pull the line backwards even
            // though playback time is moving forward.
            if note.bboxPt != nil {
                groups[key]?.exactXs.append(x)
            } else {
                groups[key]?.fallbackXs.append(x)
            }
        }

        var result = order.compactMap { key -> PlayheadOnset? in
            guard let group = groups[key] else { return nil }
            let xs = group.exactXs.isEmpty ? group.fallbackXs : group.exactXs
            guard !xs.isEmpty else { return nil }
            return PlayheadOnset(beat: group.beat, page: group.page, y0: group.y0, y1: group.y1,
                                 x: xs.reduce(0, +) / Double(xs.count),
                                 approximate: group.exactXs.isEmpty,
                                 measure: group.measure)
        }
        result.sort { $0.beat < $1.beat }

        // Recognition can still hand a later onset a slightly earlier x.
        // Clamp within each measure so the playhead never retreats on the
        // page — but never across a measure boundary, where the line is
        // legitimately meant to jump back to the start of the next system.
        var clamped: [PlayheadOnset] = []
        clamped.reserveCapacity(result.count)
        var previous: PlayheadOnset?
        for onset in result {
            var adjusted = onset
            if let previous, previous.measure == onset.measure, previous.x > onset.x {
                adjusted = PlayheadOnset(beat: onset.beat, page: onset.page, y0: onset.y0, y1: onset.y1,
                                         x: previous.x, approximate: onset.approximate, measure: onset.measure)
            }
            clamped.append(adjusted)
            previous = adjusted
        }
        return clamped
    }
}
