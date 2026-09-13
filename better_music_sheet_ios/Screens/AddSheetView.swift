import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Getting music in. The web app asks for annotation options every time; here
/// they are defaults you set once, with the current choice shown so it is
/// never a surprise.
struct AddSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = UploadModel()
    @State private var showingFiles = false
    @State private var photo: PhotosPickerItem?

    /// Handed the new job id so the library can open it straight away.
    let onStarted: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.paper.ignoresSafeArea()

                VStack(spacing: 16) {
                    if model.isBusy {
                        busy
                    } else {
                        sources
                        if case .failed(let message) = model.state {
                            Text(message)
                                .font(.system(size: 13))
                                .foregroundStyle(Brand.danger)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }
                        labelSummary
                    }
                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationTitle("Add sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.disabled(model.isBusy)
                }
            }
        }
        .fileImporter(isPresented: $showingFiles,
                      allowedContentTypes: [.pdf, .jpeg, .png]) { result in
            guard case .success(let url) = result else { return }
            Task {
                if let jobID = await model.upload(from: url) {
                    onStarted(jobID)
                    dismiss()
                }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    photo = nil
                    return
                }
                if let jobID = await model.upload(filename: "Scan.jpg", data: data) {
                    onStarted(jobID)
                    dismiss()
                }
                photo = nil
            }
        }
    }

    private var sources: some View {
        VStack(spacing: 10) {
            Button { showingFiles = true } label: {
                SourceRow(icon: "doc", title: "Choose a PDF",
                          detail: "From Files or iCloud Drive")
            }
            PhotosPicker(selection: $photo, matching: .images) {
                SourceRow(icon: "photo", title: "Photo library",
                          detail: "A photo of a page you already took")
            }
        }
        .buttonStyle(.plain)
    }

    private var busy: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Brand.accent)
            Text(model.state == .reading ? "Reading the file…" : "Uploading…")
                .font(.system(size: 15))
                .foregroundStyle(Brand.inkSoft)
        }
        .padding(.top, 40)
    }

    private var labelSummary: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LABELS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Brand.inkSoft)
                Text(summary)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Brand.ink)
            }
            Spacer()
        }
        .padding(14)
        .background(Brand.gold.opacity(0.10), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.paperDeep, lineWidth: 1))
    }

    private var summary: String {
        var parts = [model.options.style.title]
        parts.append(model.options.fontSize >= 8 ? "Large" : "Standard")
        if model.options.octave { parts.append("with octaves") }
        return parts.joined(separator: " · ")
    }
}

private struct SourceRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Brand.accentDeep)
                .frame(width: 44, height: 44)
                .background(Brand.gold.opacity(0.16), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.ink)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.hairline)
        }
        .padding(14)
        .background(Brand.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.paperDeep, lineWidth: 1))
    }
}
