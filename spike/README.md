# Phase 0 spike (throwaway)

A minimal Mac app with one visible web view on music.youtube.com. It uses a current Safari user agent and WebKit's default persistent data store. It exists to answer the questions behind gate G0 (YT-13), and is deleted once the gate passes. Results go in [`docs/spike-report.md`](../docs/spike-report.md).

## Build and run

```bash
./spike/build-app.sh
open spike/build/YTNotchSpike.app
```

The script builds with SwiftPM and wraps the binary in an ad hoc signed `.app` with its own bundle identifier (`io.github.kasra-r77.ytnotch.spike`). The data store belongs to that identifier, so the spike's login is separate from Safari's and from the real app's.

## Spike menu

- **Check Sign-in (⌘I)**: shows whether the YouTube Music sign-in cookies exist. It reports names and domains only, never values.
- **Reload (⌘R)** and **Go to YouTube Music (⌘H)**
- **Hide Player Window (⇧⌘H)**: moves the web view's window far off-screen and turns the spike into a menu bar app (S0.2). From then on, use the music-note icon in the menu bar to show the window again, play or pause, see the playback summary, or quit.
- **Playback Summary…**: totals from the playback monitor.
- **Delete Website Data…**: signs the spike out by removing its own cookies and storage.

The web view can be inspected: right-click the page and choose Inspect Element.

## From the command line

```bash
spike/build/YTNotchSpike.app/Contents/MacOS/YTNotchSpike --check-sign-in
```

This prints the same cookie report without opening a window. It exits 0 when signed in and 1 otherwise.

`--policy suspend|throttle|none` sets WebKit's inactive scheduling policy; the default is `none`.

## Logs

- `~/Library/Logs/YTNotchSpike.log`: navigation, user actions and summaries.
- `~/Library/Logs/YTNotchSpike-playback.csv`: one row every 5 seconds with the position, the pause state, stall checks and media event counts, plus rows for display sleep and wake and Space changes. Track titles are never written.
