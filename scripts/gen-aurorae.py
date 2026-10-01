#!/usr/bin/env python3
"""Generate the Plasma Mistletoe Aurorae window decorations (dark + light).

Writes window-decorations/aurorae/mistletoe-{dark,light}/ containing
metadata.json, mistletoe-<v>rc, decoration.svg and one SVG per button.

The window is a shard: the top-left corner of the titlebar is cut on the
diagonal and traced by a gold thread. That is the only ornament. The
titlebar uses the scheme's Header color so it merges with app toolbars into
one flat header, and the three window buttons are plain thin glyphs that
are always visible; hovering one lays a quiet tonal square behind it (the
close button's is the scheme's negative colour).

Aurorae's SVG is a 9-slice that also carries the shadow padding. QtSvg can't
blur, so the shadow is a real Gaussian blur of the window shape rendered with
Pillow at 2x and embedded as PNG slices; everything else is vector.

Run: python3 scripts/gen-aurorae.py
"""
import base64
import importlib.util
import io
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("gen_colors", ROOT / "scripts" / "gen-colors.py")
gen_colors = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen_colors)

TITLE = 30                      # titlebar height: slim, with room to aim
CUT = 12                        # chamfer size
PAD_T, PAD_S, PAD_B = 14, 26, 38  # shadow padding: top, sides, bottom
BUTTON = 30                     # button box height (and glyph grid)
BUTTON_W = 38                   # button hit box width: easy targets
EDGE = 32                       # stretchable strip length in the SVG
REF_EDGE = 240                  # edge length of the shadow reference render
SCALE = 2                       # shadow raster scale (HiDPI)
SHADOW = {"dark": (.62, .30), "light": (.26, .14), "neon": (.62, .30), "ember": (.62, .30)}  # (ambient, contact) alpha


def hexc(rgb, a=None):
    return "#%02x%02x%02x" % rgb


def colors(variant):
    p = gen_colors.PALETTES[variant.capitalize()]
    return dict(
        title=p["header"][0], title_inactive=p["header_inactive"][0],
        fg=p["fg"], fg_inactive=p["fg_inactive"], gold=p["accent"],
        gold_hover=p["hover"], negative=p["negative"],
        # glyphs on a gold/coral fill: darkest surface for contrast
        ink=(gen_colors.PALETTES["Dark"] if variant == "light" else p)["view"][0],
    )


# ---------------------------------------------------------------- shadow ----
def shadow_slices(ambient, contact):
    """Blur the window shape once; cut it into 8 border slices (PNG, 2x)."""
    wc, hc = PAD_S + CUT, PAD_T + TITLE          # top-left corner size
    wr, hb = CUT + PAD_S, CUT + PAD_B            # right width, bottom height
    tw, th = wc + REF_EDGE + wr, hc + REF_EDGE + hb
    S = SCALE
    shape = Image.new("L", (tw * S, th * S), 0)
    x0, y0, x1, y1 = PAD_S, PAD_T, tw - PAD_S, th - PAD_B
    poly = [(x0 + CUT, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0 + CUT)]
    ImageDraw.Draw(shape).polygon([(x * S, y * S) for x, y in poly], fill=255)

    def layer(radius, dy, alpha):
        return (ImageChops.offset(shape, 0, dy * S)
                .filter(ImageFilter.GaussianBlur(radius * S))
                .point(lambda v: int(v * alpha)))
    a = ImageChops.lighter(layer(14, 8, ambient), layer(2.5, 1, contact))
    a = ImageChops.subtract(a, shape)             # nothing under the window
    img = Image.new("RGBA", a.size, (0, 0, 0, 0))
    img.putalpha(a)

    mid_x, mid_y = wc + (REF_EDGE - EDGE) // 2, hc + (REF_EDGE - EDGE) // 2
    boxes = {
        "topleft": (0, 0, wc, hc), "top": (mid_x, 0, EDGE, hc),
        "topright": (tw - wr, 0, wr, hc),
        "left": (0, mid_y, wc, EDGE), "right": (tw - wr, mid_y, wr, EDGE),
        "bottomleft": (0, th - hb, wc, hb), "bottom": (mid_x, th - hb, EDGE, hb),
        "bottomright": (tw - wr, th - hb, wr, hb),
    }
    out = {}
    for name, (x, y, w, h) in boxes.items():
        buf = io.BytesIO()
        img.crop((x * S, y * S, (x + w) * S, (y + h) * S)).save(buf, "PNG", optimize=True)
        data = base64.b64encode(buf.getvalue()).decode()
        out[name] = f'<image width="{w}" height="{h}" preserveAspectRatio="none" href="data:image/png;base64,{data}" xlink:href="data:image/png;base64,{data}"/>'
    return out


