#!/usr/bin/env python3
"""Copy the shared QML components into every widget package that uses them.

Source: plasma-widgets/shared/*.qml. A package "uses" a component when any
of its QML mentions `Name {`. Copies are byte-identical to the source.

Run: python3 scripts/sync-shared.py [--check]
  --check  report drifted or missing copies and exit 1, changing nothing
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "plasma-widgets" / "shared"


def main():
    check = "--check" in sys.argv[1:]
    sources = {p.stem: p.read_bytes() for p in sorted(SHARED.glob("*.qml"))}
    problems = 0
    for ui in sorted(ROOT.glob("plasma-widgets/*/package/contents/ui")):
        own = "\n".join(p.read_text() for p in ui.glob("*.qml") if p.stem not in sources)
        used = {n for n in sources if re.search(rf"\b{n}\s*\{{", own)}
        pkg = ui.parts[-4]
        for name in sorted(used):
            target = ui / f"{name}.qml"
            if target.exists() and target.read_bytes() == sources[name]:
                continue
            problems += 1
            if check:
                print(f"{pkg}: {name}.qml {'differs' if target.exists() else 'missing'}")
            else:
                target.write_bytes(sources[name])
                print(f"{pkg}: synced {name}.qml")
        # Drop copies a package no longer uses.
        for name in sorted(set(sources) - used):
            stale = ui / f"{name}.qml"
            if stale.exists():
                problems += 1
                if check:
                    print(f"{pkg}: {name}.qml unused")
                else:
                    stale.unlink()
                    print(f"{pkg}: removed unused {name}.qml")
    if check and problems:
        sys.exit(1)
    if not problems:
        print("shared components in sync")


if __name__ == "__main__":
    main()
