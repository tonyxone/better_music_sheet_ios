# BetterMusicSheet iOS — native app plan

A **native iOS app designed for iOS**, sharing the backend and the music math with
the web app (`../BetterMusicSheet`) — not a port of its UI.

Two layers, two different rules:

- **Shared exactly (correctness, not design):** the REST contract, the beat/tempo
  clock, note and measure geometry (`bbox_pt`), corrections semantics, the
  free-tier gating rule. Re-deriving these produces bugs that only show up on a
  real score; they get ported line for line and tested against shared fixtures.
- **Designed from scratch for iOS (everything else):** information architecture,
  ingest, processing feedback, the practice experience, gestures, typography,
  navigation. The web's screens are a reference for *what the product does*, not
  for what the app looks like.

No OMR on device. Audiveris, annotation and timeline-building stay on the
existing FastAPI backend, which needs **no changes** for v1 (see §8 for the one
exception worth considering).

Current state: fresh Xcode SwiftUI template, iOS 26.2 target, bundle id
`tonyxone.better-music-sheet-ios`, file-system-synchronized groups (new `.swift`
files need no `project.pbxproj` edits).

---

## 1. What the app is, natively

The web app is a *tool you visit with a PDF*. The iOS app is **a practice
instrument you keep your music in**. That single shift drives the redesign:

| | Web | iOS |
|---|---|---|
| Home | Upload form | **Your library of sheets**; adding is a `+`, and the empty state does the onboarding |
| Getting music in | One file input | Share extension, Files, Photos, **camera scan**, iPad drag-and-drop, "Open in" |
| Waiting for a job | A page you must keep open | **Live Activity + notification**; close the app, get told when it's ready |
| Reading result | Preview + download button | The sheet *is* the document; Share/Files export is secondary |
| Playing | One dense desktop page | **Two purpose-built modes** — Read (portrait) and Practice (landscape) |
| Editing a wrong note | Dropdown in a `<details>` panel | **Tap the note on the sheet**, edit in an inspector |
| Sign-in | Email/password modal | Sign in with Apple first, email/password second |

## 2. Information architecture

```
Library (root)
├── + Add sheet ──▶ Scan · Photos · Files   (also arrives via Share extension)
├── Sheet row: processing (inline progress) | ready | failed
└── Sheet ──▶ Sheet detail
              ├── Read mode   (portrait: the annotated sheet, full width)
              ├── Practice    (landscape: roll + 88 keys, sheet optional)
              └── ⋯ Export PDF · Annotation settings · Delete
Settings: account, default annotation options, sound, about/licenses
```

No tab bar clone of the web's routes. One stack, rooted in the library, with the
play experience as a mode *of a sheet* rather than a separate destination.

## 3. Ingest — the biggest native win

The web can only offer a file picker. iOS should accept music the way it actually
reaches people:

1. **Share extension** — share a PDF straight out of Mail, Safari, Files or
   IMSLP into the app; annotation starts without ever opening the app.
2. **Camera scan** (`VNDocumentCameraViewController`) — multi-page capture with
   edge detection and perspective correction, rendered to one PDF locally. This
   is the flow most people will use on a phone, and the web has no equivalent.
3. **Files / Photos** pickers, iPad **drag-and-drop**, and `CFBundleDocumentTypes`
   so BetterMusicSheet appears in "Open in" for PDFs.

Annotation options (label style, font size, DPI, octave numbers, auto re-scan)
are **defaults in Settings**, not a form on the way in — with a compact
"Adjust" affordance for the one upload in twenty that needs it. The web's five
fields with `?` buttons become two presets (Standard / Large labels) plus an
Advanced disclosure.

## 4. Processing — no status page

Uploading uses a **background `URLSession`**, so a big scan finishes even if the
app is backgrounded or killed. While the job runs:

- the library row shows live stage text inline;
- a **Live Activity** (Lock Screen + Dynamic Island) carries the same stage;
- a **local notification** fires on completion or failure;
- polling backs off in the background and resumes on foreground.

