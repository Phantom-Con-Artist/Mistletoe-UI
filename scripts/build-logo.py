#!/usr/bin/env python3
"""Build the Mistletoe UI logo: the mark, the wordmark and PNG previews.

The mark is a butterfly shattered into sharp shards radiating from an impact
at its thorax, the outer fragments breaking away: straight edges and sharp
corners only. Four flat colours, one per edition: gold (Dark), orchid (Neon),
vermilion (Ember) and bone (Light). Four flat
facets, one per edition colour: gold (Dark), orchid (Neon), vermilion
(Ember) and bone (Light). No gradients, no outlines, no soft corners. The wordmark is Exo 2 SemiBold converted to outlines, so the
SVGs render anywhere without the font installed.

Writes branding/:
  mistletoe-mark.svg            the mark alone (any background)
  mistletoe-ui-dark.svg/.png    mark + wordmark for dark backgrounds
  mistletoe-ui-light.svg/.png   mark + wordmark for light backgrounds
  mistletoe-mark.png            512px mark

Needs fonttools (see build-fonts.py for the venv) and ImageMagick for PNGs.
Run: ~/.cache/mistletoe/fontenv/bin/python scripts/build-logo.py
"""
import math
import subprocess
from pathlib import Path

import pathops
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "branding"

GOLD, ORCHID, VERMILION, BONE = "#D4AC70", "#C46EC8", "#DE6A48", "#DED9CC"
OBSIDIAN = "#111316"


def poly_path(points):
    path = pathops.Path()
    pen = path.getPen()
    pen.moveTo(points[0])
    for p in points[1:]:
        pen.lineTo(p)
    pen.closePath()
    return path


def leaf(base, tip, width, bend=0.0, n=24):
    """A pointed leaf from base to tip: lens-shaped, both ends sharp, with an
    optional sideways bend so paired leaves don't mirror exactly."""
    (bx, by), (tx, ty) = base, tip
    dx, dy = tx - bx, ty - by
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    nx, ny = -uy, ux
    left, right = [], []
    for i in range(n + 1):
        t = i / n
        half = width / 2 * math.sin(math.pi * t) ** 0.85
        off = bend * math.sin(math.pi * t) * length
        cx, cy = bx + dx * t + nx * off, by + dy * t + ny * off
        left.append((cx + nx * half, cy + ny * half))
        right.append((cx - nx * half, cy - ny * half))
    return poly_path(left + right[::-1][1:-1])


def berry(cx, cy, r, sides=9):
    """A berry as a faceted polygon (no circles: every edge straight)."""
    return poly_path([(cx + r * math.cos(2 * math.pi * k / sides + 0.3),
                       cy + r * math.sin(2 * math.pi * k / sides + 0.3)) for k in range(sides)])


def union(paths):
    out = pathops.Path()
    pathops.union(paths, out.getPen())
    return out


