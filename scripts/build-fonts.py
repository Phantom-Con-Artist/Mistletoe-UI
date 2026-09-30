#!/usr/bin/env python3
"""Build the Mistletoe typefaces: Ad Astra (futuristic) and Mythril (whimsical).

Both are drawn here as stroke skeletons and expanded to outlines:

  Ad Astra  faceted monoline: straight strokes only, bevel joins, flat ends.
            Every round form is a chamfered octagon, like the shard frames.
  Mythril   soft monoline: circles and ellipses, round ends, gem-shaped dots,
            and a few curls (l, t, g, j, y, a, i) for its whimsy.

Skeleton primitives (font units, 1000/em; y up, baseline 0):
  L(p, q)                 a straight stroke
  P([p, ...], closed)     a polyline (joins per font style)
  A(cx, cy, rx, ry, a0, a1)  an elliptical arc, degrees, a0 -> a1 (either way)
  F([p, ...])             a filled polygon (dots, gems)

Outlines are unioned with skia-pathops, then each glyph gets the same side
bearings from its real bounds, so spacing needs no hand-tuning.

Needs fonttools and skia-pathops:
  python3 -m venv ~/.cache/mistletoe/fontenv
  ~/.cache/mistletoe/fontenv/bin/pip install fonttools skia-pathops
Run: ~/.cache/mistletoe/fontenv/bin/python scripts/build-fonts.py
"""
import math
from pathlib import Path

import pathops
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.t2CharStringPen import T2CharStringPen

ROOT = Path(__file__).resolve().parent.parent
K = 4 / 3 * math.tan(math.pi / 8)   # cubic handle for a 90 degree arc


# ---- Skeleton primitives -------------------------------------------------
def L(p, q):
    return ("poly", [p, q], False)


def P(points, closed=False):
    return ("poly", list(points), closed)


def A(cx, cy, rx, ry, a0, a1):
    return ("arc", cx, cy, rx, ry, a0, a1)


def F(points):
    return ("fill", list(points))


def gem(x, y, s):
    """A diamond dot centred on (x, y), s from centre to tip."""
    return F([(x, y + s), (x + s * 0.8, y), (x, y - s), (x - s * 0.8, y)])


def square(x, y, s):
    return F([(x - s, y - s), (x + s, y - s), (x + s, y + s), (x - s, y + s)])


def octagon(x0, y0, x1, y1, k):
    return P([(x0 + k, y0), (x1 - k, y0), (x1, y0 + k), (x1, y1 - k),
              (x1 - k, y1), (x0 + k, y1), (x0, y1 - k), (x0, y0 + k)], True)


# ---- Outline construction ------------------------------------------------
def polygon(points):
    path = pathops.Path()
    pen = path.getPen()
    pen.moveTo(points[0])
    for p in points[1:]:
        pen.lineTo(p)
    pen.closePath()
    return path


def arc_points(cx, cy, rx, ry, a0, a1):
    """Cubic segments approximating an elliptical arc: [(c1, c2, end), ...]."""
    sweep = a1 - a0
    n = max(1, math.ceil(abs(sweep) / 90 - 1e-9))
    step = math.radians(sweep / n)
    h = 4 / 3 * math.tan(step / 4)
    out = []
    t = math.radians(a0)
    for _ in range(n):
        t2 = t + step
        p0 = (math.cos(t), math.sin(t))
        p3 = (math.cos(t2), math.sin(t2))
        c1 = (p0[0] - h * p0[1], p0[1] + h * p0[0])
        c2 = (p3[0] + h * p3[1], p3[1] - h * p3[0])
        out.append(tuple((cx + rx * x, cy + ry * y) for x, y in (c1, c2, p3)))
        t = t2
    return out


def point_on(cx, cy, rx, ry, a):
    t = math.radians(a)
    return (cx + rx * math.cos(t), cy + ry * math.sin(t))


def circle(x, y, r):
    path = pathops.Path()
    pen = path.getPen()
    pen.moveTo((x + r, y))
    for c1, c2, end in arc_points(x, y, r, r, 0, 360):
        pen.curveTo(c1, c2, end)
    pen.closePath()
    return path


