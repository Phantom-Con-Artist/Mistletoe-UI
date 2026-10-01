# How Mistletoe UI fits together

Mistletoe is built from ordinary Plasma 6 extension points, so it installs
per-user, touches nothing system-wide and can be switched off like any theme.

```
                   ┌──────────────────── plasmashell ────────────────────┐
  Global Theme ──▶ │ strip panel: launcher · dial · arc · tray · status   │
  (layout script)  │ desktop:     dashboard cards (one widget, 6 kinds)   │
                   └───────┬──────────────────────────────┬───────────────┘
                           │ runs commands via             │ global shortcuts
                           ▼ Plasma's executable engine    ▼ (kglobalaccel)
                  mistletoe-menu (bridge)          kwin-scripts/mistletoe-edge
                  · app menus (D-Bus dbusmenu)     · floating cards: keep above,
                  · places · editions · fonts        clamp on screen
                  · wallpaper sync & brightness
                  · lock screen values
                           │ writes
                           ▼
            fontconfig roles · kdeglobals · kscreenlockerrc · lock screen package
```

## Look

| Layer | Package | Notes |
|---|---|---|
| Colours | `color-schemes/Mistletoe*.colors` | One palette table in `scripts/gen-colors.py` drives every colour everywhere. |
| Plasma style | `themes/mistletoe-*` | 9-slice SVG frames with chamfered corners and gold threads; the panel background is the matte strip. `plasmarc` turns blur and contrast off. |
| Window frames | `window-decorations/aurorae/mistletoe-*` | Aurorae SVG theme: slim title bar, chamfered corner, gem buttons, real Gaussian shadows. |
| Global Theme | `lookandfeel/org.mistletoe.*.desktop` | Sets colours, style, frames, icons, cursor, fonts (the Text role) and wallpaper; its layout script builds the strip and the cards. |
| Fonts | `fonts/`, fontconfig | Three roles (`Mistletoe Display`, `Accent`, `Text`) are fontconfig aliases written by `mistletoe-menu fonts`. Every surface names a role, never a family, so a switch changes everything at once. |
| Lock screen | `shells/org.mistletoe.lockscreen` | kscreenlocker loads its UI from a Plasma *shell* package chosen in `kscreenlockerrc [Greeter] Theme`. It is installed as a copy so the bridge can write `backdrop.js` (text contrast, distro line) into it. |

## Behaviour

### Widgets (`plasma-widgets/`)

- **launcher**: kicker's models (all apps, favourites, KRunner search) in a
  full-screen overlay window (`Overlay.qml`) with the radial fan.
- **status**: Bluetooth (BluezQt), network (plasma-nm), volume (plasma-pa),
  media (MPRIS), notifications (notificationmanager) and session actions.
- **arc**: TaskManager for open windows; ksysguard's application model for
  per-app CPU/RAM. The popup is a focus-less tooltip-type dialog.
- **dial**: three modes in one rotary view. App mode reads the active
  window's menu address from TaskManager (`ApplicationMenuServiceName/ObjectPath`)
  and asks the bridge to dump or click it. Places and Settings come from the
  bridge and a per-machine index of KCMs.
- **dashboard**: one widget, one card per instance (`section` setting):
  clock, favourites, most used, power (live graph and tips), power buttons,
  media (QtWebEngine, loaded only while open). `Card.qml` adds the grip,
  resize corner and pin; a pinned card becomes its own frameless window.

Shared shapes (`Shard`, `Gem`, `Overlay`) live once in
`plasma-widgets/shared/` and are copied into each package by
`scripts/sync-shared.py`, because widget packages must be self-contained.

### The bridge (`apps/mistletoe-menu`)

A small Python script the widgets run through Plasma's executable data
engine. Its `serve` mode runs as a user service and holds the D-Bus name
`org.kde.kappmenuview`, which makes Plasma start the AppMenu registrar; apps
then export their menu bars over `com.canonical.dbusmenu`, which is how the
dial can read and trigger any app's menus. Other commands:

| Command | Does |
|---|---|
| `dump SERVICE PATH` / `click SERVICE PATH ID` | read / trigger an app's menu |
| `places` | Dolphin places, recent folders, drives, network |
| `edition NAME` | apply a Global Theme and its Konsole colours |
| `fonts ROLE=FAMILY …` | set the font roles |
| `options` | editions and font choices for the dial |
| `sync-wallpaper` | apply the edition wallpaper on edition changes, mirror the current image to the lock screen, keep the GTK layer imported, refresh lock screen values |
| `backdrop X Y W H SW SH` | light or dark: the wallpaper behind a rectangle |
| `lock-settings` | text contrast and distro line for the lock screen |

The dial runs `sync-wallpaper` whenever the colour scheme changes (every
theme switch) and at start-up. The bridge also watches desktop and global-theme
settings, including changes made in System Settings. Custom wallpapers remain
within an edition; switching editions replaces them. The last observed edition
is stored in `mistletoerc` so restarting the bridge keeps a custom wallpaper.

### KWin (`kwin-scripts/mistletoe-edge`)

Gives floating cards (windows titled
`Mistletoe Float <id> @x,y`) keep-above, no task switcher, all desktops, and
an on-screen position.

### Native apps (`scripts/apply-apps.sh`)

App-wide settings a Global Theme can't carry: the UI font as the Text role,
icon-only toolbars, flat Breeze options, the Konsole profile, the lock
screen, a GTK 3/4 CSS layer and Firefox's global menu. It backs everything
up and `--revert` restores it.
