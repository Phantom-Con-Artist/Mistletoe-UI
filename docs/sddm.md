# Matching login screen with SDDM

The session lock screen and the boot login screen are separate. Fedora 44's
Plasma Login Manager cannot load a custom QML login theme. The optional SDDM
integration uses the existing Mistletoe lock screen presentation and adapts
its authentication and Switch User action for a boot login.

The existing lock screen QML, desktop widgets, palettes, fonts and app settings
are not edited. The generated login package bundles the current lock wallpaper,
palette, font roles, branding and action icons. It needs no access to your home
directory when running as SDDM's system user.

## Build, test and install on Fedora

Run from the repository as your normal user:

```bash
sudo dnf install sddm sddm-wayland-plasma
python3 scripts/gen-sddm.py
python3 scripts/check-sddm.py
sudo bash scripts/install-sddm.sh build/sddm/mistletoe
sudo bash scripts/install-sddm-sync.sh "$USER"
```

The test needs Python's PySide6 and Pillow modules. It starts the real SDDM
greeter offscreen with a temporary fake daemon, captures idle, active, failure,
retry and user selection screenshots, and checks password submission and session
selection. No real password or account is used. Results are in
`build/sddm-check/report.json`; screenshots and the greeter log are alongside it.

The installer checks the package checksums and refuses a build which has not
passed the greeter test. It writes only the dedicated
`/usr/share/sddm/themes/mistletoe` theme and
`/etc/sddm.conf.d/90-mistletoe.conf`, and enables SDDM for the next boot.
It uses Fedora's existing Wayland greeter configuration and packaged PAM setup.
It does not restart the display manager or reboot.

The normal view keeps the clock, password shard, branding, sleep and switch user
gems, input focus, idle fades, failure shake and retry delay from the lock screen.
Switch User opens a matching shard picker for another account; it also exposes
session selection when more than one desktop session is installed. Enter submits
the password to SDDM, which starts the selected session.

The optional sync installer watches desktop wallpaper and palette settings and
refreshes the login package at boot. It runs the image exporter as the desktop
user, then a root-owned publisher accepts only a validated PNG, three colors
and three contrast flags. The publisher retains the tested QML, fonts and
authentication code. It updates the appearance assets and their checksums
without restarting SDDM. The primary desktop image also follows through to the
session lock screen. Logs: `journalctl -u mistletoe-sddm-sync.service`.
The coordinator repeats the export if desktop settings change while it runs,
so a palette update followed by a wallpaper update cannot leave a stale image.

Changing editions applies the edition wallpaper even after a custom image;
custom images chosen within the current edition remain until the next switch.
Restart an already running bridge after upgrading its code:
`systemctl --user restart mistletoe-menu`.

Font role changes still require the build, test and install commands. To disable
only automatic appearance sync, run
`sudo bash scripts/install-sddm-sync.sh --revert`.

## Restore the previous login manager

```bash
sudo bash scripts/install-sddm.sh --revert
```

The original manager selection, custom configuration and any pre-existing theme
are backed up once under `/var/lib/mistletoe-sddm-backup`. Rollback takes effect
at the next boot and does not interrupt the current session. If necessary, open
a text console with `Ctrl+Alt+F3` and run the rollback command from the repository.
