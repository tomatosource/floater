# Floater

Floats the image on your clipboard in a frameless, always-on-top window on the current desktop.

- Opens centred on the screen with the mouse; if there's no image on the clipboard it posts a
  "No image on clipboard" notification and quits.
- Launching it again closes the running copy (re-opening a running copy reloads from the clipboard).
- Not in Cmd+Tab or the Dock (`LSUIElement`). Click the image to focus, Cmd+Q to quit.
- Drag the image to move. Drag any corner grip to resize (aspect ratio kept). The bottom-right grip
  is always visible; the others appear on hover.
- On hover, ghost buttons at the top right: copy the image to the clipboard, and toggle
  transparency (100% / 25%).

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
