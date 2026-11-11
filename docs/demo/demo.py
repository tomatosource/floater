#!/usr/bin/env python3
"""Renders docs/demo.gif: a mocked Mac desktop walking through Floater's features, with captions.

Everything is drawn here (Pillow) rather than screen-recorded, so it's reproducible and the window
never shows anything personal. The button icons are the app's own SVGs, read from main.swift.

    make demo            # or: python3 docs/demo/demo.py [--preview SECONDS] [--keep-frames]

See docs/demo/GUIDE.md for how the timeline is put together and how to add a scene.
"""
import argparse
import math
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
ASSETS = HERE / "assets"
OUT = ROOT / "docs" / "demo.gif"

# The mocked screen, in points. Everything below is laid out in these units.
SW, SH = 1200, 750
MENU = 24                          # menu bar height; the visible frame is everything below it
K = 1.6                            # render scale (points -> pixels) before downscaling
OUT_W, OUT_H = 960, 600            # GIF size
FPS = 12

# Mirrors of the app's constants (Sources/Floater/main.swift).
BIG_MARGIN = 20
SMALL_FRACTION = 0.223
EDGE_SNAP = 60
BUTTON = 32
BUTTON_INSET = 8
BUTTON_GAP = 6
ICON = 18
PIN_YELLOW = "#FFC21A"

FONT = "/System/Library/Fonts/SFNS.ttf"
MONO = "/System/Library/Fonts/SFNSMono.ttf"


def px(v):
    return int(round(v * K))


def font(size, weight="Regular", path=FONT):
    f = ImageFont.truetype(path, px(size))
    try:
        f.set_variation_by_name(weight)
    except (OSError, ValueError):
        pass
    return f


def ease(t):
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_rect(a, b, t):
    return tuple(lerp(x, y, t) for x, y in zip(a, b))


# ---------------------------------------------------------------------------------------------
# Icons: the Icon enum's SVG bodies from main.swift, rasterized with AppKit (rasterize.swift).

def load_icons(tmp):
    src = (ROOT / "Sources/Floater/main.swift").read_text()
    bodies = dict(re.findall(r'static let (\w+) = #"(.*?)"#', src))
    jobs, out = [], {}
    for name, body in bodies.items():
        for colour in ("white", PIN_YELLOW):
            svg = tmp / f"{name}-{colour.strip('#')}.svg"
            svg.write_text(
                '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '
                f'fill="none" stroke="{colour}" stroke-width="2" stroke-linecap="round" '
                f'stroke-linejoin="round">{body}</svg>')
            jobs += [str(svg), str(svg.with_suffix(".png"))]
            out[name, colour] = svg.with_suffix(".png")
    subprocess.run(["swift", str(HERE / "rasterize.swift"), str(px(ICON))] + jobs, check=True)
    return {key: Image.open(path).convert("RGBA") for key, path in out.items()}


# ---------------------------------------------------------------------------------------------
# Window geometry: Python mirrors of the app's big mode, small mode and Anchor (top-left origin).

VISIBLE = (0, MENU, SW, SH - MENU)


def big_frame(aspect):
    x, y, w, h = VISIBLE
    ax, ay, aw, ah = x + BIG_MARGIN, y + BIG_MARGIN, w - 2 * BIG_MARGIN, h - 2 * BIG_MARGIN
    bw = min(aw, ah * aspect)
    bh = bw / aspect
    return (ax + (aw - bw) / 2, ay + (ah - bh) / 2, bw, bh)


def anchor(frame):
    x, y, w, h = frame
    vx, vy, vw, vh = VISIBLE

    def side(low, high):
        return 0 if low == high else (-1 if low else 1)

    return (side(x - vx <= EDGE_SNAP, vx + vw - (x + w) <= EDGE_SNAP),
            side(y - vy <= EDGE_SNAP, vy + vh - (y + h) <= EDGE_SNAP))


def place(frame, w, h):
    ax, ay = anchor(frame)
    x, y, fw, fh = frame

    def origin(s, lo, length, new):
        return lo if s < 0 else (lo + length - new if s > 0 else lo + (length - new) / 2)

    return (origin(ax, x, fw, w), origin(ay, y, fh, h), w, h)


