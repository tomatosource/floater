# Floater

Floats the image (or animated GIF) on your clipboard in a frameless, draggable, resizable, always-on-top window on the current desktop.

![Floater pinning an image above another window](docs/screenshot.jpg)

## Install & use

```sh
git clone https://github.com/tomatosource/floater && cd floater
./install.sh   # needs Xcode command line tools; installs /Applications/Floater.app
```

With an image or GIF on your clipboard, open Floater. Click it and press ⌘Q to close.

Hover and click **A** to make it big, **B** to tuck it small into the top-right corner. Prefer a
different small spot? Put it there and double-click **B**; triple-click **B** to go back to the default.

## Features

- Opens centred on the screen with the mouse; if there's no image on the clipboard it posts a
  "No image on clipboard" notification and quits.
- Launching it again closes the running copy (re-opening a running copy reloads from the clipboard).
- Not in Cmd+Tab or the Dock (`LSUIElement`). Click the image to focus, Cmd+Q to quit.
- Drag the image to move. Drag any corner to resize (aspect ratio kept). Only the bottom-right
  corner shows a grip; the other corners are invisible hot zones with a resize cursor.
- Animated GIFs play — copied GIF data (e.g. from a browser) or a `.gif` file copied in Finder.
- On hover, a strip of buttons in the top-right corner, left to right:
  - **A** — big: as large as fits the screen (aspect kept, at least 20px clear of the menu bar,
    Dock and screen edges), centred.
  - **B** — small: by default in the top-right corner (20px in), its longer side 30% of the
    screen's longer side. Double-click to save the window's current position and size as B
    instead (a different-shaped image keeps the saved centre and width); triple-click to clear
    that and go back to the default. The saved spot persists across launches (`slotB` default).
  - A and B animate the move, so clicking them toggles between big and small.
  - **Eraser** replaces the image with a random photo from [Lorem Picsum](https://picsum.photos)
    (Unsplash photos, free to use, no API key); the window keeps its centre and area.
  - **Copy** the image to the clipboard (GIFs keep their animation).
  - **Ghost** toggles image transparency (100% / 40%; the controls stay opaque).

  Icons are [Lucide](https://lucide.dev) SVGs embedded in `Icon`.

## Build

```sh
./build.sh            # builds build/Floater.app
./install.sh          # builds and copies it to /Applications
```

## Developing (note for agents)

**Always relaunch with `./dev.sh`, never a plain `open`.** It rebuilds and launches with
`--restore`, so the window comes back at the same position and size showing the same image —
the user may have it placed somewhere deliberately and their clipboard has likely moved on.

The app saves its current image to `~/Library/Application Support/Floater/last.png` (or `last.gif`
for a GIF; `--restore` uses whichever is newer) and its window
frame to the `lastFrame` user default (bundle `com.tomatosource.floater`) every time it shows,
moves or resizes. `--restore` reads these instead of the clipboard. Keep this working when
changing how windows are created.

## Credits

Screenshot photo by [Alexey Topolyanskiy](https://unsplash.com/photos/-oWyJoSqBRM) on Unsplash.
Icons from [Lucide](https://lucide.dev) (ISC).