def arc_band(cx, cy, rx, ry, a0, a1, h):
    """The stroke of an elliptical arc: outer arc out, inner arc back."""
    path = pathops.Path()
    pen = path.getPen()
    if abs(a1 - a0) >= 360:
        # A full ring: outer contour, and the hole as its own contour.
        for sx, sy, s, e in ((rx + h, ry + h, 0, 360), (rx - h, ry - h, 360, 0)):
            pen.moveTo(point_on(cx, cy, sx, sy, s))
            for c1, c2, end in arc_points(cx, cy, sx, sy, s, e):
                pen.curveTo(c1, c2, end)
            pen.closePath()
        return path
    pen.moveTo(point_on(cx, cy, rx + h, ry + h, a0))
    for c1, c2, end in arc_points(cx, cy, rx + h, ry + h, a0, a1):
        pen.curveTo(c1, c2, end)
    pen.lineTo(point_on(cx, cy, rx - h, ry - h, a1))
    for c1, c2, end in arc_points(cx, cy, rx - h, ry - h, a1, a0):
        pen.curveTo(c1, c2, end)
    pen.closePath()
    return path


def segment(p, q, h):
    dx, dy = q[0] - p[0], q[1] - p[1]
    d = math.hypot(dx, dy) or 1
    nx, ny = -dy / d * h, dx / d * h
    return polygon([(p[0] + nx, p[1] + ny), (q[0] + nx, q[1] + ny),
                    (q[0] - nx, q[1] - ny), (p[0] - nx, p[1] - ny)])


def bevel(prev, p, nxt, h):
    """Fill the gap at a join with the quad between the two strokes' edges."""
    def normal(a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]
        d = math.hypot(dx, dy) or 1
        return -dy / d * h, dx / d * h
    n1, n2 = normal(prev, p), normal(p, nxt)
    return polygon([(p[0] + n1[0], p[1] + n1[1]), (p[0] + n2[0], p[1] + n2[1]),
                    (p[0] - n1[0], p[1] - n1[1]), (p[0] - n2[0], p[1] - n2[1])])


def expand(skeleton, weight, round_ends):
    h = weight / 2
    parts = []
    for item in skeleton:
        kind = item[0]
        if kind == "fill":
            parts.append(polygon(item[1]))
        elif kind == "poly":
            pts, closed = item[1], item[2]
            ring = pts + [pts[0]] if closed else pts
            for a, b in zip(ring, ring[1:]):
                parts.append(segment(a, b, h))
            if round_ends:
                parts.extend(circle(x, y, h) for x, y in pts)
            else:
                n = len(pts)
                inner = range(n) if closed else range(1, n - 1)
                for i in inner:
                    parts.append(bevel(pts[i - 1], pts[i], pts[(i + 1) % n], h))
        elif kind == "arc":
            _, cx, cy, rx, ry, a0, a1 = item
            parts.append(arc_band(cx, cy, rx, ry, a0, a1, h))
            if round_ends and abs(a1 - a0) < 360:
                parts.append(circle(*point_on(cx, cy, rx, ry, a0), h))
                parts.append(circle(*point_on(cx, cy, rx, ry, a1), h))
    return parts


def merge(parts):
    """Union all stroke pieces into clean, non-overlapping outlines.

    Pieces come out of the builders wound either way; overlapping pieces of
    opposite winding would cancel (visible seams, lost dots). So every
    single-contour piece is made counter-clockwise first (a ring keeps its
    hole opposite to its outline), then one simplify pass removes overlaps.
    """
    combined = pathops.Path()
    pen = combined.getPen()
    for part in parts:
        contours = list(part.contours)
        if len(contours) == 1 and contours[0].clockwise:
            contours[0].reverse()
        for c in contours:
            c.draw(pen)
    combined.simplify(fix_winding=True, keep_starting_points=False)
    return combined


