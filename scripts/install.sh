#!/usr/bin/env bash
# Symlink the workshop assets into the user's KDE data dirs (edits go live).
# Then pick Mistletoe Dark/Light in System Settings > Global Theme, or:
#   plasma-apply-lookandfeel --apply org.mistletoe.dark.desktop --resetLayout
# and scripts/apply-apps.sh for the native-app polish (fonts, toolbars, Konsole).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

link() { mkdir -p "$(dirname "$2")"; ln -sfn "$1" "$2"; echo "linked $2"; }

for t in "$ROOT"/themes/*/; do
    link "${t%/}" "$DATA/plasma/desktoptheme/$(basename "$t")"
done
for c in "$ROOT"/color-schemes/*.colors; do
    link "$c" "$DATA/color-schemes/$(basename "$c")"
done
for d in "$ROOT"/window-decorations/aurorae/*/; do
    link "${d%/}" "$DATA/aurorae/themes/$(basename "$d")"
done
python3 "$ROOT/scripts/sync-shared.py"
for p in "$ROOT"/plasma-widgets/*/package/; do
    id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Id"])' "$p/metadata.json")"
    link "${p%/}" "$DATA/plasma/plasmoids/$id"
done
for l in "$ROOT"/lookandfeel/*/; do
    link "${l%/}" "$DATA/plasma/look-and-feel/$(basename "$l")"
done
for k in "$ROOT"/konsole/*; do
    link "$k" "$DATA/konsole/$(basename "$k")"
done
# Shell packages (the lock screen) are *copied*, not linked: the bridge writes
# machine-specific values into the installed copy (lockscreen/backdrop.js).
for sh in "$ROOT"/shells/*/; do
    dest="$DATA/plasma/shells/$(basename "$sh")"
    rm -rf "$dest"; mkdir -p "$(dirname "$dest")"; cp -r "${sh%/}" "$dest"
    echo "copied $dest"
done
# The locker takes its UI from the Plasma shell package named by
# PLASMA_DEFAULT_SHELL (kscreenlockerrc's Theme key is ignored). KWin starts
# the locker, so the variable is set for KWin's service only: plasmashell
# must keep the desktop shell, or it would start with an empty desktop.
# Takes effect the next time you log in.
rm -f "$DATA/plasma/look-and-feel/org.mistletoe.lockscreen"
dropin="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/plasma-kwin_wayland.service.d"
mkdir -p "$dropin"
printf '[Service]\nEnvironment=PLASMA_DEFAULT_SHELL=org.mistletoe.lockscreen\n' > "$dropin/mistletoe-lockscreen.conf"
systemctl --user daemon-reload 2>/dev/null || true
echo "lock screen: Mistletoe from the next login"
for w in "$ROOT"/wallpapers/*/; do
    link "${w%/}" "$DATA/wallpapers/$(basename "$w")"
done
# Icon themes named by the Global Themes. They inherit Breeze until Papirus
# is installed: `bash scripts/install-icons.sh` downloads it (no root).
python3 "$ROOT/scripts/gen-icons.py" >/dev/null && echo "icon themes written"
# KWin scripts (floating-card helper), enabled.
for k in "$ROOT"/kwin-scripts/*/; do
    id="$(basename "$k")"
    link "${k%/}" "$DATA/kwin/scripts/$id"
    kwriteconfig6 --file kwinrc --group Plugins --key "${id}Enabled" true
done
# KWin effects (the fold-into-the-strip minimize animation), enabled. It
# replaces Squash, which has no task manager icon to aim at here.
for k in "$ROOT"/kwin-effects/*/; do
    [[ -f "$k/metadata.json" ]] || continue
    id="$(basename "$k")"
    link "${k%/}" "$DATA/kwin/effects/$id"
    kwriteconfig6 --file kwinrc --group Plugins --key "${id}Enabled" true
done
kwriteconfig6 --file kwinrc --group Plugins --key squashEnabled false
# The rotary Alt+Tab switcher. (Pick another under System Settings > Window
# Management > Task Switcher to go back.)
for k in "$ROOT"/kwin-tabbox/*/; do
    link "${k%/}" "$DATA/kwin/tabbox/$(basename "$k")"
done
kwriteconfig6 --file kwinrc --group TabBox --key LayoutName mistletoe-dial
qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true

# The dial: menu bridge + its user service, and this machine's settings index.
link "$ROOT/apps/mistletoe-menu/mistletoe-menu" "$HOME/.local/bin/mistletoe-menu"
link "$ROOT/apps/mistletoe-menu/mistletoe-menu.service" "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/mistletoe-menu.service"
systemctl --user daemon-reload
systemctl --user enable --now mistletoe-menu.service >/dev/null 2>&1 && echo "menu bridge running"
python3 "$ROOT/scripts/gen-settings-index.py" "$DATA/mistletoe/settings.json" | head -1
"$HOME/.local/bin/mistletoe-menu" lock-settings >/dev/null && echo "lock screen settings written"
# Font roles (fontconfig aliases); keeps any choice made in the dial.
"$HOME/.local/bin/mistletoe-menu" fonts >/dev/null && echo "font roles set"
for f in "$ROOT"/fonts/*/; do
    link "${f%/}" "$DATA/fonts/$(basename "$f")"
done
fc-cache -f "$DATA/fonts" >/dev/null && echo "font cache refreshed"