# ------------------------------------------------------------ decoration ----
def box(w, h):
    """Invisible full-size rect: pins each element's bounds to its slice."""
    return f'<rect width="{w}" height="{h}" fill="#000" fill-opacity="0"/>'


def frame(c, active, shadow, maximized=False):
    """{slice: (w, h, body)} for one decoration state."""
    title = hexc(c["title"] if active else c["title_inactive"])
    rim = f'fill="{hexc(c["fg"])}" fill-opacity="{.10 if active else .06}"'
    gold = f'fill="{hexc(c["gold"])}" fill-opacity="{.9 if active else .0}"'
    body = f'fill="{title}"'
    wc, hc = PAD_S + CUT, PAD_T + TITLE
    wr, hb = CUT + PAD_S, CUT + PAD_B
    E, P, T, K = EDGE, PAD_S, PAD_T, CUT
    D = 2 ** .5
    if maximized:
        return {"center": (E, TITLE, f'<rect width="{E}" height="{TITLE}" {body}/>')}
    s = shadow
    return {
        "topleft": (wc, hc, s["topleft"] +
                    f'<path d="M{P + K},{T}H{wc}V{hc}H{P}V{T + K}Z" {body}/>'
                    f'<rect x="{P + K}" y="{T}" width="{wc - P - K}" height="1" {rim}/>'
                    f'<rect x="{P}" y="{T + K}" width="1" height="{hc - T - K}" {rim}/>'
                    f'<path d="M{P},{T + K}L{P + K},{T}V{T + D:.4f}L{P + D:.4f},{T + K}Z" {gold}/>'),
        "top": (E, hc, s["top"] + f'<rect y="{T}" width="{E}" height="{TITLE}" {body}/>'
                f'<rect y="{T}" width="{E}" height="1" {rim}/>'),
        "topright": (wr, hc, s["topright"] + f'<rect y="{T}" width="{K}" height="{TITLE}" {body}/>'
                     f'<rect y="{T}" width="{K}" height="1" {rim}/>'
                     f'<rect x="{K - 1}" y="{T + 1}" width="1" height="{TITLE - 1}" {rim}/>'),
        "left": (wc, E, s["left"] + f'<rect x="{P}" width="{K}" height="{E}" {body}/>'
                 f'<rect x="{P}" width="1" height="{E}" {rim}/>'),
        "center": (E, E, f'<rect width="{E}" height="{E}" {body}/>'),
        "right": (wr, E, s["right"] + f'<rect width="{K}" height="{E}" {body}/>'
                  f'<rect x="{K - 1}" width="1" height="{E}" {rim}/>'),
        "bottomleft": (wc, hb, s["bottomleft"] + f'<rect x="{P}" width="{K}" height="{K}" {body}/>'
                       f'<rect x="{P}" width="1" height="{K}" {rim}/>'
                       f'<rect x="{P + 1}" y="{K - 1}" width="{K - 1}" height="1" {rim}/>'),
        "bottom": (E, hb, s["bottom"] + f'<rect width="{E}" height="{K}" {body}/>'
                   f'<rect y="{K - 1}" width="{E}" height="1" {rim}/>'),
        "bottomright": (wr, hb, s["bottomright"] + f'<rect width="{K}" height="{K}" {body}/>'
                        f'<rect x="{K - 1}" width="1" height="{K}" {rim}/>'
                        f'<rect y="{K - 1}" width="{K - 1}" height="1" {rim}/>'),
    }


