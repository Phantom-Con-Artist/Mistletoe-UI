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
| Global Theme | `lookandfeel/org.mistletoe.*.desktop` | Sets colours, style, frames, icons, cursor, fonts (the Text role) and wallpaper; its layout script builds the strip and the cards. Also carries the start-up splash (`contents/splash`) and the leave screen (`contents/logout`); both are built on one generated scene that mirrors the lock screen, with the edition's colours written in and the wallpaper and your name read from `~/.local/share/mistletoe/Appearance.qml` (kept by the bridge's `lock-settings`). |
| Fonts | `fonts/`, fontconfig | Three roles (`Mistletoe Display`, `Accent`, `Text`) are fontconfig aliases written by `mistletoe-menu fonts`. Every surface names a role, never a family, so a switch changes everything at once. |
| Lock screen | `shells/org.mistletoe.lockscreen` | kscreenlocker loads its UI from the Plasma *shell* package named by `PLASMA_DEFAULT_SHELL` (Plasma 6.7 ignores `kscreenlockerrc [Greeter] Theme`). `install.sh` sets that variable for KWin's service only, through a systemd drop-in: KWin starts the locker, while plasmashell must keep the desktop shell. Anything the package lacks falls back to the desktop shell. It is installed as a copy so the bridge can write `backdrop.js` (text contrast, distro line) into it. |

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
- **dashboard**: one widget, one card per instance (`section` setting). The
  layout places four: the clock (bare, bottom left), and on the right the
  system card (live graph, busiest apps, a tip), the favourites dock and
  media (QtWebEngine, loaded only while open; asleep it is a gem with no
  plate). Most used and power buttons exist but aren't placed. Every plate is
  the same shard; `Card.qml` adds the grip, resize corner and pin, and a
  pinned card becomes its own frameless window.

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

The **minimize effect** (`kwin-effects/mistletoe-minimize`) folds a window
into the middle of the strip; it replaces Squash, which needs a task manager
icon to aim at. The **window switcher** (`kwin-tabbox/mistletoe-dial`) is the
rotary `Alt+Tab`; it runs inside KWin, so it draws with plain rectangles only.

### Native apps (`scripts/apply-apps.sh`)

App-wide settings a Global Theme can't carry: the UI font as the Text role,
icon-only toolbars, flat Breeze options, the Konsole profile, the lock
screen, a GTK 3/4 CSS layer and Firefox's global menu. It backs everything
up and `--revert` restores it.

The controls inside Qt apps come from a **Kvantum theme** per edition
(`kvantum/`, generated by `scripts/gen-kvantum.py` as a recolouring of
Kvantum's Material-style KvAdapta). The Global Themes ask for the `kvantum`
widget style and fall back to Breeze without it; Kvantum keeps its chosen
theme in its own file, so the bridge points it at the active edition.
