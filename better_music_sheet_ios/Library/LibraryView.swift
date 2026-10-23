import SwiftUI

/// The root screen. Library-first, not upload-first: an installed app opens
/// on your music, and adding is one action in thumb reach.
struct LibraryView: View {
    @State private var model = LibraryModel()
    @State private var showingAddSheet = false
    @State private var showingAccount = false
    /// A sheet to open once the add panel has finished closing.
    @State private var pendingRoute: SheetRoute?
    @State private var entitlements = EntitlementStore.shared
    @State private var demo = DemoVisibility()
    @State private var showingPaywall = false
    @State private var showingFreeLimit = false
    /// Set when Add was tapped signed out, so signing in carries on to it.
    @State private var addAfterSignIn = false
    @State private var checkingAccess = false
    @State private var uploadCredits = UploadCredits.shared
    @State private var uploadAd = RewardedAdLoader.upload
    /// The add-sheet panel was opened with ads watched for it.
    @State private var addWithAds = false
    /// The sheet that upload replaces, deleted once the backend accepts it.
    @State private var replacing: [AnnotationJob] = []
    /// That upload goes among several sheets kept (a lapsed subscriber's),
    /// replacing the one chosen, and opens with the ad already watched.
    @State private var addingToSeveral = false
    @State private var choosingReplacement = false
    @State private var readingUnlocks = PracticeUnlocks.reading
    @State private var sheetAd = RewardedAdLoader.practice
    /// A locked sheet tapped, waiting on its unlock prompt.
    @State private var pendingUnlock: SheetRoute?
    @State private var showingUploadUnlock = false
    @State private var noAdAvailable = false
    /// The sheet a swipe asked to delete, waiting on the confirmation alert.
    @State private var pendingDeletion: AnnotationJob?
    @Binding var path: [SheetRoute]
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Split in two so the compiler can type-check it: the page, then the
        // prompts it raises.
        page
        .alert(model.hasKeptSheet ? "Replace your sheet?" : "Upload a sheet?", isPresented: $showingUploadUnlock) {
            // An ad already watched (an upload that then failed) isn't asked again.
            Button(uploadCredits.isReady ? (model.hasKeptSheet ? "Replace" : "Upload") : "Watch Ad") {
                Task { await watchUploadAds() }
            }
            Button("See Premium Plans") { showingPaywall = true }
            Button("Not Now", role: .cancel) {}
        } message: {
            if !model.hasKeptSheet {
                Text("Watch a short ad to upload a sheet — or go Premium for unlimited sheets and no ads.")
            } else if let only = model.keptSheets.first {
                Text("The free plan keeps 1 sheet at a time. Watch a short ad to upload a new sheet in place of “\(only.displayName)”, which will be deleted — or go Premium for unlimited sheets and no ads.")
            }
        }
        // Several sheets: the reader picks the one the new upload replaces.
        .confirmationDialog("Replace which sheet?", isPresented: $choosingReplacement, titleVisibility: .visible) {
            ForEach(model.keptSheets) { job in
                Button(job.displayName, role: .destructive) {
                    Task { await watchUploadAds(replacing: job) }
                }
            }
            Button("See Premium Plans") { showingPaywall = true }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Each new upload takes a short ad and replaces one of your sheets, which will be deleted. Choose which — or go Premium for unlimited sheets and no ads.")
        }
        .alert("Unlock this sheet", isPresented: Binding(
            get: { pendingUnlock != nil }, set: { if !$0 { pendingUnlock = nil } }
        ), presenting: pendingUnlock) { route in
            Button("Watch Ad") { Task { await watchSheetAd(for: route) } }
            Button("See Premium Plans") { showingPaywall = true }
            Button("Not Now", role: .cancel) {}
        } message: { route in
            Text("The free plan opens your first sheet without ads. Watch a short ad to read and practise “\(route.provisionalName)” for an hour — or go Premium to open every sheet.")
        }
        // The hour is clock time, so it runs out while a sheet is open or the
        // app is closed: checked on coming back, when the hour ends, and when
        // Premium ends (often learned just after coming back).
        .task(id: "\(scenePhase == .active) \(entitlements.isEntitled) \(openUnlockExpiry?.timeIntervalSince1970 ?? 0)") {
            guard scenePhase == .active else { return }
            closeExpiredSheets()
            guard let expiry = openUnlockExpiry else { return }
            try? await Task.sleep(for: .seconds(max(0, expiry.timeIntervalSinceNow) + 0.5))
            guard !Task.isCancelled else { return }
            closeExpiredSheets()
        }
        .task(id: model.keptSheets.contains(where: isLocked)) {
            guard model.keptSheets.contains(where: isLocked) else { return }
            await sheetAd.load()
        }
        .alert("No ad available", isPresented: $noAdAvailable) {
            Button("See Premium Plans") { showingPaywall = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text("No ad is available right now. Try again in a moment.")
        }
        // Loaded ahead while a free account is at its free sheet, so the ad
        // plays without a wait.
        .task(id: needsUploadAds) {
            guard needsUploadAds else { return }
            await uploadAd.load()
        }
        .alert("Free plan: 1 sheet at a time", isPresented: $showingFreeLimit) {
            Button("See Premium Plans") { showingPaywall = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Delete your current sheet to upload another, or go Premium for unlimited sheets and no ads.")
        }
        .alert("Delete this sheet?", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { job in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await model.delete(job) } }
        } message: { job in
            Text("“\(job.displayName)” and its annotations will be removed from your library. This can't be undone.")
        }
    }

