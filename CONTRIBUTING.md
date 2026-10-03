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

| Path | What |
|---|---|
| `App/` | The app target, which only wires the modules together |
| `YTNotchKit/` | The Swift package: `PlayerCore`, `WebPlayer`, `NotchUI`, `SystemMedia` |
| `docs/design.md` | How the app looks and behaves |
| `docs/design/brand/` | The icon and disk image, and `make-assets.swift`, which draws them |

A development build adds Debug › Notch State to the menu, which forces each notch state. To watch the app's log:

```bash
log stream --level info --predicate 'subsystem == "io.github.kasra-r77.ytnotch"'
```

## When the site changes

Most fixes for a change on YouTube Music's side belong in the `PAGE` table at the top of `YTNotchKit/Sources/WebPlayer/Resources/bridge.js`, the only place that knows the site. Update the fixture page the bridge is tested against (`YTNotchKit/Tests/WebPlayerTests/Fixtures/fake-player.html`) to match, and try the change against the real site (sign in, play, pause, next, seek, like, and both lists) before the pull request merges.

## Releases and updates

`scripts/make-dmg.sh` builds the disk image into `dist/` (`brew install create-dmg` for the styled window). Pushing a tag such as `v0.1.0` makes the Release workflow build it and publish a GitHub release. The release carries the image twice, as `YT-Notch-<version>.dmg` and as `YT-Notch.dmg`, which the README's Download button links to. For each release, raise `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` first.

Updates come through [Sparkle](https://sparkle-project.org), and stay off until the update key exists. To set it up once, after a first `scripts/make-dmg.sh` run:

1. Make the key pair; the private key goes into your login keychain, and the public key is printed:

   ```bash
   build/release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

2. Put the public key in `project.yml` as `SUPublicEDKey`.
3. Give the private key to the Release workflow:

   ```bash
   build/release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-key.txt
   gh secret set SPARKLE_PRIVATE_KEY < sparkle-key.txt
   rm sparkle-key.txt
   ```

4. Back up the private key. Without it, installed copies can't be updated.

Each release then carries a signed `appcast.xml`, and installed copies pick it up within a day.

## Never

- Ad blocking, downloading, or extracting audio.
- Calls to Google's internal API.
- Private Apple frameworks.
- Code copied from GPL projects.
- Logging what someone plays or anything from their account.

## Licence

By contributing you agree that your work is released under the [Apache License 2.0](LICENSE).
