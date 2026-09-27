import SwiftUI

/// The tile beside a sheet in the library: the same 🎼 on gold that
/// "Try a sample" uses, so the sample and your own sheets read as one set.
struct SheetThumbnail: View {
    var body: some View {
        Text("🎼")
            .font(.system(size: 24))
            .frame(width: 42, height: 54)
            .background(Brand.gold.opacity(0.16), in: .rect(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}
