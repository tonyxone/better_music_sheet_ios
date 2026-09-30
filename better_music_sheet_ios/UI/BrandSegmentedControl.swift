import SwiftUI

/// A segmented choice in the brand red: the chosen segment filled, the rest
/// outlined. Used where one view offers a choice about itself — the sheet's
/// version, and letters or jianpu — so those read as one family and stand
/// out from the plain buttons beside them.
struct BrandSegmentedControl<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, title: String, spoken: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selected ? Color.white : Brand.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(selected ? Brand.accent : Color.clear, in: .rect(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.spoken)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Brand.accent, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