def small_frame(aspect, saved=None):
    if saved:
        return place(saved, saved[2], saved[2] / aspect)
    long = SMALL_FRACTION * max(VISIBLE[2], VISIBLE[3])
    w = long if aspect >= 1 else long * aspect
    h = w / aspect
    return (SW - BIG_MARGIN - w, MENU + BIG_MARGIN, w, h)


def reshaped(frame, aspect):
    w = math.sqrt(frame[2] * frame[3] * aspect)
    return place(frame, w, w / aspect)


def button_rects(frame):
    """Hover buttons, right to left: close, pin, small, big (as in AppDelegate.show)."""
    x, y, w, _ = frame
    rects = {}
    for i, name in enumerate(["close", "pin", "small", "big"]):
        bx = x + w - BUTTON_INSET - (i + 1) * BUTTON - i * BUTTON_GAP
        rects[name] = (bx, y + BUTTON_INSET, BUTTON, BUTTON)
    return rects


def centre(rect):
    x, y, w, h = rect
    return (x + w / 2, y + h / 2)


# ---------------------------------------------------------------------------------------------
# Scene state and drawing.

class State:
    def __init__(self):
        self.win = None              # Floater window frame, or None when closed
        self.win_alpha = 1.0
        self.image = None            # key into IMAGES
        self.hover = False
        self.pinned = False
        self.flash = None            # button name showing a check mark
        self.tooltip = None          # tooltip text, shown under the cursor
        self.cursor = (SW / 2, SH / 2)
        self.cursor_kind = "arrow"   # arrow | resize | None
        self.clicks = []             # (x, y, frame index) ripples
        self.caption = None
        self.keys = []               # keycaps shown before the caption
        self.desk = 0.0              # 0 = desktop 1, 1 = desktop 2; fractional while sliding
        self.terminal = []           # lines typed in desktop 2's terminal
        self.saved_small = None
        self.end_card = 0.0          # fade-in of the closing title card


