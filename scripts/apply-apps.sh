#!/usr/bin/env bash
# Give native KDE apps the calm Mistletoe look: Exo 2 as the UI font, icon-only
# toolbars, no icons on buttons or in menus, no focus rings or toolbar
# separators, and Konsole with the Mistletoe profile and no menubar.
#
# These are app-wide settings a Global Theme can't carry, so they live here.
# Every touched file is backed up first; `apply-apps.sh --revert` restores it.
set -euo pipefail
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
BACKUP="$CONF/mistletoe-apps.backup"
FILES=(kdeglobals breezerc konsolerc)
VARIANT="${VARIANT:-Dark}"   # Dark or Light, for the Konsole profile

if [[ "${1:-}" == "--revert" ]]; then
    [[ -d "$BACKUP" ]] || { echo "no backup at $BACKUP"; exit 1; }
    for f in "${FILES[@]}"; do
        if [[ -e "$BACKUP/$f" ]]; then cp "$BACKUP/$f" "$CONF/$f"; else rm -f "$CONF/$f"; fi
    done
    rm -rf "$BACKUP"
    echo "restored app settings"
    exit 0
fi

# Back up once, so re-running never overwrites the original backup.
if [[ ! -d "$BACKUP" ]]; then
    mkdir -p "$BACKUP"
    for f in "${FILES[@]}"; do [[ -e "$CONF/$f" ]] && cp "$CONF/$f" "$BACKUP/$f"; done
fi

w() { kwriteconfig6 --file "$1" --group "$2" --key "$3" "$4"; }
font() { echo "Exo 2,$1,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"; }

# Type: Exo 2 for the UI; terminals keep the system monospace.
w kdeglobals General font "$(font 10)"
w kdeglobals General menuFont "$(font 10)"
w kdeglobals General toolBarFont "$(font 9)"
w kdeglobals General smallestReadableFont "$(font 8)"
w kdeglobals WM activeFont "$(font 10)"

# Fewer things competing for attention.
w kdeglobals "Toolbar style" ToolButtonStyle NoText
w kdeglobals "Toolbar style" ToolButtonStyleOtherToolbars NoText
w kdeglobals KDE ShowIconsOnPushButtons false
w kdeglobals KDE ShowIconsInMenuItems false

# Breeze widget style: flat, no separators, no focus rectangles in views,
# no frames around side panels; drag windows from any empty area, since
# Mistletoe title bars are slim.
w breezerc Style ToolBarDrawItemSeparator false
w breezerc Style ViewDrawFocusIndicator false
w breezerc Style SidePanelDrawFrame false
w breezerc Style MenuOpacity 100
w breezerc Style WindowDragMode WD_FULL

# Konsole: the Mistletoe profile, no menubar.
w konsolerc "Desktop Entry" DefaultProfile "Mistletoe$VARIANT.profile"
w konsolerc KonsoleWindow ShowMenuBarByDefault false

# Tell running apps to reload their style and fonts.
dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0 || true
dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:2 int32:0 || true
echo "applied Mistletoe app style ($VARIANT); revert with: $0 --revert"