# ---- Ad Astra ----------------------------------------------------------------
def ad_astra():
    w = 66                      # stroke weight
    h = w / 2
    B, T = h, 700 - h           # cap bottom/top centre lines
    X = 500 - h                 # x-height centre line
    M, XM = 350, 250            # cap and x-height middles
    D = -200 + h                # descender
    AS = 720 - h                # ascender
    k, j = 118, 86              # chamfers: caps, lowercase

    def box_open_right(l, r, top, bot, kk):
        return [(r, top), (l + kk, top), (l, top - kk), (l, bot + kk), (l + kk, bot), (r, bot)]

    g = {}
    # Capitals: width set by l..r; spacing is automatic.
    l, r = 0, 520
    g["A"] = [P([(l, B), (l, T - k), (l + k, T), (r - k, T), (r, T - k), (r, B)]), L((l, M - 20), (r, M - 20))]
    g["B"] = [P([(l, B), (l, T), (r - 40 - k, T), (r - 40, T - k), (r - 40, M + k * 0.6), (r - 40 - k * 0.6, M), (l, M)]),
              P([(l, M), (r - k, M), (r, M - k), (r, B + k), (r - k, B), (l, B)])]
    g["C"] = [P(box_open_right(l, r, T, B, k))]
    g["D"] = [P([(l, B), (l, T), (r - k, T), (r, T - k), (r, B + k), (r - k, B)], True)]
    g["E"] = [P(box_open_right(l, r - 20, T, B, k)), L((l, M), (r - 80, M))]
    g["F"] = [P([(r - 20, T), (l + k, T), (l, T - k), (l, B)]), L((l, M), (r - 80, M))]
    g["G"] = [P(box_open_right(l, r, T, B, k)[:-1] + [(r - k, B), (r, B + k), (r, M), (r - 190, M)])]
    g["H"] = [L((l, B), (l, T)), L((r, B), (r, T)), L((l, M), (r, M))]
    g["I"] = [L((0, B), (0, T))]
    g["J"] = [P([(r - 60, T), (r - 60, B + k), (r - 60 - k, B), (l + 40, B), (l, B + 40), (l, B + 170)])]
    g["K"] = [L((l, B), (l, T)), P([(r, T), (l + 150, M), (l, M)]), L((l + 150, M), (r, B))]
    g["L"] = [P([(l, T), (l, B + k), (l + k, B), (r - 30, B)])]
    g["M"] = [P([(l, B), (l, T - k), (l + k, T), (300 - k, T), (300, T - k), (300, B)]),
              P([(300, T - k), (300 + k, T), (600 - k, T), (600, T - k), (600, B)])]
    g["N"] = [P([(l, B), (l, T), (r, B), (r, T)])]
    g["O"] = [octagon(l, B, r + 20, T, k)]
    g["P"] = [P([(l, B), (l, T), (r - k, T), (r, T - k), (r, M + k * 0.8), (r - k * 0.8, M), (l, M)])]
    g["Q"] = [octagon(l, B, r + 20, T, k), L((r - 140, B + 150), (r + 60, B - 60))]
    g["R"] = g["P"] + [L((l + 240, M), (r, B))]
    g["S"] = [P([(r, T), (l + k, T), (l, T - k), (l, M + k * 0.6), (l + k * 0.6, M), (r - k * 0.6, M),
                 (r, M - k * 0.6), (r, B + k), (r - k, B), (l, B)])]
    g["T"] = [L((l - 20, T), (r + 20, T)), L(((l + r) / 2, T), ((l + r) / 2, B))]
    g["U"] = [P([(l, T), (l, B + k), (l + k, B), (r - k, B), (r, B + k), (r, T)])]
    g["V"] = [P([(l - 10, T), ((l + r) / 2, B), (r + 10, T)])]
    g["W"] = [P([(0, T), (170, B), (340, T - 250), (510, B), (680, T)])]
    g["X"] = [L((l, T), (r, B)), L((r, T), (l, B))]
    g["Y"] = [P([(l, T), ((l + r) / 2, M), (r, T)]), L(((l + r) / 2, M), ((l + r) / 2, B))]
    g["Z"] = [P([(l, T), (r, T), (l, B), (r, B)])]

    # Figures.
    l, r = 0, 440
    g["zero"] = [octagon(l, B, r, T, k), L((r - k * 0.7, T - k * 0.7), (l + k * 0.7, B + k * 0.7))]
    g["one"] = [P([(110, T - 110), (220, T), (220, B)])]
    g["two"] = [P([(l, T), (r - k, T), (r, T - k), (r, M + k * 0.6), (r - k * 0.6, M), (l + k * 0.6, M),
                   (l, M - k * 0.6), (l, B), (r, B)])]
    g["three"] = [P([(l, T), (r - k, T), (r, T - k), (r, B + k), (r - k, B), (l, B)]), L((l + 90, M), (r, M))]
    g["four"] = [P([(l, T), (l, M - 40), (r + 30, M - 40)]), L((r - 60, T), (r - 60, B))]
    g["five"] = [P([(r, T), (l, T), (l, M), (r - k * 0.8, M), (r, M - k * 0.8), (r, B + k), (r - k, B), (l, B)])]
    g["six"] = [P([(r, T), (l + k, T), (l, T - k), (l, B + k), (l + k, B), (r - k, B), (r, B + k),
                   (r, M - k * 0.8), (r - k * 0.8, M), (l, M)])]
    g["seven"] = [P([(l, T), (r, T), (r, T - 60), (l + 130, B)])]
    g["eight"] = [octagon(l, B, r, T, k), L((l, M), (r, M))]
    g["nine"] = [P([(l, B), (r - k, B), (r, B + k), (r, T - k), (r - k, T), (l + k, T), (l, T - k),
                    (l, M + k * 0.8), (l + k * 0.8, M), (r, M)])]

    # Lowercase.
    l, r = 0, 400
    bowl_r = [(l, X), (r - j, X), (r, X - j), (r, B + j), (r - j, B), (l, B)]
    bowl_l = [(r, X), (l + j, X), (l, X - j), (l, B + j), (l + j, B), (r, B)]
    g["a"] = [P(bowl_l), L((r, X), (r, B))]
    g["b"] = [L((l, AS), (l, B)), P(bowl_r)]
    g["c"] = [P(bowl_l)]
    g["d"] = [P(bowl_l), L((r, AS), (r, B))]
    g["e"] = [P([(l, XM), (r, XM), (r, X - j), (r - j, X), (l + j, X), (l, X - j), (l, B + j), (l + j, B), (r, B)])]
    g["f"] = [P([(300, AS), (120 + j, AS), (120, AS - j), (120, B)]), L((0, X), (280, X))]
    g["g"] = [P(bowl_l), P([(r, X), (r, D + j), (r - j, D), (l + 20, D)])]
    g["h"] = [L((l, AS), (l, B)), P([(l, X), (r - j, X), (r, X - j), (r, B)])]
    g["i"] = [L((0, B), (0, X)), square(0, 640, h)]
    g["j"] = [P([(120, X), (120, D + j), (120 - j, D), (-40, D)]), square(120, 640, h)]
    g["k"] = [L((l, AS), (l, B)), P([(r - 20, X), (l + 130, XM), (l, XM)]), L((l + 130, XM), (r, B))]
    g["l"] = [L((0, AS), (0, B))]
    g["m"] = [L((l, B), (l, X)), P([(l, X), (280 - j, X), (280, X - j), (280, B)]),
              P([(280, X - j), (280 + j, X), (560 - j, X), (560, X - j), (560, B)])]
    g["n"] = [L((l, B), (l, X)), P([(l, X), (r - j, X), (r, X - j), (r, B)])]
    g["o"] = [octagon(l, B, r, X, j)]
    g["p"] = [L((l, X), (l, D)), P(bowl_r)]
    g["q"] = [P(bowl_l), L((r, X), (r, D))]
    g["r"] = [L((l, B), (l, X)), P([(l, X - j), (l + j, X), (280, X)])]
    g["s"] = [P([(r, X), (l + j, X), (l, X - j), (l, XM + j * 0.5), (l + j * 0.5, XM), (r - j * 0.5, XM),
                 (r, XM - j * 0.5), (r, B + j), (r - j, B), (l, B)])]
    g["t"] = [P([(110, 640), (110, B + j), (110 + j, B), (300, B)]), L((0, X), (290, X))]
    g["u"] = [P([(l, X), (l, B + j), (l + j, B), (r, B)]), L((r, X), (r, B))]
    g["v"] = [P([(l - 10, X), (r / 2, B), (r + 10, X)])]
    g["w"] = [P([(0, X), (140, B), (280, X - 170), (420, B), (560, X)])]
    g["x"] = [L((l, X), (r, B)), L((r, X), (l, B))]
    g["y"] = [P([(l, X), (l, B + j), (l + j, B), (r, B)]), P([(r, X), (r, D + j), (r - j, D), (l + 20, D)])]
    g["z"] = [P([(l, X), (r, X), (l, B), (r, B)])]

    punctuation(g, w, h, B, T, X, M, square_dot=True)
    return dict(family="Ad Astra", ps="AdAstra-Regular", weight=w, round_ends=False, glyphs=g,
                side=46, space=280, cap=700, xh=500, asc=720, desc=-200,
                description="Ad Astra: a faceted, futuristic monoline for Plasma Mistletoe")