class Renderer:
    def __init__(self, icons, frames_dir):
        self.icons = icons
        self.dir = frames_dir
        self.n = 0
        self.s = State()
        self.cache = {}
        self.f_caption = font(21, "Semibold")
        self.f_key = font(19, "Semibold")
        self.f_tip = font(13.5)
        self.f_menu = font(13, "Semibold")
        self.f_menu_r = font(13)
        self.f_mono = font(15, path=MONO)
        self.f_title = font(54, "Bold")
        self.f_sub = font(20)
        self.desktops = [self.desktop(0), self.desktop(1)]

    # --- static layers -------------------------------------------------------------------

    def gradient(self, c1, c2):
        w, h = px(SW), px(SH)
        small = Image.new("RGB", (2, 2))
        small.putpixel((0, 0), c1)
        small.putpixel((1, 0), tuple((a + b) // 2 for a, b in zip(c1, c2)))
        small.putpixel((0, 1), tuple((a + b) // 2 for a, b in zip(c1, c2)))
        small.putpixel((1, 1), c2)
        return small.resize((w, h), Image.BILINEAR).convert("RGBA")

    def mac_window(self, img, rect, dark=False, title=None):
        x, y, w, h = rect
        shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle(
            [px(x), px(y + 10), px(x + w), px(y + h + 10)], px(12), fill=(0, 0, 0, 90))
        img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(px(18))))
        d = ImageDraw.Draw(img)
        body = (30, 30, 34) if dark else (246, 246, 246)
        bar = (44, 44, 50) if dark else (226, 226, 226)
        d.rounded_rectangle([px(x), px(y), px(x + w), px(y + h)], px(12), fill=body)
        d.rounded_rectangle([px(x), px(y), px(x + w), px(y + 38)], px(12), fill=bar)
        d.rectangle([px(x), px(y + 26), px(x + w), px(y + 38)], fill=bar)
        for i, c in enumerate([(237, 94, 87), (245, 191, 79), (98, 197, 84)]):
            cx, cy = x + 20 + i * 20, y + 19
            d.ellipse([px(cx - 6), px(cy - 6), px(cx + 6), px(cy + 6)], fill=c)
        if title:
            tw = d.textlength(title, font=self.f_menu_r)
            d.text((px(x + w / 2) - tw / 2, px(y + 11)), title, font=self.f_menu_r,
                   fill=(170, 170, 176) if dark else (110, 110, 110))
        return d

    def desktop(self, which):
        if which == 0:
            img = self.gradient((118, 98, 172), (72, 140, 172))
            rect = (70, 96, 600, 520)
            d = self.mac_window(img, rect, title="Trip ideas")
            x, y = rect[0], rect[1]
            # A page with the photo you're about to copy.
            photo = IMAGES["fjord"].resize((px(280), px(187)), Image.LANCZOS).convert("RGBA")
            img.alpha_composite(photo, (px(x + 40), px(y + 70)))
            self.photo_rect = (x + 40, y + 70, 280, 187)
            for i, ln in enumerate([200, 170, 220, 120, 210, 160]):
                d.rounded_rectangle([px(x + 340), px(y + 76 + i * 30), px(x + 340 + ln),
                                     px(y + 86 + i * 30)], px(5), fill=(205, 205, 205))
            for i, ln in enumerate([520, 480, 500, 300, 460, 380]):
                d.rounded_rectangle([px(x + 40), px(y + 290 + i * 34), px(x + 40 + ln),
                                     px(y + 300 + i * 34)], px(5), fill=(205, 205, 205))
        else:
            img = self.gradient((206, 112, 92), (120, 88, 160))
        return img

    # --- per-frame -----------------------------------------------------------------------

    def image_frame(self, key):
        im = IMAGES[key]
        if isinstance(im, list):   # animated GIF: advance every other video frame
            return im[(self.n // 2) % len(im)]
        return im

    def floater(self, img, s):
        x, y, w, h = s.win
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        # Soft window shadow, drawn small and scaled up for speed.
        q = 4
        sh = Image.new("RGBA", (img.width // q, img.height // q), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rectangle([px(x) // q, px(y + 8) // q, px(x + w) // q, px(y + h + 8) // q],
                                     fill=(0, 0, 0, 110))
        layer.alpha_composite(sh.filter(ImageFilter.GaussianBlur(px(14) / q)).resize(img.size, Image.BILINEAR))
        size = (max(1, px(w)), max(1, px(h)))
        src = self.image_frame(s.image)
        key = (id(src), size)
        if key not in self.cache:
            if len(self.cache) > 64:
                self.cache.clear()
            self.cache[key] = src.resize(size, Image.BILINEAR).convert("RGBA")
        layer.alpha_composite(self.cache[key], (px(x), px(y)))
        d = ImageDraw.Draw(layer)
        d.rectangle([px(x), px(y), px(x + w) - 1, px(y + h) - 1], outline=(255, 255, 255, 40))
        if s.hover:
            for name, r in button_rects(s.win).items():
                bx, by, bw, bh = r
                d.ellipse([px(bx + 1), px(by + 1), px(bx + bw - 1), px(by + bh - 1)],
                          fill=(0, 0, 0, 128), outline=(255, 255, 255, 153), width=max(1, px(1)))
                icon = {"close": "x", "pin": "pin", "small": "small", "big": "big"}[name]
                if s.flash == name:
                    icon = "check"
                colour = PIN_YELLOW if name == "pin" and s.pinned else "white"
                ic = self.icons[icon, colour]
                layer.alpha_composite(ic, (px(bx + bw / 2) - ic.width // 2, px(by + bh / 2) - ic.height // 2))
        if s.win_alpha < 1:
            layer.putalpha(layer.getchannel("A").point(lambda a: int(a * s.win_alpha)))
        img.alpha_composite(layer)

    def terminal(self, img, offset):
        rect = (70 + offset, 110, 720, 250)
        d = self.mac_window(img, rect, dark=True, title="Terminal")
        x, y = rect[0], rect[1]
        for i, line in enumerate(self.s.terminal[-8:]):
            colour = (130, 220, 140) if line.startswith("$") else (200, 200, 205)
            d.text((px(x + 18), px(y + 54 + i * 24)), line, font=self.f_mono, fill=colour)

    def menu_bar(self, img):
        bar = Image.new("RGBA", (px(SW), px(MENU)), (255, 255, 255, 70))
        img.alpha_composite(bar)
        d = ImageDraw.Draw(img)
        x = 18
        for i, word in enumerate(["Finder", "File", "Edit", "View", "Window"]):
            f = self.f_menu if i == 0 else self.f_menu_r
            d.text((px(x), px(5)), word, font=f, fill=(20, 20, 24))
            x += d.textlength(word, font=f) / K + 18
        clock = "Wed 9:41"
        d.text((px(SW - 18) - d.textlength(clock, font=self.f_menu_r), px(5)), clock,
               font=self.f_menu_r, fill=(20, 20, 24))

    def tooltip(self, img, text):
        d = ImageDraw.Draw(img)
        lines = text.split("\n")
        w = max(d.textlength(l, font=self.f_tip) for l in lines) / K + 16
        h = len(lines) * 18 + 8
        cx, cy = self.s.cursor
        x, y = min(cx + 2, SW - w - 6), cy + 22
        d.rounded_rectangle([px(x), px(y), px(x + w), px(y + h)], px(5), fill=(42, 42, 46, 245),
                            outline=(90, 90, 96))
        for i, l in enumerate(lines):
            d.text((px(x + 8), px(y + 5 + i * 18)), l, font=self.f_tip, fill=(236, 236, 240))

    def cursor(self, img):
        s = self.s
        x, y = s.cursor
        d = ImageDraw.Draw(img)
        for cx, cy, start in s.clicks:
            age = (self.n - start) / FPS
            if age < 0.4:
                r = 8 + age * 45
                a = int(220 * (1 - age / 0.4))
                d.ellipse([px(cx - r), px(cy - r), px(cx + r), px(cy + r)], outline=(255, 255, 255, a),
                          width=px(2.5))
        if s.cursor_kind == "arrow":
            pts = [(0, 0), (0, 17), (4.2, 13.2), (7, 19.5), (9.6, 18.4), (6.9, 12.3), (12.2, 12.2)]
            poly = [(px(x + a), px(y + b)) for a, b in pts]
            d.polygon(poly, fill=(0, 0, 0), outline=(255, 255, 255), width=px(1.4))
        elif s.cursor_kind == "resize":
            for colour, width in [((255, 255, 255), 5), ((0, 0, 0), 2)]:
                a, b = (x - 8, y - 8), (x + 8, y + 8)
                d.line([px(a[0]), px(a[1]), px(b[0]), px(b[1])], fill=colour, width=px(width / 2 + 0.6))
                for (tx, ty), sgn in [(a, 1), (b, -1)]:
                    d.polygon([(px(tx), px(ty)), (px(tx + sgn * 7), px(ty)), (px(tx), px(ty + sgn * 7))],
                              fill=colour, outline=colour, width=px(width / 4))

    def caption(self, img):
        s = self.s
        if not s.caption and not s.keys:
            return
        d = ImageDraw.Draw(img)
        text_w = d.textlength(s.caption or "", font=self.f_caption) / K
        key_ws = [d.textlength(k, font=self.f_key) / K + 18 for k in s.keys]
        w = text_w + sum(key_ws) + 10 * len(key_ws) + 40
        h = 48
        x, y = (SW - w) / 2, SH - h - 28
        d.rounded_rectangle([px(x), px(y), px(x + w), px(y + h)], px(24), fill=(18, 18, 22, 215))
        kx = x + 20
        for k, kw in zip(s.keys, key_ws):
            d.rounded_rectangle([px(kx), px(y + 10), px(kx + kw), px(y + 38)], px(7), fill=(240, 240, 244))
            d.text((px(kx + 9), px(y + 13)), k, font=self.f_key, fill=(20, 20, 24))
            kx += kw + 10
        d.text((px(kx), px(y + 12)), s.caption or "", font=self.f_caption, fill=(255, 255, 255))

    def end_card(self, img):
        a = self.s.end_card
        if a <= 0:
            return
        # Fades to a solid colour: a see-through overlay dithers badly in the GIF palette.
        layer = Image.new("RGBA", img.size, (22, 22, 28, int(255 * a)))
        d = ImageDraw.Draw(layer)
        t, sub = "Floater", "An always-on-top image window for macOS"
        tw = d.textlength(t, font=self.f_title)
        d.text((img.width / 2 - tw / 2, px(SH / 2 - 60)), t, font=self.f_title, fill=(255, 255, 255, int(255 * a)))
        sw_ = d.textlength(sub, font=self.f_sub)
        d.text((img.width / 2 - sw_ / 2, px(SH / 2 + 12)), sub, font=self.f_sub,
               fill=(220, 220, 228, int(255 * a)))
        img.alpha_composite(layer)

    def tick(self, n=1):
        for _ in range(n):
            s = self.s
            img = Image.new("RGBA", (px(SW), px(SH)))
            off = -s.desk * SW
            img.paste(self.desktops[0], (px(off), 0))   # opaque, and paste allows negative offsets
            img.paste(self.desktops[1], (px(off + SW), 0))
            if s.terminal or s.desk > 0:
                self.terminal(img, off + SW)
            if s.win:
                self.floater(img, s)
            self.menu_bar(img)
            if s.tooltip:
                self.tooltip(img, s.tooltip)
            self.cursor(img)
            self.caption(img)
            self.end_card(img)
            img.convert("RGB").resize((OUT_W, OUT_H), Image.LANCZOS).save(self.dir / f"{self.n:05d}.png")
            self.n += 1

    # --- actions: each advances time, rendering frames -----------------------------------

    def hold(self, secs):
        self.tick(max(1, round(secs * FPS)))

    def say(self, caption, keys=()):
        self.s.caption, self.s.keys = caption, list(keys)

    def move(self, to, secs=0.6, drag=None, on_step=None):
        """Moves the cursor; with drag='window' or a corner name, drags the window along."""
        s = self.s
        start, n = s.cursor, max(1, round(secs * FPS))
        win0 = s.win
        for i in range(1, n + 1):
            t = ease(i / n)
            s.cursor = (lerp(start[0], to[0], t), lerp(start[1], to[1], t))
            dx, dy = s.cursor[0] - start[0], s.cursor[1] - start[1]
            if drag == "window":
                s.win = (win0[0] + dx, win0[1] + dy, win0[2], win0[3])
            elif drag == "bottomright":
                aspect = win0[2] / win0[3]
                w = max(80, max(win0[2] + dx, (win0[3] + dy) * aspect))
                s.win = (win0[0], win0[1], w, w / aspect)
            if on_step:
                on_step()
            self.tick()

    def click(self, at=None, count=1):
        if at:
            self.move(at)
        for i in range(count):
            self.s.clicks.append((*self.s.cursor, self.n))
            self.tick(2 if count > 1 else 1)

    def animate_window(self, to, secs=0.35):
        s = self.s
        start, n = s.win, max(1, round(secs * FPS))
        for i in range(1, n + 1):
            s.win = lerp_rect(start, to, ease(i / n))
            self.tick()

    def button(self, name):
        return centre(button_rects(self.s.win)[name])

    def type(self, line, secs=None):
        s = self.s
        s.terminal.append("")
        n = max(1, round((secs or len(line) / 40) * FPS))
        for i in range(1, n + 1):
            s.terminal[-1] = line[:round(len(line) * i / n)]
            self.tick()


# ---------------------------------------------------------------------------------------------
# The timeline. Each scene is one feature; captions say what's happening.

def scenes(r):
    s = r.s
    aspect = lambda: s.win[2] / s.win[3]

    # Copy an image, open Floater.
    s.cursor = (900, 560)
    r.say("Copy any image")
    r.hold(0.4)
    r.move(centre(r.photo_rect), 0.8)
    r.say("Copy any image", ["⌘C"])
    r.click()
    r.hold(1.0)
    r.say("Open Floater: it floats above every window")
    s.image = "fjord"
    s.win = (330, 200, 540, 360)
    for i in range(1, 7):
        s.win_alpha = i / 6
        r.tick()
    r.move((760, 460), 0.6)
    r.hold(1.0)

    # Move and resize.
    r.say("Drag it anywhere")
    r.move((620, 420), 0.3)
    r.move((520, 380), 0.9, drag="window")
    r.hold(0.4)
    r.say("Drag a corner to resize (aspect ratio kept)")
    x, y, w, h = s.win
    r.move((x + w - 4, y + h - 4), 0.6)
    s.cursor_kind = "resize"
    r.hold(0.3)
    r.move((x + w - 120, y + h - 4), 0.8, drag="bottomright")
    r.move((x + w + 40, y + h + 20), 0.8, drag="bottomright")
    s.cursor_kind = "arrow"
    r.hold(0.5)

    # Hover controls, big mode, small mode.
    r.say("Hover for controls")
    r.move(centre(s.win), 0.4)
    s.hover = True
    r.hold(0.6)
    r.move(r.button("big"), 0.6)
    r.hold(0.15)
    s.tooltip = "Big mode: as large as fits the screen, centred.\nDouble-click the image to toggle between big and small mode."
    r.say("Big mode")
    r.hold(1.3)
    s.tooltip = None
    r.click()
    r.animate_window(big_frame(aspect()))
    r.hold(0.3)
    r.move(r.button("small"), 0.5)
    r.say("Small mode: tucked into the corner")
    r.hold(0.3)
    r.click()
    r.animate_window(small_frame(aspect()))
    r.hold(0.9)

    # Double-click to toggle.
    r.say("Double-click the image to toggle big / small")
    r.move((s.win[0] + s.win[2] * 0.35, s.win[1] + s.win[3] * 0.6), 0.5)
    r.click(count=2)
    r.animate_window(big_frame(aspect()))
    r.move((s.win[0] + s.win[2] * 0.4, s.win[1] + s.win[3] * 0.55), 0.6)
    r.hold(0.4)
    r.click(count=2)
    r.animate_window(small_frame(aspect()))
    r.hold(0.6)

    # Save a small-mode spot.
    r.say("Prefer another spot? Put it there…")
    r.move((s.win[0] + s.win[2] * 0.4, s.win[1] + s.win[3] * 0.6), 0.4)
    target = (SW - BIG_MARGIN - s.win[2], SH - BIG_MARGIN - s.win[3])
    dx, dy = target[0] - s.win[0], target[1] - s.win[1]
    r.move((s.cursor[0] + dx, s.cursor[1] + dy), 1.0, drag="window")
    r.say("…and double-click small mode to save it")
    r.move(r.button("small"), 0.5)
    r.click(count=2)
    s.saved_small = s.win
    s.flash = "small"
    r.hold(0.8)
    s.flash = None
    r.hold(0.3)

    # Paste a new image: the anchored corner stays put.
    r.say("Paste a new image; the corner it's tucked into stays put", ["⌘V"])
    r.move((s.win[0] + s.win[2] * 0.3, s.win[1] + s.win[3] * 0.65), 0.4)
    r.hold(0.6)
    s.image = "valley"
    w_old = s.win
    r.animate_window(reshaped(w_old, IMAGES["valley"].width / IMAGES["valley"].height), 0.25)
    r.hold(1.6)

    # GIFs.
    r.say("Animated GIFs play", ["⌘V"])
    r.hold(0.5)
    s.image = "gif"
    gif = IMAGES["gif"][0]
    r.animate_window(reshaped(s.win, gif.width / gif.height), 0.25)
    r.hold(2.2)

    # Copy back out.
    r.say("Copy it back out", ["⌘C"])
    r.hold(1.6)

    # Pin across desktops.
    r.say("Pin it to keep it on every desktop")
    r.move(r.button("pin"), 0.6)
    r.hold(0.15)
    s.tooltip = "Pin: show on every desktop, not just this one. Click again to unpin."
    r.hold(1.1)
    s.tooltip = None
    r.click()
    s.pinned = True
    r.hold(0.8)
    r.say("Switch desktops: it stays with you", ["⌃→"])
    s.hover = False
    r.move((640, 600), 0.4)
    for i in range(1, 12):
        s.desk = ease(i / 11)
        r.tick()
    r.hold(0.8)

    # Agents.
    r.say("Agents can float images and switch modes too")
    r.hold(0.5)
    r.type("$ cp photo.jpg ~/Library/Application\\ Support/Floater/last.png", 1.0)
    r.type("$ open -n -a Floater --args --restore", 0.7)
    r.hold(0.2)
    s.image = "ridge"
    rid = IMAGES["ridge"]
    r.animate_window(reshaped(s.win, rid.width / rid.height), 0.25)
    r.hold(1.0)
    r.type("$ open -g floater://big", 0.5)
    r.hold(0.2)
    r.animate_window(big_frame(aspect()))
    r.hold(1.2)
    r.type("$ open -g floater://small", 0.5)
    r.hold(0.2)
    r.animate_window(small_frame(aspect(), s.saved_small))
    r.hold(1.0)

    # Close.
    r.say("The close button (or ⌘Q) quits")
    r.move(centre(s.win), 0.5)
    s.hover = True
    r.move(r.button("close"), 0.4)
    r.hold(0.4)
    r.click()
    for i in range(1, 6):
        s.win_alpha = 1 - i / 5
        r.tick()
    s.win = None
    r.say(None)
    s.cursor_kind = None
    for i in range(1, 9):
        s.end_card = i / 8
        r.tick()
    r.hold(2.2)


# ---------------------------------------------------------------------------------------------
# Images used in the demo (assets/CREDITS.md).

def bouncing_ball_gif():
    frames = []
    for i in range(16):
        im = Image.new("RGB", (600, 400))
        d = ImageDraw.Draw(im)
        for yy in range(400):
            c = (int(40 + yy * 0.12), int(48 + yy * 0.2), int(90 + yy * 0.25))
            d.line([(0, yy), (600, yy)], fill=c)
        d.rectangle([0, 330, 600, 400], fill=(36, 40, 62))
        t = i / 16
        bounce = abs(math.sin(t * math.pi))
        by = 320 - bounce * 230
        squash = 1.25 if bounce < 0.08 else 1.0
        rx, ry = 34 * squash, 34 / squash
        sw_ = 40 * (0.6 + 0.4 * (1 - bounce))
        d.ellipse([300 - sw_, 336, 300 + sw_, 348], fill=(24, 26, 42))
        d.ellipse([300 - rx, by - ry, 300 + rx, by + ry], fill=(255, 194, 26))
        frames.append(im)
    return frames


def load_images():
    valley = Image.open(ASSETS / "valley.jpg").convert("RGB")
    vw, vh = valley.size
    portrait = valley.crop(((vw - vh * 4 // 5) // 2, 0, (vw + vh * 4 // 5) // 2, vh))  # 4:5
    return {
        "fjord": Image.open(ASSETS / "fjord.jpg").convert("RGB"),
        "valley": portrait,
        "ridge": Image.open(ASSETS / "ridge.jpg").convert("RGB"),
        "gif": bouncing_ball_gif(),
    }


IMAGES = {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", type=float, metavar="SECONDS",
                    help="write a PNG of the frame at this time to docs/demo/preview.png instead of the GIF")
    ap.add_argument("--keep-frames", action="store_true", help="keep the rendered PNG frames")
    args = ap.parse_args()
    if not shutil.which("ffmpeg") and args.preview is None:
        sys.exit("needs ffmpeg (brew install ffmpeg)")

    IMAGES.update(load_images())
    tmp = Path(tempfile.mkdtemp(prefix="floater-demo-"))
    frames = tmp / "frames"
    frames.mkdir()
    r = Renderer(load_icons(tmp), frames)
    scenes(r)
    print(f"rendered {r.n} frames ({r.n / FPS:.1f}s) in {frames}")

    if args.preview is not None:
        i = min(r.n - 1, round(args.preview * FPS))
        shutil.copy(frames / f"{i:05d}.png", HERE / "preview.png")
        print(f"wrote {HERE / 'preview.png'} (frame {i})")
    else:
        palette = tmp / "palette.png"
        src = ["-framerate", str(FPS), "-i", str(frames / "%05d.png")]
        subprocess.run(["ffmpeg", "-v", "error", "-y", *src,
                        "-vf", "palettegen=max_colors=256:stats_mode=diff", str(palette)], check=True)
        subprocess.run(["ffmpeg", "-v", "error", "-y", *src, "-i", str(palette),
                        "-lavfi", "paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle",
                        "-loop", "0", str(OUT)], check=True)
        print(f"wrote {OUT} ({OUT.stat().st_size / 1e6:.1f} MB)")
    if not args.keep_frames:
        shutil.rmtree(tmp)


if __name__ == "__main__":
    main()
