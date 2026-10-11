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
    @State private var musicXMLError: String?
    /// Scroll down through every page, or show one at a time and swipe across.
    @AppStorage("sheet.pageMode") private var pageMode = SheetPageMode.scroll
    @State private var pager = SheetPager()
    /// The sheet alone, over the whole screen.
    @State private var fullScreen = false
    @State private var notationPreference = NotationPreference.shared
    @State private var entitlements = EntitlementStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    init(route: SheetRoute, job: AnnotationJob? = nil) {
        _model = State(initialValue: SheetDetailModel(route: route, job: job))
    }

    private var isEditing: Bool { model.editor?.isEditing == true }
    private var isSwiping: Bool { pageMode == .swipe && pager.count > 1 }

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
        // Without the system's back button there is no swipe to go back
        // either, which one page at a time would take for a page turn.
        .navigationBarBackButtonHidden(isEditing || isSwiping)
        .toolbar { toolbar }
        .toolbar(fullScreen ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(fullScreen)
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
        .alert("Couldn't get the MusicXML", isPresented: Binding(
            get: { musicXMLError != nil }, set: { if !$0 { musicXMLError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(musicXMLError ?? "")
        }
        .sheet(item: $sharing) { file in
            ActivityView(url: file.url)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if AdConfig.isEnabled, !isEditing, !fullScreen, !entitlements.isEntitled {
                AdBannerSlot()
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
            if let job = model.job, !fullScreen {
                toolRow(job: job, namesLive: namesLive)
            }
            if let editor = model.editor, !fullScreen {
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
                         editor: model.editor,
                         pageMode: pageMode,
                         pager: pager)
                // Under the ad banner, but never under the editing tools.
                .ignoresSafeArea(edges: isEditing ? [] : .bottom)
                .overlay(alignment: .topTrailing) {
                    if fullScreen { closeFullScreen }
                }
                .overlay {
                    if displayedVersion == .original, model.isLoadingOriginal {
                        ProgressView("Loading original…")
                            .padding(16)
                            .background(Brand.card, in: .rect(cornerRadius: 12))
                    }
                }
        }
        // On the stack rather than the page, which runs on under the ad
        // banner: this stays clear of it.
        .overlay(alignment: .bottom) {
            if isSwiping { floatingPager }
        }
        .sheet(item: Binding(get: { model.editor?.textEditor },
                             set: { if $0 == nil, model.editor?.textEditor != nil { model.editor?.closeTextEditor(nil) } })) { target in
            SheetTextEntry(target: target) { value in
                model.editor?.closeTextEditor(value)
            }
        }
    }

    /// While editing, the back button gives way to how saving is going. One
    /// page at a time, it gives way to one of our own, which goes back on a
    /// tap but not on a swipe.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isSwiping, !isEditing {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
            }
        }
        if let editor = model.editor, editor.isEditing, let message = editor.store.saveState.message {
            ToolbarItem(placement: .topBarLeading) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.inkSoft)
                    .lineLimit(1)
            }
        }
    }

    /// The sheet's tools, in one row under its name: Edit on the left, then on
    /// the right the version, letters,
    /// jianpu or solfège, the page layout, full screen, Practice and Download.
    /// An iPad shows them all; a narrower screen puts the page layout and full
    /// screen behind the view options, and a phone too narrow even for that
    /// folds the version and the note names in there too. Editing opens its
    /// own tools under this row, and Edit becomes Done.
    private func toolRow(job: AnnotationJob, namesLive: Bool) -> some View {
        let choosesNotation = displayedVersion == .annotated && namesLive
        return ViewThatFits(in: .horizontal) {
            toolRow(job: job, choosesNotation: choosesNotation, fold: .nothing)
            toolRow(job: job, choosesNotation: choosesNotation, fold: .layout)
            toolRow(job: job, choosesNotation: choosesNotation, fold: .everything)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Brand.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.paperDeep).frame(height: 1) }
    }

    /// How much of the tool row sits behind the view options instead.
    private enum Fold {
        case nothing, layout, everything
    }

    private func toolRow(job: AnnotationJob, choosesNotation: Bool, fold: Fold) -> some View {
        let folded = fold == .everything
        return HStack(spacing: 6) {
            editButton
            Spacer(minLength: 6)
            if !folded {
                BrandSegmentedControl(
                    label: "Sheet version",
                    options: PDFVersion.allCases.map { ($0, $0.title, $0.title) },
                    selection: $displayedVersion)
                    .accessibilityHint("Switches between the annotated sheet and the uploaded original")
                if choosesNotation {
                    NotationToggle(fallback: model.editor?.labels?.notation)
                }
            }
            if fold == .nothing {
                // A one-page sheet has nothing to turn to.
                if pager.count > 1 {
                    BrandSegmentedControl(
                        label: "Page layout",
                        options: SheetPageMode.allCases.map { ($0, $0.title, $0.title) },
                        selection: $pageMode)
                        .accessibilityHint("Scrolls down through the pages, or shows one at a time to swipe across")
                }
                if !isEditing {
                    Button {
                        fullScreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold))
                            .toolButton()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Full screen")
                }
            } else {
                viewOptions(choosesNotation: choosesNotation, folded: folded)
            }
            // Leaving for Practice or exporting mid-edit would strand the
            // edit, so those wait until Done.
            if !isEditing {
                // A route, not a destination view: the app's stack is bound
                // to a typed path, and a view-destination link pushed onto it
                // crashes SwiftUI. RootView decides between practice and the
                // paywall.
                NavigationLink(value: SheetRoute(jobID: job.jobID, provisionalName: model.title, page: .practice)) {
                    KeyboardIcon()
                        .frame(width: 21, height: 14)
                        .toolButton()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Practice")
                .accessibilityHint("Opens the sheet with the keyboard and falling notes")
                shareMenu
            }
        }
    }

    /// Settings for what's on screen, behind sliders in the same solid red as
    /// Edit: how the pages are laid out, full screen, and on a narrow phone
    /// the version and the note names too.
    private func viewOptions(choosesNotation: Bool, folded: Bool) -> some View {
        Menu {
            if folded {
                Picker("Sheet version", selection: $displayedVersion) {
                    ForEach(PDFVersion.allCases) { Text($0.title).tag($0) }
                }
                if choosesNotation {
                    Picker("Note names", selection: Binding(
                        get: { notationPreference.notation(fallback: model.editor?.labels?.notation) },
                        set: { notationPreference.choose($0) })) {
                        ForEach(Notation.allCases, id: \.self) { Text($0.spokenTitle).tag($0) }
                    }
                }
            }
            // A one-page sheet has nothing to turn to.
            if pager.count > 1 {
                Picker("Page layout", selection: $pageMode) {
                    Label("Scroll", systemImage: "arrow.up.and.down").tag(SheetPageMode.scroll)
                    Label("Swipe", systemImage: "arrow.left.and.right").tag(SheetPageMode.swipe)
                }
            }
            if !isEditing {
                Button {
                    fullScreen = true
                } label: {
                    Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 34)
                .background(Brand.accent, in: .rect(cornerRadius: 9))
                .contentShape(Rectangle())
        }
        .accessibilityLabel("View options")
    }

    /// One page at a time: which page this is, and a button each way for when
    /// a swipe isn't to hand - while editing, when a drag draws instead.
    private var pagerControl: some View {
        HStack(spacing: 2) {
            pagerButton("chevron.left", label: "Previous page", by: -1)
                .disabled(pager.page <= 1)
            Text("\(pager.page) / \(pager.count)")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Brand.ink)
                .accessibilityLabel("Page \(pager.page) of \(pager.count)")
            pagerButton("chevron.right", label: "Next page", by: 1)
                .disabled(pager.page >= pager.count)
        }
    }

    private func pagerButton(_ symbol: String, label: String, by delta: Int) -> some View {
        Button {
            pager.turn(by: delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Brand.ink)
        .accessibilityLabel(label)
    }

    /// The way back out of full screen, in the same solid red as Edit.
    private var closeFullScreen: some View {
        Button {
            fullScreen = false
        } label: {
            Label("Close", systemImage: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Brand.accent, in: .rect(cornerRadius: 9))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close full screen")
        .padding(10)
    }

    /// The pager floats over the sheet, bottom centre, full screen or not, and
    /// see-through enough that the music under it still reads.
    private var floatingPager: some View {
        pagerControl
            .padding(.horizontal, 6)
            .background(Brand.card, in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Brand.paperDeep, lineWidth: 1))
            .opacity(0.7)
            .padding(.bottom, 12)
    }

    /// Red like the choices beside it, with the pencil in white on it.
    @ViewBuilder
    private var editButton: some View {
        if let editor = model.editor, editor.store.doc != nil {
            Button {
                if editor.isEditing {
                    editor.isEditing = false
                    Task { await editor.store.flush() }
                } else {
                    editor.showsNames = displayedVersion == .annotated
                    editor.isEditing = true
                }
            } label: {
                Group {
                    if editor.isEditing {
                        Text("Done").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 12)
                    } else {
                        Image(systemName: "pencil.tip.crop.circle")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 36)
                    }
                }
                .foregroundStyle(.white)
                .frame(height: 34)
                .background(Brand.accent, in: .rect(cornerRadius: 9))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(editor.isEditing ? "Done editing" : "Edit sheet")
            .accessibilityHint(editor.isEditing ? "" : editor.namesLive
                               ? "Move or retype note names, draw, highlight and add notes"
                               : "Draw, highlight and add notes")
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
            Button {
                shareMusicXML()
            } label: {
                Label("MusicXML", systemImage: "music.note.list")
                Text("The notes as read, for MuseScore, Sibelius or Finale (.mxl)")
            }
        } label: {
            Group {
                if preparingShare {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .toolButton()
        }
        .disabled(preparingShare)
        .accessibilityLabel("Share")
    }

    private func shareMusicXML() {
        preparingShare = true
        Task {
            do {
                sharing = try await model.musicXMLExportURL().map(SharedFile.init)
            } catch {
                musicXMLError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            preparingShare = false
        }
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

private extension View {
    /// A plain square tool button, outlined like the controls on Practice.
    func toolButton() -> some View {
        foregroundStyle(Brand.ink)
            .frame(width: 34, height: 34)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Brand.paperDeep, lineWidth: 1))
            .contentShape(Rectangle())
    }
}
