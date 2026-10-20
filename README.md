# MacMural

A small native macOS menu bar app for drawing over your screen. Built with Swift and AppKit, with no third-party dependencies, accounts, networking, or polling while idle. Requires macOS 13 or newer.

## Install

Download **MacMural.zip** from [GitHub Releases](https://github.com/henrikhestnes/MacMural/releases/latest), unzip it, drag **MacMural.app** to **Applications**, and open it. The app lives in the menu bar; it does not add a Dock icon.

Or install through [the Homebrew tap](https://github.com/henrikhestnes/homebrew-tap):

```sh
brew install --cask henrikhestnes/tap/macmural
```

After installation, open **MacMural** from **Applications**. You can also run:

```sh
open /Applications/MacMural.app
```

### First launch: approve MacMural

MacMural is ad-hoc signed and has not been notarized by Apple. macOS may show **“MacMural” Not Opened** and say Apple could not verify that the app is free of malware. This also applies to the Homebrew installation.

If you installed MacMural from the GitHub Releases page or the Homebrew tap linked above, follow these steps to approve it:

1. Try opening **MacMural** from **Applications**. In the blocked-app dialog, click **Done**.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to **Security** and find the message about MacMural being blocked.
4. Click **Open Anyway** beside MacMural.
5. Authenticate if prompted, then confirm **Open** in the follow-up dialog.

If **Open Anyway** is not visible, try opening MacMural again and return to Privacy & Security. On a managed Mac, your organization's policy may prevent approval.

This grants an exception for MacMural. Later builds may need approval again. The Homebrew cask preserves macOS security checks; it does not remove quarantine attributes or disable Gatekeeper. See [Apple’s instructions for opening apps](https://support.apple.com/en-us/102445).

Once open, MacMural lives in your menu bar. Press **Control + Shift + D** (or your configured shortcut) to start drawing. Check **Launch at Login** in the menu if you want it to start when you sign in; macOS may require separate login-item approval.

## Launch at login

Starting with v1.4.0, MacMural requests **Launch at Login** on its first launch from `/Applications` or your user’s `Applications` folder. Each user must open the app once after installation. The menu bar’s **Launch at Login** checkbox shows the actual macOS state and lets you turn it off or on. Changes made in System Settings are respected; the app does not automatically re-enable a disabled login item.

If macOS requires approval, the checkbox shows a mixed state and **Open Login Settings…** takes you to the approval controls. Registration failures are shown in **Launch at Login Error…**, with an option to open those settings. Successful registration must be checked with the installed build, particularly with the current ad-hoc signature.

Login startup is quiet: drawing remains off and the welcome window stays hidden. The welcome window appears once on the first manual launch and remains available through **Shortcuts & Help…**. Local builds in `dist/` do not register themselves as login items; install the app in Applications and reopen it to test that feature.

## Shortcuts

Open **MacMural’s menu bar icon → Keyboard Shortcuts…** to change the global toggle, drawing tools, clear, undo/redo, line sizes, finish, or the hold-to-interact key. Click a shortcut, press your desired keys, then click **Apply**. **Restore Defaults** resets the editor; click Apply to save the reset. You can also turn the Hyper+D aliases off.

Settings are remembered after quitting. Duplicate assignments and enabled macOS shortcut conflicts are rejected. If another app prevents registration of a new global shortcut, the previous bindings stay active. The global toggle requires Control or Command; hold-to-interact uses a single key without modifiers. Esc always finishes drawing, and ⌘Q remains available to quit. Shortcut labels in the menu, toolbar, and help update to match your settings.

The defaults are:

| Shortcut | Action |
| --- | --- |
| **⌃⇧D** (Control + Shift + D) | Enable / disable drawing, from any app |
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

Except for the global drawing toggle and optional Hyper+D aliases, drawing shortcuts apply only while drawing is enabled. Click the toolbar for tools, five ink colors, width, undo, redo, and clear. Finishing drawing removes all ink and resets undo/redo, so each new session starts clean. C remains undoable within the current session. An unfinished gesture is discarded when you switch tools, hold Space, or finish. The app remembers your tool, color, and line width.

Starting with v1.3.0, Control + Shift + D replaces Command + Option + D, leaving the macOS Dock shortcut available.

The eraser removes whole drawings that its circular cursor touches, including filled arrowheads. The empty interior of a rectangle is left alone. A fast drag erases marks anywhere along its path. Each erase-drag is a single undo step; ⌘Z restores the removed drawings in their original order and ⇧⌘Z erases them again. Switching tools or holding Space completes an erase-drag, keeping its removals undoable within the session.

Holding the interaction key (Space by default) temporarily makes all overlays click-through and hides the toolbar, preserving completed drawings and history. Click and scroll normally without holding a modifier key. The interaction key is consumed, including key repeats, so it does not type into the underlying app. Release it to resume drawing; if a drag is still in progress underneath, drawing resumes after the mouse button is released. The interaction key is reserved only while drawing mode is open; closing drawing mode restores its normal behavior. If drawing closes with the interaction key still held, capture lasts until that press is released to avoid leaking repeats. A new mouse-down is required to start another drawing or laser gesture. Laser ink is emitted only while the left mouse button is held; on release, the existing trail fades without drawing a line to the next click.

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

`MacMuralCore` contains gesture geometry, bounded undo/redo history, drawing input state, and laser expiration logic. `MacMural` owns event routing, the global Carbon hotkeys, transparent per-display panels, and the native toolbar. The hold-to-interact key’s press and release are handled by a temporary Carbon hotkey registration, including while another app has focus. No modifier polling or global keyboard monitor is needed. The laser animates only while a trail is fading. A mouse-button timer runs only when Space has been released during an underlying drag, stopping when that drag ends. Both timers stop when drawing closes; ordinary drawing redraws only when input changes.

## Publish a release

The public Homebrew tap is `henrikhestnes/homebrew-tap`, installed as `henrikhestnes/tap`. This repository keeps the source cask in `Casks/macmural.rb`, pointing to a versioned GitHub Release asset and pinning its SHA-256 checksum. The publishing script copies it to the tap only after verifying the published ZIP.

To publish the prepared release, run from a terminal with GitHub access:

```sh
./scripts/publish.sh --check  # validate locally without GitHub access
./scripts/publish.sh          # publish the app and make this repository public
```

The publishing script checks the app, ZIP, cask, release notes, and Git email before committing only the release-related files. It uploads a draft release, verifies the uploaded ZIP, publishes the release, makes the repository public if needed, checks the public ZIP and cask, and updates the separate Homebrew tap. It never replaces an existing release asset or moves an existing tag to another commit.

For future releases, update `Resources/Info.plist`, build a universal app, update the cask version and checksum, and add matching release notes under `releases/`. Commit application changes before publishing. Published ZIPs and their checksums must remain unchanged.

To create or refresh only the Homebrew tap using the latest published release:

```sh
./scripts/publish-tap.sh
```

This requires `gh` authenticated as `henrikhestnes`. It validates the published ZIP against the cask from its release tag, then creates the public tap if it is missing or updates its cask. It does not publish an unreleased app build. The older `henrikhestnes/macmural` tap remains compatible through the source cask in this repository.
