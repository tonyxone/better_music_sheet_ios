import SwiftUI

/// One sheet, from "still being recognised" through to something you can read.
struct SheetDetailView: View {
    @State private var model: SheetDetailModel
    @State private var player: PlayerModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(route: SheetRoute, job: AnnotationJob? = nil) {
        _model = State(initialValue: SheetDetailModel(route: route, job: job))
        _player = State(initialValue: PlayerModel(jobID: route.jobID))
    }

    var body: some View {
        ZStack {
            Brand.paper.ignoresSafeArea()

            switch model.stage {
            case .working(let stageText):
                WorkingView(title: model.title, stage: stageText)
            case .loadingFile:
                ProgressView().tint(Brand.accent)
            case .ready:
                if let data = model.pdfData {
                    // A phone in portrait gets just the octaves the piece uses,
                    // so keys and lanes stay big enough to read; wider screens
                    // have room for all 88. The roll and keyboard always share
                    // one range, or the lanes would drift off their keys.
                    let keyRange = horizontalSizeClass == .regular
                        ? PlayerModel.fullKeyRange
                        : player.pieceKeyRange

                    if player.availability == .ready, let notes = player.timeline?.notes {
                        // The web app's Play page — sheet, controls, falling
                        // notes, keyboard — with every section adjustable.
                        PlayLayout(keyboardHeight: { width in
                            KeyboardView.naturalHeight(width: width, range: keyRange)
                        }) {
                            SheetPDFView(data: data,
                                         highlightedMeasure: player.highlightedMeasure,
                                         playhead: player.playhead) { point, page in
                                player.handleTap(at: point, page: page)
                            }
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
                        // Still loading playback, or none for this sheet: the
                        // page, with the controls area saying which.
                        VStack(spacing: 0) {
                            SheetPDFView(data: data,
                                         highlightedMeasure: player.highlightedMeasure,
                                         playhead: player.playhead) { point, page in
                                player.handleTap(at: point, page: page)
                            }
                            TransportBar(player: player)
                        }
                    }
                }
            case .failed(let message):
                FailureView(title: model.title, message: message)
            }
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.stage == .ready, let url = model.exportURL() {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        // Restarted each time the app comes back to the foreground, so a
        // sheet that finished while the phone was locked shows up at once,
        // and a PDF download that failed then gets another try.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.run()
        }
        .task(id: model.stage == .ready) {
            guard model.stage == .ready else { return }
            await player.load()
        }
        // Without background audio the system suspends the engine, so pause
        // cleanly instead of resuming onto a stale clock.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.pause() }
        }
        .onDisappear { player.stop() }
    }
}

/// Recognition takes a minute or two, so this says what is happening rather
/// than spinning anonymously.
private struct WorkingView: View {
    let title: String
    let stage: String

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "music.note")
                .font(.system(size: 30))
                .foregroundStyle(Brand.accent)
                .symbolEffect(.pulse)

            VStack(spacing: 6) {
                Text("Reading your sheet")
                    .font(Brand.title(22))
                    .foregroundStyle(Brand.ink)
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(Brand.inkSoft)
                    .lineLimit(1)
            }

            HStack(spacing: 14) {
                ProgressView().tint(Brand.accent)
                Text(stage)
                    .font(.system(size: 15))
                    .foregroundStyle(Brand.ink)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Brand.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.paperDeep, lineWidth: 1))

            Text("This usually takes a minute or two. You can leave this screen.")
                .font(.system(size: 12.5))
                .foregroundStyle(Brand.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }
}

private struct FailureView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(Brand.danger)
            Text("Couldn't read this sheet")
                .font(Brand.title(20))
                .foregroundStyle(Brand.ink)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Brand.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }
}
