# Working on YT Notch

Read this before changing anything. The plan is the source of truth for what to build: [YT Notch: architecture and agent build plan](https://claude.ai/code/artifact/ba6e79a8-515e-4999-9f4f-8edc8d25d893). Work is tracked in Jira, project YT, epic YT-1.

## Standing rules

1. Keep the module rules (below).
2. Google-specific knowledge goes only in `bridge.js`.
3. Public Apple APIs only. No private frameworks.
4. No ad blocking, no downloading, no audio extraction, no calls to Google's internal API.
5. Do not copy code from GPL projects (Boring Notch is GPL-3.0: read it for ideas only).
6. Edit `project.yml`, never the generated Xcode project.
7. New logic comes with tests.
8. No new compiler warnings. The project treats warnings as errors.
9. Record any choice the plan did not make in `docs/decisions.md`.
10. If a "done when" point cannot be met, stop and report instead of working around it.

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

- One web view, created at launch, never recreated except by the recovery steps in the plan.
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

## How a ticket becomes a change

- **One ticket = one branch = one pull request.** Name the branch `yt-<number>-<short-name>` and start the PR title with the ticket key.
- The PR description lists the ticket's "done when" points and which ones it met.
- CI (`.github/workflows/ci.yml`, job "Build and test") must pass before merging. GitHub does not enforce this until the repo goes public (YT-39), so check it yourself before merging.
- Build tickets labelled `needs-design` wait for their design ticket's approval. The approved values are in the ticket's "Design spec" section and in `docs/design/`.
- Gate tickets (G0 to G3) are hands-on reviews by the owner.

## Reference

- The bridge: `YTNotchKit/Sources/WebPlayer/Resources/bridge.js`. Its page selectors are in the `PAGE` table at the top. Its Swift side is `Bridge.swift`.
- The fixture page the bridge is tested against: `YTNotchKit/Tests/WebPlayerTests/Fixtures/fake-player.html`. Web view tests must wait with `await` (see `BridgeHarness`); spinning the run loop blocks WebKit under `swift test`.
- Design specs: `docs/design/`: D1 `notch-shapes.md`, D2 `playing-view.md`, D3 `list-views.md`, D4 `message-states.md`, D5 `tokens.md`, D6 `brand/`, D7 `windows-and-menus.md`. Mockups: the D1 canvas and the D2 to D7 canvas, linked at the top of each spec.
- The notch: `YTNotchKit/Sources/NotchUI`. `NotchDisplayManager` keeps one notch per chosen display and follows display, Space and full-screen changes; `NotchPanel` is one display's notch, `ScreenGeometry` what it reads from the screen (never hard-code notch or menu bar sizes), `NotchShape` the spec's path. Hit-test paths with `CGPath.contains`; SwiftUI's `Path.contains` misreads the joined outline.
- Design values: `YTNotchKit/Sources/NotchUI/Tokens.swift` holds the D1 tokens. Sizes and timings come from there, never from literals in code. `HoverMachine` is the hover logic (plain, no views or timers).
- What the site exposes, and what it doesn't: `docs/spike-report.md`
- The live check against the real site: `docs/live-check.md`. Run it after any change to `bridge.js` and record the run there.
- Decisions outside the plan: `docs/decisions.md`
