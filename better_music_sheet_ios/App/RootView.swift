import SwiftUI

/// One stack, rooted in the library. A sheet has two pages — reading it and
/// practising it — and either can be opened straight from the library.
struct RootView: View {
    @State private var path: [SheetRoute] = []
    /// Not stored, so a guest sees the welcome splash again each time the
    /// app starts fresh (but not when it merely comes back from the
    /// background) — except a returning signed-in visitor, who skips it
    /// outright rather than tapping through onboarding to reach their own
    /// library every launch. Computed synchronously (a plain Keychain
    /// existence check, not the full session decode `current()` does) so
    /// the splash never flashes on screen only to be dismissed a moment
    /// later once the async check would have resolved.
    @State private var welcomeSeen = SessionStore.hasStoredSession()
    @State private var entitlements = EntitlementStore.shared

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView(path: $path)
                .navigationDestination(for: SheetRoute.self) { route in
                    switch route.page {
                    case .sheet:
                        SheetDetailView(route: route)
                    case .practice:
                        // Practice mode is premium-gated; a signed-in
                        // free-tier or guest visitor sees the paywall in
                        // place of the practice screen itself.
                        if entitlements.isEntitled {
                            PracticeView(jobID: route.jobID, title: route.provisionalName)
                        } else {
                            PaywallView()
                        }
                    }
                }
        }
        .tint(Brand.accent)
        // Over the library rather than instead of it, so the library has
        // already loaded by the time Get Started reveals it.
        .fullScreenCover(isPresented: Binding(get: { !welcomeSeen }, set: { welcomeSeen = !$0 })) {
            WelcomeView { welcomeSeen = true }
        }
    }
}
