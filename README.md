# BetterMusicSheet for iOS

A native iOS client for [BetterMusicSheet](https://bettermusicsheet.com) — it
reads the notes on a piano score and pencils in the letter name of every one,
then plays the piece back with the keys lit up.

The optical music recognition stays on the existing backend. This app is a
REST client plus native re-implementations of everything the browser used to
do locally: PDF rendering, audio scheduling, the keyboard and note roll, and
the correction store.

## Design

This is a native redesign, not a port of the web UI. The web app's home is an
upload form because a visitor arrives cold with a file; an installed app opens
on your music instead. See [docs/ios-app-plan.md](docs/ios-app-plan.md) for the
reasoning and the phase plan, and `design/` for the screen artboards.

Two layers, two different rules:

- **Shared exactly** — the REST contract, the beat and tempo clock, note and
  measure geometry, corrections semantics, the free-tier rule. Re-deriving
  these produces bugs that only show up on a real score, so they are ported
  line for line and covered by tests.
- **Designed for iOS** — everything above that.

## Building

Open `better_music_sheet_ios.xcodeproj` in Xcode 26 or later. The app targets
iOS 26.2 and builds in the Swift 6 language mode.

`AppConfig` points at the production API by default. To use a local
`server.py`, set the override at runtime:

```swift
AppConfig.setAPIBaseOverride("http://localhost:8000")
```

Plain-HTTP localhost also needs an App Transport Security exception.

## Tests

```bash
swift test
```

`Package.swift` compiles the **same** source files as the app target — there is
no second copy — so the platform-independent layer can be tested natively on
macOS without a simulator. This matters more than it sounds: the simulator
cannot run on every Mac (an older GPU aborts `SimMetalHost`), and these are the
parts where correctness actually lives.

Note that SwiftPM defaults to `nonisolated` while the app target compiles with
main-actor-by-default isolation, so a green `swift test` does not by itself
prove the app compiles. Build both.

## License

[GNU AGPL v3.0](LICENSE), inherited deliberately: the playback core here is
derived field-for-field from the AGPL-3.0 BetterMusicSheet project. Note that
AGPL/GPLv3 terms are in tension with App Store distribution, which is worth
settling before shipping a build.
