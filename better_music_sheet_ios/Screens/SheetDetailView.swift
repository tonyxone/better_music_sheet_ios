import SwiftUI

/// Reading one sheet, from "still being recognised" through to the annotated
/// page. Practising it is a separate page, opened from the toolbar.
struct SheetDetailView: View {
    private enum PDFVersion: String, CaseIterable, Identifiable {
        case annotated, original

        var id: Self { self }
        var title: String { rawValue.capitalized }
    }

    private struct SharedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    @State private var model: SheetDetailModel
    @State private var displayedVersion: PDFVersion = .annotated
    @State private var originalError: String?
    @State private var sharing: SharedFile?
    @State private var preparingShare = false
    @State private var entitlements = EntitlementStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init(route: SheetRoute, job: AnnotationJob? = nil) {
        _model = State(initialValue: SheetDetailModel(route: route, job: job))
    }

    private var isEditing: Bool { model.editor?.isEditing == true }

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
                    sheet(annotated: data)
                }
            case .failed(let message):
                FailureView(title: model.title, message: message)
            }
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .toolbar { toolbar }
        // Restarted each time the app comes back to the foreground, so a
        // sheet that finished while the phone was locked shows up at once,
        // and a PDF download that failed then gets another try.
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                // Leaving the app is the last moment to save for a while.
                await model.editor?.store.flush()
                return
            }
            await model.run()
        }
        .task(id: displayedVersion) {
            model.editor?.showsNames = displayedVersion == .annotated
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
        .onDisappear {
            guard let store = model.editor?.store else { return }
            Task { await store.flush() }
        }
        .alert("Couldn't load the original", isPresented: Binding(
            get: { originalError != nil }, set: { if !$0 { originalError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(originalError ?? "")
        }
        .sheet(item: $sharing) { file in
            ActivityView(url: file.url)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if AdConfig.isEnabled, !isEditing, !entitlements.isEntitled {
                AdBannerView().frame(height: 50)
            }
        }
    }

    /// The names are drawn over the original when they can be (see
    /// SheetDetailModel.makeEditor); otherwise the annotated copy shows.
    @ViewBuilder
    private func sheet(annotated data: Data) -> some View {
        let namesLive = model.editor?.namesLive == true && model.originalPDFData != nil
        let base = displayedVersion == .original || namesLive ? (model.originalPDFData ?? data) : data
        VStack(spacing: 0) {
            if let editor = model.editor {
                if editor.isEditing {
                    SheetEditToolbar(editor: editor)
                }
                if editor.isEditing || editor.notice != nil {
                    SheetSelectionBar(editor: editor)
                } else if let error = editor.store.loadError {
                    Text(error)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Brand.danger)
                        .padding(10)
                }
            }
            SheetPDFView(data: base,
                         overlay: model.editor.map {
                             SheetOverlayContent(editor: $0, showsNames: displayedVersion == .annotated && namesLive)
                         },
                         editor: model.editor)
                // Under the ad banner, but never under the editing tools.
                .ignoresSafeArea(edges: isEditing ? [] : .bottom)
                .overlay {
                    if displayedVersion == .original, model.isLoadingOriginal {
                        ProgressView("Loading original…")
                            .padding(16)
                            .background(Brand.card, in: .rect(cornerRadius: 12))
                    }
                }
        }
        .sheet(item: Binding(get: { model.editor?.textEditor },
                             set: { if $0 == nil, model.editor?.textEditor != nil { model.editor?.closeTextEditor(nil) } })) { target in
            SheetTextEntry(target: target) { value in
                model.editor?.closeTextEditor(value)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.stage == .ready, model.pdfData != nil, let job = model.job {
            if let editor = model.editor, editor.isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Text(editor.store.saveState.message)
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.inkSoft)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        editor.isEditing = false
                        Task { await editor.store.flush() }
                    }
                    .bold()
                }
            } else {
                if #available(iOS 26.0, *) {
                    // The segmented control is its own box; without this iOS 26
                    // also draws the toolbar's glass capsule around it.
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
                    .sharedBackgroundVisibility(.hidden)
                } else {
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
                }

                if let editor = model.editor, editor.store.doc != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            editor.showsNames = displayedVersion == .annotated
                            editor.isEditing = true
                        } label: {
                            Image(systemName: "pencil.tip.crop.circle")
                        }
                        .accessibilityLabel("Edit sheet")
                        .accessibilityHint(editor.namesLive
                                           ? "Move or retype note names, draw, highlight and add notes"
                                           : "Draw, highlight and add notes")
                    }
                }

                // Just left of the download, as on the web app's result page.
                ToolbarItem(placement: .topBarTrailing) {
                    // A route, not a destination view: the app's stack is
                    // bound to a typed path, and a view-destination link
                    // pushed onto it crashes SwiftUI. RootView decides
                    // between practice and the paywall.
                    NavigationLink(value: SheetRoute(jobID: job.jobID, provisionalName: model.title, page: .practice)) {
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

                ToolbarItem(placement: .topBarTrailing) {
                    shareMenu
                }
            }
        }
    }

    /// The web app's Download menu: the reader's own version, the annotated
    /// copy as generated, or the file as uploaded.
    private var shareMenu: some View {
        Menu {
            if model.editor != nil {
                Button {
                    shareCustomized()
                } label: {
                    Label("Customized", systemImage: "pencil.and.list.clipboard")
                    Text(displayedVersion == .original
                         ? "The original with your drawings and notes"
                         : "With your moved and retyped names, drawings and notes")
                }
            }
            Button {
                sharing = model.exportURL().map(SharedFile.init)
            } label: {
                Label("Annotated", systemImage: "doc.richtext")
                Text("Note names as generated")
            }
            Button {
                Task {
                    try? await model.loadOriginal()
                    sharing = model.originalExportURL().map(SharedFile.init)
                }
            } label: {
                Label("Original", systemImage: "doc")
                Text("The file as you uploaded it")
            }
        } label: {
            if preparingShare {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .disabled(preparingShare)
        .accessibilityLabel("Share")
    }

    private func shareCustomized() {
        preparingShare = true
        Task {
            await model.editor?.store.flush()
            // The original is needed as the base for the Original view.
            if displayedVersion == .original { try? await model.loadOriginal() }
            sharing = model.customizedExportURL(showingOriginal: displayedVersion == .original).map(SharedFile.init)
            preparingShare = false
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