def mark(berry_color=BONE):  # berry_color: the body
    """A butterfly shattered into shards, Frostbite-style.

    The silhouette (slim body and antennae, gold and orchid upper wings,
    vermilion lower wings) is cut by a crack pattern centred on the thorax: jittered radial cracks crossed by jittered ring cracks, some
    cells split diagonally. Each shard gets a hairline gap and is pushed
    outwards in proportion to its distance from the impact, so the gaps
    widen towards the tips and the outermost fragments break away. Every
    edge is straight and every corner sharp. Deterministic (fixed seed).
    256 x 256 grid, y down.
    """
    import random
    rnd = random.Random(7)
    impact = (128.0, 132.0)          # the thorax: where the butterfly shatters from
    gap = 2.4

    # Silhouette regions, highest priority first (overlaps go to the first).
    # A butterfly of sharp facets: slim body and antennae, large upper wings,
    # smaller lower wings; slightly asymmetric so it feels alive.
    body = union([
        poly_path([(128, 96), (135, 118), (133, 176), (128, 192), (123, 176), (121, 118)]),
        poly_path([(126, 100), (129, 99), (104, 48), (101, 49)]),        # antennae
        poly_path([(127, 99), (130, 100), (156, 50), (153, 49)]),
    ])
    upper_l = poly_path([(122, 124), (70, 58), (34, 44), (14, 68), (26, 118), (60, 146), (120, 146)])
    upper_r = poly_path([(134, 124), (188, 62), (226, 50), (244, 76), (230, 124), (194, 148), (136, 146)])
    lower = union([
        poly_path([(122, 150), (66, 158), (44, 196), (62, 226), (100, 214), (124, 172)]),
        poly_path([(134, 150), (190, 160), (210, 198), (190, 224), (154, 212), (132, 172)]),
    ])
    regions = []
    taken = pathops.Path()
    for shape, color in ((body, berry_color), (upper_l, GOLD), (upper_r, ORCHID), (lower, VERMILION)):
        regions.append((pathops.op(shape, taken, pathops.PathOp.DIFFERENCE), color))
        taken = union([taken, shape])

    # Crack pattern: rays x rings with jittered vertices, so cells tile.
    rays = 28
    angles = sorted((i + rnd.uniform(-0.3, 0.3)) * 2 * math.pi / rays for i in range(rays))
    # Dense near the impact, larger shards outwards.
    rings = [0, 7, 16, 28, 44, 64, 90, 122, 162, 220]
    vert = [[(impact[0] + r * (1 + rnd.uniform(-0.18, 0.18)) * math.cos(a),
              impact[1] + r * (1 + rnd.uniform(-0.18, 0.18)) * math.sin(a)) for r in rings] for a in angles]
    cells = []
    for i in range(rays):
        j2 = (i + 1) % rays
        for k in range(len(rings) - 1):
            quad = [vert[i][k], vert[j2][k], vert[j2][k + 1], vert[i][k + 1]]
            if k > 1 and rnd.random() < 0.3:          # some shards are triangles
                cells += [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]]
            else:
                cells.append(quad)

    out = []
    for cell in cells:
        cpath = poly_path(cell)
        for region, color in regions:
            piece = pathops.op(cpath, region, pathops.PathOp.INTERSECTION)
            if abs(piece.area) < 6:
                continue
            # Hairline cracks at the core, wider towards the tips.
            px0, py0, px1, py1 = piece.bounds
            dist = math.hypot((px0 + px1) / 2 - impact[0], (py0 + py1) / 2 - impact[1])
            edge = pathops.Path(piece)
            edge.stroke(1.1 + dist * 0.014, pathops.LineCap.BUTT_CAP, pathops.LineJoin.MITER_JOIN, 4)
            shard = pathops.op(piece, edge, pathops.PathOp.DIFFERENCE)
            if abs(shard.area) < 4:
                continue
            # Explode outwards: more the further from the impact.
            x0, y0, x1, y1 = shard.bounds
            cx, cy = (x0 + x1) / 2 - impact[0], (y0 + y1) / 2 - impact[1]
            d = math.hypot(cx, cy) or 1
            # Only the outer fragments break away; the core stays tight.
            push = max(0.0, d - 64) ** 2 * 0.0028 + rnd.uniform(0, 0.8)
            shard.transform(1, 0, 0, 1, cx / d * push, cy / d * push)
            pen = SVGPathPen(None)
            shard.draw(pen)
            out.append(f'<path d="{pen.getCommands()}" fill="{color}"/>')
    return "".join(out)


def wordmark(text_color):
    """'Mistletoe UI' as outlines; returns (svg, width) at cap height ~ 100."""
    font = TTFont(ROOT / "fonts" / "Exo2" / "Exo2.ttf")
    font = instancer.instantiateVariableFont(font, {"wght": 600})
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    upm = font["head"].unitsPerEm
    scale = 150 / upm
    x = 0.0
    paths = []
    for i, ch in enumerate("Mistletoe UI"):
        name = cmap[ord(ch)]
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, 0)))
        color = GOLD if i >= len("Mistletoe ") else text_color
        if pen.getCommands():
            paths.append(f'<path d="{pen.getCommands()}" fill="{color}"/>')
        x += glyphs[name].width * scale + (4 if ch != " " else 0)   # a touch of tracking
    return "".join(paths), x


def svg(width, height, body, background=None):
    bg = f'<rect width="100%" height="100%" fill="{background}"/>' if background else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width:.0f} {height:.0f}" '
            f'width="{width:.0f}" height="{height:.0f}">{bg}{body}</svg>\n')


def main():
    OUT.mkdir(exist_ok=True)
    (OUT / "mistletoe-mark.svg").write_text(svg(256, 256, mark()))
    for variant, text, berry, bg in (("dark", BONE, BONE, OBSIDIAN), ("light", OBSIDIAN, "#23272C", "#F0ECE1")):
        words, w = wordmark(text)
        # Mark at 256 -> 200 px tall, wordmark baseline aligned to its centre.
        body = (f'<g transform="translate(10,4) scale(0.92)">{mark(berry)}</g>'
                f'<g transform="translate(262,168)">{words}</g>')
        width = 262 + w + 32
        (OUT / f"mistletoe-ui-{variant}.svg").write_text(svg(width, 240, body))
        # PNG preview on its intended background.
        preview = OUT / f".preview-{variant}.svg"
        preview.write_text(svg(width, 240, body, bg))
        subprocess.run(["magick", "-background", "none", "-density", "144", str(preview),
                        str(OUT / f"mistletoe-ui-{variant}.png")], check=True)
        preview.unlink()
    subprocess.run(["magick", "-background", "none", "-density", "288", str(OUT / "mistletoe-mark.svg"),
                    "-resize", "512x512", str(OUT / "mistletoe-mark.png")], check=True)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
