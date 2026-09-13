import SwiftUI

/// One stack, rooted in the library. Play is a mode of a sheet rather than a
/// separate destination, so there is no tab bar here.
struct RootView: View {
    var body: some View {
        NavigationStack {
            LibraryView()
        }
        .tint(Brand.accent)
    }
}
