# Design

How YT Notch looks and behaves. Every size, colour and timing lives in `YTNotchKit/Sources/NotchUI/Tokens.swift`; code reads values from there, never from literals. Notch and menu bar sizes are read from each screen at runtime, never hard-coded. The section labels (D1–D9) are the ones code comments refer to.

## The notch (D1)

The notch is always black (`#000000`) in light and dark mode, with white text at 100% or 60%. It never tints or blurs the menu bar around it.

| State | Shape |
|---|---|
| Idle, built-in display | Exactly the hardware notch: invisible, but hoverable. No flare. |
| Idle, other displays | A 190 wide pill, menu bar height, centred on the top edge. |
| Playing | Wings grow 44 out of each side: artwork on the left, four moving bars in the accent on the right. Nothing is drawn where the real notch is. Pausing keeps the wings; only having no track loaded removes them. |
| Peek | On a track change while collapsed, the title and artist slide out in a 26 row under the notch, hold 2.5 s, and slide back. |
| Expanded | 400 × 148 for Playing, 400 × 300 for the lists. A 32 band at the top stays clear of the real notch. Bottom radius 24, flare 12, and a shadow while open. |

The bottom corners are continuous; the flare is the concave curve where the shape meets the top edge and bends into the menu bar. The flares are part of the hit area, and everything outside the shape passes clicks through.

**Hover.**

| From | Trigger | Result |
|---|---|---|
| Collapsed | The pointer rests in the shape for 150 ms | Opens |
| Open | The pointer leaves | Closes after 400 ms, unless it comes back first |
| Any | A mouse button is held (dragging along the top edge) | The dwell doesn't start |

Other hover rules:
- The notch reopens on Playing, unless it closed less than 10 s ago; then it reopens on the last view.
- Opening never takes keyboard focus.

**Motion.**
- One spring (response 0.35, damping 0.8) drives opening, closing, the peek and resizing. It moves width, height, radius and flare together, anchored at the top centre, and retargets if interrupted.
- Content never scales: it fades in from 60% open and fades out on close.
- Under Reduce Motion, shapes crossfade instead and the bars stand still.

**Accent.** The artwork's dominant colour, used on the progress fill and the bars only. If it is too dark on black (under 3:1), its lightness rises to 3:1. Near grey, or no artwork, falls back to white.

**Displays and full screen.**
- Every display shows the same track, but hover and expansion belong to each display.
- A setting picks which displays show a notch.
- When a full-screen app takes a display, that display's notch fades out and closes at once. On the built-in display, wings, peek and hover are turned off so nothing covers the app.

## Playing view (D2)

400 × 148:
- **Band:** the view switcher (Playing, Playlists, Up next, as icon tabs) in the left ear; Like and Open in the right ear.
- **Artwork:** 84 square at radius 10.
- **Text column:** the title and artist, a progress row (elapsed, track, total), and five controls (shuffle, previous, play or pause, next, repeat).

Rules:
- **Shows only what the page reports.** Like, play state and modes change when the player says so, never ahead of it.
- **Long text:** titles and artists are cut at the tail and never scroll; the help tag has them in full.
- **Seeking:** a knob shows on hover, and seeking happens on release (Escape cancels).
- **Buffering:** a spinner replaces play or pause.
- **Shuffle and repeat:** on is white with a dot, off is 60%. Repeat cycles off, all, one.
- **Unavailable controls:** shown at 25%.
- **Hit targets:** every target is at least 28 × 28. Transport controls share the row in 44 wide columns, so a click between two lands on the nearer one.

## Playlists and Up next (D3)

400 × 300: the band, then 48 tall rows, five in view, scrolling under the band with fades at the edges.
- **Playlists:** Liked music first, then the library in the site's sidebar order. Each row has an icon tile (the site gives no playlist pictures).
- **Up next:** the queue as the page shows it, with artwork, title, artist and length. Autoplay suggestions are left out.
- **Playing row:** white 10%, a semibold title, and three accent bars. The list opens scrolled to it.
- **Click:** plays the playlist or jumps to the track. The marker moves when the player reports the change.
- **Saved list:** a remembered playlist list shows while the sidebar can't be read, under "Saved list · may be out of date".
- **Hidden tabs:** a tab with no data hides. Playing is always there.

## Messages (D4)

When the notch can't play, opening it shows one message and at most one button, in the 400 × 148 frame:

| State | Message | Button |
|---|---|---|
| Signed out | Sign in to YouTube Music | Sign In: opens the full window |
| No connection | No connection | Try Again |
| Player broken | Player needs an update | Open Full Window |
| Loading | Loading YouTube Music… | none |

The collapsed notch never shows these; the menu bar icon gets a dot instead. When only part of the page can't be read, only that part changes:
- controls dim
- the progress row fades to 40%
- shuffle and repeat hide
- the list tabs hide

## Tokens (D5)

All values are in `Tokens.swift`, under the names the views use:
- **Colours:** black surface; white at set opacities for text, fills and the track.
- **Type:** SF Pro, at 13, 12, 11 and 10.
- **Layout:** an 8 pt grid; radii; sizes.
- **Motion:** timings.
- **Icons:** SF Symbols at medium weight.

## Brand (D6, D9)

| Asset | Design |
|---|---|
| App icon (D9, C1) | An amber body (#F8C46E to #E3892C); a black notch hanging from the top with three white bars; two white beamed quavers below. Below about 48 px, the notch grows and drops its flares, and the bars get fewer. |
| Menu bar icon | An 18 pt template glyph: a screen outline with a notch and bars. While something needs the user, a dot is cut out of it. |
| Disk image | A 660 × 400 window. The app sits at (165, 180) and the Applications link at (495, 180), both at 128, with an arrow and "Drag YT Notch to Applications". |
| Screenshots | 2× on Slate (#C5CED9 to #B4C1D0), or Graphite (#2B2F36 to #1F2227) for dark. |

All of these are drawn by `docs/design/brand/make-assets.swift`; run `swift docs/design/brand/make-assets.swift` from the repository root after changing it. The `icon-*.svg` files are layers for a macOS 26 Icon Composer `.icon`.

**Guardrails:** no YouTube logo, no red, no play triangle, nothing that echoes a Google mark.

## Menu, Settings and the full window (D7)

- **Menu bar menu:**
  - a status line and its action, only while something needs the user
  - Open YT Notch Window
  - Settings… ⌘,
  - Check for Updates… (Update Available… while one waits)
  - Copy Diagnostics: versions, health and the last 50 log lines, with no titles, playlists, account names or IDs
  - Quit ⌘Q
- **Settings,** 520 wide:
  - **General:** which displays show the notch; Open at login.
  - **Updates:** automatic daily check, last checked, Check Now.
  - **About:** version, the disclaimer, the copyright line, and links to the source and issues.
- **Full window:** the one web view, on screen.
  - A unified title bar with Back, Forward and Reload, and no address bar.
  - Opens at 1100 × 760, minimum 800 × 600.
  - Closing only hides it, so the music goes on.
  - Links outside YouTube Music and Google sign-in open in the browser.
- **First run:** the full window opens on sign-in with a bar saying what to do. Once signed in, it says so and offers Close Window. No later launch opens a window by itself.

## The pill without a notch (D8)

On a screen with no hardware notch, the playing pill shows the title and artist between the artwork and the bars, and a 2 pt progress line along its bottom edge. A title too long for it scrolls while music plays.

When menu bar icons crowd the pill:
1. It narrows from the right, ending 8 before the first icon.
2. Once only the artwork and bars are left, it slides left.
3. If even that doesn't fit, it hides until there is room.

Opening is unchanged.
