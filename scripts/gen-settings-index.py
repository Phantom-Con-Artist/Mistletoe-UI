#!/usr/bin/env python3
"""Index this machine's System Settings pages for the Mistletoe Settings dial.

Reads every settings module's plugin metadata (via Qt's qtplugininfo) and
System Settings' category files, resolves each module to its top-level
category, and writes ~/.local/share/mistletoe/settings.json (or the path
given as the first argument):

  { "categories": [{ id, name, icon, weight }],
    "modules": [{ id, name, description, icon, keywords, category, sub, weight }] }

The module set depends on what is installed, so install.sh runs this on
each machine; the output is not committed.

Run: python3 scripts/gen-settings-index.py [OUT]
"""
import configparser
import json
import os
import subprocess
import sys
from pathlib import Path

DATA = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else DATA / "mistletoe" / "settings.json"
PLUGINS = Path("/usr/lib64/qt6/plugins/plasma/kcms")
CATEGORY_DIR = Path("/usr/share/systemsettings/categories")
PLUGININFO = "/usr/lib64/qt6/bin/qtplugininfo"


def read_categories():
    cats = {}
    for f in sorted(CATEGORY_DIR.glob("*.desktop")):
        cp = configparser.ConfigParser(interpolation=None, strict=False)
        cp.optionxform = str
        cp.read(f, encoding="utf-8")
        e = cp["Desktop Entry"]
        cid = e.get("X-KDE-System-Settings-Category", "")
        if cid:
            cats[cid] = dict(
                id=cid, name=e.get("Name", cid), icon=e.get("Icon", "preferences-system"),
                parent=e.get("X-KDE-System-Settings-Parent-Category", ""),
                weight=int(e.get("X-KDE-Weight", "100") or 100))
    return cats


def top_level(cats, cid):
    seen = set()
    while cid in cats and cats[cid]["parent"] and cid not in seen:
        seen.add(cid)
        cid = cats[cid]["parent"]
    return cid


def read_modules():
    files = sorted(PLUGINS.glob("systemsettings/*.so")) + sorted(PLUGINS.glob("systemsettings_qwidgets/*.so"))
    files += [p for p in [PLUGINS / "kcm_about-distro.so"] if p.exists()]
    mods = []
    for so in files:
        try:
            raw = subprocess.run([PLUGININFO, "--full-json", str(so)], capture_output=True, text=True, timeout=10).stdout
            meta = json.loads(raw)["MetaData"]
        except Exception:
            continue
        kp = meta.get("KPlugin", {})
        if not kp.get("Name"):
            continue
        mods.append(dict(
            id=so.stem, name=kp["Name"], description=kp.get("Description", ""),
            icon=kp.get("Icon", "preferences-system"),
            keywords=meta.get("X-KDE-Keywords", ""),
            parent=meta.get("X-KDE-System-Settings-Parent-Category", ""),
            weight=int(meta.get("X-KDE-Weight", 100) or 100)))
    return mods


def main():
    cats = read_categories()
    mods = read_modules()
    used = {}
    for m in mods:
        top = top_level(cats, m["parent"]) if m["parent"] else "system"
        if top not in cats:
            top = "other"
        m["category"] = top
        sub = m.pop("parent")
        m["sub"] = cats[sub]["name"] if sub in cats and sub != top else ""
        used[top] = True
    # System Settings' root group only holds Quick Settings; call it Start.
    if "rootcategory" in cats:
        cats["rootcategory"].update(name="Start", icon="go-home", weight=0)
    categories = [dict(id=c["id"], name=c["name"], icon=c["icon"], weight=c["weight"])
                  for c in cats.values() if not c["parent"] and c["id"] in used]
    if "other" in used:
        categories.append(dict(id="other", name="Other", icon="preferences-other", weight=999))
    categories.sort(key=lambda c: c["weight"])
    order = {c["id"]: i for i, c in enumerate(categories)}
    mods.sort(key=lambda m: (order.get(m["category"], 999), m["sub"], m["weight"], m["name"]))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(dict(categories=categories, modules=mods), indent=1))
    print(f"wrote {OUT}: {len(categories)} categories, {len(mods)} modules")
    for c in categories:
        print(f"  {c['name']}: {sum(1 for m in mods if m['category'] == c['id'])}")


if __name__ == "__main__":
    main()
