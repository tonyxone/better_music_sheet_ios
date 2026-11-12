import SwiftUI

extension View {
    /// Asks for a new name for `job` while it is set, saves it on the server
    /// (SheetTitle.rename), and hands the renamed sheet to `onRenamed`.
    func renameSheet(_ job: Binding<AnnotationJob?>,
                     onRenamed: @escaping (AnnotationJob) -> Void) -> some View {
        modifier(RenameSheetPrompt(job: job, onRenamed: onRenamed))
    }
}

/// The rename prompt, shared by the library's rows and a sheet's own page.
private struct RenameSheetPrompt: ViewModifier {
    @Binding var job: AnnotationJob?
    let onRenamed: (AnnotationJob) -> Void
    @State private var name = ""
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: job?.jobID) { _, _ in
                name = job?.displayName ?? ""
            }
            .alert("Rename sheet", isPresented: Binding(
                get: { job != nil }, set: { if !$0 { job = nil } }
            ), presenting: job) { target in
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Save") { save(target) }
            }
            .alert("Couldn't rename this sheet", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
    }

    private func save(_ target: AnnotationJob) {
        let title = SheetTitle.cleaned(name)
        guard !title.isEmpty else {
            error = String(localized: "Enter a name for this sheet.", bundle: .app)
            return
        }
        guard title != target.displayName else { return }
        let capped = String(title.prefix(SheetTitle.maxLength))
        Task {
            do {
                onRenamed(try await SheetTitle.rename(jobID: target.jobID, to: capped))
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
