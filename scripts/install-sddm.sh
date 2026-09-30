#!/usr/bin/env bash
# Install the verified, self-contained theme and select SDDM for the next boot.
# Run as root: sudo bash scripts/install-sddm.sh build/sddm/mistletoe
# Restore the previous login manager: sudo bash scripts/install-sddm.sh --revert
set -euo pipefail
DEST=/usr/share/sddm/themes/mistletoe
CONF=/etc/sddm.conf.d/90-mistletoe.conf
BACKUP=/var/lib/mistletoe-sddm-backup

[[ $EUID == 0 ]] || { echo "Run this installer with sudo." >&2; exit 1; }

restore() {
    local previous
    [[ -f "$BACKUP/previous-manager" ]] || { echo "No Mistletoe login backup exists." >&2; return 1; }
    previous=$(cat "$BACKUP/previous-manager")
    if [[ -f "$BACKUP/90-mistletoe.conf" ]]; then
        install -m 644 "$BACKUP/90-mistletoe.conf" "$CONF"
    else
        rm -f "$CONF"
    fi
    if [[ -d "$BACKUP/theme" ]]; then
        rm -rf "$DEST"
        cp -a "$BACKUP/theme" "$DEST"
    fi
    systemctl enable --force "$previous"
    echo "Restored $previous for the next boot. The running session was not restarted."
}

if [[ ${1:-} == --revert ]]; then
    if [[ -f /etc/systemd/system/mistletoe-sddm-sync.path ]]; then
        systemctl disable --now mistletoe-sddm-sync.path mistletoe-sddm-sync.service
    fi
    restore
    exit
fi

SOURCE=$(realpath "${1:-build/sddm/mistletoe}")
command -v sddm >/dev/null || { echo "Install sddm and sddm-wayland-plasma first." >&2; exit 1; }
[[ -f /usr/lib/sddm/sddm.conf.d/plasma-wayland.conf ]] || { echo "Missing Fedora's sddm-wayland-plasma configuration." >&2; exit 1; }
[[ -f "$SOURCE/SHA256SUMS" ]] || { echo "Build and test the theme first." >&2; exit 1; }
[[ -f "$SOURCE/VERIFIED_SHA256" ]] || { echo "Run python3 scripts/check-sddm.py before installing." >&2; exit 1; }
read -r digest _ < <(sha256sum "$SOURCE/SHA256SUMS")
[[ "$digest" == "$(cat "$SOURCE/VERIFIED_SHA256")" ]] || { echo "The theme was rebuilt after its last test. Test it again." >&2; exit 1; }
[[ -f "$SOURCE/Main.qml" && -f "$SOURCE/wallpaper.png" ]] || { echo "Incomplete theme package." >&2; exit 1; }
[[ -z $(find "$SOURCE" -type l -print -quit) ]] || { echo "The theme must bundle its assets, without symlinks." >&2; exit 1; }
(cd "$SOURCE" && sha256sum --check --status SHA256SUMS)

if [[ ! -d "$BACKUP" ]]; then
    install -d -m 700 "$BACKUP"
    basename "$(readlink -f /etc/systemd/system/display-manager.service)" > "$BACKUP/previous-manager"
    [[ ! -f "$CONF" ]] || cp -a "$CONF" "$BACKUP/90-mistletoe.conf"
    [[ ! -d "$DEST" ]] || cp -a "$DEST" "$BACKUP/theme"
fi

trap 'echo "Installation failed; restoring the previous login manager." >&2; restore' ERR
install -d -m 755 "$DEST" "$(dirname "$CONF")"
cp -r "$SOURCE/." "$DEST/"
chown -R root:root "$DEST"
find "$DEST" -type d -exec chmod 755 {} +
find "$DEST" -type f -exec chmod 644 {} +
cat > "$CONF" <<'CONFIG'
[General]
DisplayServer=wayland

[Theme]
Current=mistletoe
CursorTheme=breeze_cursors
CONFIG
chmod 644 "$CONF"
if command -v restorecon >/dev/null; then restorecon -RF "$DEST" "$CONF"; fi
systemctl enable --force sddm.service
trap - ERR
echo "SDDM with Mistletoe is selected for the next boot. The running session was not restarted."
