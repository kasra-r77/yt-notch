# Working on YT Notch

Read this before changing anything. Work is tracked in [GitHub issues](https://github.com/kasra-r77/yt-notch/issues), and `docs/design.md` describes how the app looks and behaves.

## Standing rules

1. Keep the module rules (below).
2. Google-specific knowledge goes only in `bridge.js`.
3. Public Apple APIs only. No private frameworks.
4. No ad blocking, no downloading, no audio extraction, no calls to Google's internal API.
5. Do not copy code from GPL projects (Boring Notch is GPL-3.0: read it for ideas only).
6. Edit `project.yml`, never the generated Xcode project.
7. New logic comes with tests.
8. No new compiler warnings. The project treats warnings as errors.
9. Explain any design choice the issue or `docs/design.md` doesn't settle in the pull request description.
10. If part of an issue cannot be done as asked, stop and say so in the issue instead of working around it.

## Modules

```
App (thin: wires modules together)
 ├── PlayerCore    state, store, PlayerEngine protocol, FakeEngine
 ├── WebPlayer     the one web view, bridge.js, message passing   → PlayerCore
 ├── NotchUI       notch windows, shapes, views                    → PlayerCore
 └── SystemMedia   Now Playing and media keys                     → PlayerCore
```

- `PlayerCore` imports only Foundation and Observation.
- `WebPlayer`, `NotchUI` and `SystemMedia` import `PlayerCore` and never each other.
- Only `WebPlayer` imports WebKit.
- The app target only wires modules together.

Test support lives in `YTNotchKit/Tests/EngineConformance`: scenarios every `PlayerEngine` must pass. FakeEngine and WebPlayerController both run them, and any new engine must too.

`YTNotchKit/Tests/ArchitectureTests` checks the import rules on every `swift test`. Don't weaken it to make a change pass.

## Architecture rules

- One web view, created at launch, never recreated except by `WebPlayerController`'s crash recovery.
- The store runs on the main actor and is the only writer of state.
- The notch never talks to the web view, and the web view never talks to the notch: everything goes through the store.
- The UI only shows what the bridge reports; it never assumes a command worked.
- Log with `Logger(subsystem: "io.github.kasra-r77.ytnotch", category: <component>)`: one subsystem for the app, one category per component (`WebPlayer` so far). Never log what is playing or anything from the user's account; keep logged values to states, counts and errors.

## Build and test

```bash
xcodegen generate                        # after any change to project.yml
xcodebuild -scheme YTNotch build
swift test --package-path YTNotchKit
```

## How an issue becomes a change

- **One issue = one branch = one pull request.** Name the branch `<issue-number>-<short-name>`, and write `Fixes #<number>` in the PR description.
- The PR description says what changed and how it was checked.
- CI (`.github/workflows/ci.yml`, job "Build and test") must pass before merging; `main` requires it.
- A change to how the app looks needs the owner's agreement in the issue first, and updates `docs/design.md`.

## Reference

- The bridge: `YTNotchKit/Sources/WebPlayer/Resources/bridge.js`. Its page selectors are in the `PAGE` table at the top. Its Swift side is `Bridge.swift`.
- The fixture page the bridge is tested against: `YTNotchKit/Tests/WebPlayerTests/Fixtures/fake-player.html`. Web view tests must wait with `await` (see `BridgeHarness`); spinning the run loop blocks WebKit under `swift test`.
- Design: `docs/design.md`, with sections D1 to D9 that code comments refer to. The icon and disk image are drawn by `docs/design/brand/make-assets.swift`.
- The notch: `YTNotchKit/Sources/NotchUI`. `NotchDisplayManager` keeps one notch per chosen display and follows display, Space and full-screen changes; `NotchPanel` is one display's notch, `ScreenGeometry` what it reads from the screen (never hard-code notch or menu bar sizes), `NotchShape` the spec's path. Hit-test paths with `CGPath.contains`; SwiftUI's `Path.contains` misreads the joined outline.
- Design values: `YTNotchKit/Sources/NotchUI/Tokens.swift` holds the D1 tokens. Sizes and timings come from there, never from literals in code. `HoverMachine` is the hover logic (plain, no views or timers).
- After any change to `bridge.js`, try it against the real site (sign in, play, pause, next, seek, like, and both lists) and say so in the pull request.
