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

# name -> geometry / look. r = corner radius, m = content margin,
# s = shadow extent, a = fill opacity per transparency mode.
FRAMES = {
    "dialogs/background":       dict(r=16, m=12, s=32, a=dict(base=.74, translucent=.74, opaque=.96, solid=1.0)),
    "widgets/background":       dict(r=14, m=10, s=24, a=dict(base=.70, translucent=.70, opaque=.96, solid=1.0)),
    "widgets/panel-background": dict(r=16, m=6,  s=24, a=dict(base=.66, translucent=.66, opaque=.96, solid=1.0)),
    "widgets/tooltip":          dict(r=10, m=8,  s=18, a=dict(base=.88, translucent=.88, opaque=.98, solid=1.0)),
}
MODES = {"base": "", "translucent": "translucent/", "opaque": "opaque/", "solid": "solid/"}
SHADOW = {"dark": .55, "light": .26}
EDGE = 32          # length of the stretchable edge/center strips
HAIR_OPACITY = .11  # 1px glass rim, drawn in the scheme's text color


def falloff(alpha):
    """Soft, gaussian-ish stop list from full alpha at offset 0 to 0 at 1."""
    return [(0, alpha), (.15, alpha * .70), (.35, alpha * .38),
            (.55, alpha * .16), (.78, alpha * .04), (1, 0)]


def stops(alpha):
    return "".join(f'<stop offset="{o}" stop-color="#000" stop-opacity="{a:.4f}"/>' for o, a in falloff(alpha))


def frame_slices(r, opacity):
    """Return {name: (w, h, svg_body)} for the 9 slices at local origin.

    The glass rim is a filled 1px shape, not a stroke: strokes inflate the
    element bounds Plasma measures and open gaps between the slices.
    """
    fill = f'class="ColorScheme-Background" style="fill:currentColor;opacity:{opacity}"'
    rim = f'class="ColorScheme-Text" style="fill:currentColor;opacity:{HAIR_OPACITY}"'
    e = EDGE
    q = r - 1
    return {
        "center": (e, e, f'<rect width="{e}" height="{e}" {fill}/>'),
        "top": (e, r, f'<rect width="{e}" height="{r}" {fill}/><rect width="{e}" height="1" {rim}/>'),
        "bottom": (e, r, f'<rect width="{e}" height="{r}" {fill}/><rect y="{q}" width="{e}" height="1" {rim}/>'),
        "left": (r, e, f'<rect width="{r}" height="{e}" {fill}/><rect width="1" height="{e}" {rim}/>'),
        "right": (r, e, f'<rect width="{r}" height="{e}" {fill}/><rect x="{q}" width="1" height="{e}" {rim}/>'),
        "topleft": (r, r, f'<path d="M0,{r}A{r},{r} 0 0 1 {r},0V{r}Z" {fill}/>'
                          f'<path d="M0,{r}A{r},{r} 0 0 1 {r},0V1A{q},{q} 0 0 0 1,{r}Z" {rim}/>'),
        "topright": (r, r, f'<path d="M0,0A{r},{r} 0 0 1 {r},{r}H0Z" {fill}/>'
                           f'<path d="M0,0A{r},{r} 0 0 1 {r},{r}H{q}A{q},{q} 0 0 0 0,1Z" {rim}/>'),
        "bottomleft": (r, r, f'<path d="M0,0H{r}V{r}A{r},{r} 0 0 1 0,0Z" {fill}/>'
                             f'<path d="M{r},{r}A{r},{r} 0 0 1 0,0H1A{q},{q} 0 0 0 {r},{q}Z" {rim}/>'),
        "bottomright": (r, r, f'<path d="M0,0H{r}A{r},{r} 0 0 1 0,{r}Z" {fill}/>'
                              f'<path d="M{r},0A{r},{r} 0 0 1 0,{r}V{q}A{q},{q} 0 0 0 {q},0Z" {rim}/>'),
    }


def mask_slices(r):
    """Plain black shapes: same geometry as the frame, no rim."""
    e = EDGE
    k = 'style="fill:#000"'
    return {
        "center": (e, e, f'<rect width="{e}" height="{e}" {k}/>'),
        "top": (e, r, f'<rect width="{e}" height="{r}" {k}/>'),
        "bottom": (e, r, f'<rect width="{e}" height="{r}" {k}/>'),
        "left": (r, e, f'<rect width="{r}" height="{e}" {k}/>'),
        "right": (r, e, f'<rect width="{r}" height="{e}" {k}/>'),
        "topleft": (r, r, f'<path d="M0,{r}A{r},{r} 0 0 1 {r},0V{r}Z" {k}/>'),
        "topright": (r, r, f'<path d="M0,0A{r},{r} 0 0 1 {r},{r}H0Z" {k}/>'),
        "bottomleft": (r, r, f'<path d="M0,0H{r}V{r}A{r},{r} 0 0 1 0,0Z" {k}/>'),
        "bottomright": (r, r, f'<path d="M0,0H{r}A{r},{r} 0 0 1 0,{r}Z" {k}/>'),
    }


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

    place("", frame_slices(r, opacity))
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
            f'.ColorScheme-Text{{color:#e9eef3}} .ColorScheme-Background{{color:#161a20}}'
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
                out.write_text(build(cfg, cfg["a"][mode], salpha, uid))
        print("wrote", base)


if __name__ == "__main__":
    main()
