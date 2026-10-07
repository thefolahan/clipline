<p align="center">
  <img src="docs/icon.png" width="160" alt="Clipline icon">
</p>

<h1 align="center">Clipline</h1>

<p align="center">Your screenshots, pegged to a line under the menu bar or swept under a rug on the Desktop, instead of piling up in plain sight.</p>

---

Clipline is a small native macOS app that lives in the menu bar. Every new screenshot goes somewhere tidy, in one of two styles you pick from the Style menu:

- **Washing Line.** Screenshots are clipped to a line that slides down from under the menu bar.
- **Rug.** A rug lies on your Desktop, behind every window, and screenshots are swept under it. Grab a corner and fold it back to find them.

From there you copy a screenshot, drag it where it needs to go, or let it clear itself away. Nothing is uploaded and there is no account: everything, including reading the text inside screenshots, happens on your Mac.

## Features

- **A line that appears when you need it.** Rest the pointer on the menu bar and the line slides down. Move away and it tucks itself back. Control Option L shows or hides it from anywhere.
- **A rug that behaves like cloth.** The rug is a physical simulation, not an animation. Pick it up anywhere and it lifts, drapes and follows the pointer; let go and it falls where you left it, so a corner folded over stays folded until you pull it back. Drag it by the middle to move it across the Desktop. Control Option L folds it back or lays it flat, and Lay Rug Flat in the menu smooths out any creases.
- **New screenshots announce themselves.** On the line, each capture drops on with a little swing. Under the rug, a corner lifts briefly as the screenshot slides beneath it.
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
| `RugController.swift` | The Desktop level window for the rug style and the screenshots scattered beneath it |
| `ClothSim.swift` | The cloth: particles, distance constraints, gravity, friction and layering |
| `RugScene.swift` | Renders the cloth with SceneKit from shared Metal buffers and turns the pointer into grabs |
| `RugArt.swift` | Paints the rug pattern and its darker underside in code |
| `PrintView.swift` | One screenshot under the rug, sharing every gesture with the line |
| `HotKey.swift` | Registers the global shortcut without needing Accessibility permission |
| `FullScreen.swift` | Detects when the frontmost app covers the whole display |

A few details worth calling out:

- **Telling screenshots apart from other images.** When Clipline is not redirecting captures it watches your existing screenshot folder and only accepts files carrying the `kMDItemIsScreenCapture` extended attribute that macOS adds to real screenshots. The attribute arrives slightly after the file does, so each new file is checked a few times before being skipped.
- **Knowing where a drag ended up.** Dragging hands the file to the system with copy, move and delete allowed. Finder moves the file when you drop it into a folder on the same disk, while apps such as Mail or Slack take a copy. Afterwards Clipline simply checks whether the file still exists, which keeps the line accurate whatever the destination did.
- **Text recognition that degrades gracefully.** Clipline asks Vision for its accurate model first and falls back to the fast model when the accurate one is unavailable or finds nothing.
- **Simulating the rug.** The rug is a 46 by 29 grid of particles integrated with Verlet steps at 240 Hz, held together by stretch, shear and weak bending constraints. The floor has high friction so the rug never skids, and a spatial hash keeps a folded layer resting on top of the layer beneath it, with friction between them so folds hold. The grabbed particle chases the pointer through exponential smoothing, which is what makes the motion feel soft rather than mechanical.
- **Rendering the rug.** Particle positions and normals are written straight into Metal buffers that SceneKit reads, so nothing is rebuilt per frame. The top uses the rug texture, the underside a darker copy with flipped normals, a perspective camera makes lifted parts look closer, and the shadow is a Core Animation layer traced from the outline of the cloth. When the rug is still for a moment the simulation sleeps and costs nothing.
- **Clicking through the rug.** The rug window covers the Desktop but only accepts the mouse where the rug or a revealed screenshot actually is, so clicks everywhere else reach the Desktop as normal.
- **No permissions prompts in the default setup.** Polling the pointer position, reading window bounds and Carbon hot keys all work without Accessibility or Screen Recording access.

The app icon and the rug pattern are drawn in code by `scripts/draw-icon.swift`; run `scripts/make-icon.sh` to regenerate it.

## Privacy

Clipline makes no network requests, collects no analytics and has no account. Screenshots stay in `~/Pictures/Clipline`, and the line's state is a small JSON file in `~/Library/Application Support/Clipline`.

## Licence

MIT. See [LICENSE](LICENSE).
