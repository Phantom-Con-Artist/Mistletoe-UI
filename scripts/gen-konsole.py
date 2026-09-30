#!/usr/bin/env python3
"""Generate the Plasma Mistletoe Konsole color schemes and profile.

Terminal colors follow the Mistletoe palette: an obsidian (dark) or bone
(light) ground, and ANSI colors muted toward the palette so nothing
shouts. The profile adds roomy margins, a gold beam cursor and no
scrollbar, for a clean, headerless terminal.

Run: python3 scripts/gen-konsole.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "konsole"

# (normal, intense) for the eight ANSI colors, plus ground and text.
SCHEMES = {
    "Dark": dict(
        background=(13, 15, 18), foreground=(222, 217, 204), bold=(240, 236, 225),
        ansi=[
            ((35, 39, 44), (70, 76, 82)),        # black / slate
            ((201, 110, 98), (226, 140, 126)),   # red
            ((146, 176, 132), (172, 200, 156)),  # green
            ((212, 172, 112), (232, 196, 140)),  # yellow: champagne gold
            ((122, 146, 172), (152, 176, 200)),  # blue
            ((170, 136, 168), (196, 164, 194)),  # magenta
            ((120, 166, 160), (150, 192, 186)),  # cyan
            ((200, 195, 183), (240, 236, 225)),  # white / bone
        ]),
    "Light": dict(
        background=(240, 236, 225), foreground=(35, 39, 44), bold=(8, 9, 11),
        ansi=[
            ((35, 39, 44), (70, 76, 82)),
            ((168, 52, 44), (190, 74, 62)),
            ((62, 116, 70), (84, 138, 92)),
            ((150, 112, 52), (176, 136, 72)),
            ((52, 88, 132), (74, 110, 154)),
            ((122, 72, 120), (146, 96, 144)),
            ((44, 110, 106), (66, 132, 128)),
            ((170, 164, 150), (213, 207, 192)),
        ]),
}


def rgb(c):
    return ",".join(str(v) for v in c)


def colorscheme(name, s):
    lines = []
    def entry(key, color):
        lines.append(f"[{key}]\nColor={rgb(color)}\n")
    entry("Background", s["background"])
    entry("BackgroundIntense", s["background"])
    entry("BackgroundFaint", s["background"])
    entry("Foreground", s["foreground"])
    entry("ForegroundIntense", s["bold"])
    entry("ForegroundFaint", s["ansi"][0][1] if name == "Dark" else s["ansi"][7][0])
    for i, (normal, intense) in enumerate(s["ansi"]):
        entry(f"Color{i}", normal)
        entry(f"Color{i}Intense", intense)
        entry(f"Color{i}Faint", normal)
    lines.append(f"[General]\nDescription=Mistletoe {name}\nOpacity=1\nBlur=false\nWallpaper=\n")
    return "\n".join(lines)


PROFILE = """[Appearance]
ColorScheme=Mistletoe{variant}
Font=Monospace,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
LineSpacing=2

[Cursor Options]
CursorShape=1
UseCustomCursorColor=true
CustomCursorColor={gold}
CustomCursorTextColor={ground}

[General]
Name=Mistletoe {variant}
Parent=FALLBACK/
TerminalMargin=16
TerminalCenter=false

[Scrolling]
ScrollBarPosition=2
HistoryMode=2

[Terminal Features]
BlinkingCursorEnabled=true
"""

GOLD = {"Dark": (212, 172, 112), "Light": (150, 112, 52)}


def main():
    OUT.mkdir(exist_ok=True)
    for name, s in SCHEMES.items():
        (OUT / f"Mistletoe{name}.colorscheme").write_text(colorscheme(name, s))
        (OUT / f"Mistletoe{name}.profile").write_text(
            PROFILE.format(variant=name, gold=rgb(GOLD[name]), ground=rgb(s["background"])))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
