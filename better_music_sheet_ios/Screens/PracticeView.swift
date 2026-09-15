import SwiftUI

/// The Practice page, as the web app's Play page has it: the sheet, the
/// controls, the falling notes and the keyboard, all on one screen.
///
/// A page of its own rather than a mode of the reading page. Reading a sheet
/// and practising it are different moments, and each gets the whole screen.
struct PracticeView: View {
    let title: String

    @State private var player: PlayerModel
    /// Handed over when opened from the reading page, which already has it;
    /// fetched here when opened straight from the library.
    @State private var pdfData: Data?
    @State private var pdfFailed = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let jobID: String
    private let files: SheetFiles

    init(jobID: String, title: String, pdfData: Data? = nil) {
        self.jobID = jobID
        self.title = title
        self.files = SheetFiles()
        _pdfData = State(initialValue: pdfData)
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
        .task { await loadPDFIfNeeded() }
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
            } loadingOverlay: {
                soundLoadingOverlay
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

    /// One indicator centred over the falling notes and keyboard together
    /// while the piano's samples are still loading — both stay fully visible
    /// underneath, just with a sign that sound isn't ready to play yet.
    @ViewBuilder
    private var soundLoadingOverlay: some View {
        if case .loading = player.soundState {
            RingSpinner(size: 28, lineWidth: 3)
                .padding(16)
                .background(.ultraThinMaterial, in: .circle)
                .transition(.opacity)
        }
    }

    /// The page is a visual aid. Practice runs entirely from the timeline, so a
    /// sheet that fails to load leaves everything else working.
    @ViewBuilder
    private var sheet: some View {
        if let pdfData {
            SheetPDFView(data: pdfData,
                         highlightedMeasure: player.highlightedMeasure,
                         playhead: player.playhead) { point, page in
                player.handleTap(at: point, page: page)
            }
        } else if pdfFailed {
            Text("The sheet couldn't be loaded, but practice still works.")
                .font(.system(size: 13))
                .foregroundStyle(Brand.inkSoft)
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .tint(Brand.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadPDFIfNeeded() async {
        guard pdfData == nil else { return }
        do {
            pdfData = try await files.data(jobID: jobID, artifact: .pdf)
        } catch {
            pdfFailed = true
        }
    }
}
