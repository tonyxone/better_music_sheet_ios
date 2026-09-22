// swift-tools-version: 6.0
import PackageDescription

// The simulator on this machine cannot render (its GPUs are Metal 2; the iOS
// 26 runtime needs Metal 3), which takes `xcodebuild test` off the table here.
//
// This package compiles the SAME source files as the app target — no copies,
// no second source of truth — so the platform-independent layer can be built
// and tested natively on macOS with `swift test`. The Xcode project remains
// the thing that ships; this is how the logic underneath it gets verified.
//
// Only Foundation/Security-based code belongs here. Anything that imports
// SwiftUI stays in the app target and is not listed below.
let package = Package(
    name: "BetterMusicSheetCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    targets: [
        .target(
            name: "better_music_sheet_ios",
            path: "better_music_sheet_ios",
            // PaywallView imports SwiftUI, so — like the rest of the UI —
            // it stays app-target-only even though it lives in Subscription/
            // alongside the StoreKit/Foundation code that is tested here.
            exclude: ["App", "Library", "UI", "Screens", "Assets.xcassets", "Subscription/PaywallView.swift"],
            sources: ["Models", "Networking", "Auth", "Config", "Playback", "Sheet", "Upload", "Subscription"]
        ),
        .testTarget(
            name: "better_music_sheet_iosTests",
            dependencies: ["better_music_sheet_ios"],
            path: "better_music_sheet_iosTests"
        ),
    ]
)