# ---- Mythril -----------------------------------------------------------------
def mythril():
    w = 56
    h = w / 2
    B, T = h, 690 - h           # cap bottom/top centre lines
    X = 460 - h                 # x-height centre line
    AS = 760 - h                # ascenders rise above the caps
    D = -230 + h
    XM = (X + B) / 2
    M = (T + B) / 2

    def curl_foot(x, y, r=58):
        """A stem that flicks out to the right at the baseline."""
        return A(x + r, y, r, r, 180, 270)

    def hook_top(x, y, r=46):
        """Ascender top bending gently to the left, like a flag."""
        return A(x - r, y, r, r, 0, 70)

    def tail(x, y, r):
        """Descender that curls back under to the left."""
        return A(x - r, y, r, r, 0, -165)

    rx, ry = 196, (X - B) / 2        # the o
    cy = (X + B) / 2
    g = {}
    # Lowercase.
    g["o"] = [A(rx, cy, rx, ry + 8, 0, 360)]
    g["c"] = [A(rx, cy, rx, ry + 8, 42, 318)]
    g["e"] = [L((20, cy - 6), (2 * rx - 4, cy + 34)), A(rx, cy, rx, ry + 8, 12, 322)]
    g["a"] = [A(rx - 10, cy, rx - 10, ry + 8, 0, 360), L((2 * rx - 20, X), (2 * rx - 20, B + 58)),
              curl_foot(2 * rx - 20, B + 58)]
    g["d"] = [A(rx - 10, cy, rx - 10, ry + 8, 0, 360), L((2 * rx - 20, AS), (2 * rx - 20, B + 58)),
              curl_foot(2 * rx - 20, B + 58), hook_top(2 * rx - 20, AS)]
    g["b"] = [L((0, AS), (0, B)), A(rx + 10, cy, rx - 10, ry + 8, 0, 360), hook_top(0, AS)]
    g["p"] = [L((0, X), (0, D)), A(rx + 10, cy, rx - 10, ry + 8, 0, 360)]
    g["q"] = [A(rx - 10, cy, rx - 10, ry + 8, 0, 360), L((2 * rx - 20, X), (2 * rx - 20, D + 40)),
              curl_foot(2 * rx - 20, D + 40, 46)]
    g["g"] = [A(rx - 10, cy, rx - 10, ry + 8, 0, 360), L((2 * rx - 20, X), (2 * rx - 20, D + 150)),
              tail(2 * rx - 20 - 150, D + 150, 150)]
    g["g"][-1] = A(2 * rx - 20 - 150, D + 150, 150, 150 - h, 0, -170)
    arch = lambda x0, x1: [A((x0 + x1) / 2, X - (x1 - x0) / 2, (x1 - x0) / 2, (x1 - x0) / 2, 180, 0),
                           L((x1, X - (x1 - x0) / 2), (x1, B))]
    g["n"] = [L((0, X), (0, B))] + arch(0, 360)
    g["m"] = [L((0, X), (0, B))] + arch(0, 290) + arch(290, 580)
    g["h"] = [L((0, AS), (0, B)), hook_top(0, AS)] + arch(0, 360)
    g["u"] = [L((0, X), (0, X - 180)), A(180, X - 180, 180, 180 + 0, 180, 360), L((360, X), (360, B + 58)),
              curl_foot(360, B + 58)]
    g["u"][1] = A(180, B + 180 - 0, 180, 180 - 0, 180, 360)
    g["u"][0] = L((0, X), (0, B + 180))
    g["i"] = [L((0, X), (0, B + 58)), curl_foot(0, B + 58), gem(0, 600, 58)]
    g["j"] = [L((120, X), (120, D + 120)), A(0, D + 120, 120, 120 - h, 0, -170), gem(120, 600, 58)]
    g["l"] = [L((0, AS), (0, B + 70)), A(70, B + 70, 70, 70 - 0, 180, 270), hook_top(0, AS)]
    g["t"] = [L((90, 620), (90, B + 70)), A(160, B + 70, 70, 70, 180, 270), L((-10, X), (240, X))]
    g["f"] = [L((110, B), (110, 590)), A(220, 590, 110, 150, 180, 20), L((0, X), (250, X))]
    g["k"] = [L((0, AS), (0, B)), hook_top(0, AS), A(170, 280, 150, 110, -150, 110),
              L((70, 240), (340, B))]
    g["k"][2] = A(120, 300, 120, 100, 200, 20)
    g["k"] = [L((0, AS), (0, B)), hook_top(0, AS), L((330, X), (0, 190)), L((130, 250), (340, B))]
    g["r"] = [L((0, X), (0, B)), A(150, X - 130, 150, 130, 180, 70)]
    g["s"] = [A(150, X - 102, 150, 102 - h / 2, 25, 270), A(150, B + 102, 150, 102 - h / 2, 90, -155)]
    g["v"] = [P([(0, X), (190, B), (380, X)])]
    g["w"] = [P([(0, X), (150, B), (300, X - 160), (450, B), (600, X)])]
    g["x"] = [L((0, X), (340, B)), L((340, X), (0, B))]
    g["y"] = [L((0, X), (0, B + 180)), A(180, B + 180, 180, 180, 180, 360), L((360, X), (360, D + 150)),
              A(210, D + 150, 150, 150 - h, 0, -170)]
    g["z"] = [P([(0, X), (340, X), (0, B), (340, B)])]

    # Capitals.
    W = 560
    g["A"] = [P([(0, B), (W / 2, T), (W, B)]), A(W / 2, 250, 170, 50, 200, 340)]
    g["A"][1] = L((110, 230), (W - 110, 230))
    g["B"] = [L((0, B), (0, T)), L((0, T), (250, T)), A(250, T - 150, 150, 150 - h * 0, 90, -90), L((250, M), (0, M)),
              L((0, B), (280, B)), A(280, (M + B) / 2, 160, (M - B) / 2, -90, 90), ]
    g["B"][2] = A(250, (T + M) / 2, 150, (T - M) / 2, 90, -90)
    g["B"][5] = A(280, (M + B) / 2, 170, (M - B) / 2, -90, 90)
    g["C"] = [A(300, M, 300, M - B + 8, 45, 315)]
    g["D"] = [L((0, B), (0, T)), L((0, T), (220, T)), A(220, M, 300, (T - B) / 2, 90, -90), L((220, B), (0, B))]
    g["E"] = [P([(460, T), (0, T), (0, B), (460, B)]), L((0, M + 10), (330, M + 10))]
    g["F"] = [P([(460, T), (0, T), (0, B)]), L((0, M + 10), (330, M + 10))]
    g["G"] = [A(300, M, 300, M - B + 8, 50, 330), L((600 - 38, M - 60), (360, M - 60))]
    g["G"][1] = P([(300 + 300 * math.cos(math.radians(330)), M + (M - B + 8) * math.sin(math.radians(330))),
                   (590, M - 40), (380, M - 40)])
    g["H"] = [L((0, B), (0, T)), L((480, B), (480, T)), L((0, M), (480, M))]
    g["I"] = [L((0, B), (0, T))]
    g["J"] = [L((300, T), (300, 200)), A(130, 200, 170, 172, 0, -180)]
    g["K"] = [L((0, B), (0, T)), L((440, T), (0, 270)), L((150, 390), (470, B))]
    g["L"] = [P([(0, T), (0, B), (420, B)])]
    g["M"] = [P([(0, B), (40, T), (330, 200), (620, T), (660, B)])]
    g["N"] = [P([(0, B), (0, T), (500, B), (500, T)])]
    g["O"] = [A(320, M, 320, M - B + 8, 0, 360)]
    g["P"] = [L((0, B), (0, T)), L((0, T), (240, T)), A(240, (T + 300) / 2, 170, (T - 300) / 2, 90, -90),
              L((240, 300), (0, 300))]
    g["Q"] = [A(320, M, 320, M - B + 8, 0, 360), A(560, 20, 160, 110, 150, 270)]
    g["R"] = g["P"] + [L((230, 300), (470, B))]
    g["S"] = [A(250, (T + M) / 2 + 4, 230, (T - M) / 2 + 4, 20, 270), A(250, (M + B) / 2 - 4, 250, (M - B) / 2 + 4, 90, -160)]
    g["T"] = [L((0, T), (540, T)), L((270, T), (270, B))]
    g["U"] = [L((0, T), (0, 260)), A(260, 260, 260, 260 - h, 180, 360), L((520, T), (520, 260))]
    g["V"] = [P([(0, T), (280, B), (560, T)])]
    g["W"] = [P([(0, T), (190, B), (400, T - 260), (610, B), (800, T)])]
    g["X"] = [L((0, T), (520, B)), L((520, T), (0, B))]
    g["Y"] = [P([(0, T), (270, 330), (540, T)]), L((270, 330), (270, B))]
    g["Z"] = [P([(0, T), (500, T), (0, B), (500, B)])]

    # Figures.
    g["zero"] = [A(230, M, 230, M - B + 8, 0, 360)]
    g["one"] = [P([(40, T - 110), (160, T), (160, B)])]
    g["two"] = [A(220, T - 180, 210, 180, 160, -20), P([(220 + 210 * math.cos(math.radians(-20)), T - 180 + 180 * math.sin(math.radians(-20))), (0, B), (450, B)])]
    g["three"] = [A(220, (T + M) / 2, 200, (T - M) / 2, 150, -90), A(220, (M + B) / 2, 230, (M - B) / 2, 90, -150)]
    g["four"] = [P([(340, B), (340, T), (0, 220), (460, 220)])]
    g["five"] = [P([(420, T), (40, T), (20, 400)]), A(220, 230, 220, 205, 150, -155)]
    g["six"] = [A(230, 230, 210, 205, 0, 360), A(330, 300, 330, 370, 180, 95)]
    g["seven"] = [P([(0, T), (450, T), (140, B)])]
    g["eight"] = [A(230, 515, 180, 150, 0, 360), A(230, 200, 220, 175, 0, 360)]
    g["nine"] = [A(230, 460, 210, 205, 0, 360), A(110, 390, 330, 370, 0, -85)]

    punctuation(g, w, h, B, T, X, M, square_dot=False)
    return dict(family="Mythril", ps="Mythril-Regular", weight=w, round_ends=True, glyphs=g,
                side=44, space=260, cap=690, xh=460, asc=760, desc=-230,
                description="Mythril: a whimsical, soft monoline for Plasma Mistletoe")


