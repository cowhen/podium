<div align="center">
  <img src="assets/AppIcon_1024.png" width="160" alt="PODIUM app icon">

  # PODIUM

  A window switcher and positioner for macOS, built entirely on public
  Accessibility and CoreGraphics APIs.
</div>

---

One hotkey (**⌥⇥**) opens **Podium** — a flat, searchable list of every
window. Pick one, confirm, and it drops you into **Loop mode**: a radial
menu that positions that window on screen, mouse or keyboard, with a live
preview and instant commit.

Unlike snap tools (Rectangle), always-on tilers (AeroSpace, yabai) or
switchers (AltTab), PODIUM combines *switch + position* into one continuous
gesture — no private frameworks, no SIP disabling, no event taps. Every
window move goes through `AXUIElementSetAttributeValue`, nothing else.

## How it works

**Podium** — three ways to pick a window, freely mixable: arrow keys,
typing to filter, or hovering the real window on its real monitor (a click
there confirms like Enter). The active window is pre-selected on open and
gets a live highlight + brief raise so you can see it.

By default, Enter/click open Loop mode and `⌘↵`/double-click just switch
focus — flip a setting to swap which is which. In either mode, Space checks
a window for **Auto-Arrange**: check two or more, then Enter tiles them
across every connected monitor, proportional to screen area.

**Loop mode** — confirming a selection opens a radial ring on the window's
monitor. Move the mouse into a quadrant (it follows you across monitors
too) or use the keyboard:

| Keys | Action |
|---|---|
| `← → ↑ ↓` (repeat cycles) | edge: half → third → two-thirds |
| `U I J K` (repeat cycles) | corners: ½ → ⅓ → ⅔ |
| `E` / `⇧E` | more positions (center-half/-third, quarter-stripes) |
| `F` / right-click | cycle fill: solo → 3 largest neighbors → all neighbors |
| `M A H W C` | maximize / almost-maximize / full height / full width / center |
| `Z` / `⇧Z` | minimize / minimize others |
| `X` | hide app · `S` / `⇧S` stash / unstash · `⌘Z` undo |
| `1–9` | throw to display N · `⇥` / `⇧⇥` neighbor display |
| `↵` or click anywhere | commit · `esc` back to the stage |

Haptic feedback on every zone change; Escape backs out untouched.

## Features

- **Fill neighbors** — an edge/corner placement can fill the rest of the
  display with other windows too, live-cycled with `F`/right-click: solo →
  3 largest → all, auto-grid, with a live preview of every window that
  would move.
- **Linked edges** — no modifier key needed: drag a real window's edge
  *slowly* and its real neighbors resize with it; drag fast and they're
  left alone. Speed is sampled live and gated through hysteresis (separate
  engage/disengage thresholds, so it never flickers right at the cutoff),
  with a live ghost-preview plus a border glow on the dragged window before
  you let go. Hold **⌃ (Control)** to force linking regardless of speed.
  Neighbors are found geometrically on every resize, not from stale
  bookkeeping — works for windows arranged by PODIUM *or* dragged into
  place by hand.
- **Drag-to-edge snap** — drag a window to a screen edge on the real
  desktop and it snaps like Aero Snap, independent of the overlay.
- **Configurable direct hotkeys** — bind any layout (halves, thirds,
  corners, maximize, undo, monitor throw) to its own global shortcut, no
  overlay needed. Settings → Hotkeys.
- **Per-window actions on the stage** — `⌘M` minimize, `⌘H` hide app,
  `⌘⌫` close, or right-click a tile for a full menu including quitting.
- **Layout presets** — save an arrangement per monitor setup (fingerprinted
  by screen names + resolutions), auto-restored on dock/undock. "Apply and
  launch apps" starts anything missing first.
- **App groups** — define named app groups in Settings → Apps; Auto-Arrange
  keeps every checked window from the same group on one monitor.
- **Wake restore** — the last known-good arrangement re-applies itself
  after sleep/wake or a display reconnect.
- **Floating apps** — Finder and System Settings (configurable) are never
  tiled, just centered.
- **Monitor number badges** — a Liquid Glass badge (macOS 26+, translucent
  fallback) marks each display's number while the overlay is open.

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

Everything lives in the Settings window (menu bar icon → Einstellungen):

- **Allgemein** — interaction model (switch-first vs. position-first),
  default Loop-mode fill mode, auto-minimize, auto-apply layouts,
  drag-to-edge.
- **Hotkeys** — the Podium activation shortcut plus a global shortcut per
  layout, bind or clear.
- **Darstellung** — grouping, tile size, per-monitor accent colors.
- **Apps** — ignored apps, floating apps, app groups.
- **Layouts** — saved per-setup arrangements, with "apply and launch apps".

Or edit `~/.config/podium/config.json` directly: ignore lists by app name,
bundle id or title pattern; floating apps; app groups.

## Development

```sh
swift test        # pure-logic tests: layout math, linked-edges geometry,
                   # drag-speed hysteresis, loop-action frames, window history
./build.sh         # release build + app bundle + signing
```

The interaction core is split into small, pure, fully unit-tested modules
with no AppKit/Accessibility dependency — `Layout`, `BentoLayout`,
`LoopEngine`, `LinkedEdges.computeNeighborUpdates`, `LinkedEdgeVelocity` —
each wired to the real window server by a thin AX layer (`AX.swift`,
`WindowManager.swift`). `OverlayController` orchestrates the stage and Loop
mode on top of that.

## License

GPLv2 — see [LICENSE](LICENSE).
