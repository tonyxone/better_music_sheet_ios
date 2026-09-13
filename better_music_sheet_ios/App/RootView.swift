import SwiftUI

/// One stack, rooted in the library. Play is a mode of a sheet rather than a
/// separate destination, so there is no tab bar here.
struct RootView: View {
    @State private var path: [SheetRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView(path: $path)
                .navigationDestination(for: SheetRoute.self) { route in
                    SheetDetailView(route: route)
                }
        }
        .tint(Brand.accent)
    }
}
