/*
    Mistletoe Dashboard: the desktop as a quiet overview, built from
    separate cards. Each instance of this widget shows one card, chosen by
    its `section` setting, and every card has its own facet shape:

      clock      big time and date, straight on the wallpaper (no plate)
      favorites  launcher favorites (KActivities)        chamfered all round
      mostused   apps ranked by how often you start them mirrored shard
      hungry     live CPU/memory graph, hungriest apps, tips   one deep TR cut
      power      lock, sleep, restart, shut down, log out pointed hexagon

    The Mistletoe layout script places one of each on the desktop; they can
    be moved and resized independently like any desktop widget.
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
        power: { file: "PowerCard.qml", w: 352, h: 64, cuts: [32, 32, 32, 32] }
    })
    readonly property var card: cards[section] || cards.clock
    readonly property bool pointed: section === "power"
    readonly property bool bare: !!card.bare

    fullRepresentation: Item {
        Layout.minimumWidth: 240
        Layout.minimumHeight: Math.min(root.card.h, 64)
        Layout.preferredWidth: root.card.w
        Layout.preferredHeight: root.card.h

        Plate {
            anchors.fill: parent
            visible: !root.bare
            // Pointed ends follow the card's height when it is resized.
            cutTL: root.pointed ? height / 2 : root.card.cuts[0]
            cutTR: root.pointed ? height / 2 : root.card.cuts[1]
            cutBR: root.pointed ? height / 2 : root.card.cuts[2]
            cutBL: root.pointed ? height / 2 : root.card.cuts[3]
            fill: root.tint(root.ink, 0.97)
            hairline: root.tint(root.bone, 0.10)
            thread: root.tint(root.gold, 0.85)
        }

        // The section is often written right after the widget is created
        // (by the layout script), so reload when it changes.
        Connections {
            target: root
            function onCardChanged() {
                loader.load();
            }
        }

        Loader {
            id: loader

            function load() {
                setSource(root.card.file, { dash: root });
            }

            anchors.fill: parent
            anchors.leftMargin: root.bare ? 0 : root.pointed ? parent.height / 2 : 28
            anchors.rightMargin: root.pointed ? parent.height / 2 : 28
            anchors.topMargin: root.bare || root.pointed ? 0 : 26
            anchors.bottomMargin: root.bare || root.pointed ? 0 : 26
            // Pass the dashboard in up front so no binding sees it unset.
            Component.onCompleted: load()
        }
    }
}
