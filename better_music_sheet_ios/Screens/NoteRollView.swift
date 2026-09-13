import SwiftUI

/// Falling notes: each note descends toward the key it will be played on,
/// arriving exactly as it sounds.
///
/// Ported from the web app's app/play/note-roll.tsx. The lanes come from the
/// keyboard's own geometry and use the same horizontal mapping as
/// KeyboardView, so a note can never land a lane off its key — which would be
/// worse than having no roll at all.
struct NoteRollView: View {
    let player: PlayerModel
    /// Sorted by onset.
    let notes: [TimelineNote]
    let range: KeyboardLayout.KeyRange

    private static let layout = KeyboardLayout()
    private static let background = Color(hex: 0x0F1113)
    /// The hand colours lifted for a black background. The keys mix their
    /// colour into ivory, which lightens it; on black the unmodified values
    /// read as muddy.
    private static let rightOnDark = Color(hex: 0x4F9BE6)
    private static let leftOnDark = Color(hex: 0x4FBC7C)

    var body: some View {
        // Animates only while playing. Paused, it redraws whenever the
        // position changes — a step or a scrub.
        TimelineView(.animation(minimumInterval: nil, paused: !player.isPlaying)) { _ in
            let beat = player.rollBeat()
            Canvas { context, size in
                draw(in: &context, size: size, beat: beat)
            }
        }
        .background(Self.background)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, beat: Double?) {
        guard range.width > 0, size.height > 0 else { return }
        let unit = size.width / range.width

        // Octave divisions, drawn first so bars sit over them: somewhere for
        // the eye to anchor, since a lane forty keys along is otherwise
        // impossible to place without counting.
        var octaves = Path()
        for midi in range.lowMIDI...range.highMIDI where KeyboardLayout.pitchClass(midi) == 0 {
            let edge = ((Self.layout.centers[midi] ?? 0) - KeyboardLayout.whiteWidth / 2 - range.left) * unit
            let x = edge.rounded() + 0.5
            octaves.move(to: CGPoint(x: x, y: 0))
            octaves.addLine(to: CGPoint(x: x, y: size.height))
        }
        context.stroke(octaves, with: .color(.white.opacity(0.10)), lineWidth: 1)

        let hitY = NoteRollGeometry.hitY(height: size.height)

        if let beat {
            let frame = NoteRollGeometry(notes: notes).frame(atBeat: beat, height: size.height)
            for bar in frame.whiteKeyBars + frame.blackKeyBars {
                context.fill(Self.roundedBar(rect(for: bar.midi, top: bar.top, bottom: bar.bottom,
                                                  unit: unit, height: size.height)),
                             with: .color(bar.role == 1 ? Self.leftOnDark : Self.rightOnDark))
            }
            for highlight in frame.highlights {
                let lane = rect(for: highlight.midi, top: highlight.top, bottom: highlight.bottom,
                                unit: unit, height: size.height)
                // A translucent white foreground follows a note while its key is
                // held: the hand colour shows through, and the played note is
                // far easier to pick out from the ones falling above it.
                context.fill(Self.roundedBar(lane), with: .color(.white.opacity(0.42)))
                if highlight.flash > 0 {
                    // A crisp landing, especially when one pitch repeats.
                    let flash = CGRect(x: lane.minX, y: hitY - 5, width: lane.width, height: 10)
                    context.fill(Self.roundedBar(flash), with: .color(.white.opacity(highlight.flash)))
                }
            }
        }

        // The line notes land on, drawn last so bars pass behind it.
        var hitLine = Path()
        hitLine.move(to: CGPoint(x: 0, y: hitY + 0.5))
        hitLine.addLine(to: CGPoint(x: size.width, y: hitY + 0.5))
        context.stroke(hitLine, with: .color(.white.opacity(0.34)), lineWidth: 1)
    }

    /// A lane's bar, clipped to just past the visible area: a whole note can be
    /// many screens tall.
    private func rect(for midi: Int, top: Double, bottom: Double, unit: CGFloat, height: CGFloat) -> CGRect {
        let extent = Self.layout.extent(of: midi)
        let drawTop = max(top, -8)
        let drawBottom = min(bottom, height + 8)
        return CGRect(x: (extent.x - range.left) * unit, y: drawTop,
                      width: extent.width * unit, height: max(0, drawBottom - drawTop))
    }

    private static func roundedBar(_ rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: min(3, rect.width / 2, rect.height / 2))
    }
}
