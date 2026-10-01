#!/usr/bin/env bash
# Install the Mistletoe boot screen (Plymouth) and make it the default.
#
#   sudo bash scripts/install-plymouth.sh            install and select
#   sudo bash scripts/install-plymouth.sh --revert   go back to the previous theme
#
# Selecting a theme rebuilds the initramfs (that is what -R does), which takes
# a minute. The previous theme's name is kept so --revert can restore it.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST=/usr/share/plymouth/themes/mistletoe
STATE=/var/lib/mistletoe-plymouth-previous

if [[ "${1:-}" == "--revert" ]]; then
    previous="$(cat "$STATE" 2>/dev/null || echo bgrt)"
    plymouth-set-default-theme -R "$previous"
    rm -rf "$DEST" "$STATE"
    echo "boot screen restored to $previous"
    exit 0
fi

command -v plymouth-set-default-theme >/dev/null || { echo "plymouth is not installed"; exit 1; }
rpm -q plymouth-plugin-script >/dev/null 2>&1 || dnf install -y plymouth-plugin-script
[[ -e "$STATE" ]] || plymouth-set-default-theme > "$STATE"
install -d "$DEST"
install -m 0644 "$ROOT"/plymouth/mistletoe/* "$DEST"/
plymouth-set-default-theme -R mistletoe
echo "boot screen set to Mistletoe; revert with: sudo bash $0 --revert"
