import SwiftUI

/// The web app's Play controls: a position scrubber, then play and step,
/// speed, tempo, key names and sound.
struct TransportBar: View {
    let player: PlayerModel

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var showingTempo = false
    @State private var tempoText = ""
    /// Collapsed by default: playing and stepping are what you reach for
    /// while practising; the rest is set once and left.
    @State private var showingOptions = false

    /// The web app's slider runs 0.1x to 2x. A menu of the useful stops fits a
    /// phone better than a slider squeezed into the same row.
    private static let speedPresets: [Double] = [0.1, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2]
    private static let tempoRange: ClosedRange<Double> = 20...300

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background(Brand.card)
            .overlay(alignment: .top) {
                Rectangle().fill(Brand.paperDeep).frame(height: 1)
            }
            .alert("Tempo", isPresented: $showingTempo) {
                TextField("Beats per minute", text: $tempoText)
                    .keyboardType(.decimalPad)
                Button("Set") { applyTempo() }
                Button("Use the score's tempo") { player.setTempo(nil) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(tempoMessage)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch player.availability {
        case .unloaded, .loading:
            HStack(spacing: 10) {
                ProgressView().tint(Brand.accent)
                Text("Loading playback…")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.inkSoft)
            }
            .padding(.vertical, 14)
        case .unavailable(let message):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Brand.inkSoft)
                .multilineTextAlignment(.center)
                .padding(14)
        case .ready:
            VStack(spacing: 8) {
                // The measure timeline stays; it also carries any loading or
                // failure message for the instrument.
                scrubber

                // The play button stays centred whatever sits beside it.
                ZStack {
                    transport
                    HStack {
                        Spacer()
                        toggle("slider.horizontal.3", on: showingOptions,
                               label: showingOptions ? "Hide options" : "Show options") {
                            withAnimation(.snappy(duration: 0.22)) { showingOptions.toggle() }
                        }
                    }
                }

                if showingOptions {
                    // Scrolls sideways on a screen too narrow for one row.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { options }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) { options }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var scrubber: some View {
        VStack(alignment: .leading, spacing: 2) {
            Slider(value: Binding(
                       get: { isScrubbing ? scrubValue : player.beat },
                       set: { value in
                           scrubValue = value
                           // Paused, the page and keyboard follow the thumb.
                           // Playing, playback restarts once on release rather
                           // than at every point of the drag.
                           if !player.isPlaying { player.seek(to: value) }
                       }),
                   in: 0...max(1, player.totalBeats),
                   onEditingChanged: { editing in
                       if editing {
                           scrubValue = player.beat
                           isScrubbing = true
                       } else {
                           isScrubbing = false
                           player.seek(to: scrubValue)
                       }
                   })
                .tint(Brand.accent)
                .accessibilityLabel("Position in the piece")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let position = player.positionLabel {
                    Text(position)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Brand.inkSoft)
                }
                Spacer(minLength: 8)
                if let status = player.soundStatus {
                    Text(status)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(player.soundFailed ? Brand.danger : Brand.inkSoft)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
            roundButton("backward.end.fill", size: 40, filled: false, label: "Step to the previous note") {
                player.step(-1)
            }
            roundButton(player.isPlaying || player.isWaitingForSound ? "pause.fill" : "play.fill", size: 46, filled: true,
                        label: player.isPlaying || player.isWaitingForSound ? "Pause" : "Play") {
                player.togglePlay()
            }
            roundButton("forward.end.fill", size: 40, filled: false, label: "Step to the next note") {
                player.step(1)
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        Menu {
            Picker("Instrument", selection: Binding(get: { player.instrument },
                                                    set: { player.setInstrument($0) })) {
                ForEach(Instrument.allCases) { instrument in
                    Text(instrument.name).tag(instrument)
                }
            }
            // The samples' licences ask for credit where they are used.
            Section("Sample credits") {
                Text("Grand piano: Akai Steinway, public domain")
                Text("Electric pianos: Greg Sullivan, CC BY 3.0")
                Text("Organ: FluidR3 GM, CC BY 3.0")
            }
        } label: {
            Image(systemName: "pianokeys")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.ink)
                .frame(width: 40, height: 40)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.paperDeep, lineWidth: 1))
        }
        .accessibilityLabel("Instrument, \(player.instrument.name)")

        Menu {
            ForEach(Self.speedPresets, id: \.self) { value in
                Button {
                    player.setSpeed(value)
                } label: {
                    if abs(player.speed - value) < 1e-9 {
                        Label(Self.format(speed: value), systemImage: "checkmark")
                    } else {
                        Text(Self.format(speed: value))
                    }
                }
            }
        } label: {
            // The rate actually applied: a tempo override near the ceiling can
            // hold it below what was asked, and echoing the request would read
            // as broken rather than capped.
            pill(Self.format(speed: player.effectiveSpeed))
        }
        .accessibilityLabel("Speed, \(Self.format(speed: player.effectiveSpeed))")

        Button {
            tempoText = player.tempoControl.map { Self.format(number: $0.bpm) } ?? ""
            showingTempo = true
        } label: {
            pill(player.tempoControl.map { "\(Self.format(number: $0.bpm)) BPM" } ?? "BPM")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tempo")

        toggle("textformat", on: player.showKeyNames,
               label: player.showKeyNames ? "Hide key names" : "Show key names") {
            player.showKeyNames.toggle()
        }
        toggle(player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", on: !player.isMuted,
               label: player.isMuted ? "Unmute" : "Mute") {
            player.setMuted(!player.isMuted)
        }
    }

    // MARK: - Pieces

    private func roundButton(_ symbol: String, size: CGFloat, filled: Bool, label: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: filled ? 17 : 15, weight: .semibold))
                .foregroundStyle(filled ? Color.white : Brand.ink)
                .frame(width: size, height: size)
                .background(filled ? Brand.accent : Brand.paper, in: .circle)
                .overlay(Circle().stroke(filled ? Color.clear : Brand.paperDeep, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Off reads as a plain outline; on fills, so the state is visible without
    /// a text label beside it.
    private func toggle(_ symbol: String, on: Bool, label: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? Color.white : Brand.inkSoft)
                .frame(width: 40, height: 40)
                .background(on ? Brand.accent : Color.clear, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Brand.accent : Brand.paperDeep, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 10)
            .frame(height: 40)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.paperDeep, lineWidth: 1))
    }

    private var tempoMessage: String {
        let unit = player.tempoControl?.unit ?? "quarter note"
        let source = player.tempoFromScore
            ? "Detected from the score."
            : "No tempo marking was found on the sheet, so this is a default."
        return "Beats per minute, counted in \(unit)s, from 20 to 300. \(source)"
    }

    private func applyTempo() {
        let cleaned = tempoText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), Self.tempoRange.contains(value) else { return }
        player.setTempo(value)
    }

    private static func format(speed: Double) -> String {
        "\(format(number: speed))×"
    }

    private static func format(number: Double) -> String {
        let rounded = (number * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}
