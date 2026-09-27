import SwiftUI

@main
struct BetterMusicSheetApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                // The app's paper/ink identity (see Brand.swift) has no dark
                // palette — without this, a device in system Dark Mode
                // renders system-styled chrome (navigation titles, etc.) in
                // white, unreadable against the app's fixed light
                // backgrounds. Forcing light appearance keeps every screen
                // consistent regardless of the device's own setting.
                .preferredColorScheme(.light)
                .task {
                    SubscriptionManager.shared.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await SubscriptionManager.shared.syncCurrentEntitlement() }
                    }
                }
        }
    }
}
