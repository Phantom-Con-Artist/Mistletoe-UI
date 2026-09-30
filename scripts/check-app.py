#!/usr/bin/env python3
"""Report how well Plasma Mistletoe reaches an app.

  scripts/check-app.py APP     APP: a desktop id (org.kde.dolphin), a .desktop
                               name (firefox) or a command (kwrite)

Works out the app's toolkit (from its .desktop file and binary) and lists,
for colours, fonts, window frame and the dial's App mode, whether Mistletoe
applies fully, partly or not at all, with the fix where there is one. If the
app is running, it also checks whether it is sharing its menus right now.
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

APPDIRS = [Path.home() / ".local/share/applications", Path("/usr/share/applications"),
           Path("/var/lib/flatpak/exports/share/applications"),
           Path.home() / ".local/share/flatpak/exports/share/applications"]


def find_desktop(app):
    for d in APPDIRS:
        for name in (app, app + ".desktop"):
            if (d / name).is_file():
                return d / name
    for d in APPDIRS:
        for f in d.glob("*.desktop"):
            if app.lower() in f.stem.lower():
                return f
    return None


def exec_line(desktop):
    for line in desktop.read_text(errors="ignore").splitlines():
        if line.startswith("Exec="):
            return line[5:]
    return ""


def resolve_binary(cmd):
    parts = [p for p in cmd.split() if not p.startswith("%") and "=" not in p.split("/")[-1]]
    if not parts:
        return None
    path = shutil.which(parts[0]) or parts[0]
    path = os.path.realpath(path)
    # Shell wrappers (Firefox, Electron apps): follow the exec'd binary.
    try:
        head = open(path, "rb").read(4096)
        if head.startswith(b"#!"):
            m = re.search(rb'exec\s+"?([^"\s]+)', open(path, "rb").read())
            if m:
                inner = m.group(1).decode()
                inner = shutil.which(inner) or inner
                if os.path.exists(inner):
                    return os.path.realpath(inner)
    except OSError:
        pass
    return path


def toolkit(binary, cmd):
    if "flatpak run" in cmd:
        return "flatpak"
    try:
        libs = subprocess.run(["ldd", binary], capture_output=True, text=True, timeout=10).stdout
    except Exception:
        libs = ""
    folder = os.path.dirname(binary or "")
    if "libxul" in libs or os.path.exists(os.path.join(folder, "libxul.so")):
        return "firefox"
    if os.path.exists(os.path.join(folder, "resources", "app.asar")) or "electron" in (binary or ""):
        return "electron"
    if "libQt6Core" in libs:
        return "kde" if "libKF6" in libs else "qt6"
    if "libQt5Core" in libs:
        return "qt5"
    if "libadwaita" in libs:
        return "libadwaita"
    if "libgtk-4" in libs:
        return "gtk4"
    if "libgtk-3" in libs:
        return "gtk3"
    if "libchrome" in libs or "chrome" in (binary or ""):
        return "electron"
    return "unknown"


FULL, PART, NONE = "full", "partly", "no"
REPORT = {
    "kde":  [(FULL, "Mistletoe scheme"), (FULL, "Text role"), (FULL, "Mistletoe frame"), (FULL, "exports its menus")],
    "qt6":  [(FULL, "via the KDE platform theme"), (FULL, "Text role"), (FULL, "Mistletoe frame"),
             (FULL, "exports its menus (if it has a menu bar)")],
    "qt5":  [(PART, "needs plasma-integration for Qt 5"), (FULL, "Text role"), (FULL, "Mistletoe frame"),
             (PART, "only with the Qt 5 platform theme")],
    "gtk3": [(FULL, "KDE's GTK colours + mistletoe.css"), (FULL, "Text role"),
             (PART, "Mistletoe frame, or its own header bar (reshaped by mistletoe.css)"),
             (PART, "needs: sudo dnf install appmenu-gtk3-module")],
    "gtk4": [(FULL, "KDE's GTK colours + mistletoe.css"), (FULL, "Text role"),
             (PART, "own header bar (reshaped by mistletoe.css)"), (NONE, "GTK 4 has no menu bar to share")],
    "libadwaita": [(PART, "libadwaita keeps its own palette; mistletoe.css reshapes"), (FULL, "Text role"),
                   (PART, "own header bar"), (NONE, "no menu bar to share")],
    "firefox": [(PART, "follows the system dark/light choice"), (FULL, "Text role"),
                (PART, "Mistletoe frame if title bar is on; else its own"),
                (FULL, "global menu enabled by apply-apps.sh (restart Firefox)")],
    "electron": [(NONE, "app draws its own UI"), (PART, "only where it uses system fonts"),
                 (PART, "Mistletoe frame unless it draws its own"), (NONE, "doesn't share its menus")],
    "flatpak": [(PART, "needs the GTK/Qt theme inside the sandbox"), (PART, "needs font access"),
                (FULL, "Mistletoe frame (server-side)"), (PART, "depends on its toolkit")],
    "unknown": [(PART, "unknown toolkit"), (PART, "unknown"), (FULL, "Mistletoe frame (server-side)"), (PART, "unknown")],
}


def sharing_menus(name):
    try:
        names = subprocess.run(["qdbus"], capture_output=True, text=True, timeout=5).stdout.split()
    except Exception:
        return None
    services = [n for n in names if name.lower() in n.lower()]
    for svc in services:
        objs = subprocess.run(["qdbus", svc], capture_output=True, text=True, timeout=5).stdout
        if re.search(r"^/MenuBar", objs, re.M):
            return True
    return False if services else None


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip())
        return 2
    app = sys.argv[1]
    desktop = find_desktop(app)
    cmd = exec_line(desktop) if desktop else app
    binary = resolve_binary(cmd)
    kit = toolkit(binary, cmd)
    print(f"{app}: {desktop.name if desktop else 'no .desktop file'}  ·  {binary}  ·  toolkit: {kit}")
    for (level, note), what in zip(REPORT[kit], ("colours", "fonts", "window frame", "dial menus")):
        mark = {"full": "✔", "partly": "◐", "no": "✘"}[level]
        print(f"  {mark} {what:<13} {note}")
    live = sharing_menus(Path(binary or app).name)
    if live is True:
        print("  ✔ running now and sharing its menus with the dial")
    elif live is False:
        print("  ◐ running, but not sharing menus (started before the dial's bridge? restart it)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
