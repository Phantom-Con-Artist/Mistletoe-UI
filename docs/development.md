# Developing Mistletoe UI

## Edit, reload, check

Widgets are installed as symlinks, so an edit only needs a shell restart:

```bash
systemctl --user restart plasma-plasmashell
```

After changing a Plasma style SVG, clear Plasma's SVG caches too:

```bash
systemctl --user stop plasma-plasmashell
rm -rf ~/.cache/plasma-svgelements* ~/.cache/plasma_theme_* ~/.cache/ksvg-elements*
systemctl --user start plasma-plasmashell
```

Generated files: change the generator, not its output, then run it
(`python3 scripts/gen-*.py`). The fonts and logo need a small venv:

```bash
python3 -m venv ~/.cache/mistletoe/fontenv
~/.cache/mistletoe/fontenv/bin/pip install fonttools skia-pathops pillow
~/.cache/mistletoe/fontenv/bin/python scripts/build-fonts.py
~/.cache/mistletoe/fontenv/bin/python scripts/build-logo.py
```

Before committing widget changes: `python3 scripts/sync-shared.py --check`.

## Test headlessly first

A widget that hangs or crashes takes plasmashell (and the desktop) with it,
so load changed widgets in the viewer before restarting the real shell:

```bash
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORMTHEME=kde QT_QPA_PLATFORM=offscreen \
  timeout 10 plasmoidviewer -a plasma-widgets/<name>/package -f horizontal -l bottomedge
```

On a copy of the package, append a `Timer` to `main.qml` that logs
`console.warn("SELFTEST …")` or saves `fullRepresentationItem.grabToImage(…)`.
Use `-f planar` for desktop cards. Limits: a default colour scheme, an
800×800 screen, and no windows (Wayland only shares them with plasmashell).

The lock screen has a test mode (it covers the screen; it closes itself):

```bash
timeout 9 /usr/libexec/kscreenlocker_greet --testing --shell org.mistletoe.lockscreen
```

Test mode ignores your lock wallpaper and always uses the default shell
unless `--shell` is given.

On the live session: `spectacle -b -n -f -o shot.png` takes a screenshot;
`qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '…'`
scripts panels and widgets; widget shortcuts can be invoked through
`org.kde.kglobalaccel`. KWin scripts must be files KWin can read (not a
private temp directory).

## Hard-won rules

- **Never give a `Shape` degenerate geometry.** Qt's curve renderer spins
  forever on zero-size paths, duplicate consecutive points or folded edges,
  hanging plasmashell (white screen, 99% CPU). `Shard`/`Gem` skip drawing
  below 2px; `Plate` de-duplicates its outline. Diagnose a hang with
  `eu-stack -p $(pgrep -x plasmashell)`.
- A panel reads size and fill from the **PlasmoidItem root's** `Layout.*`
  hints, and that file must `import QtQuick.Layouts`.
- `fullRepresentation: null` means Plasma never creates the compact button:
  make the button the full representation.
- `rootModel.modelForRow()` builds a new model on every call; never call it
  from a binding.
- Kicker's `DashboardWindow` forces blur; use the plain `Overlay.qml`.
- Don't name a property `data` (it shadows `Item.data`), and don't give a
  function the same name as a property (the lock screen's `ink()` clash made
  every call fail).
- Desktop widgets snap to a 16px grid and are at least 64px tall; the
  scripting API's `geometry` doesn't persist. Edit `ItemGeometries-*` in
  `plasma-org.kde.plasma.desktop-appletsrc` with the shell stopped.
- Plasma animates desktop widget moves and starts its own drag on
  press-and-hold; cards turn press-and-hold off and settle themselves.
- `PlasmaCore.Dialog` sizes and places itself; floating cards use a plain
  window moved by the compositor (`startSystemMove`).
- `plasma-apply-lookandfeel` won't replace a wallpaper you've set; the
  bridge's `sync-wallpaper` does it for the editions.
- kscreenlocker rejects a shell package without `X-Plasma-APIVersion: 2`.
- kscreenlocker takes the lock screen from the Plasma shell package
  (`PLASMA_DEFAULT_SHELL`, default `org.kde.plasma.desktop`), not from
  `kscreenlockerrc [Greeter] Theme`. `--testing --shell X` proves the QML
  works, not that a real lock will use it: test without `--shell`.
- Never set `PLASMA_DEFAULT_SHELL` for the whole session: plasmashell names
  its config after the shell and would start with an empty desktop.
- MultiEffect layer shadows render blank offscreen; use `Text.Raised`.
- `WebEngineProfilePrototype` segfaults inside plasmashell here; keep the
  `WebEngineProfile` form.
- Plasma rewrites `AppletOrder` on save; edit it only while the shell is
  stopped.
