#!/usr/bin/env python3
"""Generate the Plasma Mistletoe color schemes (dark + light) from one palette.

Writes:
  color-schemes/MistletoeDark.colors    color-schemes/MistletoeLight.colors
  themes/mistletoe-dark/colors          themes/mistletoe-light/colors

Edit PALETTES below, run `python3 scripts/gen-colors.py`, and it also prints
WCAG contrast ratios so unreadable combinations are caught early.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Colors are (r, g, b). Each surface is (normal, alternate).
PALETTES = {
    "Dark": dict(
        window=((22, 26, 32), (29, 34, 42)),
        view=((14, 17, 21), (19, 23, 28)),
        button=((35, 41, 50), (43, 50, 61)),
        header=((18, 21, 26), (24, 28, 34)),
        header_inactive=((14, 17, 21), (18, 21, 26)),
        tooltip=((30, 36, 44), (38, 45, 55)),
        complementary=((17, 20, 25), (24, 28, 34)),
        fg=(233, 238, 243),
        fg_inactive=(140, 152, 165),
        link=(96, 220, 214),
        visited=(166, 148, 255),
        negative=(255, 107, 122),
        neutral=(255, 180, 84),
        positive=(92, 220, 150),
        accent=(79, 216, 208),          # decoration focus / rings / glow
        hover=(150, 236, 230),
        selection=(24, 116, 122),       # matte selection fill (white text)
        selection_alt=(20, 96, 102),
        selection_fg=(255, 255, 255),
        selection_link=(255, 224, 150),
        title_active=(20, 24, 30),
        title_inactive=(16, 19, 24),
    ),
    "Light": dict(
        window=((236, 240, 244), (226, 232, 238)),
        view=((250, 251, 252), (241, 245, 248)),
        button=((244, 247, 250), (231, 237, 242)),
        header=((228, 234, 240), (219, 226, 233)),
        header_inactive=((238, 242, 246), (230, 235, 240)),
        tooltip=((252, 253, 254), (240, 244, 248)),
        complementary=((28, 33, 40), (36, 42, 51)),
        fg=(24, 30, 38),
        fg_inactive=(96, 108, 122),
        link=(0, 118, 124),
        visited=(98, 78, 196),
        negative=(196, 38, 58),
        neutral=(154, 82, 0),
        positive=(16, 124, 76),
        accent=(0, 150, 158),
        hover=(0, 176, 184),
        selection=(0, 118, 126),
        selection_alt=(0, 98, 106),
        selection_fg=(255, 255, 255),
        selection_link=(255, 240, 190),
        title_active=(228, 234, 240),
        title_inactive=(238, 242, 246),
    ),
}


def c(rgb):
    return "%d,%d,%d" % rgb


def lum(rgb):
    def f(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (f(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def section(name, p, bg, alt, fg=None, fg_inactive=None, selection=False,
            fg_active=None, decoration_focus=None):
    fg = fg or p["fg"]
    fg_inactive = fg_inactive or p["fg_inactive"]
    lines = [f"[{name}]"]
    lines.append(f"BackgroundAlternate={c(alt)}")
    lines.append(f"BackgroundNormal={c(bg)}")
    lines.append(f"DecorationFocus={c(decoration_focus or p['accent'])}")
    lines.append(f"DecorationHover={c(p['hover'])}")
    lines.append(f"ForegroundActive={c(fg_active or p['accent'])}")
    lines.append(f"ForegroundInactive={c(fg_inactive)}")
    lines.append(f"ForegroundLink={c(p['selection_link'] if selection else p['link'])}")
    lines.append(f"ForegroundNegative={c(p['negative'])}")
    lines.append(f"ForegroundNeutral={c(p['neutral'])}")
    lines.append(f"ForegroundNormal={c(fg)}")
    lines.append(f"ForegroundPositive={c(p['positive'])}")
    lines.append(f"ForegroundVisited={c(p['visited'])}")
    return "\n".join(lines)


def build(variant, p):
    out = []
    # Effects
    out.append("[ColorEffects:Disabled]\n"
               f"Color={c(p['window'][0])}\nColorAmount=0\nColorEffect=0\n"
               "ContrastAmount=0.65\nContrastEffect=1\nIntensityAmount=0.1\nIntensityEffect=2")
    out.append("[ColorEffects:Inactive]\nChangeSelectionColor=true\n"
               f"Color={c(p['fg_inactive'])}\nColorAmount=0.025\nColorEffect=2\n"
               "ContrastAmount=0.1\nContrastEffect=2\nEnable=false\n"
               "IntensityAmount=0\nIntensityEffect=0")
    out.append(section("Colors:Button", p, *p["button"]))
    out.append(section("Colors:Complementary", p, *p["complementary"],
                       fg=(233, 238, 243), fg_inactive=(140, 152, 165)))
    out.append(section("Colors:Header", p, *p["header"]))
    out.append(section("Colors:Header][Inactive", p, *p["header_inactive"]))
    out.append(section("Colors:Selection", p, p["selection"], p["selection_alt"],
                       fg=p["selection_fg"], fg_inactive=(210, 232, 234),
                       selection=True, fg_active=p["selection_fg"]))
    out.append(section("Colors:Tooltip", p, *p["tooltip"]))
    out.append(section("Colors:View", p, *p["view"]))
    out.append(section("Colors:Window", p, *p["window"]))
    out.append("[General]\n"
               f"ColorScheme=Mistletoe{variant}\nName=Mistletoe {variant}\nshadeSortColumn=true")
    out.append("[KDE]\ncontrast=4")
    out.append("[WM]\n"
               f"activeBackground={c(p['title_active'])}\nactiveBlend={c(p['fg'])}\n"
               f"activeForeground={c(p['fg'])}\n"
               f"inactiveBackground={c(p['title_inactive'])}\n"
               f"inactiveBlend={c(p['fg_inactive'])}\ninactiveForeground={c(p['fg_inactive'])}")
    return "\n\n".join(out) + "\n"


def report(variant, p):
    print(f"== {variant} contrast (WCAG; >=4.5 body text, >=3 large/UI)")
    for label, fg, bg in [
        ("text on window", p["fg"], p["window"][0]),
        ("text on view", p["fg"], p["view"][0]),
        ("text on button", p["fg"], p["button"][0]),
        ("inactive text on window", p["fg_inactive"], p["window"][0]),
        ("link on window", p["link"], p["window"][0]),
        ("link on view", p["link"], p["view"][0]),
        ("visited on window", p["visited"], p["window"][0]),
        ("negative on window", p["negative"], p["window"][0]),
        ("neutral on window", p["neutral"], p["window"][0]),
        ("positive on window", p["positive"], p["window"][0]),
        ("selection text", p["selection_fg"], p["selection"]),
        ("selection link", p["selection_link"], p["selection"]),
        ("accent ring on window", p["accent"], p["window"][0]),
    ]:
        r = contrast(fg, bg)
        print(f"  {'OK ' if r >= 4.5 else ('ui ' if r >= 3 else 'LOW')} {r:5.2f}  {label}")


def main():
    for variant, p in PALETTES.items():
        text = build(variant, p)
        (ROOT / "color-schemes").mkdir(exist_ok=True)
        (ROOT / "color-schemes" / f"Mistletoe{variant}.colors").write_text(text)
        theme = ROOT / "themes" / f"mistletoe-{variant.lower()}"
        theme.mkdir(parents=True, exist_ok=True)
        (theme / "colors").write_text(text)
        report(variant, p)


if __name__ == "__main__":
    main()