The user never sits on a spinner page — that's a web constraint, not a product
requirement.

## 5. The practice experience

This is the app's reason to exist and deserves the most design work. The web
crams sheet, note roll, 88 keys and a transport onto one desktop page with
collapsible panels. On iPhone that layout is unusable; split it by intent.

**Read mode (portrait).** The annotated sheet, full-width, pinch-zoomable,
continuous scroll. A floating transport capsule at the bottom (play/pause,
position, speed). The keyboard is a slim optional strip. This is the "prop the
phone on the music stand and read" mode.

**Practice mode (landscape).** Full-bleed note roll above an 88-key board — the
only orientation where 88 keys are legible on a phone. The sheet becomes a
peek-able overlay. This is the "learn the notes" mode.

**iPad / Stage Manager.** The one place the web's simultaneous layout genuinely
works: sheet, roll and keyboard together, with the sheet getting the space.

**Interaction is gestural, not button-driven.**
- Tap a measure → play from there; tap and hold → **loop that measure** (looped
  practice is the single most requested feature of tools like this, and the
  backend data already supports it).
- Drag across measures → set a loop range.
- Pinch → zoom the sheet; the playhead and measure overlays scale with it.
- Scrub by dragging the position capsule; haptic tick on each downbeat.
- Speed as a native menu of common values (¼×, ½×, ¾×, 1×) plus fine control,
  rather than a raw slider.

**System integration the web can't have:** background audio, Lock Screen and
AirPods transport controls (`MPNowPlayingInfoCenter`), AirPlay, interruption and
route-change handling, keep-awake while playing.

**Corrections by direct manipulation.** Tap a wrong note *on the sheet* → an
inspector with a pitch wheel, hand toggle, beat and duration steppers. The web's
"choose a measure, then choose a note from a dropdown" indirection disappears.
Warnings and recognition stats become a quiet banner, not a `<details>` list.

## 6. Visual design

Keep the brand, express it natively. The web's warm paper/ink identity
(`#FAF3E6` paper, `#2E2117` ink, `#A83C34` accent, Spectral + Work Sans) is
distinctive and worth carrying — as a **semantic color set and custom Dynamic
Type text styles**, not as ported CSS. Native structure (SF Symbols, system
materials, standard navigation and sheets) underneath it.

Two things this forces that the web never had to decide:

- **Dark mode.** The web is paper-only. A practice app used on a music stand in
  a dim room needs a real dark reading mode — which means deciding whether the
  sheet itself inverts (usually wrong for engraved music) or sits on a dark
  surround (recommended).
- **The hand colors stay exactly as they are** — blue `#2f6fb5` right,
  green `#3e8e5a` left. They're functional, not decorative, and consistency with
  the web matters for someone using both.

## 7. Phases

Each ships something usable.

**P0 · Foundations (½ day).** xcconfig-driven `AppConfig` (API base, Cognito),
Swift 6 + strict concurrency, folder structure, ATS (localhost exception for
debug only), design-system primitives (colors, type scale, spacing).

**P1 · Data layer (1 day).** `Codable` models for `AnnotationJob`, `MusicSheet`,
`User`, `Timeline`; `APIClient` actor with the web's exact identity rule
(`Authorization` **or** `X-Guest-Id`, never both); guest id + session in Keychain;
the `/assets` → presigned-S3 two-step *including* its 404 fallback and the rule
that S3 fetches carry no auth headers.

**P2 · Library (1 day).** The root screen: list, status, swipe-to-delete,
pull-to-refresh, empty-state onboarding.

**P3 · Ingest (1.5–2 days).** Scanner, Photos, Files, background upload,
share extension, document types. Settings-based annotation defaults.

**P4 · Processing feedback (1 day).** Polling service, Live Activity, local
notifications, background refresh.

**P5 · Read mode (1.5 days).** PDFKit sheet with measure overlays from `bbox_pt`
(note the PyMuPDF top-down → PDFKit bottom-up **y-flip**), zoom, export via
share sheet.

