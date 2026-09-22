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
            if !entitlements.isEntitled {
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
        }
        .task(id: model.hasWorkInProgress) {
            await model.pollWhileWorking()
        }
        .refreshable { await model.load() }
        .sheet(isPresented: $showingAddSheet, onDismiss: openPendingSheet) {
            AddSheetView { jobID in
                pendingRoute = SheetRoute(jobID: jobID, provisionalName: "New sheet")
                Task { await model.load() }
            }
        }
        .sheet(isPresented: $showingAccount, onDismiss: { Task { await model.load() } }) {
            AccountView()
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
            if model.jobs.isEmpty {
                EmptyLibrary()
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

    private var addButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            Label("Add sheet", systemImage: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 26)
                .frame(height: 52)
                .background(Brand.accent, in: .capsule)
                .shadow(color: Brand.accentDeep.opacity(0.32), radius: 12, y: 6)
        }
        .padding(.bottom, 16)
    }
}

/// One sheet. A ready sheet says nothing about its status — only the states
/// that need attention speak up, which is the point of a library you own
/// rather than a job queue you are watching.
///
/// Practising sits beside the card rather than inside it, as a small card of its
/// own at the same height so the two read as a pair.
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
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Brand.accent)
                    .frame(height: 3)
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