    private var page: some View {
        ZStack(alignment: .bottom) {
            Brand.paper.ignoresSafeArea()

            content
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }

            addButton
        }
        .safeAreaInset(edge: .top) {
            if AdConfig.isEnabled, !entitlements.isEntitled {
                AdBannerSlot()
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAccount = true
                } label: {
                    if let name = model.currentUser?.displayName ?? model.currentUser?.email {
                        HStack(spacing: 5) {
                            Text(name)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 18))
                        }
                        .foregroundStyle(Brand.inkSoft)
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(Brand.inkSoft)
                    }
                }
                .accessibilityLabel(model.currentUser.map { Text("Account, signed in as \($0.displayName ?? $0.email ?? "")") } ?? Text("Account"))
            }
        }
        // Reloads on appearing, and again whenever the app returns to the
        // foreground — a sheet can finish while the phone is locked.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.load()
            await demo.load()
        }
        .task(id: model.hasWorkInProgress) {
            await model.pollWhileWorking()
        }
        .refreshable {
            await model.load()
            await demo.load()
        }
        .sheet(isPresented: $showingAddSheet, onDismiss: openPendingSheet) {
            AddSheetView(adUnlock: addWithAds) { jobID in
                pendingRoute = SheetRoute(jobID: jobID, provisionalName: String(localized: "New sheet", bundle: .app))
                let replaced = replacing
                replacing = []
                if addWithAds, addingToSeveral {
                    // Locked like the other extras, but its ad is already watched.
                    readingUnlocks.unlock(jobID)
                    PracticeUnlocks.shared.unlock(jobID)
                }
                addingToSeveral = false
                Task {
                    for job in replaced where job.jobID != jobID { await model.delete(job) }
                    await model.load()
                }
            }
        }
        .sheet(isPresented: $showingAccount, onDismiss: afterAccount) {
            AccountView()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }

    private func afterAccount() {
        Task {
            await model.load()
            await demo.load()
            if addAfterSignIn {
                addAfterSignIn = false
                if model.currentUser != nil { await startAdding() }
            }
        }
    }

    /// Uploading needs an account. Premium uploads freely. Every upload from a
    /// free account takes a rewarded ad (UploadCredits), the first included.
    /// It keeps one sheet at a time, so with one already the new sheet goes
    /// in its place, and the old one is deleted once the backend accepts the
    /// upload (the ad lets it past the backend's one-sheet check for that
    /// moment). An account already holding several — a lapsed subscriber's —
    /// keeps them, opening them with ads (see isLocked), but each upload
    /// replaces the one it picks. Entitlement is checked fresh rather than
    /// trusted from before signing in.
    private func startAdding() async {
        guard model.currentUser != nil else {
            addAfterSignIn = true
            showingAccount = true
            return
        }
        checkingAccess = true
        await entitlements.refresh()
        checkingAccess = false
        if entitlements.isEntitled || (!AdConfig.isEnabled && !model.hasKeptSheet) {
            addWithAds = false
            replacing = []
            showingAddSheet = true
        } else if !AdConfig.isEnabled {
            showingFreeLimit = true
        } else if model.keptSheets.count > 1 {
            choosingReplacement = true
        } else {
            // Always asked, even with an ad already watched: it may delete a sheet.
            showingUploadUnlock = true
        }
    }

    private var needsUploadAds: Bool {
        AdConfig.isEnabled && model.currentUser != nil && !entitlements.isEntitled
    }

    /// The ad an upload takes, from one tap. Closing it early earns nothing.
    /// What it replaces is fixed here, as the prompt named it: the sheet
    /// chosen among several, or the one sheet kept.
    private func watchUploadAds(replacing chosen: AnnotationJob? = nil) async {
        checkingAccess = true
        defer { checkingAccess = false }
        while !uploadCredits.isReady {
            guard await uploadAd.present() else {
                uploadCredits.abandon()
                if !uploadAd.isReady { noAdAvailable = true }
                return
            }
            uploadCredits.earn()
            // Let the finished ad's screen finish closing before the next.
            if !uploadCredits.isReady { try? await Task.sleep(for: .milliseconds(600)) }
        }
        let kept = model.keptSheets
        replacing = chosen.map { [$0] } ?? kept
        addingToSeveral = kept.count > 1
        addWithAds = true
        showingAddSheet = true
    }

    /// A free account holding more than its one sheet — most often a lapsed
    /// subscriber's — opens its first for free and every other with an ad,
    /// for PracticeUnlocks.readingDuration. Down to one sheet, it's free.
    private func needsAd(_ job: AnnotationJob) -> Bool {
        PracticeUnlocks.needsReadingAd(job.jobID, isDone: job.status == .done,
                                       kept: model.keptSheets.map { ($0.jobID, $0.createdAt) },
                                       isPremium: entitlements.isEntitled, adsEnabled: AdConfig.isEnabled)
    }

    private func isLocked(_ job: AnnotationJob) -> Bool {
        needsAd(job) && !readingUnlocks.isUnlocked(job.jobID)
    }

    private func job(for route: SheetRoute) -> AnnotationJob? {
        model.jobs.first { $0.jobID == route.jobID }
    }

    /// When the soonest unlock among the sheets open now runs out.
    private var openUnlockExpiry: Date? {
        path.compactMap { route in
            job(for: route).flatMap { needsAd($0) ? readingUnlocks.unlockedUntil($0.jobID) : nil }
        }.min()
    }

    /// Back to the library from a sheet whose hour is up, asking for an ad.
    private func closeExpiredSheets() {
        guard let index = path.firstIndex(where: { job(for: $0).map(isLocked) ?? false }) else { return }
        let route = path[index]
        path.removeSubrange(index...)
        pendingUnlock = route
    }

    private func open(_ route: SheetRoute) {
        if let job = job(for: route), isLocked(job) {
            pendingUnlock = route
        } else {
            path.append(route)
        }
    }

    /// One ad opens the sheet, reading and practice, for an hour.
    private func watchSheetAd(for route: SheetRoute) async {
        checkingAccess = true
        let earned = await sheetAd.present()
        checkingAccess = false
        guard earned else {
            if !sheetAd.isReady { noAdAvailable = true }
            return
        }
        readingUnlocks.unlock(route.jobID)
        PracticeUnlocks.shared.unlock(route.jobID)
        path.append(route)
    }

    /// Pushed only after the panel has gone. SwiftUI often drops a navigation
    /// change made while a sheet is mid-dismissal, which left a fresh upload
    /// sitting unopened on the library instead of on its polling screen.
    private func openPendingSheet() {
        guard let route = pendingRoute else { return }
        pendingRoute = nil
        path.append(route)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading where model.jobs.isEmpty:
            ProgressView().tint(Brand.accent)

        case .failed(let message) where model.jobs.isEmpty:
            RetryNotice(message: message) { Task { await model.load() } }

        default:
            if model.jobs.isEmpty && demo.isHidden != false {
                // The footer at the bottom of the screen, below the message,
                // and scrolled to where the screen is too short for both.
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 18) {
                            Spacer(minLength: 0)
                            EmptyLibrary()
                            if demo.isHidden == true {
                                showSampleButton
                            }
                            Spacer(minLength: 0)
                            AppFooter()
                                .padding(.horizontal, 24)
                        }
                        .frame(minHeight: proxy.size.height)
                    }
                }
            } else {
                List {
                    ForEach(model.visibleJobs) { job in
                        SheetRow(job: job, locked: isLocked(job)) {
                            open(SheetRoute(jobID: job.jobID, provisionalName: job.displayName))
                        } practice: {
                            open(SheetRoute(jobID: job.jobID, provisionalName: job.displayName,
                                            page: .practice))
                        } delete: {
                            pendingDeletion = job
                        }
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    // Built-in sample, not the reader's own music — always
                    // last, so it never sits among their sheets.
                    if !model.hasMoreToShow {
                        demoRow
                    }

                    if model.hasMoreToShow {
                        Button("Show more") { model.loadMore() }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Brand.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    AppFooter()
                        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder
    private var demoRow: some View {
        switch demo.isHidden {
        case false?:
            DemoRow {
                path.append(SheetRoute(jobID: DemoSheet.jobID, provisionalName: DemoSheet.title))
            } practice: {
                path.append(SheetRoute(jobID: DemoSheet.jobID, provisionalName: DemoSheet.title, page: .practice))
            } remove: {
                Task { await demo.setHidden(true) }
            }
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        case true?:
            showSampleButton
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        case nil:
            EmptyView()
        }
    }

    private var showSampleButton: some View {
        Button("Show the sample again") {
            Task { await demo.setHidden(false) }
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Brand.accent)
        .padding(.vertical, 8)
    }

    private var addButton: some View {
        Button {
            Task { await startAdding() }
        } label: {
            Label(checkingAccess ? "Checking…" : "Add sheet", systemImage: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 26)
                .frame(height: 52)
                .background(Brand.accent, in: .capsule)
                .shadow(color: Brand.accentDeep.opacity(0.32), radius: 12, y: 6)
        }
        .padding(.bottom, 16)
        .disabled(checkingAccess)
    }
}

/// "Try a sample": the bundled demo, which anyone can open and practise in
/// full — no upload, no account, no subscription. Shaped like a sheet row,
/// so it reads as one more thing to open rather than an advert.
private struct DemoRow: View {
    let open: () -> Void
    let practice: () -> Void
    /// Hides the sample; Show sample brings it back, so nothing asks first.
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 14) {
                    SheetThumbnail()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Try a sample")
                            .font(Brand.title(17))
                            .foregroundStyle(Brand.ink)
                        Text(verbatim: "\(DemoSheet.title) · \(DemoSheet.detail)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Brand.inkSoft)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Brand.hairline)
                }
                .padding(.vertical, 13)
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
                .background(Brand.card, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.paperDeep, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the sample sheet, annotated — free, no account needed")

            Button(action: practice) {
                KeyboardIcon()
                    .foregroundStyle(Brand.ink)
                    .frame(width: 30, height: 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Brand.card, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.paperDeep, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 64)
            .accessibilityLabel("Practice the sample")

            // In the delete button's place on a sheet's row, so the cards line up.
            Button(action: remove) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.inkSoft)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Brand.card, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.paperDeep, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 48)
            .accessibilityLabel("Remove the sample")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One sheet. A ready sheet says nothing about its status — only the states
/// that need attention speak up, which is the point of a library you own
/// rather than a job queue you are watching.
///
/// Practising sits beside the card rather than inside it, as a small card of its
/// own at the same height so the two read as a pair.
/// A determinate bar for a job still being read. Within its stage's slice it
/// eases toward the slice's end — fast at first, never reaching it — so the
/// bar keeps moving while a long stage runs, without claiming the stage is
/// done before the server says so.
private struct JobProgressBar: View {
    let range: ClosedRange<Double>

    /// Seconds to cover about two-thirds of the remaining slice.
    private static let easing: Double = 40
    @State private var stageStart = Date.now

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.paperDeep)
                    Capsule()
                        .fill(Brand.accent)
                        .frame(width: proxy.size.width * fraction(at: context.date))
                        .animation(.linear(duration: 0.5), value: fraction(at: context.date))
                }
            }
        }
        .frame(height: 4)
        .onChange(of: range) { stageStart = .now }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(Text(fraction(at: .now), format: .percent.precision(.fractionLength(0))))
    }

    private func fraction(at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(stageStart))
        let eased = 1 - exp(-elapsed / Self.easing)
        return range.lowerBound + (range.upperBound - range.lowerBound) * eased
    }
}

