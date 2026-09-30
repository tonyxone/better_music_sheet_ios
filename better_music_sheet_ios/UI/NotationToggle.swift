import SwiftUI

/// Letter names (C D E…) or jianpu numbers with 1 = C (1 2 3…, see
/// Notation.swift), styled like the Annotated/Original choice beside it,
/// since it is the same kind of choice about one view. The choice is shared:
/// switching here switches the reading page, Practice, the keyboard and the
/// falling notes together.
struct NotationToggle: View {
    /// The notation the sheet was made with, shown until the reader chooses.
    let fallback: Notation?

    @State private var preference = NotationPreference.shared

    var body: some View {
        BrandSegmentedControl(
            label: "Note names",
            options: Notation.allCases.map { ($0, $0.title, $0.spokenTitle) },
            selection: Binding(get: { preference.notation(fallback: fallback) },
                               set: { preference.choose($0) }))
            .accessibilityHint("Shows note names as letters, or as jianpu numbers with 1 as C")
    }
}
