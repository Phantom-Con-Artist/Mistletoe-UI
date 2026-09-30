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
        if (on && Plasmoid.configuration.floatW <= 0) {
            // First float: same size as the card, near where it sits.
            const c = container();
            Plasmoid.configuration.floatW = Math.round(c ? c.width : root.card.w);
            Plasmoid.configuration.floatH = Math.round(c ? c.height : root.card.h);
            Plasmoid.configuration.floatX = Math.round(c ? c.x + 24 : 120);
            Plasmoid.configuration.floatY = Math.round(c ? c.y + 24 : 120);
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

            // Floating: move/resize the window live from where the drag began.
            property rect start
            onWindowDragStarted: start = Qt.rect(floatWindow.x, floatWindow.y, floatHost.width, floatHost.height)
            onWindowMoveTo: (dx, dy) => {
                floatWindow.x = Math.round(start.x + dx);
                floatWindow.y = Math.round(start.y + dy);
            }
            onWindowResizeTo: (dw, dh) => {
                floatHost.width = Math.max(240, Math.round(start.width + dw));
                floatHost.height = Math.max(64, Math.round(start.height + dh));
            }

            onPlaced: (dx, dy, dw, dh) => {
                if (root.pinned) {
                    Plasmoid.configuration.floatX = floatWindow.x;
                    Plasmoid.configuration.floatY = floatWindow.y;
                    Plasmoid.configuration.floatW = Math.round(floatHost.width);
                    Plasmoid.configuration.floatH = Math.round(floatHost.height);
                    return;
                }
                // Docked: commit once to the desktop layout, which snaps to its
                // grid, keeps clear of other cards and saves.
                const c = root.container();
                if (!c) {
                    return;
                }
                c.layout.releaseSpace(c);
                c.x += dx;
                c.y += dy;
                c.width = Math.max(240, c.width + dw);
                c.height = Math.max(Math.min(root.card.h, 64), c.height + dh);
                c.layout.positionItem(c);
                c.layout.save();
            }
        }

        // Always above other windows; a notification-type window skips the
        // task switcher and the arc. Only the media card takes keyboard focus
        // (for its search field), so floating cards never steal your typing.
        PlasmaCore.Dialog {
            id: floatWindow
            visible: root.pinned
            location: PlasmaCore.Types.Floating
            type: PlasmaCore.Dialog.Notification
            flags: Qt.WindowStaysOnTopHint | (root.card.typing ? 0 : Qt.WindowDoesNotAcceptFocus)
            backgroundHints: PlasmaCore.Dialog.NoBackground
            hideOnWindowDeactivate: false
            x: Plasmoid.configuration.floatX
            y: Plasmoid.configuration.floatY
            mainItem: Item {
                id: floatHost
                width: Math.max(240, Plasmoid.configuration.floatW)
                height: Math.max(64, Plasmoid.configuration.floatH)
            }
        }
    }
}
