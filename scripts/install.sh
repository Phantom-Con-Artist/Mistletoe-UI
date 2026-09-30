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
for sh in "$ROOT"/shells/*/; do
    link "${sh%/}" "$DATA/plasma/shells/$(basename "$sh")"
done
for w in "$ROOT"/wallpapers/*/; do
    link "${w%/}" "$DATA/wallpapers/$(basename "$w")"
done
# KWin scripts (the left-edge dial trigger), enabled.
for k in "$ROOT"/kwin-scripts/*/; do
    id="$(basename "$k")"
    link "${k%/}" "$DATA/kwin/scripts/$id"
    kwriteconfig6 --file kwinrc --group Plugins --key "${id}Enabled" true
done
qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true

# The dial: menu bridge + its user service, and this machine's settings index.
link "$ROOT/apps/mistletoe-menu/mistletoe-menu" "$HOME/.local/bin/mistletoe-menu"
link "$ROOT/apps/mistletoe-menu/mistletoe-menu.service" "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/mistletoe-menu.service"
systemctl --user daemon-reload
systemctl --user enable --now mistletoe-menu.service >/dev/null 2>&1 && echo "menu bridge running"
python3 "$ROOT/scripts/gen-settings-index.py" "$DATA/mistletoe/settings.json" | head -1
for f in "$ROOT"/fonts/*/; do
    link "${f%/}" "$DATA/fonts/$(basename "$f")"
done
fc-cache -f "$DATA/fonts" >/dev/null && echo "font cache refreshed"
