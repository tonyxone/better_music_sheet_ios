import SwiftUI

/// The Play page, as the web app has it: the sheet, the controls, the falling
/// notes and the keyboard, all on one screen.
///
/// A page of its own rather than a mode of the reading page. Reading a sheet
/// and practising it are different moments, and each gets the whole screen.
struct PlayView: View {
    let title: String
    /// Handed over by the reading page, which has already downloaded it.
    let pdfData: Data

    @State private var player: PlayerModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(jobID: String, title: String, pdfData: Data) {
        self.title = title
        self.pdfData = pdfData
        _player = State(initialValue: PlayerModel(jobID: jobID))
    }

    var body: some View {
        ZStack {
            Brand.paper.ignoresSafeArea()
            content
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await player.load() }
        // Without background audio the system suspends the engine, so pause
        // cleanly instead of resuming onto a stale clock.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.pause() }
        }
        .onDisappear { player.stop() }
    }

    @ViewBuilder
    private var content: some View {
        // A phone in portrait gets just the octaves the piece uses, so keys and
        // lanes stay big enough to read; wider screens have room for all 88.
        // The falling notes and the keyboard always share one range, or the
        // lanes would drift off their keys.
        let keyRange = horizontalSizeClass == .regular
            ? PlayerModel.fullKeyRange
            : player.pieceKeyRange

        if player.availability == .ready, let notes = player.timeline?.notes {
            PlayLayout(keyboardHeight: { width in
                KeyboardView.naturalHeight(width: width, range: keyRange)
            }) {
                sheet
            } controls: {
                TransportBar(player: player)
            } roll: {
                NoteRollView(player: player, notes: notes, range: keyRange)
            } keyboard: {
                KeyboardView(range: keyRange,
                             litKeys: player.litKeys,
                             showNames: player.showKeyNames)
            }
        } else {
            // Still loading playback, or none for this sheet: the page, with
            // the controls area saying which.
            VStack(spacing: 0) {
                sheet
                TransportBar(player: player)
            }
        }
    }

    private var sheet: some View {
        SheetPDFView(data: pdfData,
                     highlightedMeasure: player.highlightedMeasure,
                     playhead: player.playhead) { point, page in
            player.handleTap(at: point, page: page)
        }
    }
}
