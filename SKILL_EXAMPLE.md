---
name: floater
description: "Show the user images in Floater (an always-on-top image window on their Mac), read what's floated there, or switch it between big and small mode. Use whenever the user asks to be shown something visual — \"show me\", \"what does X look like\", a photo, diagram, chart, screenshot, map or GIF, or any topic where a picture beats words — not only when they say \"floater\". Also use when they mention \"floater\", \"what's in floater\", or ask to put/float an image there, or to make it big/small. Not for websites: link those instead."
---

# floater

[Floater](https://github.com/tomatosource/floater) floats an image in a frameless, always-on-top
window. This skill lets you put images there, read the one that's there, and switch its size.

Copy this file to `~/.claude/skills/floater/SKILL.md` (Claude Code) or wherever your agent reads skills.

## Showing the user things

When the user asks to *see* something and an image would answer it, float it rather than
describing it or pasting a link: find or make the image (download a freely licensed photo, render a
diagram or chart, take a screenshot), save it to a temp file and write it (below).

The image is the answer. The user flips Floater into big mode, reads it, decides, flips back to
small mode and replies, so it must stand on its own:

- Put labels, numbers for options, sources and caveats on the image itself, in small text.
- For comparisons, lay options out in a numbered grid that fits one screen. Rendering an HTML page
  to PNG with headless Chrome is an easy way to build one.
- Keep your reply to a line. Don't repeat in text what the image shows.

## Write (float an image)

Floater shows `~/Library/Application Support/Floater/last.png`, or `last.gif` for an animated GIF
(whichever is newer), when launched with `--restore`. A new instance replaces the running one. The
window keeps its position and area, reshaped to the new image.

```sh
dir=~/Library/Application\ Support/Floater
mkdir -p "$dir"
sips -s format png IMAGE --out "$dir/last.png" && rm -f "$dir/last.gif"   # GIF: cp IMAGE "$dir/last.gif" && rm -f "$dir/last.png"
# First run only: Floater needs a saved frame to restore into (small mode fixes it up below).
defaults read com.tomatosource.floater lastFrame >/dev/null 2>&1 ||
  defaults write com.tomatosource.floater lastFrame -string '{{100, 100}, {480, 320}}'
open -n -a Floater --args --restore
sleep 1 && open -g floater://small   # optional: tuck it into the user's small-mode spot
```

Never launch Floater with a plain `open -a Floater`: that floats the clipboard, not your image.
Never touch the clipboard.

## Read (look at the floated image)

```sh
dir=~/Library/Application\ Support/Floater
src="$dir/last.png"; [ "$dir/last.gif" -nt "$src" ] && src="$dir/last.gif"
sips -s format png "$src" --out /tmp/floater.png   # a GIF gives its first frame
```

Then open `/tmp/floater.png` with your image-reading tool. Read it fresh each time: it changes
whenever the user floats something new.

## Mode (big / small / pin)

```sh
open -g floater://big      # as large as fits the screen, centred
open -g floater://small    # the user's small-mode spot (default: top-right corner)
open -g floater://toggle   # big unless it already is, else small
open -g floater://pin      # show on every desktop
open -g floater://unpin    # show on the current desktop only
```

Only while Floater is running (`pgrep -xq Floater`): if it isn't, the URL launches it on whatever
is on the clipboard.
