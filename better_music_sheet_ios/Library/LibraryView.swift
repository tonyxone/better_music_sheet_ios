import SwiftUI

/// The root screen. Library-first, not upload-first: an installed app opens
/// on your music, and adding is one action in thumb reach.
struct LibraryView: View {
    @State private var model = LibraryModel()
    @State private var showingAddSheet = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Brand.paper.ignoresSafeArea()

            content
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }

            addButton
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Account screen lands with the auth phase.
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Brand.inkSoft)
                }
                .accessibilityLabel("Account")
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(isPresented: $showingAddSheet) {
            Text("Adding a sheet arrives with the ingest phase.")
                .font(.callout)
                .foregroundStyle(Brand.inkSoft)
                .presentationDetents([.medium])
        }
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
                    ForEach(model.jobs) { job in
                        SheetRow(job: job)
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
private struct SheetRow: View {
    let job: AnnotationJob

    var body: some View {
        HStack(spacing: 14) {
            thumbnail

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

            Spacer(minLength: 6)

            if job.status == .failed {
                Text("Retry")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .overlay(Capsule().stroke(Brand.hairline, lineWidth: 1))
            } else if job.status == .done {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.hairline)
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .background(Brand.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.paperDeep, lineWidth: 1))
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
    NavigationStack { LibraryView() }
}
