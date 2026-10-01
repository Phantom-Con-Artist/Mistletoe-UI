/*
    Favorites card: the launcher's favorites (KActivities, shared across
    Plasma) as a dock; the heading names the hovered app. The icons share
    one row for as long as they fit at a usable size, then wrap.
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.private.kicker as Kicker

ColumnLayout {
    id: card

    required property var dash
    property string note: ""

    spacing: 12

    Kicker.KAStatsFavoritesModel {
        id: favorites
        Component.onCompleted: initForClient("org.mistletoe.dashboard.favorites")
    }

    SectionLabel {
        Layout.fillWidth: true
        text: i18n("Favorites")
        note: card.note
        gold: card.dash.gold
        bone: card.dash.bone
    }

    // One row while every favorite gets at least 40px, otherwise as many
    // ~48px columns as fit. Cells are square, up to 52px.
    Grid {
        id: grid
        readonly property int count: Math.max(1, favorites.count)
        readonly property real fit: Math.floor((width - (count - 1) * spacing) / count)
        readonly property int columns_: fit >= 40 ? count : Math.max(1, Math.floor((width + spacing) / (48 + spacing)))
        readonly property real cell: Math.max(32, Math.min(52, Math.floor((width - (columns_ - 1) * spacing) / columns_)))
        Layout.fillWidth: true
        columns: columns_
        spacing: 8
        Repeater {
            model: favorites
            delegate: AppButton {
                required property int index
                required property var model
                width: grid.cell
                height: grid.cell
                iconSource: model.decoration
                ink: card.dash.ink
                bone: card.dash.bone
                gold: card.dash.gold
                onHoveredChanged: card.note = hovered ? model.display : ""
                onClicked: favorites.trigger(index, "", null)
            }
        }
    }
    Text {
        visible: favorites.count === 0
        text: i18n("Right-click an app in the launcher to pin it here")
        color: card.dash.tint(card.dash.bone, 0.5)
        font.family: "Mistletoe Text"
        font.pixelSize: 11
    }
    Item {
        Layout.fillHeight: true
    }
}
