/*
    Mistletoe Dashboard: the desktop as a quiet overview, built from
    separate cards. Each instance of this widget shows one card, chosen by
    its `section` setting, and every card has its own facet shape:

      clock      big time and date, straight on the wallpaper (no plate)
      favorites  launcher favorites (KActivities)        chamfered all round
      mostused   apps ranked by how often you start them mirrored shard
      hungry     live CPU/memory graph, hungriest apps, tips   one deep TR cut
      power      lock, sleep, restart, shut down, log out pointed hexagon
      media      YouTube / YouTube Music player with controls   top-chamfered

    The Mistletoe layout script places one of each on the desktop. Hover a
    card for its grip (move), corner (resize) and pin (float above all
    windows); see Card.qml.
*/
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    compactRepresentation: null
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    readonly property string section: Plasmoid.configuration.section || "clock"

    // ---- Palette (shared by every card) --------------------------------
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
    readonly property color ink: Kirigami.Theme.backgroundColor
    readonly property color bone: Kirigami.Theme.textColor
    readonly property color gold: Kirigami.Theme.focusColor

    function tint(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // Default size and corner cuts [TL, TR, BR, BL] per card.
    readonly property var cards: ({
        clock: { file: "ClockCard.qml", w: 352, h: 224, cuts: [0, 0, 0, 0], bare: true },
        favorites: { file: "FavoritesCard.qml", w: 352, h: 208, cuts: [14, 14, 14, 14] },
        mostused: { file: "MostUsedCard.qml", w: 352, h: 272, cuts: [0, 26, 0, 26] },
        hungry: { file: "HungryCard.qml", w: 448, h: 576, cuts: [0, 56, 0, 0] },
        power: { file: "PowerCard.qml", w: 352, h: 64, cuts: [32, 32, 32, 32] },
        // Chamfered along the top like a screen; takes keyboard focus for search.
        media: { file: "MediaCard.qml", w: 448, h: 352, cuts: [20, 20, 0, 0], typing: true }
    })
    readonly property var card: cards[section] || cards.clock
    readonly property bool pointed: section === "power"
    readonly property bool bare: !!card.bare

    // ---- Placement --------------------------------------------------------
    // Cards move and resize themselves through the desktop's own layout
    // (the ItemContainer that holds this widget), so positions snap to the
    // grid and persist exactly as with Plasma's edit mode. A pinned card
    // floats in its own always-on-top window instead; the same content item
    // is reparented, so nothing reloads (a playing video keeps playing).
    readonly property bool pinned: Plasmoid.configuration.pinned

    function container() {
        for (let p = root.parent; p; p = p.parent) {
            if (p.editModeCondition !== undefined && p.layout !== undefined) {
                return p;
            }
        }
        return null;
    }

    function setPinned(on) {
        // Float where the card sits (desktop coordinates are screen
        // coordinates); KWin reads this from the window title.
        const c0 = container();
        if (on && c0) {
            Plasmoid.configuration.floatX = Math.round(c0.x);
            Plasmoid.configuration.floatY = Math.round(c0.y);
        }
        if (on && Plasmoid.configuration.floatW <= 0) {
            // First float: same size as the card, near where it sits.
            const c = container();
            Plasmoid.configuration.floatW = Math.round(c ? c.width : root.card.w);
            Plasmoid.configuration.floatH = Math.round(c ? c.height : root.card.h);
        }
        Plasmoid.configuration.pinned = on;
    }

    fullRepresentation: Item {
        id: slot

        Layout.minimumWidth: 240
        Layout.minimumHeight: Math.min(root.card.h, 64)
        Layout.preferredWidth: root.card.w
        Layout.preferredHeight: root.card.h

        // While the card floats, its desktop slot keeps a faint outline and a
        // pin to bring it back.
        Plate {
            anchors.fill: parent
            visible: root.pinned
            cutTL: 12; cutBR: 12
            fill: "transparent"
            hairline: root.tint(root.bone, 0.14)
            thread: root.tint(root.gold, 0.4)
        }
        PinGem {
            anchors.centerIn: parent
            visible: root.pinned
            dash: root
            pinned: true
            onToggled: root.setPinned(false)
        }

        Card {
            id: cardItem
            parent: root.pinned ? floatHost : slot
            dash: root
            floating: root.pinned
            onPinToggled: root.setPinned(!root.pinned)

            // Floating: the compositor moves and resizes the window.
            onWindowMove: floatWindow.startSystemMove()
            onWindowResize: floatWindow.startSystemResize(Qt.RightEdge | Qt.BottomEdge)

            onPlaced: (dx, dy, dw, dh) => {
                if (root.pinned) {
                    return;
                }
                // Docked: commit once to the desktop layout. Plasma animates any
                // move of the container (ShortDropBehavior), so snap the target
                // ourselves and let the card's visual offset track the animation
                // (offset = target - current), keeping the card exactly where it
                // was dropped while the container catches up underneath.
                const c = root.container();
                if (!c) {
                    return;
                }
                const grid = 16;
                const snap = (v) => Math.round(v / grid) * grid;
                const tx = snap(c.x + dx), ty = snap(c.y + dy);
                const minH = Math.min(root.card.h, 64);
                c.width = Math.max(240, snap(c.width + dw));
                c.height = Math.max(minH, snap(c.height + dh));
                if (dw === 0 && dh === 0) {
                    cardItem.settle(c, tx, ty, dx, dy);
                }
                c.x = tx;
                c.y = ty;
                c.layout.save();
            }
        }

        // Cards manage their own moves; Plasma's press-and-hold edit mode would
        // start its own drag underneath ours. (Global Edit Mode still works.)
        Component.onCompleted: Qt.callLater(() => {
            const c = root.container();
            if (c) {
                c.editModeCondition = 1; // ItemContainer.Manual
            }
        })

        // A floating card is a plain frameless window. KWin keeps it above
        // other windows, off the task switcher and on every desktop (rule in
        // kwin-scripts/mistletoe-edge, matched by the title) and places it
        // at the "@x,y" in its title: where the card sat on the desktop.
        // Moving and resizing are done by the compositor (startSystemMove /
        // startSystemResize), so they are as smooth as any window.
        Window {
            id: floatWindow
            visible: root.pinned
            flags: Qt.FramelessWindowHint | (root.card.typing ? 0 : Qt.WindowDoesNotAcceptFocus)
            color: "transparent"
            // Only a position on screen is trusted; anything else (a stale or
            // corrupt value) falls back to where the card sits, or top right.
            readonly property point place: {
                const x = Plasmoid.configuration.floatX, y = Plasmoid.configuration.floatY;
                const sw = floatWindow.screen ? floatWindow.screen.width : 1920;
                const sh = floatWindow.screen ? floatWindow.screen.height : 1080;
                if (x >= 0 && y >= 0 && x + 80 <= sw && y + 60 <= sh) {
                    return Qt.point(x, y);
                }
                const c = root.container();
                if (c && c.x >= 0 && c.y >= 0 && c.x + 80 <= sw && c.y + 60 <= sh) {
                    return Qt.point(Math.round(c.x), Math.round(c.y));
                }
                return Qt.point(Math.max(0, sw - width - 48), 48);
            }
            title: "Mistletoe Float " + Plasmoid.id + " @" + place.x + "," + place.y
            width: Math.max(240, Plasmoid.configuration.floatW || root.card.w)
            height: Math.max(64, Plasmoid.configuration.floatH || root.card.h)
            minimumWidth: 240
            minimumHeight: 64
            // Remember the size the user gives it.
            onWidthChanged: if (visible) Plasmoid.configuration.floatW = width
            onHeightChanged: if (visible) Plasmoid.configuration.floatH = height

            Item {
                id: floatHost
                anchors.fill: parent
            }
        }
    }
}
