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
    # Obsidian, bone and champagne gold, sampled from the MyTheme.png reference.
    "Dark": dict(
        window=((17, 19, 22), (25, 29, 33)),
        view=((8, 9, 11), (14, 16, 19)),
        button=((35, 39, 44), (50, 55, 60)),
        header=((13, 15, 17), (19, 21, 24)),
        header_inactive=((10, 11, 13), (14, 16, 19)),
        tooltip=((25, 29, 33), (35, 39, 44)),
        complementary=((8, 9, 11), (17, 19, 22)),
        complementary_fg=(233, 228, 214),
        complementary_fg_inactive=(150, 146, 136),
        fg=(233, 228, 214),
        fg_inactive=(150, 146, 136),
        link=(222, 185, 139),
        visited=(160, 172, 190),
        negative=(226, 104, 92),
        neutral=(232, 150, 72),
        positive=(146, 196, 150),
        accent=(212, 172, 112),         # champagne gold: focus rings, hairlines
        hover=(238, 209, 155),
        selection=(212, 172, 112),      # gold fill, obsidian text
        selection_alt=(186, 150, 96),
        selection_fg=(8, 9, 11),
        selection_fg_inactive=(50, 44, 34),
        selection_link=(35, 39, 44),
        title_active=(13, 15, 17),
        title_inactive=(10, 11, 13),
    ),
    "Light": dict(
        window=((227, 222, 208), (218, 212, 196)),
        view=((240, 236, 225), (232, 227, 214)),
        button=((233, 228, 214), (222, 217, 204)),
        header=((222, 217, 204), (213, 207, 192)),
        header_inactive=((230, 225, 212), (222, 217, 204)),
        tooltip=((240, 236, 225), (227, 222, 208)),
        complementary=((17, 19, 22), (25, 29, 33)),
        complementary_fg=(233, 228, 214),
        complementary_fg_inactive=(150, 146, 136),
        fg=(17, 19, 22),
        fg_inactive=(86, 88, 90),
        link=(122, 86, 30),
        visited=(70, 80, 104),
        negative=(168, 40, 36),
        neutral=(146, 72, 0),
        positive=(40, 104, 58),
        accent=(150, 112, 52),
        hover=(176, 136, 72),
        selection=(35, 39, 44),         # obsidian fill, bone text
        selection_alt=(50, 55, 60),
        selection_fg=(233, 228, 214),
        selection_fg_inactive=(170, 164, 150),
        selection_link=(222, 185, 139),
        title_active=(222, 217, 204),
        title_inactive=(230, 225, 212),
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
                       fg=p["complementary_fg"], fg_inactive=p["complementary_fg_inactive"]))
    out.append(section("Colors:Header", p, *p["header"]))
    out.append(section("Colors:Header][Inactive", p, *p["header_inactive"]))
    out.append(section("Colors:Selection", p, p["selection"], p["selection_alt"],
                       fg=p["selection_fg"], fg_inactive=p["selection_fg_inactive"],
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
