import SwiftUI

/// Reading one sheet, from "still being recognised" through to the annotated
/// page. Practising it is a separate page, opened from the toolbar.
struct SheetDetailView: View {
    private enum PDFVersion: String, CaseIterable, Identifiable {
        case annotated, original

        var id: Self { self }
        var title: String { rawValue.capitalized }
    }

    @State private var model: SheetDetailModel
    @State private var displayedVersion: PDFVersion = .annotated
    @State private var originalError: String?
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
                if let data = model.pdfData {
                    SheetPDFView(data: displayedVersion == .original ? (model.originalPDFData ?? data) : data)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay {
                            if displayedVersion == .original, model.isLoadingOriginal {
                                ProgressView("Loading original…")
                                    .padding(16)
                                    .background(Brand.card, in: .rect(cornerRadius: 12))
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
            if model.stage == .ready, let data = model.pdfData, let job = model.job {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Sheet version", selection: $displayedVersion) {
                        ForEach(PDFVersion.allCases) { version in
                            Text(version.title).tag(version)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                    .accessibilityHint("Switches between the annotated sheet and the uploaded original")
                }

                // Just left of the download, as on the web app's result page.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        PracticeView(jobID: job.jobID, title: model.title, pdfData: data)
                    } label: {
                        KeyboardIcon()
                            .foregroundStyle(Brand.ink)
                            .frame(width: 26, height: 18)
                    }
                    .tint(Brand.ink)
                    .accessibilityLabel("Practice")
                    .accessibilityHint("Opens the sheet with the keyboard and falling notes")
                }

                // Without this, iOS 26's glass toolbar draws adjacent items
                // as one grouped button; a fixed spacer gives each its own.
                // Earlier OS versions never group them, so there's nothing
                // to separate.
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }

                if let url = model.exportURL() {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
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
        .task(id: displayedVersion) {
            guard displayedVersion == .original else { return }
            do {
                try await model.loadOriginal()
                originalError = nil
            } catch {
                // Keep the annotated document visible rather than leaving the
                // reader on a blank page when an older server lacks originals.
                displayedVersion = .annotated
                originalError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
        .alert("Couldn't load the original", isPresented: Binding(
            get: { originalError != nil }, set: { if !$0 { originalError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(originalError ?? "")
        }
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
