#!/usr/bin/env python3
"""Generate the Plasma Mistletoe Aurorae window decorations (dark + light).

Writes window-decorations/aurorae/mistletoe-{dark,light}/ containing
metadata.json, mistletoe-<v>rc, decoration.svg and one SVG per button.

The window is a shard: the top-left corner of the titlebar is cut on the
diagonal and traced by a gold thread, and a small gold chip floats just off
the bottom-right corner. The titlebar uses the scheme's Header color so it
merges with app toolbars instead of stacking a second band on top.

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

TITLE = 26                      # titlebar height: slim, no big header
CUT = 12                        # chamfer size
PAD_T, PAD_S, PAD_B = 14, 26, 38  # shadow padding: top, sides, bottom
BUTTON = 26                     # button hit box
EDGE = 32                       # stretchable strip length in the SVG
REF_EDGE = 240                  # edge length of the shadow reference render
SCALE = 2                       # shadow raster scale (HiDPI)
SHADOW = {"dark": (.62, .30), "light": (.26, .14)}  # (ambient, contact) alpha


def hexc(rgb, a=None):
    return "#%02x%02x%02x" % rgb


def colors(variant):
    p = gen_colors.PALETTES[variant.capitalize()]
    return dict(
        title=p["header"][0], title_inactive=p["header_inactive"][0],
        fg=p["fg"], fg_inactive=p["fg_inactive"], gold=p["accent"],
        gold_hover=p["hover"], negative=p["negative"],
        # glyphs on a gold/coral fill: darkest surface for contrast
        ink=gen_colors.PALETTES["Dark"]["view"][0],
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
    chip = f'fill="{hexc(c["gold"])}" fill-opacity="{.85 if active else .35}"'
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
                        f'<rect y="{K - 1}" width="{K - 1}" height="1" {rim}/>'
                        # floating gold chip echoing the cut, just off the corner
                        f'<path d="M{K + 9},{K + 3}L{K + 3},{K + 9}L{K + 3 - D:.3f},{K + 9 - D:.3f}L{K + 9 - D:.3f},{K + 3 - D:.3f}Z" {chip}/>'),
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
# Glyphs drawn in a 26x26 box as filled paths (no strokes, see box()).
GLYPHS = {
    "close": "M9.2,10.6L10.6,9.2L13,11.6L15.4,9.2L16.8,10.6L14.4,13L16.8,15.4L15.4,16.8L13,14.4L10.6,16.8L9.2,15.4L11.6,13Z",
    "minimize": "M9,12.3H17V13.7H9Z",
    "maximize": "M13,8.6L17.4,13L13,17.4L8.6,13ZM13,10.6L10.6,13L13,15.4L15.4,13Z",
    "restore": "M9,11H15V17H9ZM10.4,12.4V15.6H13.6V12.4ZM11,9H17V15H16V10H11Z",
    "alldesktops": "M11.6,11.6H14.4V14.4H11.6Z",
    "keepabove": "M13,9L17,14H9Z",
    "keepbelow": "M13,17L9,12H17Z",
    "shade": "M9,10H17V11.4H9Z",
    "help": "M12.3,15.6H13.7V17H12.3ZM10,11.2C10,9.4 11.4,8.6 13,8.6C14.6,8.6 16,9.5 16,11C16,13 13.7,12.8 13.7,14.6H12.3C12.3,12 14.6,12.3 14.6,11C14.6,10.3 14,9.9 13,9.9C12,9.9 11.4,10.4 11.4,11.2Z",
}
# Diamond "gem" outline and fill, centered in the box.
GEM = "M13,5.5L20.5,13L13,20.5L5.5,13Z"
GEM_RING = GEM + "M13,7.2L7.2,13L13,18.8L18.8,13Z"


def button_svg(name, c):
    fill_hover = c["negative"] if name == "close" else c["gold"]
    glyph = GLYPHS[name]
    fg, ink = hexc(c["fg"]), hexc(c["ink"])
    states = {
        # rest: a quiet hairline gem; the glyph shows on hover, Apple-style
        "active": f'<path d="{GEM_RING}" fill="{fg}" fill-opacity=".55" fill-rule="evenodd"/>',
        "inactive": f'<path d="{GEM_RING}" fill="{fg}" fill-opacity=".22" fill-rule="evenodd"/>',
        "hover": f'<path d="{GEM}" fill="{hexc(fill_hover)}"/><path d="{glyph}" fill="{ink}" fill-rule="evenodd"/>',
        "hover-inactive": f'<path d="{GEM}" fill="{hexc(fill_hover)}"/><path d="{glyph}" fill="{ink}" fill-rule="evenodd"/>',
        "pressed": f'<path d="{GEM}" fill="{hexc(fill_hover)}" fill-opacity=".7"/><path d="{glyph}" fill="{ink}" fill-rule="evenodd"/>',
        "pressed-inactive": f'<path d="{GEM}" fill="{hexc(fill_hover)}" fill-opacity=".7"/><path d="{glyph}" fill="{ink}" fill-rule="evenodd"/>',
        "deactivated": f'<path d="{GEM_RING}" fill="{fg}" fill-opacity=".12" fill-rule="evenodd"/>',
        "deactivated-inactive": f'<path d="{GEM_RING}" fill="{fg}" fill-opacity=".08" fill-rule="evenodd"/>',
    }
    sh = Sheet(width=BUTTON * 4)
    for state, body in states.items():
        sh.add(f"{state}-center", BUTTON, BUTTON, body)
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
TitleEdgeRight=6
TitleEdgeTopMaximized=0
TitleEdgeBottomMaximized=0
TitleEdgeLeftMaximized=6
TitleEdgeRightMaximized=6
TitleBorderLeft=8
TitleBorderRight=8
TitleHeight={TITLE}
ButtonWidth={BUTTON}
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
    for variant in ("dark", "light"):
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
            "Description": f"Plasma Mistletoe ({variant.capitalize()}): slim shard-cut window decoration",
            "Id": name, "License": "GPL-2.0-or-later",
            "Name": f"Mistletoe {variant.capitalize()}", "Version": "0.1.0",
        }}, indent=4) + "\n")
        print("wrote", out)


if __name__ == "__main__":
    main()
