#!/usr/bin/env python3
"""Generate the Mistletoe Kvantum themes: the look of the controls inside
every Qt app (buttons, tabs, fields, scrollbars, menus), one per edition.

Each theme is a recolouring of Kvantum's own Material-style KvAdapta themes
(by Tsu Jan, GPL; the dark one for the dark editions, the light one for
Light): flat tonal surfaces, thin lines, accent-filled active controls. The
shapes are kept; every colour is moved onto the edition's palette:

  - the base's teal accent becomes the edition's accent,
  - its blue-grey neutrals are mapped by lightness onto the edition's own
    ramp (view, window, button ... text),
  - its red becomes the edition's negative colour,
  - text drawn on an accent fill becomes the edition's selection text, so it
    stays readable on a light accent such as gold.

Writes kvantum/Mistletoe<Edition>/Mistletoe<Edition>.{svg,kvconfig}.
install.sh links them into ~/.config/Kvantum; the bridge selects the one
that matches the active edition.

Run: python3 scripts/gen-kvantum.py   (needs the kvantum package installed)
"""
import colorsys
import importlib.util
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASES = Path("/usr/share/Kvantum")
_spec = importlib.util.spec_from_file_location("gen_colors", ROOT / "scripts" / "gen-colors.py")
gen_colors = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen_colors)

NAMED = {"white": (255, 255, 255), "black": (0, 0, 0)}


def parse(text):
    """'#rrggbb', '#rrggbbaa', 'white' or 'black' -> ((r, g, b), 'aa' or '')."""
    text = text.strip()
    if text.lower() in NAMED:
        return NAMED[text.lower()], ""
    m = re.fullmatch(r"#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?", text)
    if not m:
        return None, ""
    v = m.group(1)
    return tuple(int(v[i:i + 2], 16) for i in (0, 2, 4)), (m.group(2) or "")


def hexc(rgb, alpha=""):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(c))) for c in rgb) + alpha


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def light(rgb):
    return colorsys.rgb_to_hls(*(c / 255 for c in rgb))[1]


class Mapper:
    """Moves the base theme's colours onto one edition's palette."""

    def __init__(self, p, base_colors, dark):
        self.p, self.dark = p, dark
        self.accent = p["accent"]
        # Lightness anchors: where the base's key surfaces sit, and what they
        # become. Everything neutral is interpolated between them.
        fg, window, view, button = p["fg"], p["window"][0], p["view"][0], p["button"][0]
        src_window = light(base_colors["window.color"])
        src_button = light(base_colors["button.color"])
        if dark:
            anchors = [(0.0, view), (src_window * 0.8, view), (src_window, window),
                       (max(src_button, src_window + 0.02), button), (src_window + 0.08, p["button"][1]), (1.0, fg)]
        else:
            # The light base has dark bars (menus, toolbars); they become the
            # edition's ink, and its light surfaces the edition's paper.
            anchors = [(0.0, fg), (0.2, mix(fg, window, 0.12)), (src_window - 0.12, p["button"][1]),
                       (src_window - 0.03, window), (0.985, p["button"][0]), (1.0, view)]
        self.anchors = sorted(anchors, key=lambda a: a[0])

    def neutral(self, rgb):
        l = light(rgb)
        for (l0, c0), (l1, c1) in zip(self.anchors, self.anchors[1:]):
            if l <= l1:
                t = 0 if l1 == l0 else (l - l0) / (l1 - l0)
                return mix(c0, c1, max(0, min(1, t)))
        return self.anchors[-1][1]

    def color(self, rgb):
        h, l, s = colorsys.rgb_to_hls(*(c / 255 for c in rgb))
        hue = h * 360
        if s > 0.3 and 150 <= hue <= 215:
            # Teal family: the accent, or a tint of it for the darker ones.
            if l >= 0.33:
                return self.accent
            return mix(self.p["window"][0], self.accent, 0.18 + l)
        if s > 0.5 and (hue <= 20 or hue >= 345):
            return self.p["negative"]
        if s > 0.5:
            return rgb            # other signal colours (green, orange, purple) stay
        return self.neutral(rgb)


# The base draws a full accent outline round whatever view has the keyboard
# focus (the file view in Dolphin, every list). That is a lot of accent for a
# quiet desktop, so those frames only take a tint of it.
QUIET = ("common-focused",)


def element_spans(text, prefixes):
    """(start, end) of every element whose id starts with one of prefixes;
    a group runs to its closing tag."""
    spans = []
    for m in re.finditer(r'id="([^"]+)"', text):
        if not m.group(1).startswith(prefixes):
            continue
        start = text.rfind("<", 0, m.start())
        end = text.find(">", m.end()) + 1
        if text.startswith("<g", start) and not text[start:end].endswith("/>"):
            close = text.find("</g>", end)
            end = close + 4 if close > 0 else end
        spans.append((start, end))
    return spans


