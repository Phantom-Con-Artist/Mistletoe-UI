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
for w in "$ROOT"/wallpapers/*/; do
    link "${w%/}" "$DATA/wallpapers/$(basename "$w")"
done
link "$ROOT/fonts/Exo2" "$DATA/fonts/Exo2"
fc-cache -f "$DATA/fonts" >/dev/null && echo "font cache refreshed"
