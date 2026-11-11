# Floater

Floats the image (or animated GIF) on your clipboard in a frameless, draggable, resizable, always-on-top window on the current desktop.

![Floater pinning an image above another window](docs/screenshot.jpg)

## Install & use

Needs macOS 14+ and the Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/tomatosource/floater && cd floater
make install   # installs /Applications/Floater.app
```

With an image or GIF on your clipboard, open Floater. Click it and press ⌘Q to close.

Hover and click **BIG MODE** to make it big, **SMALL MODE** to tuck it small into the top-right
corner. Prefer a different small spot? Put it there and double-click **SMALL MODE**; triple-click it
to go back to the default. Double-click the image to toggle between the two.

## Features

- Opens centred on the screen with the mouse. If there's no image on the clipboard it reopens the
  last image where it was (or, with no last image, opens on a random photo; if that fetch fails it
  posts "No image on clipboard" and quits).
- Click the window and press ⌘V to replace the image with the one on the clipboard (keeps the
  window's area; beeps if there's no image).
- Edge anchoring: when the window is within 60px of (or past) a screen edge, resizing, pasting
  and SMALL MODE keep that edge where it is — two edges pin the corner, one pins that edge (centred
  along it). Away from the edges, or touching both opposite edges (like BIG MODE), it keeps its centre.
- Launching it again closes the running copy (re-opening a running copy reloads from the clipboard).
- Not in Cmd+Tab or the Dock (`LSUIElement`). Click the image to focus, Cmd+Q to quit.
- Drag the image to move. Drag any corner to resize (aspect ratio kept); the corners are invisible
  hot zones with a resize cursor.
- Animated GIFs play — copied GIF data (e.g. from a browser) or a `.gif` file copied in Finder.
- On hover, a strip of buttons in the top-right corner, left to right (hover one for a tooltip):
  - **BIG MODE** (screen with a big window) — as large as fits the screen (aspect kept, at least
    20px clear of the menu bar, Dock and screen edges), centred.
  - **SMALL MODE** (screen with a small window top-right) — by default in the top-right corner
    (20px in), its longer side ~22% of the screen's longer side. Double-click to save the window's
    current position and size as the small-mode spot instead (a different-shaped image keeps the
    saved width and anchored edges); triple-click to clear that and go back to the default. The
    saved spot persists across launches (`slotB` default, from when the buttons were A and B).
  - BIG MODE and SMALL MODE animate the move. Double-clicking the image toggles between them (BIG
    MODE unless it's already big, else SMALL MODE).
  - **Pin** — show on every desktop (Space) instead of following the active one; the icon turns
    yellow while on. Persists across launches (`pinned` default).
  - **Close** quits Floater.

  Icons are [Lucide](https://lucide.dev) SVGs embedded in `Icon`, except the two mode icons.
  Tooltips are dark and show after 150ms.
- Click the window and press ⌘C to copy the image (GIFs keep their animation).

## Scripting (for you or an agent)

**Switch modes** on the running window with a URL:

```sh
open -g floater://big      # BIG MODE
open -g floater://small    # SMALL MODE
open -g floater://toggle   # BIG MODE unless it already is, else SMALL MODE
open -g floater://pin      # show on every desktop
open -g floater://unpin    # show on the current desktop only
```

`-g` leaves focus where it is. Only use these while Floater is running: if it isn't, the URL
launches it, floating whatever is on the clipboard.

**Set the image** without touching the clipboard: write it to
`~/Library/Application Support/Floater/last.png` (or `last.gif` to keep a GIF animated; Floater
shows whichever is newer, so delete the other), optionally set the window frame, then relaunch with
`--restore`. The new instance closes the running one.

```sh
cp image.png ~/Library/Application\ Support/Floater/last.png
rm -f ~/Library/Application\ Support/Floater/last.gif
defaults write com.tomatosource.floater lastFrame -string '{{x, y}, {w, h}}'  # optional; Cocoa coords, origin bottom-left
open -n /Applications/Floater.app --args --restore
```

The user's Claude Code `floater` skill (`~/.claude/skills/floater/floater.sh`) wraps both: `write
IMG` floats an image in SMALL MODE, `read OUT` copies out the current one, and `mode big|small|...`
switches modes, on this Mac or the user's other one.

## Development

```sh
make build      # build build/Floater.app
make run        # build and launch, floating the image on the clipboard
make dev        # rebuild and relaunch, restoring the last image, position and size
make watch      # `make dev` on every source change (needs entr: brew install entr)
make install    # build and copy to /Applications
make uninstall  # remove /Applications/Floater.app
make clean      # remove build output
```

The whole app is `Sources/Floater/main.swift`; `build.sh` wraps the SwiftPM binary in an ad-hoc
signed `.app` bundle.

The app saves its current image to `~/Library/Application Support/Floater/last.png` (or `last.gif`
for a GIF; whichever is newer wins) and its window frame to the `lastFrame` user default (bundle
`com.tomatosource.floater`) every time it shows, moves or resizes. Launching with `--restore`
(what `make dev` does) reads these instead of the clipboard. Keep this working when changing how
windows are created.

**Note for agents:** relaunch with `make dev`, never a plain `open` or `make run`. The user may
have the window placed somewhere deliberately, and their clipboard has likely moved on.

## Credits

Screenshot photo by [Alexey Topolyanskiy](https://unsplash.com/photos/-oWyJoSqBRM) on Unsplash.
Icons from [Lucide](https://lucide.dev) (ISC).
