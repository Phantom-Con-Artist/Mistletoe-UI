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
`mistletoe-menu sync-wallpaper`. It never replaces a wallpaper that isn't one
of Mistletoe's.

**The lock screen looks like Plasma's default.** Check
`kreadconfig6 --file kscreenlockerrc --group Greeter --key Theme` prints
`org.mistletoe.lockscreen`, and re-run `scripts/apply-apps.sh`.

**Undo everything.**

```bash
bash scripts/apply-apps.sh --revert
plasma-apply-lookandfeel --apply org.kde.breezedark.desktop --resetLayout
systemctl --user disable --now mistletoe-menu
```