def mask():
    wc, hc = PAD_S + CUT, PAD_T + TITLE
    wr, hb = CUT + PAD_S, CUT + PAD_B
    E, P, T, K = EDGE, PAD_S, PAD_T, CUT
    k = 'fill="#000"'
    return {
        "topleft": (wc, hc, f'<path d="M{P + K},{T}H{wc}V{hc}H{P}V{T + K}Z" {k}/>'),
        "top": (E, hc, f'<rect y="{T}" width="{E}" height="{TITLE}" {k}/>'),
        "topright": (wr, hc, f'<rect y="{T}" width="{K}" height="{TITLE}" {k}/>'),
        "left": (wc, E, f'<rect x="{P}" width="{K}" height="{E}" {k}/>'),
        "center": (E, E, f'<rect width="{E}" height="{E}" {k}/>'),
        "right": (wr, E, f'<rect width="{K}" height="{E}" {k}/>'),
        "bottomleft": (wc, hb, f'<rect x="{P}" width="{K}" height="{K}" {k}/>'),
        "bottom": (E, hb, f'<rect width="{E}" height="{K}" {k}/>'),
        "bottomright": (wr, hb, f'<rect width="{K}" height="{K}" {k}/>'),
    }


class Sheet:
    """Lays out named elements left to right, wrapping rows."""

    def __init__(self, width=420):
        self.width, self.x, self.y, self.row, self.parts = width, 0, 0, 0, []

    def add(self, eid, w, h, body):
        if self.x + w > self.width:
            self.x, self.y, self.row = 0, self.y + self.row, 0
        self.parts.append(f'<g id="{eid}" transform="translate({self.x},{self.y})">{box(w, h)}{body}</g>')
        self.x += w
        self.row = max(self.row, h)

    def svg(self):
        h = self.y + self.row
        return ('<?xml version="1.0" encoding="UTF-8"?>\n'
                f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
                f'viewBox="0 0 {self.width} {h}" width="{self.width}" height="{h}">\n'
                + "\n".join(self.parts) + "\n</svg>\n")


def decoration_svg(c, shadow):
    sh = Sheet()
    for prefix, slices in (("decoration", frame(c, True, shadow)),
                           ("decoration-inactive", frame(c, False, shadow)),
                           ("decoration-maximized", frame(c, True, shadow, maximized=True)),
                           ("decoration-maximized-inactive", frame(c, False, shadow, maximized=True)),
                           ("mask", mask())):
        for name, (w, h, body) in slices.items():
            sh.add(f"{prefix}-{name}", w, h, body)
    sh.add("hint-stretch-borders", 2, 2, "")
    return sh.svg()


# --------------------------------------------------------------- buttons ----
# Thin line glyphs drawn as filled paths (no strokes, see box()) on a 16x16
# grid, centered in the button box. 1.2px lines, crisp at 1x.
def _ring(x0, y0, x1, y1, t=1.2):
    """A rectangular outline of thickness t."""
    return (f"M{x0},{y0}H{x1}V{y1}H{x0}Z"
            f"M{x0 + t},{y0 + t}V{y1 - t}H{x1 - t}V{y0 + t}Z")


def _cross(a, b, t=0.85):
    """An X from (a,a) to (b,b): two diagonal bars of half-width t."""
    return (f"M{a + t},{a}L8,{8 - t}L{b - t},{a}L{b},{a + t}L{8 + t},8L{b},{b - t}"
            f"L{b - t},{b}L8,{8 + t}L{a + t},{b}L{a},{b - t}L{8 - t},8L{a},{a + t}Z")


GLYPHS = {
    "close": _cross(3.5, 12.5),
    "minimize": "M3.5,7.4H12.5V8.6H3.5Z",
    "maximize": _ring(3.5, 3.5, 12.5, 12.5),
    "restore": _ring(3.5, 5.5, 10.5, 12.5) + "M5.5,3.5H12.5V10.5H11.3V4.7H5.5Z",
    "alldesktops": "M8,5.2A2.8,2.8 0 1 0 8,10.8A2.8,2.8 0 1 0 8,5.2ZM8,6.4A1.6,1.6 0 1 1 8,9.6A1.6,1.6 0 1 1 8,6.4Z",
    "keepabove": "M8,4.6L12.4,9.6L11.5,10.4L8,6.4L4.5,10.4L3.6,9.6Z",
    "keepbelow": "M8,11.4L3.6,6.4L4.5,5.6L8,9.6L11.5,5.6L12.4,6.4Z",
    "shade": "M3.5,4.4H12.5V5.6H3.5ZM8,7.2L11.4,10.8H4.6Z",
    "help": "M7.4,10.6H8.6V11.8H7.4ZM5.4,6.6C5.4,5 6.6,4.2 8,4.2C9.4,4.2 10.6,5 10.6,6.4C10.6,8.2 8.6,8 8.6,9.6H7.4C7.4,7.4 9.4,7.6 9.4,6.4C9.4,5.8 8.8,5.4 8,5.4C7.2,5.4 6.6,5.8 6.6,6.6Z",
}


