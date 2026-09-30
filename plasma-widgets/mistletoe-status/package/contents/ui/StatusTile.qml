/*
    A status tile: a shard plate with a gem-framed icon, a gold label and a
    value. `on` fills the gem gold (Bluetooth on, audio playing, ...).
*/
import QtQuick
import org.kde.kirigami as Kirigami

MouseArea {
    id: tile

    property string icon
    property string label
    property string value
    property bool on: false
    property real unit: 1
    property color ink
    property color bone
    property color gold

    signal wheelStep(int direction)

    function tint(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    width: Math.round(150 * unit)
    height: Math.round(48 * unit)
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onWheel: (wheel) => tile.wheelStep(wheel.angleDelta.y > 0 ? 1 : -1)

    Item {
        anchors.fill: parent
        scale: tile.containsMouse ? 1.05 : 1
        Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Shard {
            anchors.fill: parent
            cut: Math.round(9 * tile.unit)
            fill: tile.tint(tile.ink, tile.containsMouse ? 0.96 : 0.84)
            rim: tile.containsMouse ? tile.gold : tile.tint(tile.bone, 0.16)
        }

        Gem {
            id: gem
            width: Math.round(28 * tile.unit)
            height: width
            x: Math.round(10 * tile.unit)
            anchors.verticalCenter: parent.verticalCenter
            fill: tile.on ? tile.gold : "transparent"
            rim: tile.on ? tile.gold : tile.tint(tile.bone, 0.4)
            Behavior on fill {
                ColorAnimation { duration: 200 }
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: Math.round(parent.width * 0.46)
                height: width
                source: tile.icon
                isMask: true
                color: tile.on ? tile.ink : tile.bone
                animated: false
            }
        }

        Column {
            anchors.left: gem.right
            anchors.leftMargin: Math.round(9 * tile.unit)
            anchors.right: parent.right
            anchors.rightMargin: Math.round(10 * tile.unit)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: tile.label.toUpperCase()
                color: tile.gold
                font.family: "Exo 2"
                font.pixelSize: Math.round(9 * tile.unit)
                font.letterSpacing: 2
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: tile.value
                color: tile.bone
                font.family: "Exo 2"
                font.pixelSize: Math.round(12 * tile.unit)
                elide: Text.ElideRight
            }
        }
    }
}