# ---- Shared punctuation ----------------------------------------------------------
def punctuation(g, w, h, B, T, X, M, square_dot):
    dot = (lambda x, y: square(x, y, h + 2)) if square_dot else (lambda x, y: gem(x, y, h + 24))
    g["period"] = [dot(0, B + 4)]
    g["comma"] = [dot(0, B + 4), L((h * 0.4, B - 10), (-30, -130))]
    g["colon"] = [dot(0, B + 4), dot(0, X - 10)]
    g["semicolon"] = [dot(0, X - 10), dot(0, B + 4), L((h * 0.4, B - 10), (-30, -130))]
    g["exclam"] = [L((0, T), (0, 200)), dot(0, B + 4)]
    g["question"] = [P([(0, T - 60), (60, T), (300, T), (360, T - 60), (360, 440), (180, 330), (180, 200)]), dot(180, B + 4)]
    g["quotesingle"] = [L((0, T), (0, T - 180))]
    g["quotedbl"] = [L((0, T), (0, T - 180)), L((120, T), (120, T - 180))]
    g["quoteright"] = [L((40, T), (-20, T - 190))]
    g["quoteleft"] = [L((-20, T - 190), (40, T))]
    g["quotedblright"] = [L((40, T), (-20, T - 190)), L((160, T), (100, T - 190))]
    g["quotedblleft"] = [L((-20, T - 190), (40, T)), L((100, T - 190), (160, T))]
    g["hyphen"] = [L((0, 260), (240, 260))]
    g["endash"] = [L((0, 260), (440, 260))]
    g["emdash"] = [L((0, 260), (880, 260))]
    g["underscore"] = [L((0, -80), (480, -80))]
    g["parenleft"] = [P([(160, T + 40), (40, T - 120), (40, 40), (160, -120)])]
    g["parenright"] = [P([(0, T + 40), (120, T - 120), (120, 40), (0, -120)])]
    g["bracketleft"] = [P([(160, T + 40), (0, T + 40), (0, -120), (160, -120)])]
    g["bracketright"] = [P([(0, T + 40), (160, T + 40), (160, -120), (0, -120)])]
    g["slash"] = [L((0, -80), (340, T + 40))]
    g["backslash"] = [L((0, T + 40), (340, -80))]
    g["bar"] = [L((0, T + 60), (0, -140))]
    g["plus"] = [L((0, 280), (400, 280)), L((200, 80), (200, 480))]
    g["minus"] = [L((0, 280), (400, 280))]
    g["equal"] = [L((0, 360), (400, 360)), L((0, 200), (400, 200))]
    g["less"] = [P([(400, 500), (0, 280), (400, 60)])]
    g["greater"] = [P([(0, 500), (400, 280), (0, 60)])]
    g["asterisk"] = [L((150, T), (150, T - 260)), L((30, T - 60), (270, T - 200)), L((270, T - 60), (30, T - 200))]
    g["numbersign"] = [L((120, T - 40), (80, B)), L((320, T - 40), (280, B)), L((0, 470), (420, 470)), L((0, 230), (420, 230))]
    # Rings, not dots, so the sign reads at text sizes: octagons for the
    # faceted face, circles for the round one.
    if square_dot:
        g["percent"] = [L((20, B), (500, T)), octagon(0, T - 190, 170, T, 50), octagon(350, B, 520, B + 190, 50)]
    else:
        g["percent"] = [L((20, B), (500, T)), A(85, T - 95, 85, 95, 0, 360), A(435, B + 95, 85, 95, 0, 360)]
    g["ampersand"] = [P([(460, B), (80, 420), (80, T - 60), (140, T), (300, T), (360, T - 60), (360, 520), (0, 260),
                         (0, B + 60), (60, B), (300, B), (460, 280)])]
    g["at"] = [octagon(0, -40, 660, T, 120), octagon(180, 140, 420, 420, 60), L((420, 420), (420, 160)),
               P([(420, 160), (480, 120), (540, 160)])]
    g["periodcentered"] = [dot(0, 300)]
    g["degree"] = [octagon(0, T - 200, 200, T, 60)]
    g["ellipsis"] = [dot(0, B + 4), dot(180, B + 4), dot(360, B + 4)]
    g["dollar"] = g["S"] + [L((260, T + 80), (260, -80))] if "S" in g else []


