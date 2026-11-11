# Floater: notes for agents

- The whole app is `Sources/Floater/main.swift`; `build.sh` wraps the SwiftPM binary in an ad-hoc
  signed `.app` bundle (and declares the `floater://` URL scheme).
- The app saves its current image to `~/Library/Application Support/Floater/last.png` (or `last.gif`
  for a GIF; whichever is newer wins) and its window frame to the `lastFrame` user default (bundle
  `com.tomatosource.floater`) every time it shows, moves or resizes. Launching with `--restore`
  (what `make dev` does) reads these instead of the clipboard, fitting the frame to the image's
  shape. Keep this working when changing how windows are created: scripts and the example skill rely on it.
- Relaunch with `make dev`, never a plain `open` or `make run`. The user may have the window placed
  somewhere deliberately, and their clipboard has likely moved on.
- Other saved defaults: `slotB` (the saved small-mode spot; named from when the buttons were A/B)
  and `pinned`.
- The README demo GIF is rendered by `docs/demo/demo.py`. When a user-visible feature changes,
  update the demo too: follow `docs/demo/GUIDE.md`.
- `SKILL_EXAMPLE.md` is the public example agent skill; keep it generic (no personal paths or hosts)
  and in step with the scripting hooks in the README.
