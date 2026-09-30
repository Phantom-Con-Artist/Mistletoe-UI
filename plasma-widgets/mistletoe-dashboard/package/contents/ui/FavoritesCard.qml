/*
    Favorites card: the launcher's favorites (KActivities, shared across
    Plasma) as an icon grid; the heading names the hovered app.
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

    // As many ~56px columns as fit; cells stretch so each row spans the card.
    Grid {
        id: grid
        readonly property int columns_: Math.max(1, Math.floor((width + spacing) / (56 + spacing)))
        readonly property real cell: Math.max(32, Math.floor((width - (columns_ - 1) * spacing) / columns_))
        Layout.fillWidth: true
        columns: columns_
        spacing: 8
        Repeater {
            model: favorites
            delegate: AppButton {
                required property int index
                required property var model
                width: grid.cell
                height: 50
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