/// A sheet's card, then its practice and delete buttons. Delete is a button
/// of its own rather than a swipe, which readers didn't find.
private struct SheetRow: View {
    let job: AnnotationJob
    /// Takes an ad to open (see LibraryView.isLocked).
    let locked: Bool
    let open: () -> Void
    let practice: () -> Void
    let delete: () -> Void

    private static let practiceWidth: CGFloat = 64
    private static let deleteWidth: CGFloat = 48

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 14) {
                    thumbnail
                    details
                    Spacer(minLength: 6)
                    trailing
                }
                .padding(.vertical, 13)
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
                .background(Brand.card, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.paperDeep, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if job.status == .done {
                // Only a finished sheet has a timeline to practise with.
                Button(action: practice) {
                    KeyboardIcon()
                        .foregroundStyle(Brand.ink)
                        .frame(width: 30, height: 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Brand.card, in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.paperDeep, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: Self.practiceWidth)
                .accessibilityLabel("Practice \(job.displayName)")
            } else {
                // Keeps the space, so every card lines up along the right.
                Color.clear
                    .frame(width: Self.practiceWidth)
                    .accessibilityHidden(true)
            }

            // Asks first (the library's confirmation alert), so a stray tap
            // deletes nothing.
            Button(action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.danger)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Brand.card, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.paperDeep, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: Self.deleteWidth)
            .accessibilityLabel("Delete \(job.displayName)")
        }
        // Lets both cards stretch to the taller one's height.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var trailing: some View {
        switch job.status {
        case .done:
            Image(systemName: locked ? "lock.fill" : "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(locked ? Brand.inkSoft : Brand.hairline)
                .accessibilityLabel(Text("Locked"))
                .accessibilityHidden(!locked)
        case .failed:
            Text("Retry")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.ink)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .overlay(Capsule().stroke(Brand.hairline, lineWidth: 1))
        default:
            EmptyView()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(job.displayName)
                .font(Brand.title(17))
                .foregroundStyle(Brand.ink)
                .lineLimit(1)

            switch job.status {
            case .done:
                Text(meta).font(.system(size: 12.5)).foregroundStyle(Brand.inkSoft)
            case .failed:
                (job.error.map { Text(ServerText.translate($0)) } ?? Text("Couldn't read this sheet"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.danger)
                    .lineLimit(2)
            default:
                (job.stage.map { Text(ServerText.translate($0)) } ?? Text("Queued"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.inkSoft)
                JobProgressBar(range: job.progressRange)
                    .padding(.top, 3)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch job.status {
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18))
                .foregroundStyle(Brand.danger)
                .frame(width: 42, height: 54)
                .background(Brand.danger.opacity(0.10), in: .rect(cornerRadius: 6))
        case .done:
            SheetThumbnail()
        default:
            ProgressView()
                .tint(Brand.accent)
                .frame(width: 42, height: 54)
                .background(Brand.paper, in: .rect(cornerRadius: 6))
        }
    }

    private var meta: String {
        var parts = [job.createdDate.formatted(.relative(presentation: .named).locale(AppLanguage.current.locale))]
        if let groups = job.labeledGroups { parts.append(String(localized: "\(groups) labels", bundle: .app)) }
        return parts.joined(separator: " · ")
    }
}

private struct EmptyLibrary: View {
    var body: some View {
        VStack(spacing: 10) {
            SheetThumbnail().scaleEffect(1.3).padding(.bottom, 8)
            Text("No sheets yet")
                .font(Brand.title(20))
                .foregroundStyle(Brand.ink)
            Text("Scan or open a piano score and we'll pencil in the letter name of every note.")
                .font(.system(size: 14))
                .foregroundStyle(Brand.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(.bottom, 60)
    }
}

private struct RetryNotice: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Couldn't load your library")
                .font(Brand.title(19))
                .foregroundStyle(Brand.ink)
            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(Brand.inkSoft)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 44)
                .background(Brand.accent, in: .capsule)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 60)
    }
}

#Preview {
    @Previewable @State var path: [SheetRoute] = []
    return NavigationStack(path: $path) { LibraryView(path: $path) }
}
