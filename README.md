# YT Notch

A free, open-source macOS app that turns the notch into a YouTube Music player. On a MacBook it sits over the real notch; on any other display it draws a notch-shaped pill at the top centre. Hover to expand it into a player with Playing, Playlists and Up next views.

> **Status:** early development, not usable yet.

YT Notch is unofficial and not affiliated with, endorsed by or connected to Google or YouTube. You sign in on Google's own page, and the app loads the real site unmodified, apart from a small bridge script that reads what is playing and presses the site's own controls. It does no ad blocking, no downloading, and makes no calls to Google's internal API.

## Requirements

- macOS 14 or later, Apple silicon or Intel
- To build: Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```bash
xcodegen generate
xcodebuild -scheme YTNotch build
```

The Xcode project is generated from `project.yml` and is not committed. The app is `YT Notch.app` under Xcode's DerivedData; open `YTNotch.xcodeproj` in Xcode to run it from there.

### Running on the real site

Until the web player is wired in for good (I4.1), the app runs on canned tracks. To use YouTube Music instead:

```bash
defaults write io.github.kasra-r77.ytnotch engine web
```

Then open the app and choose **Show Web Player** in its menu to sign in. To go back, run `defaults delete io.github.kasra-r77.ytnotch engine`.

The app logs to the system log under one subsystem. To watch what the web player does, including its recovery steps:

```bash
log stream --level info --predicate 'subsystem == "io.github.kasra-r77.ytnotch"'
```

## Test

```bash
swift test --package-path YTNotchKit
```

## Layout

| Path | What |
|---|---|
| `App/` | The thin app target, which only wires the modules together |
| `YTNotchKit/` | The Swift package: `PlayerCore`, `WebPlayer`, `NotchUI`, `SystemMedia` |
| `docs/design/` | Approved design specs |
| `docs/spike-report.md` | What phase 0 learned about the site |
| `docs/decisions.md` | Choices the plan did not make |
| `spike/` | The phase 0 spike (throwaway) |

Contributors and coding agents: read [AGENTS.md](AGENTS.md) first.

## License

[MIT](LICENSE)
