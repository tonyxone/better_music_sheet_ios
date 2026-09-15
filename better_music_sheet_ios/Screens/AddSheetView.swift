import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Getting music in, and choosing how its note names look. The options are the
/// web app's upload options plus the names' colour. They are remembered, so
/// the usual visit is picking a file and nothing else.
struct AddSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = UploadModel()
    @State private var showingFiles = false
    @State private var photo: PhotosPickerItem?
    /// The option whose explanation is showing, if any.
    @State private var openHelp: Option?
    /// Hidden by default: the remembered choices are usually right.
    @State private var showingOptions = false

    /// Handed the new job id so the library can open it straight away.
    let onStarted: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.paper.ignoresSafeArea()

                if model.isBusy {
                    busy
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            sources
                            options
                        }
                        .padding(20)
                    }
                }
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
        .onChange(of: model.options) { _, options in
            options.save()
        }
    }

    private var sources: some View {
        VStack(spacing: 10) {
            if case .failed(let message) = model.state {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
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
    }

    // MARK: - Options

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { showingOptions.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("OPTIONS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Brand.inkSoft)
                    Spacer(minLength: 8)
                    if !showingOptions {
                        Text(optionsSummary)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Brand.inkSoft)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Brand.inkSoft)
                        .rotationEffect(.degrees(showingOptions ? 180 : 0))
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Options")
            .accessibilityValue(showingOptions ? "Expanded" : optionsSummary)
            .accessibilityHint(showingOptions ? "Hides the options" : "Shows the options")

            if showingOptions {
                VStack(spacing: 0) {
                    LabelPreview(options: model.options)
                    divider

                    row(.style) {
                        Picker(Option.style.title, selection: $model.options.style) {
                            Text("B♭ C♯").tag(AnnotationOptions.LabelStyle.unicode)
                                .accessibilityLabel(AnnotationOptions.LabelStyle.unicode.title)
                            Text("Bb C#").tag(AnnotationOptions.LabelStyle.ascii)
                                .accessibilityLabel(AnnotationOptions.LabelStyle.ascii.title)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                    divider

                    row(.fontSize) {
                        HStack(spacing: 10) {
                            Text("\(model.options.fontSize, format: .number.precision(.fractionLength(1))) pt")
                                .font(.system(size: 15).monospacedDigit())
                                .foregroundStyle(Brand.ink)
                            Stepper(Option.fontSize.title, value: $model.options.fontSize,
                                    in: AnnotationOptions.fontSizeRange, step: AnnotationOptions.fontSizeStep)
                                .labelsHidden()
                        }
                    }
                    divider

                    row(.labelColor) {
                        ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                            .labelsHidden()
                    } below: {
                        colorSwatches
                    }
                    divider

                    row(.dpi) {
                        Picker(Option.dpi.title, selection: $model.options.dpi) {
                            Text("Auto").tag(Int?.none)
                            ForEach(AnnotationOptions.dpiChoices, id: \.self) { dpi in
                                Text("\(dpi) DPI").tag(Int?.some(dpi))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Brand.ink)
                    }
                    divider

                    row(.octave) {
                        Toggle(Option.octave.title, isOn: $model.options.octave)
                            .labelsHidden()
                            .tint(Brand.accent)
                    }
                    divider

                    row(.autoRetry) {
                        Toggle(Option.autoRetry.title, isOn: $model.options.autoRetry)
                            .labelsHidden()
                            .tint(Brand.accent)
                            .disabled(model.options.dpi != nil)
                    } below: {
                        if model.options.dpi != nil {
                            Text("Only used while DPI is Auto.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Brand.inkSoft)
                        }
                    }
                }
                .background(Brand.card, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.paperDeep, lineWidth: 1))
            }
        }
    }

    /// The current choices in a line, for when the options are hidden.
    private var optionsSummary: String {
        let options = model.options
        let color = AnnotationOptions.labelColorPresets
            .first { $0.hex == options.labelColor.uppercased() }?.name ?? "Custom color"
        let size = options.fontSize.formatted(.number.precision(.fractionLength(1)))
        return [options.style == .unicode ? "B♭ C♯" : "Bb C#", "\(size) pt", color].joined(separator: " · ")
    }

    private var colorSwatches: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationOptions.labelColorPresets, id: \.hex) { preset in
                let selected = model.options.labelColor.uppercased() == preset.hex
                Button {
                    model.options.labelColor = preset.hex
                } label: {
                    Circle()
                        .fill(Color(hexString: preset.hex))
                        .frame(width: 28, height: 28)
                        .padding(4)
                        .overlay(Circle().stroke(selected ? Brand.ink : .clear, lineWidth: 2))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.leading, -8)
    }

    /// The system colour picker, for anything the presets don't cover.
    private var customColor: Binding<Color> {
        Binding {
            Color(hexString: model.options.labelColor)
        } set: { color in
            model.options.labelColor = color.hexString
        }
    }

    private func row<Control: View>(_ option: Option, @ViewBuilder control: () -> Control) -> some View {
        row(option, control: control) { EmptyView() }
    }

    private func row<Control: View, Below: View>(_ option: Option,
                                                 @ViewBuilder control: () -> Control,
                                                 @ViewBuilder below: () -> Below) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text(option.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Brand.ink)
                helpButton(option)
                Spacer(minLength: 8)
                control()
            }
            .frame(minHeight: 44)

            if openHelp == option {
                Text(option.help)
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }
            below()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private func helpButton(_ option: Option) -> some View {
        let open = openHelp == option
        return Button {
            withAnimation(.snappy(duration: 0.2)) { openHelp = open ? nil : option }
        } label: {
            Image(systemName: open ? "questionmark.circle.fill" : "questionmark.circle")
                .font(.system(size: 15))
                .foregroundStyle(Brand.inkSoft)
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(option.title)")
    }

    private var divider: some View {
        Rectangle()
            .fill(Brand.paperDeep)
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

/// The upload options, with the web app's explanations.
private enum Option: Hashable {
    case style, fontSize, labelColor, dpi, octave, autoRetry

    var title: String {
        switch self {
        case .style: "Label style"
        case .fontSize: "Font size"
        case .labelColor: "Note name color"
        case .dpi: "Force DPI"
        case .octave: "Show octave number"
        case .autoRetry: "Auto re-scan"
        }
    }

    var help: String {
        switch self {
        case .style:
            "Unicode uses musical accidental symbols such as B♭ and C♯. ASCII uses plain-text Bb and C#, which can be easier to copy into older software."
        case .fontSize:
            "Controls the printed note-label size. Larger labels are easier to read but have less room around dense chords."
        case .labelColor:
            "The color the note names are printed in. Dark colors are easiest to read on white paper."
        case .dpi:
            "Controls the scan resolution used for recognition. Leave it on auto for most sheets; 300 DPI can help a blurry scan but takes longer to process."
        case .octave:
            "Adds the scientific octave number to every label, such as B♭4. This identifies the exact piano key but makes each label longer."
        case .autoRetry:
            "Automatically scans a page again at higher resolution when unusually few notes are found. It can improve difficult pages but increases processing time."
        }
    }
}

/// Two names as they'll be printed, so style, size, octave and colour can be
/// judged before uploading.
private struct LabelPreview: View {
    let options: AnnotationOptions

    var body: some View {
        HStack {
            Text("Preview")
                .font(.system(size: 13))
                .foregroundStyle(Brand.inkSoft)
            Spacer()
            Text(sample)
                // Labels are printed in points on the page; this scale matches
                // how a sheet reads at its fitted width on a phone.
                .font(.system(size: options.fontSize * 2.2))
                .foregroundStyle(Color(hexString: options.labelColor))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(.white, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.paperDeep, lineWidth: 1))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var sample: String {
        let names = options.style == .unicode ? ["B♭", "F♯"] : ["Bb", "F#"]
        let octaves = options.octave ? ["4", "5"] : ["", ""]
        return zip(names, octaves).map { $0 + $1 }.joined(separator: "   ")
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

private extension Color {
    /// From "#RRGGBB"; black if it isn't one.
    init(hexString: String) {
        self.init(hex: AnnotationOptions.isValidColor(hexString)
                  ? UInt32(hexString.dropFirst(), radix: 16) ?? 0 : 0)
    }

    /// "#RRGGBB" in sRGB, the form the backend takes.
    var hexString: String {
        let resolved = resolve(in: EnvironmentValues())
        func byte(_ component: Float) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(resolved.red), byte(resolved.green), byte(resolved.blue))
    }
}

#Preview {
    AddSheetView { _ in }
}
