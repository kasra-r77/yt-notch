# YT Notch

![YT Notch: the Playing view open in a MacBook's notch](docs/images/hero.png)

A free, open-source Mac app that turns the notch into a YouTube Music player. Hover the notch to see what's playing, skip songs, start a playlist or jump ahead in Up next. On a Mac without a notch, it draws a small pill at the top of the screen instead.

> **Unofficial.** Not affiliated with, endorsed by or sponsored by Google or YouTube. YouTube Music is a trademark of Google LLC.

YT Notch plays the real YouTube Music website in a window of its own, signed in with your account. There's no ad blocking and no downloading.

![The Playing, Playlists and Up next views](docs/images/views.png)

## Install

1. Download the latest `.dmg` from [Releases](https://github.com/kasra-r77/yt-notch/releases).
2. Open it and drag **YT Notch** to **Applications**.
3. Open YT Notch. The first time, macOS blocks it because the app isn't notarised by Apple:
   1. Close the message.
   2. Go to **System Settings › Privacy & Security**, scroll down, and click **Open Anyway** next to "YT Notch was blocked".
   3. Confirm, then click **Open**.

   You only do this once. Or, in Terminal: `xattr -dr com.apple.quarantine "/Applications/YT Notch.app"`.

Requires macOS 14 or later, on Apple silicon or Intel.

## Get started

1. On first launch, YT Notch opens YouTube Music. Sign in on Google's page as usual. YT Notch never sees your password.
2. When it says you're signed in, click **Close Window**. The music keeps playing.
3. Play something, then hover the notch.

To search or browse, open the window from the menu bar icon › **Open YT Notch Window**.

## Use

- **Hover the notch** to open it.
  - **Playing** has the controls.
  - **Playlists** starts one of your playlists.
  - **Up next** jumps to a song in the queue.
- **On screens without a notch,** a pill at the top shows the song and its progress, and moves aside for other apps' menu bar icons.
- **Media keys, headphone buttons and Control Centre** work as with any music app.
- **The menu bar icon** opens the window, Settings and updates. A dot on it means something needs you, like signing in.

## Troubleshooting

- **"No connection":** YT Notch keeps retrying; **Try Again** in the menu retries at once.
- **"Player needs an update":** YouTube Music changed. Music still plays in the window. Open an issue with the **Player stopped working** template and paste **Copy Diagnostics** from the menu, which holds nothing from your account.
- **Anything else:** open a **Bug report**.

## Privacy

YT Notch talks only to YouTube Music, plus a daily check for app updates. It keeps no record of what you play and has no analytics.

## Build from source

You need Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
xcodebuild -scheme YTNotch build
swift test --package-path YTNotchKit
```

Open `YTNotch.xcodeproj` in Xcode to run it. To try the app without an account, switch it to built-in sample songs:

```bash
defaults write io.github.kasra-r77.ytnotch engine fake
```

To switch back, run `defaults delete io.github.kasra-r77.ytnotch engine`.

See [CONTRIBUTING.md](CONTRIBUTING.md) to help out.

## License

[Apache License 2.0](LICENSE). If you reuse the code, keep the [LICENSE](LICENSE) and [NOTICE](NOTICE) files with it. YT Notch includes [Sparkle](https://sparkle-project.org) (MIT); see [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).
