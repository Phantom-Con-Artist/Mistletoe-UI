#!/usr/bin/env bash
# Install a root-owned, data-only publisher and a desktop-settings watcher.
set -euo pipefail
[[ $EUID == 0 ]] || { echo "Run with sudo." >&2; exit 1; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [[ ${1:-} == --revert ]]; then
    systemctl disable --now mistletoe-sddm-sync.path mistletoe-sddm-sync.service
    echo "Automatic SDDM appearance sync disabled. The current theme is retained."
    exit
fi
USER_NAME=${1:-${SUDO_USER:-}}
[[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]*$ && "$USER_NAME" != root ]] || { echo "Specify the desktop user." >&2; exit 1; }
IFS=: read -r _ _ USER_UID USER_GID _ USER_HOME _ < <(getent passwd "$USER_NAME")
[[ -n "$USER_HOME" && "$USER_UID" -ge 1000 ]] || { echo "Invalid desktop user." >&2; exit 1; }
[[ -f /usr/share/sddm/themes/mistletoe/Main.qml ]] || { echo "Install the tested Mistletoe SDDM theme first." >&2; exit 1; }
install -d -m 755 /usr/local/libexec /var/lib/mistletoe-sddm-sync
install -d -m 700 -o "$USER_UID" -g "$USER_GID" /var/lib/mistletoe-sddm-sync/incoming
install -m 755 "$ROOT/scripts/sync-sddm.py" /usr/local/libexec/mistletoe-sddm-sync
cat > /etc/systemd/system/mistletoe-sddm-sync.service <<UNIT
[Unit]
Description=Match the Mistletoe login screen to desktop appearance
After=local-fs.target
Before=display-manager.service
ConditionPathExists=/usr/share/sddm/themes/mistletoe/settings.js

[Service]
Type=oneshot
User=$USER_NAME
Environment="HOME=$USER_HOME"
ExecStart=+/usr/bin/python3 /usr/local/libexec/mistletoe-sddm-sync refresh --state /var/lib/mistletoe-sddm-sync/incoming --config $USER_HOME/.config --data $USER_HOME/.local/share --uid $USER_UID
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
UNIT
cat > /etc/systemd/system/mistletoe-sddm-sync.path <<UNIT
[Unit]
Description=Watch desktop wallpaper and palette changes for Mistletoe SDDM

[Path]
PathChanged=$USER_HOME/.config/kdeglobals
PathChanged=$USER_HOME/.config/plasma-org.kde.plasma.desktop-appletsrc
Unit=mistletoe-sddm-sync.service

[Install]
WantedBy=multi-user.target
UNIT
chmod 644 /etc/systemd/system/mistletoe-sddm-sync.{service,path}
if command -v restorecon >/dev/null; then
    restorecon -RF /usr/local/libexec/mistletoe-sddm-sync /var/lib/mistletoe-sddm-sync /etc/systemd/system/mistletoe-sddm-sync.{service,path}
fi
systemctl daemon-reload
systemctl enable mistletoe-sddm-sync.service
systemctl enable --now mistletoe-sddm-sync.path
systemctl start mistletoe-sddm-sync.service
echo "Desktop wallpaper and colors now synchronize automatically to the login screen."
