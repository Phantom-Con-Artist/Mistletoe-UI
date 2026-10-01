#!/usr/bin/env bash
# Download the Papirus icon theme (GPL-3) into ~/.local/share/icons and build
# the Mistletoe icon themes on top of it (see gen-icons.py). No root needed.
#
#   bash scripts/install-icons.sh            download (once) and build
#   bash scripts/install-icons.sh --remove   remove Papirus and the Mistletoe themes
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
TAG=20260801   # the Papirus release this was tested with
URL="https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/archive/refs/tags/$TAG.tar.gz"

if [[ "${1:-}" == "--remove" ]]; then
    rm -rf "$ICONS"/Papirus "$ICONS"/Papirus-Dark "$ICONS"/Mistletoe-{Dark,Light,Neon,Ember}
    echo "removed; pick another icon theme in System Settings > Colors & Themes > Icons"
    exit 0
fi

mkdir -p "$ICONS"
if [[ ! -f "$ICONS/Papirus-Dark/index.theme" ]]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    echo "downloading Papirus $TAG (about 33 MB)..."
    curl -fL --retry 2 -o "$tmp/papirus.tar.gz" "$URL"
    tar xzf "$tmp/papirus.tar.gz" --strip-components=1 -C "$ICONS" \
        "papirus-icon-theme-$TAG/Papirus" "papirus-icon-theme-$TAG/Papirus-Dark"
fi
python3 "$ROOT/scripts/gen-icons.py"
echo "done; the Mistletoe Global Themes select these icons"
