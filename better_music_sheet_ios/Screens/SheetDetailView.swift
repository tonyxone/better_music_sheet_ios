import SwiftUI

/// Reading one sheet, from "still being recognised" through to the annotated
/// page. Playing it is a separate page, opened from here.
struct SheetDetailView: View {
    @State private var model: SheetDetailModel
    @Environment(\.scenePhase) private var scenePhase

    init(route: SheetRoute, job: AnnotationJob? = nil) {
        _model = State(initialValue: SheetDetailModel(route: route, job: job))
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
                if let data = model.pdfData, let job = model.job {
                    ZStack(alignment: .bottom) {
                        SheetPDFView(data: data)
                            .ignoresSafeArea(edges: .bottom)
                        playButton(jobID: job.jobID, data: data)
                            .padding(.bottom, 16)
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
    }

    private func playButton(jobID: String, data: Data) -> some View {
        NavigationLink {
            PlayView(jobID: jobID, title: model.title, pdfData: data)
        } label: {
            Label("Play", systemImage: "pianokeys")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .frame(height: 52)
                .background(Brand.accent, in: .capsule)
                .shadow(color: Brand.accentDeep.opacity(0.32), radius: 12, y: 6)
        }
        .accessibilityHint("Opens the sheet with the keyboard and falling notes")
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