**P6 · Music engine (2–3 days, headless).** Port `tempo.ts`, `timeline.ts`,
`corrections.ts` to Swift *exactly*, with unit tests against JSON fixtures
exported from real jobs. Then `AVAudioEngine` + `AVAudioUnitSampler` over a
**bundled SF2** (grand, electric, organ) — which deletes the web's entire
sample-download/progress/cache path — and the scheduler from `playback.ts`
(100 ms lookahead, 25 ms tick, 4-beat count-in, one audio clock for both sound
and visuals). No UI in this phase; correctness is verified by tests.

**P7 · Practice mode (3–4 days).** Keyboard (`keyboard-layout.ts`'s geometry
ported verbatim — the black-key offsets are what make it look real), note roll,
transport, looping, gestures, haptics, orientation-driven mode switch, Now
Playing integration, free-tier gate (`FREE_LINES = 2`).

**P8 · Corrections (1 day).** Tap-to-edit inspector, local per-sheet persistence.

**P9 · Auth (1–1.5 days).** See §8.

**P10 · Polish & release (2 days).** VoiceOver, Dynamic Type, iPad multitasking,
app icon, `PrivacyInfo.xcprivacy`, TestFlight.

## 8. Auth — the one place a backend change may be worth it

The backend today verifies a **Cognito ID token** and mints its own JWT; the
user pool allows `USER_PASSWORD_AUTH` and lists only `COGNITO` as an identity
provider, with web-only callback URLs. So:

- **Email/password works today**, natively, with the same unauthenticated
  `cognito-idp` JSON calls the web makes — no AWS SDK, tokens in Keychain,
  AutoFill and Passwords app support for free.
- **Sign in with Apple** is what iOS users expect and is the single strongest
  conversion lever for the sign-in-gated playback. It needs either Apple added
  as a Cognito IdP plus `ASWebAuthenticationSession` against the hosted UI (infra
  change, no server code), or a small `POST /api/auth/apple` that verifies an
  Apple identity token directly (server change, best native UX).

Recommendation: ship P9 with email/password, then add Sign in with Apple before
the App Store submission — Apple does not *require* it when you offer only your
own email sign-in, but on a paywalled-feature app it's worth having regardless.

## 9. Native-only opportunities (post-v1, worth knowing now)

- **CoreMIDI input** — connect a digital piano and check what you actually play
  against the score. For a "learn to read music" app this is the obvious next
  product, and the timeline data already supports it.
- **App Intents / Shortcuts** — "Practice Menuet in G" from Siri or the Action button.
- **Widget** — recent sheets on the Home Screen.
- **CloudKit** sync of corrections and library across devices.
- **Handoff** from the web app.

## 10. Open decisions

1. **Dark mode treatment of the sheet** — dark surround with the sheet left
   white (recommended) vs inverted engraving.
2. **Brand vs system look** — carry the paper/ink identity (recommended) or go
   fully neutral-native.
3. **Sign in with Apple** — infra change (Cognito IdP) vs server change
   (`/api/auth/apple`) vs defer.
4. **License.** The web/backend repo is AGPL-3.0. A native redesign written
   against the public HTTP API is naturally an independent work — but the P6
   engine port *is* derived from AGPL sources, and AGPL on the App Store
   conflicts with Apple's distribution terms. Decide before P6 whether that code
   is clean-roomed from the data format or the app ships AGPL.

## 11. Risks

- **Timeline fidelity.** Playhead, roll and keyboard all hang off `bbox_pt` and
  beat math; a y-flip or tie-chain error is invisible until it looks wrong on a
  real score. Shared fixtures in P6 are the mitigation.
- **One clock.** Audio scheduling and the visual frame loop must read the same
  engine clock, or they drift apart audibly.
- **Presigned upload expiry** (15 min) on slow cellular — must fail with that
  explanation, not a generic error.
- **Audiveris is slow.** The Live Activity has to stay honest about long jobs.