GLYPH_UNICODE = {
    **{c: ord(c) for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"},
    "zero": 0x30, "one": 0x31, "two": 0x32, "three": 0x33, "four": 0x34, "five": 0x35,
    "six": 0x36, "seven": 0x37, "eight": 0x38, "nine": 0x39,
    "period": 0x2E, "comma": 0x2C, "colon": 0x3A, "semicolon": 0x3B, "exclam": 0x21, "question": 0x3F,
    "quotesingle": 0x27, "quotedbl": 0x22, "quoteright": 0x2019, "quoteleft": 0x2018,
    "quotedblright": 0x201D, "quotedblleft": 0x201C, "hyphen": 0x2D, "endash": 0x2013, "emdash": 0x2014,
    "underscore": 0x5F, "parenleft": 0x28, "parenright": 0x29, "bracketleft": 0x5B, "bracketright": 0x5D,
    "slash": 0x2F, "backslash": 0x5C, "bar": 0x7C, "plus": 0x2B, "minus": 0x2212, "equal": 0x3D,
    "less": 0x3C, "greater": 0x3E, "asterisk": 0x2A, "numbersign": 0x23, "percent": 0x25,
    "ampersand": 0x26, "at": 0x40, "periodcentered": 0xB7, "degree": 0xB0, "ellipsis": 0x2026,
    "dollar": 0x24, "space": 0x20,
}


def build(spec):
    order = [".notdef", "space"] + [n for n in spec["glyphs"] if spec["glyphs"][n]]
    charstrings, metrics = {}, {}
    side = spec["side"]
    for name in order:
        if name == "space":
            pen = T2CharStringPen(spec["space"], None)
            charstrings[name] = pen.getCharString()
            metrics[name] = (spec["space"], 0)
            continue
        if name == ".notdef":
            parts = expand([P([(0, 0), (400, 0), (400, 700), (0, 700)], True)], spec["weight"], False)
        else:
            parts = expand(spec["glyphs"][name], spec["weight"], spec["round_ends"])
        merged = merge(parts)
        bounds = BoundsPen(None)
        merged.draw(bounds)
        xmin, _, xmax, _ = bounds.bounds
        shift = side - xmin
        advance = round(xmax - xmin + 2 * side)
        pen = T2CharStringPen(advance, None)
        from fontTools.pens.transformPen import TransformPen
        merged.draw(TransformPen(pen, (1, 0, 0, 1, shift, 0)))
        charstrings[name] = pen.getCharString()
        metrics[name] = (advance, side)

    fb = FontBuilder(1000, isTTF=False)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap({GLYPH_UNICODE[n]: n for n in order if n in GLYPH_UNICODE})
    fb.setupCFF(spec["ps"], {"FullName": spec["family"] + " Regular"}, charstrings, {})
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=spec["asc"] + 40, descent=spec["desc"] - 40)
    fb.setupNameTable({
        "familyName": spec["family"], "styleName": "Regular",
        "uniqueFontIdentifier": spec["ps"] + " 1.0 Mistletoe", "fullName": spec["family"] + " Regular",
        "psName": spec["ps"], "version": "Version 1.000",
        "copyright": "Copyright 2026 Subhradeep Sarkar",
        "licenseDescription": "This Font Software is licensed under the SIL Open Font License, Version 1.1.",
        "licenseInfoURL": "https://openfontlicense.org", "description": spec["description"],
    })
    fb.setupOS2(sTypoAscender=spec["asc"], sTypoDescender=spec["desc"], sTypoLineGap=120,
                usWinAscent=spec["asc"] + 80, usWinDescent=-spec["desc"] + 80,
                sxHeight=spec["xh"], sCapHeight=spec["cap"], achVendID="MSTL", fsType=0)
    fb.setupPost()
    out = ROOT / "fonts" / spec["family"].replace(" ", "")
    out.mkdir(parents=True, exist_ok=True)
    path = out / (spec["ps"] + ".otf")
    fb.save(str(path))
    ofl = ROOT / "fonts" / "Exo2" / "OFL.txt"
    (out / "OFL.txt").write_text(
        f"Copyright 2026 Subhradeep Sarkar, with Reserved Font Name \"{spec['family']}\".\n\n"
        + ofl.read_text().split("\n", 3)[-1] if ofl.exists() else "SIL Open Font License 1.1\n")
    print("wrote", path, len(order), "glyphs")


if __name__ == "__main__":
    build(ad_astra())
    build(mythril())
