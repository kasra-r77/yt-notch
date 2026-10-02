# Contributing

Thanks for helping with YT Notch. It's a small app kept to a few firm rules, so a change goes in more easily when it follows them.

## Before you start

- Read [AGENTS.md](AGENTS.md). It has the module rules, the rules for the bridge, and how a change becomes a pull request.
- For anything bigger than a fix, open an issue first, so we can agree on it before you build it.

## Build and test

```bash
xcodegen generate
xcodebuild -scheme YTNotch build
swift test --package-path YTNotchKit
```

Edit `project.yml`, never the generated Xcode project. The project treats warnings as errors, and new logic comes with tests.

## When the site changes

Most fixes for a change on YouTube Music's side belong in the `PAGE` table at the top of `YTNotchKit/Sources/WebPlayer/Resources/bridge.js`, the only place that knows the site. Update the fixture page the bridge is tested against (`YTNotchKit/Tests/WebPlayerTests/Fixtures/fake-player.html`) to match, and run the [live check](docs/live-check.md) against the site before the pull request merges.

## Never

- Ad blocking, downloading, or extracting audio.
- Calls to Google's internal API.
- Private Apple frameworks.
- Code copied from GPL projects.
- Logging what someone plays or anything from their account.

## Licence

By contributing you agree that your work is released under the [Apache License 2.0](LICENSE).
