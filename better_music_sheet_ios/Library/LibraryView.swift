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
    @Binding var path: [SheetRoute]
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            Brand.paper.ignoresSafeArea()

            content
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }

            addButton
        }
        .safeAreaInset(edge: .top) {
            if AdConfig.isEnabled, !entitlements.isEntitled {
                AdBannerView().frame(height: 50)
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
                .accessibilityLabel(model.currentUser.map { "Account, signed in as \($0.displayName ?? $0.email ?? "")" } ?? "Account")
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
            AddSheetView { jobID in
                pendingRoute = SheetRoute(jobID: jobID, provisionalName: "New sheet")
                Task { await model.load() }
            }
        }
        .sheet(isPresented: $showingAccount, onDismiss: afterAccount) {
            AccountView()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .alert("Free plan: 1 sheet at a time", isPresented: $showingFreeLimit) {
            Button("See Premium Plans") { showingPaywall = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Delete your current sheet to upload another, or go Premium for unlimited sheets and no ads.")
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

    /// Uploading needs an account. Premium uploads freely; the free plan keeps
    /// one sheet at a time (the backend enforces it too), so a free account
    /// that already has one is told to delete it or go Premium. Entitlement
    /// is checked fresh rather than trusted from before signing in.
    private func startAdding() async {
        guard model.currentUser != nil else {
            addAfterSignIn = true
            showingAccount = true
            return
        }
        checkingAccess = true
        await entitlements.refresh()
        checkingAccess = false
        if entitlements.isEntitled || !model.hasKeptSheet {
            showingAddSheet = true
        } else {
            showingFreeLimit = true
        }
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
                VStack(spacing: 18) {
                    EmptyLibrary()
                    if demo.isHidden == true {
                        showSampleButton
                    }
                }
            } else {
                List {
                    ForEach(model.visibleJobs) { job in
                        SheetRow(job: job) {
                            path.append(SheetRoute(jobID: job.jobID, provisionalName: job.displayName))
                        } practice: {
                            path.append(SheetRoute(jobID: job.jobID, provisionalName: job.displayName,
                                                   page: .practice))
                        }
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await model.delete(job) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
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
            }
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await demo.setHidden(true) }
                } label: {
                    Label("Remove", systemImage: "eye.slash")
                }
            }
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

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 14) {
                    SheetThumbnail()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Try a sample")
                            .font(Brand.title(17))
                            .foregroundStyle(Brand.ink)
                        Text("\(DemoSheet.title) · \(DemoSheet.detail)")
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

private struct SheetRow: View {
    let job: AnnotationJob
    let open: () -> Void
    let practice: () -> Void

    private static let practiceWidth: CGFloat = 64

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
        }
        // Lets both cards stretch to the taller one's height.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var trailing: some View {
        switch job.status {
        case .done:
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.hairline)
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
                Text(job.error ?? "Couldn't read this sheet")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.danger)
                    .lineLimit(2)
            default:
                Text(job.stage ?? "Queued")
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
        var parts = [job.createdDate.formatted(.relative(presentation: .named))]
        if let groups = job.labeledGroups { parts.append("\(groups) labels") }
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
