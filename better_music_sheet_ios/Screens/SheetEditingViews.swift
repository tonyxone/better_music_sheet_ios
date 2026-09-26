import SwiftUI
import UIKit

/// The tools across the top while editing, as on the web: what a finger
/// does, its colour, and undo, redo and reset.
struct SheetEditToolbar: View {
    @Bindable var editor: SheetEditorModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(SheetEditorModel.Tool.allCases) { tool in
                    Button {
                        editor.tool = tool
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: icon(tool))
                                .font(.system(size: 18))
                                .frame(height: 22)
                            Text(tool.title)
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(editor.tool == tool ? Brand.accent : Brand.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(editor.tool == tool ? Brand.accent.opacity(0.1) : .clear, in: .rect(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tool.title)
                    .accessibilityAddTraits(editor.tool == tool ? .isSelected : [])
                }

                Divider().frame(height: 32).padding(.horizontal, 2)

                historyButton("arrow.uturn.backward", label: "Undo", enabled: editor.store.canUndo) { editor.store.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                historyButton("arrow.uturn.forward", label: "Redo", enabled: editor.store.canRedo) { editor.store.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                Menu {
                    ResetMenuItems(editor: editor)
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(editor.doc.isEmpty ? Brand.hairline : Brand.ink)
                        .frame(width: 40, height: 48)
                }
                .disabled(editor.doc.isEmpty)
                .accessibilityLabel("Reset")
            }
            if editor.tool == .pen || editor.tool == .text {
                swatches(SheetEditorModel.penColors, selection: $editor.penColor, label: "Colour")
            } else if editor.tool == .highlighter {
                swatches(SheetEditorModel.highlightColors, selection: $editor.highlightColor, label: "Highlighter colour")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Brand.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.paperDeep).frame(height: 1) }
    }

    private func icon(_ tool: SheetEditorModel.Tool) -> String {
        switch tool {
        case .select: "cursorarrow"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .eraser: "eraser"
        }
    }

    private func historyButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(enabled ? Brand.ink : Brand.hairline)
                .frame(width: 40, height: 48)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func swatches(_ colors: [String], selection: Binding<String>, label: String) -> some View {
        ColorSwatches(colors: colors, selected: selection.wrappedValue, label: label) { selection.wrappedValue = $0 }
    }
}

/// A row of colour dots, the chosen one ringed.
struct ColorSwatches: View {
    let colors: [String]
    let selected: String?
    let label: String
    let choose: (String) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(colors, id: \.self) { color in
                let isSelected = selected?.caseInsensitiveCompare(color) == .orderedSame
                Button {
                    choose(color)
                } label: {
                    Circle()
                        .fill(Color(uiColor: UIColor(hex: color)))
                        .frame(width: 26, height: 26)
                        .padding(3)
                        .overlay(Circle().stroke(isSelected ? Brand.ink : .clear, lineWidth: 2))
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label) \(color)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Back to the annotated version as it was generated: just the names (and
/// the playback fixes they made), or everything.
struct ResetMenuItems: View {
    let editor: SheetEditorModel

    var body: some View {
        Button("Note names only", systemImage: "character.cursor.ibeam") { editor.reset(.names) }
            .disabled(!editor.hasNameChanges)
        Button(editor.hasMarks ? "Everything, including drawings and notes" : "Everything",
               systemImage: "arrow.counterclockwise", role: .destructive) { editor.reset(.everything) }
    }
}

/// The line under the sheet's top edge while editing: what is selected and
/// what can be done with it, or the latest notice, or a hint.
struct SheetSelectionBar: View {
    let editor: SheetEditorModel

    var body: some View {
        VStack(spacing: 4) {
            line
            if !editor.selection.isEmpty {
                HStack(spacing: 6) {
                    Text("Colour")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Brand.inkSoft)
                    ColorSwatches(colors: editor.selectionPalette, selected: editor.selectionColor,
                                  label: "Colour selection") { editor.recolorSelection($0) }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Brand.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.paperDeep).frame(height: 1) }
    }

    private var line: some View {
        HStack(spacing: 14) {
            if let notice = editor.notice {
                Text(notice)
                    .foregroundStyle(Brand.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if notice == editor.resetNotice {
                    Button("Undo") { editor.undoReset() }
                }
                Button {
                    editor.dismissNotice()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                }
                .accessibilityLabel("Dismiss")
            } else if editor.selection.count == 1, let item = editor.selection.first {
                single(item)
            } else if editor.selection.count > 1 {
                Text("\(editor.selection.count) selected · drag one to move them all")
                    .foregroundStyle(Brand.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(editor.selection.allSatisfy { $0.kind == .label } ? "Hide" : "Delete") { editor.deleteSelection() }
                let names = editor.selection.filter { $0.kind == .label }.map(\.id)
                if names.contains(where: { editor.doc.labels[$0] != nil }) {
                    Button("Reset") { editor.resetLabels(names) }
                }
                Button("Clear") { editor.select([]) }
            } else {
                Text(hint)
                    .foregroundStyle(Brand.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 13))
        .tint(Brand.accent)
        .lineLimit(2)
        .frame(minHeight: 38)
    }

    @ViewBuilder
    private func single(_ item: SelectedItem) -> some View {
        switch item.kind {
        case .label:
            let label = editor.label(item.id)
            let text = label.flatMap(editor.doc.resolve)?.text ?? ""
            Text("Note name \(Text(text).bold())\(label?.notes.isEmpty == false ? " · plays" : " · not linked to playback")")
            .foregroundStyle(Brand.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retype") { editor.openTextEditor(for: item) }
            if editor.chord(of: item.id).count > 1 {
                Button("Chord") { editor.selectChord(of: item.id) }
                    .accessibilityLabel("Select the whole chord")
            }
            Button("Hide") { editor.deleteSelection() }
            if editor.doc.labels[item.id] != nil {
                Button("Reset") { editor.resetLabels([item.id]) }
            }
        case .text:
            Text("Text note").foregroundStyle(Brand.ink).frame(maxWidth: .infinity, alignment: .leading)
            Button("Edit") { editor.openTextEditor(for: item) }
            Button("Delete") { editor.deleteSelection() }
        case .stroke:
            Text("Drawing").foregroundStyle(Brand.ink).frame(maxWidth: .infinity, alignment: .leading)
            Button("Delete") { editor.deleteSelection() }
        }
    }

    private var hint: String {
        switch editor.tool {
        case .select:
            editor.showsNames || !editor.namesLive
                ? "Tap to select, tap again to retype · drag to move · touch and hold empty space to select several"
                : "Tap to select · note names are edited in the Annotated view"
        case .pen, .highlighter: "Draw with one finger · scroll and zoom with two"
        case .text: "Tap where the note should go"
        case .eraser: "Tap or rub over drawings and notes to erase them"
        }
    }
}

/// Typing a note name or a text note. A sheet rather than a box floating on
/// the page: the keyboard would cover a box near the bottom, and this keeps
/// the name readable at any zoom.
struct SheetTextEntry: View {
    let target: SheetEditorModel.TextEditTarget
    let finish: (String?) -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(target: SheetEditorModel.TextEditTarget, finish: @escaping (String?) -> Void) {
        self.target = target
        self.finish = finish
        _text = State(initialValue: target.initialText)
    }

    private var isName: Bool { target.item.kind == .label }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                if isName {
                    TextField("Note name", text: $text)
                        .font(.system(size: 22))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit { finish(text) }
                } else {
                    TextField("Type a note", text: $text, axis: .vertical)
                        .font(.system(size: 17))
                        .lineLimit(1...6)
                        .focused($focused)
                }
                Text(isName
                     ? "Type a note name such as B♭ or F#4 — playback follows. Leave it empty to hide the name."
                     : "Leave it empty to remove the note.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.inkSoft)
                if isName {
                    HStack(spacing: 8) {
                        ForEach(["♭", "♯", "♮"], id: \.self) { symbol in
                            Button(symbol) { text += symbol }
                                .font(.system(size: 18))
                                .frame(width: 44, height: 36)
                                .background(Brand.paperDeep, in: .rect(cornerRadius: 8))
                                .accessibilityLabel(symbol == "♭" ? "Flat" : symbol == "♯" ? "Sharp" : "Natural")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.ink)
                }
                Spacer()
            }
            .textFieldStyle(.roundedBorder)
            .padding(20)
            .background(Brand.paper)
            .navigationTitle(isName ? "Retype name" : target.isNew ? "Add a note" : "Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { finish(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish(text) }.bold()
                }
            }
        }
        .tint(Brand.accent)
        .presentationDetents([.height(isName ? 250 : 290)])
        .interactiveDismissDisabled()
        .onAppear { focused = true }
    }
}

/// The system share sheet, for a file that only exists once asked for (the
/// Customized PDF is built on demand).
struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
