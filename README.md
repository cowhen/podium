# PODIUM

A visual window arranger and switcher for macOS with multiple displays.

One hotkey (⌥⇥) opens an overlay showing a true-to-scale map of your monitor
arrangement with the foreground windows tiled inside, and a searchable "stage"
with everything else, grouped by app. Drag, click or type to rearrange —
every action applies to the real windows immediately, Escape rolls the whole
session back.

Unlike snap tools (Rectangle, Loop), always-on tilers (AeroSpace, yabai) or
switchers (AltTab), PODIUM combines *overview + arrangement + search* in one
surface — and it does so using only public Accessibility and CoreGraphics
APIs. No SIP disabling, no private frameworks, no event taps.

## Features

- **Monitor map** — true relative positions and aspect ratios, like System
  Settings → Displays. Up to 4 windows per display in orientation-aware
  layouts (split, 1+2 stack, 2×2 grid).
- **Live tiling** — drag windows between displays, drag the seams to snap
  through 33/50/67 ratios, click a tile to cycle its prominence.
- **Stage** — all background windows grouped by app with live thumbnails,
  hover for a large preview, type to filter (matches also highlight in the
  map). Click focuses, ✕ closes the real window.
- **Full keyboard control** — arrows navigate, digits throw the selected
  window to a display, ⇧-arrows adjust ratios, Space grabs for slot-by-slot
  moves. Press `?` in the overlay for the cheat sheet.
- **Global hotkeys** — ⌃⌥←/→ halves, ⌃⌥↑ maximizes, ⌃⌥↓ centers,
  ⌃⌥1–4 throws the focused window to display N. No overlay needed.
- **Wake restore** — the last blessed arrangement is re-applied after
  sleep/wake or dock reconnect, fixing macOS's window scrambling.
- **Floating apps** — Finder and System Settings (configurable) are never
  tiled; dropping them on a display just centers them on top.

## Install

Build from source (requires Xcode command line tools, macOS 14+):

```sh
git clone https://github.com/cowhen/podium.git
cd podium
./build.sh
open Podium.app
```

Or grab `Podium-*.zip` from the [releases](https://github.com/cowhen/podium/releases).
Release builds are ad-hoc signed: macOS will warn on first launch —
right-click → Open once.

### Permissions

PODIUM needs two permissions, requested on first launch:

- **Accessibility** — to read and move windows (the entire mechanism).
- **Screen Recording** — for the window thumbnails only. Without it you get
  app icons instead.

Note for developers: `build.sh` signs with a persistent self-signed identity
(`ScrollWM Local`) if present, so TCC grants survive rebuilds. With ad-hoc
signing you must re-grant permissions after every build.

## Configuration

- **Settings window** (menu bar icon → Einstellungen): overlay hotkey,
  per-monitor accent colors, ignored apps, floating apps.
- **Config file** `~/.config/podium/config.json`: ignore lists by app name,
  bundle id or title pattern; floating apps.

## Development

```sh
swift test        # pure-logic tests (layout, arrangement model)
./build.sh        # release build + app bundle + signing
```

The interaction core lives in `ArrangementModel` (pure, no AppKit) and
`Layout` (pure geometry) — both fully unit-tested. `OverlayController` wires
them to AppKit.

## License

GPLv2 — see [LICENSE](LICENSE).
