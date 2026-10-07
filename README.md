<p align="center">
  <img src="docs/icon.png" width="160" alt="Clipline icon">
</p>

<h1 align="center">Clipline</h1>

<p align="center">Your screenshots, pegged to a line at the top of the screen instead of piling up on the Desktop.</p>

---

Clipline is a small native macOS app that lives in the menu bar. Every new screenshot is clipped to a washing line that slides down from under the menu bar. From there you copy it, drag it where it needs to go, or let it clear itself away. Nothing is uploaded and there is no account: everything, including reading the text inside screenshots, happens on your Mac.

## Features

- **A line that appears when you need it.** Rest the pointer on the menu bar and the line slides down. Move away and it tucks itself back. Control Option L shows or hides it from anywhere.
- **New screenshots announce themselves.** Each capture drops onto the line with a little swing, then the line hides again after a moment.
- **Pinning.** Press and hold a screenshot to pin it. Pinned screenshots get a red peg, stay at the front of the line and are never cleared automatically.
- **Automatic clearing.** Unpinned screenshots move to the Trash after one hour, one day or one week, or never. Nothing is deleted permanently, so the Trash is always a safety net.
- **Copy the text, not just the picture.** Clipline reads the text in every screenshot on device with the Vision framework. Option click a screenshot to copy its text.
- **Steps aside for full screen apps.** The line will not appear while you are watching a video or presenting.
- **Leaves your Mac as it found it.** Catching screenshots changes the system save location and hides the floating thumbnail. Both settings are restored the moment you quit Clipline or switch the option off.

## Gestures

| Gesture | Result |
| --- | --- |
| Click | Copy the image |
| Option click | Copy the text found in the image |
| Double click | Open in Preview |
| Press and hold | Pin or unpin |
| Drag into an app | Send a copy; the screenshot stays on the line |
| Drag into a Finder folder | Move it there; it leaves the line |
| Drag to the Trash, or click the cross | Move it to the Trash |
| Right click | Every action, plus Show in Finder |

## Install

Requires macOS 14 Sonoma or later, on Apple silicon or Intel.

```sh
git clone https://github.com/thefolahan/clipline.git
cd clipline
scripts/build-app.sh
open build/Clipline.app
```

Run `scripts/build-app.sh --dmg` to also produce a disk image. Set `SIGN_IDENTITY` to a Developer ID certificate to sign for distribution; without it the app is signed for local use only.

## How it works

| File | Role |
| --- | --- |
| `AppController.swift` | Menu bar item, global shortcut, the logic that reveals and hides the line |
| `LinePanel.swift` | A borderless, non activating panel pinned under the menu bar on every Space |
| `LineView.swift` | Draws the rope, lays out the screenshots along its curve, handles overflow scrolling |
| `ShotCard.swift` | One screenshot: the print frame, the peg, the drop and swing animations |
| `GrabArea.swift` | AppKit view that turns clicks, long presses and drags into actions |
| `ShotStore.swift` | The line itself: ordering, pinning, expiry, persistence and text recognition |
| `FolderWatcher.swift` | Watches the capture folder with a kernel file system event source |
| `CaptureSettings.swift` | Redirects system screenshots and restores the previous settings |
| `HotKey.swift` | Registers the global shortcut without needing Accessibility permission |
| `FullScreen.swift` | Detects when the frontmost app covers the whole display |

A few details worth calling out:

- **Telling screenshots apart from other images.** When Clipline is not redirecting captures it watches your existing screenshot folder and only accepts files carrying the `kMDItemIsScreenCapture` extended attribute that macOS adds to real screenshots. The attribute arrives slightly after the file does, so each new file is checked a few times before being skipped.
- **Knowing where a drag ended up.** Dragging hands the file to the system with copy, move and delete allowed. Finder moves the file when you drop it into a folder on the same disk, while apps such as Mail or Slack take a copy. Afterwards Clipline simply checks whether the file still exists, which keeps the line accurate whatever the destination did.
- **Text recognition that degrades gracefully.** Clipline asks Vision for its accurate model first and falls back to the fast model when the accurate one is unavailable or finds nothing.
- **No permissions prompts in the default setup.** Polling the pointer position, reading window bounds and Carbon hot keys all work without Accessibility or Screen Recording access.

The app icon is drawn in code by `scripts/draw-icon.swift`; run `scripts/make-icon.sh` to regenerate it.

## Privacy

Clipline makes no network requests, collects no analytics and has no account. Screenshots stay in `~/Pictures/Clipline`, and the line's state is a small JSON file in `~/Library/Application Support/Clipline`.

## Licence

MIT. See [LICENSE](LICENSE).
