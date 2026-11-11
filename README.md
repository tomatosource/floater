# Floater

![Floater demo: open an image from the clipboard, move and resize it, big and small mode, paste, pin across desktops, and an agent floating an image](docs/demo.gif)

## Install

Paste this to your coding agent:

```text
Install Floater from https://github.com/tomatosource/floater: clone it, run `make install`, then
install its SKILL_EXAMPLE.md as a skill named "floater" so you can show me images in it.
```

## Scripting

Scripts and agents can drive Floater directly; [`SKILL_EXAMPLE.md`](SKILL_EXAMPLE.md) wraps this up
as an agent skill.

```sh
open -g floater://big      # big mode
open -g floater://small    # small mode
open -g floater://toggle   # big mode unless it already is, else small mode
open -g floater://pin      # show on every desktop
open -g floater://unpin    # show on the current desktop only
```

These only work while Floater is running; otherwise the URL launches it with the clipboard image.

To set the image without touching the clipboard, write it to Floater's saved image and relaunch.
The window keeps its place, reshaped to the new image:

```sh
cp image.png ~/Library/Application\ Support/Floater/last.png   # a GIF goes to last.gif
open -n -a Floater --args --restore
```

## Development

```sh
make build      # build build/Floater.app
make run        # build and launch, floating the image on the clipboard
make dev        # rebuild and relaunch, restoring the last image, position and size
make watch      # `make dev` on every source change (needs entr: brew install entr)
make install    # build and copy to /Applications
make uninstall  # remove /Applications/Floater.app
make demo       # re-render docs/demo.gif (see docs/demo/GUIDE.md)
make clean      # remove build output
```

## Credits

Demo photos from Unsplash, credited in [`docs/demo/assets/CREDITS.md`](docs/demo/assets/CREDITS.md).
Icons from [Lucide](https://lucide.dev) (ISC).