def recolor_svg(text, mapper):
    quiet = element_spans(text, QUIET)

    def swap(m):
        rgb, _ = parse(m.group(0))
        new = mapper.color(rgb)
        if new == mapper.accent and any(a <= m.start() < b for a, b in quiet):
            new = mix(mapper.p["window"][0], mapper.accent, 0.3)
        return hexc(new)
    return re.sub(r"#[0-9a-fA-F]{6}\b", swap, text)


def sections(text):
    """{section: {key: value}} of a kvconfig, in file order."""
    found, name = {}, ""
    for line in text.splitlines():
        if line.startswith("["):
            name = line.strip()[1:-1]
            found[name] = {}
        elif "=" in line and name:
            key, value = line.split("=", 1)
            found[name][key] = value
    return found


def accent_filled(conf, svg, section, state):
    """Whether this section's control is drawn on an accent fill in this
    state (toggled or pressed), judged from the base theme's artwork."""
    seen = set()
    element = None
    while section and section not in seen:
        seen.add(section)
        keys = conf.get(section, {})
        element = keys.get("interior.element") or keys.get("frame.element")
        if element:
            break
        section = keys.get("inherits", "")
    if not element:
        return False
    at = svg.find(f'id="{element}-{state}"')
    if at < 0:
        return False
    # The element's own markup: back to its opening tag, on to the next id.
    start = svg.rfind("<", 0, at)
    end = svg.find(' id="', at + 10)
    chunk = svg[start:end if end > 0 else at + 3000]
    for m in re.finditer(r"#[0-9a-fA-F]{6}\b", chunk):
        h, l, sat = colorsys.rgb_to_hls(*(c / 255 for c in parse(m.group(0))[0]))
        if sat > 0.3 and 150 <= h * 360 <= 215 and l >= 0.33:
            return True
    return False


def recolor_config(text, mapper, p, name, svg):
    conf = sections(text)
    general = {
        "window.color": p["window"][0], "base.color": p["view"][0], "alt.base.color": p["view"][1],
        "button.color": p["button"][0], "light.color": p["button"][1],
        "mid.light.color": mix(p["window"][0], p["fg"], 0.12), "mid.color": mix(p["window"][0], p["fg"], 0.06),
        "dark.color": p["view"][0], "highlight.color": p["selection"], "inactive.highlight.color": p["selection_alt"],
        "highlight.text.color": p["selection_fg"], "progress.indicator.text.color": p["selection_fg"],
        "link.color": p["link"], "link.visited.color": p["visited"], "tooltip.text.color": p["fg"],
    }
    out, section = [], ""
    for line in text.splitlines():
        if line.startswith("["):
            section = line.strip()
            out.append(line)
            continue
        if "=" not in line:
            out.append(line)
            continue
        key, value = line.split("=", 1)
        if key == "author":
            value = "Subhradeep Sarkar (recoloured from KvAdapta by Tsu Jan)"
        elif key == "comment":
            value = f"Mistletoe {name}: flat, tonal controls in the edition's palette"
        elif section == "[GeneralColors]" and key in general:
            value = hexc(general[key])
        elif key.endswith(".color") or key.endswith("color"):
            rgb, alpha = parse(value)
            if rgb is not None:
                # Text on a pressed or toggled control sits on an accent
                # fill: use the selection text colour, not plain text.
                state = {"text.toggle.color": "toggled", "text.press.color": "pressed"}.get(key)
                if state and accent_filled(conf, svg, section[1:-1], state):
                    value = hexc(p["selection_fg"])
                else:
                    value = hexc(mapper.color(rgb), alpha)
        out.append(f"{key}={value}")
    return "\n".join(out) + "\n"


def base_colors(config):
    found, section = {}, ""
    for line in config.splitlines():
        if line.startswith("["):
            section = line.strip()
        elif section == "[GeneralColors]" and "=" in line:
            key, value = line.split("=", 1)
            rgb, _ = parse(value)
            if rgb is not None:
                found[key] = rgb
    return found


def main():
    for edition, p in gen_colors.PALETTES.items():
        dark = edition != "Light"
        base = "KvAdaptaDark" if dark else "KvAdapta"
        src = BASES / base
        if not src.is_dir():
            raise SystemExit(f"{src} not found: install the kvantum package first")
        config = (src / f"{base}.kvconfig").read_text()
        mapper = Mapper(p, base_colors(config), dark)
        name = f"Mistletoe{edition}"
        out = ROOT / "kvantum" / name
        out.mkdir(parents=True, exist_ok=True)
        svg = (src / f"{base}.svg").read_text()
        (out / f"{name}.svg").write_text(recolor_svg(svg, mapper))
        (out / f"{name}.kvconfig").write_text(recolor_config(config, mapper, p, edition, svg))
        print("wrote", out)


if __name__ == "__main__":
    main()
