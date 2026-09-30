#!/usr/bin/env python3
"""Generate the Plasma Mistletoe Plasma-style frame SVGs (dark + light).

Each frame is a 9-slice: center/top/bottom/left/right + four corners, drawn
three times on one sheet: the frame itself, its `shadow-*` and its `mask-*`
(the blur/contrast region KWin uses). Fill follows the color scheme through
the ColorScheme-Background / ColorScheme-Text classes, so one set of shapes
serves both variants; only the shadow strength differs.

Run: python3 scripts/gen-svgs.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# name -> geometry / look. r = chamfer size, m = content margin,
# s = shadow extent, a = fill opacity per transparency mode.
# Surfaces are matte, not glass: blur is off (see plasmarc), so fills stay
# nearly opaque. The panel is invisible: Mistletoe has no taskbar, so its
# panels only carry floating widgets that draw their own plates.
FRAMES = {
    "dialogs/background":       dict(r=12, m=10, s=30, a=dict(base=.96, translucent=.96, opaque=.98, solid=1.0)),
    "widgets/background":       dict(r=10, m=8,  s=24, a=dict(base=.94, translucent=.94, opaque=.97, solid=1.0)),
    "widgets/panel-background": dict(r=4,  m=2,  s=4,  a=dict(base=0, translucent=0, opaque=0, solid=0), invisible=True),
    "widgets/tooltip":          dict(r=8,  m=7,  s=18, a=dict(base=.97, translucent=.97, opaque=.98, solid=1.0)),
}
MODES = {"base": "", "translucent": "translucent/", "opaque": "opaque/", "solid": "solid/"}
SHADOW = {"dark": .60, "light": .22}
EDGE = 32          # length of the stretchable edge/center strips
HAIR_OPACITY = .10  # 1px bone rim on straight edges (scheme text color)
GOLD_OPACITY = .85  # 1px gold thread on the diagonal cuts (scheme focus color)


def falloff(alpha):
    """Soft, gaussian-ish stop list from full alpha at offset 0 to 0 at 1."""
    return [(0, alpha), (.15, alpha * .70), (.35, alpha * .38),
            (.55, alpha * .16), (.78, alpha * .04), (1, 0)]


def stops(alpha):
    return "".join(f'<stop offset="{o}" stop-color="#000" stop-opacity="{a:.4f}"/>' for o, a in falloff(alpha))


# Shard geometry: top-left and bottom-right corners are cut on the diagonal
# (the "chamfer"), the other two stay square. Every frame reads as a cut
# prism rather than a rounded card.
D = 2 ** .5  # a 1px band measured perpendicular to a 45 degree cut


def corner_paths(c):
    """Fill outline of each corner slice (c x c, local origin)."""
    return {
        "topleft": f"M0,{c}L{c},0V{c}Z",
        "topright": f"M0,0H{c}V{c}H0Z",
        "bottomleft": f"M0,0H{c}V{c}H0Z",
        "bottomright": f"M0,0H{c}L0,{c}Z",
    }


def frame_slices(c, opacity, rims=True):
    """Return {name: (w, h, svg_body)} for the 9 slices at local origin.

    Rims are filled 1px shapes, never strokes: strokes inflate the element
    bounds Plasma measures and open gaps between the slices. Straight edges
    get a faint bone hairline; the diagonal cuts get the gold accent.
    """
    fill = f'class="ColorScheme-Background" style="fill:currentColor;opacity:{opacity}"'
    rim = f'class="ColorScheme-Text" style="fill:currentColor;opacity:{HAIR_OPACITY if rims else 0}"'
    gold = f'class="ColorScheme-ButtonFocus" style="fill:currentColor;opacity:{GOLD_OPACITY if rims else 0}"'
    e = EDGE
    q = c - 1
    cp = corner_paths(c)
    return {
        "center": (e, e, f'<rect width="{e}" height="{e}" {fill}/>'),
        "top": (e, c, f'<rect width="{e}" height="{c}" {fill}/><rect width="{e}" height="1" {rim}/>'),
        "bottom": (e, c, f'<rect width="{e}" height="{c}" {fill}/><rect y="{q}" width="{e}" height="1" {rim}/>'),
        "left": (c, e, f'<rect width="{c}" height="{e}" {fill}/><rect width="1" height="{e}" {rim}/>'),
        "right": (c, e, f'<rect width="{c}" height="{e}" {fill}/><rect x="{q}" width="1" height="{e}" {rim}/>'),
        "topleft": (c, c, f'<path d="{cp["topleft"]}" {fill}/>'
                          f'<path d="M0,{c}L{c},0V{D:.4f}L{D:.4f},{c}Z" {gold}/>'),
        "topright": (c, c, f'<path d="{cp["topright"]}" {fill}/>'
                           f'<path d="M0,0H{c}V{c}H{q}V1H0Z" {rim}/>'),
        "bottomleft": (c, c, f'<path d="{cp["bottomleft"]}" {fill}/>'
                             f'<path d="M0,0H1V{q}H{c}V{c}H0Z" {rim}/>'),
        "bottomright": (c, c, f'<path d="{cp["bottomright"]}" {fill}/>'
                              f'<path d="M{c},0L0,{c}V{c - D:.4f}L{c - D:.4f},0Z" {gold}/>'),
    }


def mask_slices(c):
    """Plain black shapes: same geometry as the frame, no rim."""
    e = EDGE
    k = 'style="fill:#000"'
    sl = {
        "center": (e, e, f'<rect width="{e}" height="{e}" {k}/>'),
        "top": (e, c, f'<rect width="{e}" height="{c}" {k}/>'),
        "bottom": (e, c, f'<rect width="{e}" height="{c}" {k}/>'),
        "left": (c, e, f'<rect width="{c}" height="{e}" {k}/>'),
        "right": (c, e, f'<rect width="{c}" height="{e}" {k}/>'),
    }
    for name, d in corner_paths(c).items():
        sl[name] = (c, c, f'<path d="{d}" {k}/>')
    return sl


def shadow_slices(s, alpha, uid):
    """Shadow ring of thickness s. Edges fade outward; corners are radial."""
    st = stops(alpha)
    def lin(gid, x1, y1, x2, y2):
        return f'<linearGradient id="{uid}{gid}" gradientUnits="userSpaceOnUse" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{st}</linearGradient>'
    def rad(gid, cx, cy):
        return f'<radialGradient id="{uid}{gid}" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{s}">{st}</radialGradient>'
    e = EDGE
    defs = "".join([
        lin("gt", 0, s, 0, 0), lin("gb", 0, 0, 0, s),
        lin("gl", s, 0, 0, 0), lin("gr", 0, 0, s, 0),
        rad("ctl", s, s), rad("ctr", 0, s), rad("cbl", s, 0), rad("cbr", 0, 0),
    ])
    def R(w, h, g):
        return f'<rect width="{w}" height="{h}" fill="url(#{uid}{g})"/>'
    sl = {
        "top": (e, s, R(e, s, "gt")), "bottom": (e, s, R(e, s, "gb")),
        "left": (s, e, R(s, e, "gl")), "right": (s, e, R(s, e, "gr")),
        "topleft": (s, s, R(s, s, "ctl")), "topright": (s, s, R(s, s, "ctr")),
        "bottomleft": (s, s, R(s, s, "cbl")), "bottomright": (s, s, R(s, s, "cbr")),
    }
    return defs, sl


def build(cfg, opacity, shadow_alpha, uid):
    r, m, s = cfg["r"], cfg["m"], cfg["s"]
    groups = []
    x = y = 0
    pad = 0
    rowh = 0
    sheetw = 320

    def place(prefix, slices):
        nonlocal x, y, rowh
        for name, (w, h, body) in slices.items():
            if x + w > sheetw:
                x, y, rowh = 0, y + rowh + pad, 0
            groups.append(f'<g id="{prefix}{name}" transform="translate({x},{y})">{body}</g>')
            x += w + pad
            rowh = max(rowh, h)

    place("", frame_slices(r, opacity, rims=not cfg.get("invisible")))
    place("mask-", mask_slices(r))
    sdefs, sl = shadow_slices(s, shadow_alpha, uid)
    place("shadow-", sl)

    def hint(idn, w, h):
        nonlocal x, y, rowh
        if x + w > sheetw:
            x, y, rowh = 0, y + rowh + pad, 0
        groups.append(f'<rect id="{idn}" x="{x}" y="{y}" width="{w}" height="{h}" fill="#f0f"/>')
        x += w + pad
        rowh = max(rowh, h)

    for side, (w, h) in (("top", (4, m)), ("bottom", (4, m)), ("left", (m, 4)), ("right", (m, 4))):
        hint(f"hint-{side}-margin", w, h)
    for side, (w, h) in (("top", (4, s)), ("bottom", (4, s)), ("left", (s, 4)), ("right", (s, 4))):
        hint(f"shadow-hint-{side}-margin", w, h)

    hint("hint-stretch-borders", 2, 2)
    height = y + rowh
    return (f'<?xml version="1.0" encoding="UTF-8"?>\n'
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {sheetw} {height}" width="{sheetw}" height="{height}">\n'
            f'<defs><style type="text/css" id="current-color-scheme">'
            f'.ColorScheme-Text{{color:#e9e4d6}} .ColorScheme-Background{{color:#111316}} .ColorScheme-ButtonFocus{{color:#d4ac70}}'
            f'</style>{sdefs}</defs>\n' + "\n".join(groups) + "\n</svg>\n")


def main():
    for variant, salpha in SHADOW.items():
        base = ROOT / "themes" / f"mistletoe-{variant}"
        for name, cfg in FRAMES.items():
            for mode, sub in MODES.items():
                # Plasma looks for e.g. translucent/widgets/background, so the
                # mode directory wraps the usual path.
                out = base / f"{sub}{name}.svg"
                out.parent.mkdir(parents=True, exist_ok=True)
                uid = name.replace("/", "-") + mode[:2]
                shadow = 0 if cfg.get("invisible") else salpha
                out.write_text(build(cfg, cfg["a"][mode], shadow, uid))
        print("wrote", base)


if __name__ == "__main__":
    main()
