# Floater

Floats the image on your clipboard in a frameless, draggable, resizable, always-on-top window on the current desktop.

![Floater pinning an image above another window](docs/screenshot.jpg)

## Install & use

```sh
git clone https://github.com/tomatosource/floater && cd floater
./build.sh --install   # needs Xcode command line tools; installs /Applications/Floater.app
```

With an image on your clipboard, open Floater. Click it and press ⌘Q to close.

## Features

- Opens centred on the screen with the mouse; if there's no image on the clipboard it posts a
  "No image on clipboard" notification and quits.
- Launching it again closes the running copy (re-opening a running copy reloads from the clipboard).
- Not in Cmd+Tab or the Dock (`LSUIElement`). Click the image to focus, Cmd+Q to quit.
- Drag the image to move. Drag any corner to resize (aspect ratio kept). Only the bottom-right
  corner shows a grip; the other corners are invisible hot zones with a resize cursor.
- On hover, buttons in the top-right corner: copy the image to the clipboard, and a ghost that
  toggles image transparency (100% / 40%; the controls stay opaque). Icons are
  [Lucide](https://lucide.dev) SVGs embedded in `Icon`.

## Build

```sh
./build.sh            # builds build/Floater.app
./build.sh --install  # also copies it to /Applications
```

## Developing (note for agents)

**Always relaunch with `./dev.sh`, never a plain `open`.** It rebuilds and launches with
`--restore`, so the window comes back at the same position and size showing the same image —
the user may have it placed somewhere deliberately and their clipboard has likely moved on.

The app saves its current image to `~/Library/Application Support/Floater/last.png` and its window
frame to the `lastFrame` user default (bundle `com.tomatosource.floater`) every time it shows,
moves or resizes. `--restore` reads these instead of the clipboard. Keep this working when
changing how windows are created.

## Credits

Screenshot photo by [Alexey Topolyanskiy](https://unsplash.com/photos/-oWyJoSqBRM) on Unsplash.
Icons from [Lucide](https://lucide.dev) (ISC).
