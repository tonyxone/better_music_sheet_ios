import SwiftUI

/// One stack, rooted in the library. A sheet has two pages — reading it and
/// practising it — and either can be opened straight from the library.
struct RootView: View {
    @State private var path: [SheetRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView(path: $path)
                .navigationDestination(for: SheetRoute.self) { route in
                    switch route.page {
                    case .sheet:
                        SheetDetailView(route: route)
                    case .practice:
                        PracticeView(jobID: route.jobID, title: route.provisionalName)
                    }
                }
        }
        .tint(Brand.accent)
    }
}
