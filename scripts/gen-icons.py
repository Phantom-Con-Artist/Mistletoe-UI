#!/usr/bin/env python3
"""Build the Mistletoe icon themes, one per edition, in ~/.local/share/icons.

Each is a thin theme on top of Papirus (GPL-3, by the Papirus Development
Team): it inherits every icon from Papirus (or Papirus-Dark for the dark
editions) and only re-points the folder icons at the Papirus folder colour
closest to the edition's accent, the way Papirus' own papirus-folders tool
does inside the theme. Nothing of Papirus is copied or changed.

  Dark   champagne gold  -> paleorange      Neon   orchid     -> magenta
  Light  bronze          -> brown           Ember  vermilion  -> deeporange

Without Papirus installed the themes are still written, empty, and simply
inherit Breeze, so the Global Themes can always name them.
scripts/install-icons.sh downloads Papirus and runs this.

Run: python3 scripts/gen-icons.py
"""
import os
import re
import shutil
from pathlib import Path

ICONS = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "icons"
SYSTEM = Path("/usr/share/icons")

EDITIONS = {
    # edition: (Papirus base, folder colour, Breeze fallback)
    "Dark": ("Papirus-Dark", "paleorange", "breeze-dark"),
    "Light": ("Papirus", "brown", "breeze"),
    "Neon": ("Papirus-Dark", "magenta", "breeze-dark"),
    "Ember": ("Papirus-Dark", "deeporange", "breeze-dark"),
}
STOCK = "blue"   # the colour Papirus' own folder links point at
# Only names that mean "a folder" are overridden. KDE falls back from a
# missing icon to shorter names *inside the same theme* before trying the
# inherited one, so an override called `network` here would also answer for
# network-wireless-symbolic, and every network icon would turn into a folder.
FOLDERISH = re.compile(r"^(folder|inode-directory|gtk-directory|stock_folder|stock_open|user-home|user-desktop|gnome-home|insync-folder)")


def find(theme):
    for root in (ICONS, SYSTEM):
        if (root / theme / "index.theme").is_file():
            return root / theme
    return None


def build(edition, base_name, colour, fallback):
    out = ICONS / f"Mistletoe-{edition}"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    base = find(base_name)
    sections, made = [], 0
    if base:
        for places in sorted(base.glob("*/places")):
            size = places.parent.name
            links = {}
            for entry in places.iterdir():
                if not entry.is_symlink():
                    continue
                # Papirus links e.g. folder.svg -> folder-blue.svg and
                # user-home.svg -> user-blue-home.svg, and some names go
                # through a second link (inode-directory.svg -> folder.svg).
                # Follow each to the file it ends at and re-point those that
                # end at a stock-coloured one.
                if not FOLDERISH.match(entry.name):
                    continue
                final = entry.resolve()
                if final.parent != places.resolve() or not re.search(rf"-{STOCK}(-|\.)", final.name):
                    continue
                wanted = final.with_name(re.sub(rf"-{STOCK}(?=-|\.)", f"-{colour}", final.name, count=1))
                if wanted.exists():
                    links[entry.name] = wanted
            if not links:
                continue
            folder = out / size / "places"
            folder.mkdir(parents=True)
            for name, wanted in links.items():
                # Resolve through Papirus-Dark's own links to the real file,
                # then link relatively so the icons folder can be moved.
                (folder / name).symlink_to(os.path.relpath(wanted.resolve(), folder))
                made += 1
            px = size.split("x")[0]
            scale = "\nScale=2" if size.endswith("@2x") else ""
            sections.append(f"[{size}/places]\nContext=Places\nSize={px}\nType=Fixed{scale}\n")
    inherits = ",".join(([base_name] if base else []) + [fallback, "hicolor"])
    index = ["[Icon Theme]", f"Name=Mistletoe {edition}",
             f"Comment=Papirus with folders in the {edition} edition's accent" if base
             else f"Comment=Breeze (install Papirus for the Mistletoe {edition} folders)",
             f"Inherits={inherits}", "Example=folder",
             "FollowsColorScheme=true",
             "Directories=" + ",".join(s.split("]")[0][1:] for s in sections), ""]
    (out / "index.theme").write_text("\n".join(index) + "\n" + "\n".join(sections))
    print(f"wrote {out} ({made} folder icons, inherits {inherits})")


def main():
    ICONS.mkdir(parents=True, exist_ok=True)
    for edition, (base, colour, fallback) in EDITIONS.items():
        build(edition, base, colour, fallback)


if __name__ == "__main__":
    main()