def button_svg(name, c):
    fg, ink = hexc(c["fg"]), hexc(c["ink"])
    gx, gy = (BUTTON_W - 16) / 2, (BUTTON - 16) / 2

    def glyph(color, opacity):
        return (f'<path transform="translate({gx},{gy})" d="{GLYPHS[name]}" fill="{color}" '
                f'fill-opacity="{opacity}" fill-rule="evenodd"/>')

    def plate(opacity):
        # Tonal square behind the glyph, inset so neighbours don't touch.
        if name == "close":
            return (f'<rect x="3" y="3" width="{BUTTON_W - 6}" height="{BUTTON - 6}" '
                    f'fill="{hexc(c["negative"])}" fill-opacity="{opacity}"/>')
        return (f'<rect x="3" y="3" width="{BUTTON_W - 6}" height="{BUTTON - 6}" '
                f'fill="{fg}" fill-opacity="{opacity * .14:.3f}"/>')

    on_plate = ink if name == "close" else fg
    states = {
        "active": glyph(fg, .78),
        "inactive": glyph(fg, .36),
        "hover": plate(1) + glyph(on_plate, 1),
        "hover-inactive": plate(1) + glyph(on_plate, 1),
        "pressed": plate(1.6 if name != "close" else .75) + glyph(on_plate, 1),
        "pressed-inactive": plate(1.6 if name != "close" else .75) + glyph(on_plate, 1),
        "deactivated": glyph(fg, .2),
        "deactivated-inactive": glyph(fg, .12),
    }
    sh = Sheet(width=BUTTON_W * 4)
    for state, body in states.items():
        sh.add(f"{state}-center", BUTTON_W, BUTTON, body)
    return sh.svg()


# ------------------------------------------------------------------ rc ----
def rc(c):
    return f"""[General]
TitleAlignment=Center
TitleVerticalAlignment=Center
Animation=160
ActiveTextColor={",".join(map(str, c["fg"]))}
InactiveTextColor={",".join(map(str, c["fg_inactive"]))}
UseTextShadow=false
HaloActive=false
HaloInactive=false

[Layout]
BorderLeft=1
BorderRight=1
BorderBottom=1
TitleEdgeTop=0
TitleEdgeBottom=0
TitleEdgeLeft={CUT - 2}
TitleEdgeRight=2
TitleEdgeTopMaximized=0
TitleEdgeBottomMaximized=0
TitleEdgeLeftMaximized=6
TitleEdgeRightMaximized=2
TitleBorderLeft=8
TitleBorderRight=8
TitleHeight={TITLE}
ButtonWidth={BUTTON_W}
ButtonHeight={BUTTON}
ButtonSpacing=0
ButtonMarginTop=0
ButtonMarginTopMaximized=0
ExplicitButtonSpacer=8
PaddingTop={PAD_T}
PaddingBottom={PAD_B}
PaddingLeft={PAD_S}
PaddingRight={PAD_S}
"""


def main():
    for variant in ("dark", "light", "neon", "ember"):
        c = colors(variant)
        name = f"mistletoe-{variant}"
        out = ROOT / "window-decorations" / "aurorae" / name
        out.mkdir(parents=True, exist_ok=True)
        (out / "decoration.svg").write_text(decoration_svg(c, shadow_slices(*SHADOW[variant])))
        for b in GLYPHS:
            (out / f"{b}.svg").write_text(button_svg(b, c))
        (out / f"{name}rc").write_text(rc(c))
        (out / "metadata.json").write_text(json.dumps({"KPlugin": {
            "Authors": [{"Name": "Subhradeep Sarkar"}],
            "Description": f"Plasma Mistletoe ({variant.capitalize()}): slim, flat shard-cut window decoration",
            "Id": name, "License": "GPL-2.0-or-later",
            "Name": f"Mistletoe {variant.capitalize()}", "Version": "0.1.0",
        }}, indent=4) + "\n")
        print("wrote", out)


if __name__ == "__main__":
    main()
