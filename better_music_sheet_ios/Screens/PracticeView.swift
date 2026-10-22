import SwiftUI

/// The Practice page, as the web app's Play page has it: the sheet, the
/// controls, the falling notes and the keyboard, all on one screen.
///
/// A page of its own rather than a mode of the reading page. Reading a sheet
/// and practising it are different moments, and each gets the whole screen.
struct PracticeView: View {
    private enum PDFVersion: String, CaseIterable, Identifiable {
        case annotated, original

        var id: Self { self }
        var title: String {
            switch self {
            case .annotated: String(localized: "Annotated", bundle: .app)
            case .original: String(localized: "Original", bundle: .app)
            }
        }
    }

    let title: String

    @State private var player: PlayerModel
    /// Handed over when opened from the reading page, which already has it;
    /// fetched here when opened straight from the library.
    @State private var pdfData: Data?
    @State private var pdfFailed = false
    @State private var originalPDFData: Data?
    @State private var isLoadingOriginal = false
    @State private var displayedVersion: PDFVersion = .annotated
    @State private var originalError: String?
    /// The names as data, drawn over the original — so names moved or
    /// retyped on the reading page show here as they do there. Nil keeps the
    /// annotated copy as it was made.
    @State private var labels: LabelSet?
    /// Holds the sheet back until it's known which copy to show, rather than
    /// flashing the annotated one first.
    @State private var overlayReady = false
    @State private var entitlements = EntitlementStore.shared
    @State private var unlocks = PracticeUnlocks.shared
    @State private var rewardedAd = RewardedAdLoader.practice
    @State private var showingPaywall = false
    @State private var watchingAd = false
    /// Bumped when this sheet's unlock runs out, so the page locks again
    /// without waiting for something else to redraw it.
    @State private var unlockExpired = 0
    @State private var noAdAvailable = false
    @State private var notationPreference = NotationPreference.shared
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
        // Above the sheet, so the keyboard keeps the bottom of the screen.
        .safeAreaInset(edge: .top, spacing: 0) {
            if AdConfig.isEnabled, !entitlements.isEntitled {
                AdBannerSlot()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Side by side, in the reading page's order: version, then
            // letters, jianpu or solfège.
            if #available(iOS 26.0, *) {
                // The segmented controls are their own boxes; without this
                // iOS 26 also draws the toolbar's glass capsule around them.
                ToolbarItem(placement: .topBarTrailing) {
                    sheetChoices
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    sheetChoices
                }
            }
        }
        .task { await player.load() }
        .task { await loadPDFIfNeeded() }
        .task { await loadLabels() }
        .task(id: displayedVersion) {
            guard displayedVersion == .original else { return }
            await loadOriginalIfNeeded()
        }
        // A free sheet plays its opening measures; the rest unlocks with a
        // rewarded ad, or Premium.
        .onChange(of: previewEnd, initial: true) { _, end in
            player.previewEndBeat = end
        }
        .task(id: isLocked) {
            guard isLocked else { return }
            await rewardedAd.load()
        }
        .task(id: unlockedUntil) {
            guard let unlockedUntil else { return }
            try? await Task.sleep(for: .seconds(max(0, unlockedUntil.timeIntervalSinceNow) + 0.5))
            guard !Task.isCancelled else { return }
            unlockExpired += 1
        }
        .alert("Unlock this sheet", isPresented: Binding(
            get: { player.hitPreviewEnd && isLocked && !watchingAd },
            set: { if !$0 { player.hitPreviewEnd = false } }
        )) {
            Button("Watch Ad") { Task { await watchAd() } }
            Button("See Premium Plans") { showingPaywall = true }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("The free preview is the first \(PracticeUnlocks.freeMeasures) measures. Watch a short ad to practise this whole sheet for an hour, or go Premium to practise every sheet with no ads.")
        }
        .alert("No ad available", isPresented: $noAdAvailable) {
            Button("See Premium Plans") { showingPaywall = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text("No ad is available right now. Try again in a moment.")
        }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .overlay {
            if watchingAd {
                RingSpinner(size: 28, lineWidth: 3)
                    .padding(16)
                    .background(.ultraThinMaterial, in: .circle)
            }
        }
        .alert("Couldn't load the original", isPresented: Binding(
            get: { originalError != nil }, set: { if !$0 { originalError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(originalError ?? "")
        }
        // Without background audio the system suspends the engine, so pause
        // cleanly instead of resuming onto a stale clock.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.pause() }
        }
        .onDisappear { player.stop() }
    }

    /// Free users practise only the first measures of a sheet they haven't
    /// unlocked. The built-in demo stays whole, so practice can be tried
    /// without an ad.
    private var isLocked: Bool {
        _ = unlockExpired
        return AdConfig.isEnabled && !entitlements.isEntitled
            && !unlocks.isUnlocked(jobID) && !DemoSheet.isDemo(jobID)
    }

    /// When an ad's hour on this sheet runs out, for a free user.
    private var unlockedUntil: Date? {
        _ = unlockExpired
        guard AdConfig.isEnabled, !entitlements.isEntitled else { return nil }
        return unlocks.unlockedUntil(jobID)
    }

    private var previewEnd: Double? {
        guard isLocked, let timeline = player.timeline else { return nil }
        return PracticeUnlocks.previewEndBeat(in: timeline)
    }

    /// Unlocks only once the ad has been watched through, then carries on
    /// from where the preview stopped.
    private func watchAd() async {
        player.pause()
        player.hitPreviewEnd = false
        watchingAd = true
        let earned = await rewardedAd.present()
        watchingAd = false
        guard earned else {
            if !rewardedAd.isReady { noAdAvailable = true }
            return
        }
        unlocks.unlock(jobID)
        player.previewEndBeat = nil
        player.play(from: player.beat)
    }

    private var sheetChoices: some View {
        HStack(spacing: 6) {
            versionPicker
            if showsNotationToggle {
                NotationToggle(fallback: labels?.notation)
            }
        }
    }

    private var versionPicker: some View {
        BrandSegmentedControl(label: "Sheet version",
                              options: PDFVersion.allCases.map { ($0, $0.title, $0.title) },
                              selection: $displayedVersion)
            .accessibilityHint("Switches between the annotated sheet and the uploaded original")
    }

    /// Letters or jianpu, for the names on the page, the keys and the
    /// falling notes alike.
    private var notation: Notation {
        notationPreference.notation(fallback: labels?.notation)
    }

    /// Whenever something on screen shows names.
    private var showsNotationToggle: Bool {
        (labels != nil && displayedVersion == .annotated) || player.showKeyNames || player.showNoteNames
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
                NoteRollView(player: player, notes: notes, range: keyRange, notation: notation)
            } keyboard: {
                KeyboardView(range: keyRange,
                             litKeys: player.litKeys,
                             showNames: player.showKeyNames,
                             notation: notation)
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

    private var sheet: some View {
        sheetPage.overlay(alignment: .bottomLeading) {
            if previewEnd != nil {
                previewChip
            } else if let unlockedUntil {
                unlockedChip(until: unlockedUntil)
            }
        }
    }

    /// Says up front how much is free and what an ad unlocks, as AdMob asks
    /// of rewarded ads.
    private var previewChip: some View {
        Button {
            player.pause()
            player.hitPreviewEnd = true
        } label: {
            Label("Free preview · \(PracticeUnlocks.freeMeasures) measures", systemImage: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: .capsule)
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityHint("Shows how to unlock the whole sheet")
    }

    /// So the sheet locking again an hour later comes as no surprise.
    private func unlockedChip(until date: Date) -> some View {
        Label {
            Text("Unlocked until \(date, style: .time)")
        } icon: {
            Image(systemName: "lock.open.fill")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Brand.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: .capsule)
        .padding(10)
    }

    /// The page is a visual aid. Practice runs entirely from the timeline, so a
    /// sheet that fails to load leaves everything else working.
    @ViewBuilder
    private var sheetPage: some View {
        if let pdfData, overlayReady {
            let namesLive = labels != nil && originalPDFData != nil
            let base = displayedVersion == .original || namesLive ? (originalPDFData ?? pdfData) : pdfData
            SheetPDFView(data: base,
                         highlightedMeasure: player.highlightedMeasure,
                         playhead: player.playhead,
                         overlay: SheetOverlayContent(labels: labels?.adoptingIDs(of: player.edits.labels.keys),
                                                      edits: player.edits,
                                                      showsNames: namesLive && displayedVersion == .annotated,
                                                      notation: notation,
                                                      keyMarks: player.keyMarks)) { point, page in
                player.handleTap(at: point, page: page)
            }
            .overlay {
                if displayedVersion == .original, isLoadingOriginal {
                    ProgressView("Loading original…")
                        .padding(16)
                        .background(Brand.card, in: .rect(cornerRadius: 12))
                }
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

    private func loadLabels() async {
        defer { overlayReady = true }
        guard let assets = try? await files.assets(jobID: jobID) else { return }
        let (original, labelData) = await SheetDetailModel.labelSources(jobID: jobID, assets: assets, files: files)
        guard let original else { return }
        var found = labelData.flatMap(LabelSet.decode)
        if found == nil {
            // Older sheets: the names are read back out of the annotated PDF.
            let annotated: Data?
            if let pdfData { annotated = pdfData } else { annotated = try? await files.data(jobID: jobID, artifact: .pdf, assets: assets) }
            if let annotated {
                found = await Task.detached { LabelSet.reading(pdf: annotated, timeline: nil) }.value
            }
        }
        guard let found else { return }
        if originalPDFData == nil { originalPDFData = original }
        labels = found
    }

    private func loadPDFIfNeeded() async {
        guard pdfData == nil else { return }
        do {
            pdfData = try await files.data(jobID: jobID, artifact: .pdf)
        } catch {
            pdfFailed = true
        }
    }

    /// Practice playback is based on the timeline, not the rendered PDF, so
    /// switching documents leaves its current position and sound untouched.
    private func loadOriginalIfNeeded() async {
        guard originalPDFData == nil, !isLoadingOriginal else { return }
        isLoadingOriginal = true
        defer { isLoadingOriginal = false }
        do {
            originalPDFData = try await files.data(jobID: jobID, artifact: .original)
            originalError = nil
        } catch {
            // Continue showing the annotated sheet if an older server does
            // not expose the uploaded original.
            displayedVersion = .annotated
            originalError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
