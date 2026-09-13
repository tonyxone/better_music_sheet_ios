import SwiftUI

/// Play, and where you are, floating over the page.
struct TransportBar: View {
    let player: PlayerModel

    var body: some View {
        switch player.availability {
        case .unloaded, .loading:
            EmptyView()
        case .unavailable(let message):
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Brand.inkSoft)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Brand.card.opacity(0.96), in: .capsule)
                .overlay(Capsule().stroke(Brand.paperDeep, lineWidth: 1))
        case .ready:
            bar
        }
    }

    private var bar: some View {
        HStack(spacing: 12) {
            Button {
                player.togglePlay()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Brand.accent, in: .circle)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                    .tint(Brand.accent)
                Text(caption)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Brand.inkSoft)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 66)
        .background(Brand.card.opacity(0.96), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Brand.paperDeep, lineWidth: 1))
        .shadow(color: Brand.ink.opacity(0.12), radius: 14, y: 6)
    }

    private var caption: String {
        if let label = player.measureLabel { return label }
        return player.isPlaying ? "Counting in…" : "Tap a measure to play from there"
    }

    private var progress: Double {
        guard player.totalBeats > 0 else { return 0 }
        return min(1, max(0, player.beat / player.totalBeats))
    }
}
