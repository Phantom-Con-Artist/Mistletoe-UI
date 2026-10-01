# Troubleshooting

**The screen went white or black after a change.** plasmashell is hung or
stopped. Bring your windows back with `Alt+Tab`, then in a terminal:

```bash
systemctl --user kill -s KILL plasma-plasmashell
systemctl --user start plasma-plasmashell
```

If it hangs again, a widget is at fault: test it headlessly (see
[development.md](development.md)) or remove it from
`~/.config/plasma-org.kde.plasma.desktop-appletsrc` while the shell is stopped.

**The dial shows Settings instead of the app's menus.** The app either
doesn't share its menus (Electron apps, VS Code, Chrome) or was started before
the menu bridge was running: restart it. `python3 scripts/check-app.py APP`
tells you which. Check the bridge with
`systemctl --user status mistletoe-menu`.

**KDE apps have no menu bar.** That's intended: their menus are in the dial
(`Meta+Space`). Stop the bridge (`systemctl --user disable --now
mistletoe-menu`) to get in-window menu bars back.

**Firefox menus aren't in the dial.** Restart Firefox after running
`scripts/apply-apps.sh`.

**GTK apps' menus aren't in the dial.** Install the module:
`sudo dnf install appmenu-gtk3-module`, then log out and back in. GTK 4 apps
have no menu bar to share.

**A floating card disappeared.** Unpin it from its outline on the desktop, or
reset it: its saved position is ignored unless it is on screen.

**The Neon or Ember wallpaper didn't follow the theme.** Run
`mistletoe-menu edition ember` (or `neon`, `dark`, `light`) to reapply its
wallpaper. Edition changes replace custom wallpapers; choosing a custom image
keeps it until the next edition change. The bridge watches System Settings too.

**The lock screen looks like Plasma's default.** The locker only uses the
Mistletoe screen when KWin was started with `PLASMA_DEFAULT_SHELL` set, so log
out and back in after installing. Check that
`systemctl --user show plasma-kwin_wayland.service -p Environment` prints
`PLASMA_DEFAULT_SHELL=org.mistletoe.lockscreen`; if not, re-run
`scripts/install.sh`. To see the Mistletoe screen without locking:
`PLASMA_DEFAULT_SHELL=org.mistletoe.lockscreen timeout 9 /usr/libexec/kscreenlocker_greet --testing`.

**Undo everything.**

```bash
bash scripts/apply-apps.sh --revert
plasma-apply-lookandfeel --apply org.kde.breezedark.desktop --resetLayout
systemctl --user disable --now mistletoe-menu
```
