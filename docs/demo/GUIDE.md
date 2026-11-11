# Updating the demo GIF

`docs/demo.gif` (the README's demo) is rendered, not screen-recorded: `demo.py` draws a mocked Mac
desktop frame by frame with Pillow and encodes the frames with ffmpeg. That keeps it reproducible and
free of anything from a real desktop, and lets any agent update it when features change.

```sh
make demo                                   # re-render docs/demo.gif (about 40s)
python3 docs/demo/demo.py --preview 12.5    # also writes the frame at 12.5s to docs/demo/preview.png
python3 docs/demo/demo.py --keep-frames     # keep the PNG frames (path printed) for inspection
```

Needs macOS (for the system fonts and the Swift icon rasterizer), Python 3 with Pillow
(`pip3 install pillow`) and ffmpeg (`brew install ffmpeg`).

## How it fits together

| Piece | What it does |
|---|---|
| `demo.py` → `scenes()` | The timeline: one block per feature, each starting with a caption. **This is what you edit.** |
| `demo.py` → `Renderer` | Draws a frame from `State`: desktops, the Floater window and its hover buttons, tooltip, cursor, caption, end card. Actions (`move`, `click`, `animate_window`, `type`, `hold`, …) advance time by rendering frames. |
| `demo.py` → geometry helpers | Python copies of the app's big mode, small mode, edge anchoring (`Anchor`) and button layout. Keep them in step with `Sources/Floater/main.swift`. |
| `rasterize.swift` | Renders the app's own icon SVGs (read from the `Icon` enum in `main.swift`) to PNGs, so the demo's buttons always match the app's. |
| `assets/` | Photos used in the demo, with credits in `assets/CREDITS.md`. |

The mocked screen is 1200×750 points with a 24pt menu bar; the GIF is 960×600 at 12fps.

## Adding or changing a scene

1. Find the feature's place in the story in `scenes()`. The current order: copy an image and open
   Floater → drag to move → corner resize → hover controls and tooltip → big mode → small mode →
   double-click to toggle → save a small-mode spot → ⌘V paste keeps the corner → GIFs play → ⌘C →
   pin and switch desktops → an agent in Terminal floats an image and switches modes → close → title card.
2. Add a block that starts with `r.say("What's happening", ["⌘X"])` (keycaps are optional), then drives
   the state:
   - `r.move((x, y), secs)` moves the cursor; `drag="window"` or `drag="bottomright"` drags along.
   - `r.click()` / `r.click(count=2)` shows click ripples; follow with the effect, e.g.
     `r.animate_window(big_frame(aspect()))`.
   - Set `s.hover`, `s.pinned`, `s.flash = "small"`, `s.tooltip = "…"`, `s.image = "key"` directly.
   - `r.type("$ command", secs)` types into the Terminal on desktop 2.
   - `r.hold(secs)` gives the viewer time to read. Allow ~1s per caption.
3. If the app's UI changed (new button, new icon, different layout), update the matching mirror in
   `demo.py` too: `button_rects()` for the hover strip order, the tooltips' text in `scenes()`, the
   constants at the top for sizes. New icons in the `Icon` enum are picked up automatically.
4. Check a frame or two with `--preview SECONDS`, then `make demo` and look at the whole GIF.
   Floating it in Floater is a good way to watch it.
5. Keep the GIF under ~8 MB (GitHub shows up to 10 MB). The script prints the size. If it grows, trim
   holds, lower `FPS`, or shrink `OUT_W`/`OUT_H`.

## Images

New photos go in `assets/` with a line in `assets/CREDITS.md`; only use freely licensed ones
(Unsplash via Lorem Picsum is easiest). Register them in `load_images()`. Animated content is a list
of frames (see `bouncing_ball_gif()`); it advances one frame every two video frames.
