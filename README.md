# MacMural

A small native macOS menu bar app for drawing over your screen. Built with Swift and AppKit, with no third-party dependencies, accounts, networking, or polling while idle. Requires macOS 13 or newer.

## Install

Build the app using the instructions below, then open `dist/MacMural.zip`, drag **MacMural.app** to **Applications**, and open it. The app lives in the menu bar; it does not add a Dock icon. The local build is ad-hoc signed. Distribution to other Macs requires Developer ID signing and notarization for a normal Gatekeeper experience.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| **⌘⌥D** | Enable / disable drawing, from any app |
| **Hyper+D** | Enable / disable drawing with Caps Lock remapped to Hyper: ⌃⌥⌘D or ⌃⌥⌘⇧D |
| **A** | Arrow mode, with prominent arrowheads that scale with length |
| **L** | Laser mode: click and hold while moving to leave a fading red trail |
| **R** | Rectangle mode |
| **C** | Clear all drawings |
| **⌘Z** | Undo the last gesture or clear |
| **⇧⌘Z** | Redo |
| **D** | Freehand pen |
| **E** | Eraser: click or drag over a mark to remove that drawing |
| **1 / 2 / 3** | Thin / medium / thick lines, or small / medium / large eraser |
| **Shift + drag** | Square rectangles / arrows at 45-degree angles |
| **Hold Space** | Temporarily interact with the screen underneath; release to resume drawing |
| **Esc** or **right click** | Finish drawing and remove all drawings |

Except for ⌘⌥D and Hyper+D, drawing shortcuts apply only while drawing is enabled. Click the toolbar for tools, five ink colors, width, undo, redo, and clear. Finishing drawing removes all ink and resets undo/redo, so each new session starts clean. C remains undoable within the current session. An unfinished gesture is discarded when you switch tools, hold Space, or finish. The app remembers your tool, color, and line width.

The eraser removes whole drawings that its circular cursor touches, including filled arrowheads. The empty interior of a rectangle is left alone. A fast drag erases marks anywhere along its path. Each erase-drag is a single undo step; ⌘Z restores the removed drawings in their original order and ⇧⌘Z erases them again. Switching tools or holding Space completes an erase-drag, keeping its removals undoable within the session.

Holding Space temporarily makes all overlays click-through and hides the toolbar, preserving completed drawings and history. Click and scroll normally without holding a modifier key. Space is consumed, including key repeats, so it does not type into the underlying app. Release Space to resume drawing; if a drag is still in progress underneath, drawing resumes after the mouse button is released. Space is reserved only while drawing mode is open; closing drawing mode restores normal Space behavior. If drawing closes with Space still held, capture lasts until that press is released to avoid leaking repeats. A new mouse-down is required to start another drawing or laser gesture. Laser ink is emitted only while the left mouse button is held; on release, the existing trail fades without drawing a line to the next click.

All connected displays receive an overlay, including displays with negative coordinates. The toolbar opens on the display under your pointer. Overlays join desktop Spaces and full-screen apps. The menu bar and Dock remain accessible. The app does not require screen recording, Accessibility, or Input Monitoring access. If another app owns a shortcut, the help window reports that conflict; the other registered shortcuts and menu bar remain available.

## Build and test

Requires Xcode or Apple's Command Line Tools with Swift 5.9 or newer.

```sh
swift test --disable-sandbox
./scripts/build.sh              # current Mac architecture
./scripts/build.sh --universal  # Apple Silicon + Intel
open dist/MacMural.app
```

The build script creates `dist/MacMural.app` and `dist/MacMural.zip`. It creates the icon locally, uses only system frameworks, and ad-hoc signs the bundle. To install without Finder:

```sh
ditto dist/MacMural.app /Applications/MacMural.app
```

`MacMuralCore` contains gesture geometry, bounded undo/redo history, drawing input state, and laser expiration logic. `MacMural` owns event routing, the global Carbon hotkeys, transparent per-display panels, and the native toolbar. Space press and release are handled by a temporary Carbon hotkey registration, including while another app has focus. No modifier polling or global keyboard monitor is needed. The laser animates only while a trail is fading. A mouse-button timer runs only when Space has been released during an underlying drag, stopping when that drag ends. Both timers stop when drawing closes; ordinary drawing redraws only when input changes.
