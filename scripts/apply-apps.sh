#!/usr/bin/env bash
# Give native KDE apps the calm Mistletoe look: Exo 2 as the UI font, icon-only
# toolbars, no icons on buttons or in menus, no focus rings or toolbar
# separators, Konsole with the Mistletoe profile and no menubar, the
# Mistletoe lock screen, a sharp flat layer for GTK apps, and Firefox's
# global menu (so its menus appear in the dial).
#
# These are app-wide settings a Global Theme can't carry, so they live here.
# Every touched file is backed up first; `apply-apps.sh --revert` restores it.
set -euo pipefail
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
BACKUP="$CONF/mistletoe-apps.backup"
FILES=(kdeglobals breezerc konsolerc kscreenlockerrc)
VARIANT="${VARIANT:-Dark}"   # Dark or Light, for the Konsole profile

if [[ "${1:-}" == "--revert" ]]; then
    [[ -d "$BACKUP" ]] || { echo "no backup at $BACKUP"; exit 1; }
    # GTK layer and Firefox prefs.
    for v in 3.0 4.0; do
        rm -f "$CONF/gtk-$v/mistletoe.css"
        sed -i "/@import 'mistletoe.css';/d" "$CONF/gtk-$v/gtk.css" 2>/dev/null || true
    done
    for prof in "$CONF"/mozilla/firefox/*.default* "$HOME"/.mozilla/firefox/*.default*; do
        [[ -f "$prof/user.js" ]] && sed -i '/Mistletoe: global menu for the dial/,+2d' "$prof/user.js"
    done
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
# The UI font is the Mistletoe *Text role* (a fontconfig alias, Exo 2 by
# default), so changing the role in the dial restyles apps too.
font() { echo "Mistletoe Text,$1,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"; }

# Type: the Text role for the UI; terminals keep the system monospace.
w kdeglobals General font "$(font 10)"
w kdeglobals General menuFont "$(font 10)"
w kdeglobals General toolBarFont "$(font 9)"
w kdeglobals General smallestReadableFont "$(font 8)"
w kdeglobals WM activeFont "$(font 10)"

# Offer Mistletoe as the light/dark pair in Quick Settings (and for the
# "Automatic" day/night switch) instead of Breeze.
w kdeglobals KDE DefaultLightLookAndFeel org.mistletoe.light.desktop
w kdeglobals KDE DefaultDarkLookAndFeel org.mistletoe.dark.desktop

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
# Quieter chrome: scrollbars only while the pointer is near them, no frames
# around docked panels or page titles, and a light highlight in menus.
w breezerc Style ScrollBarShowOnMouseOver true
w breezerc Style DockWidgetDrawFrame false
w breezerc Style TitleWidgetDrawFrame false
w breezerc Style MenuItemDrawStrongFocus false
w breezerc Style WindowDragMode WD_FULL

# Controls inside Qt apps: the Mistletoe Kvantum theme, when Kvantum is
# installed (sudo dnf install kvantum). The Global Themes ask for the kvantum
# style and fall back to Breeze without it; the bridge keeps Kvantum on the
# active edition's theme.
if [[ -n "$(find /usr/lib64/qt6/plugins/styles /usr/lib/qt6/plugins/styles -name 'libkvantum.so' 2>/dev/null | head -1)" ]]; then
    mkdir -p "$CONF/Kvantum"
    for k in "$(cd "$(dirname "$0")/.." && pwd)"/kvantum/*/; do
        ln -sfn "${k%/}" "$CONF/Kvantum/$(basename "$k")"
    done
    [[ -e "$CONF/Kvantum/kvantum.kvconfig" ]] || printf '[General]\ntheme=Mistletoe%s\n' "$VARIANT" > "$CONF/Kvantum/kvantum.kvconfig"
    w kdeglobals KDE widgetStyle kvantum
fi

# Konsole: the Mistletoe profile, no menubar.
w konsolerc "Desktop Entry" DefaultProfile "Mistletoe$VARIANT.profile"
w konsolerc KonsoleWindow ShowMenuBarByDefault false

# Lock screen wallpaper: the Mistletoe one (the dial's wallpaper sync keeps
# it matching the desktop afterwards). Which lock screen is used is set by
# install.sh; the Theme key below is only read by older Plasma versions.
w kscreenlockerrc Greeter Theme org.mistletoe.lockscreen
kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General \
    --key Image "file://${XDG_DATA_HOME:-$HOME/.local/share}/wallpapers/Mistletoe"

# GTK 3/4 apps: the sharp, flat Mistletoe layer over KDE's generated colours.
for v in 3.0 4.0; do
    dir="$CONF/gtk-$v"
    mkdir -p "$dir"
    ln -sfn "$(cd "$(dirname "$0")/.." && pwd)/gtk/mistletoe.css" "$dir/mistletoe.css"
    if ! grep -qs "mistletoe.css" "$dir/gtk.css"; then
        # KDE writes gtk.css without a trailing newline.
        [[ -s "$dir/gtk.css" && -n "$(tail -c1 "$dir/gtk.css")" ]] && echo >> "$dir/gtk.css"
        echo "@import 'mistletoe.css';" >> "$dir/gtk.css"
    fi
done

# Firefox: its built-in global menu, so its menus appear in the dial.
MARK="// Mistletoe: global menu for the dial"
for prof in "$CONF"/mozilla/firefox/*.default* "$HOME"/.mozilla/firefox/*.default*; do
    [[ -d "$prof" ]] || continue
    grep -qsF "$MARK" "$prof/user.js" && continue
    printf '%s\nuser_pref("widget.gtk.global-menu.enabled", true);\nuser_pref("widget.gtk.global-menu.wayland.enabled", true);\n' \
        "$MARK" >> "$prof/user.js"
done

# Tell running apps to reload their style and fonts.
dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0 || true
dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:2 int32:0 || true
echo "applied Mistletoe app style ($VARIANT); revert with: $0 --revert"
