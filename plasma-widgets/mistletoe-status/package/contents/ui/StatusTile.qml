/*
    A status cell: a square shard with a gem-framed icon, the same size and
    cut as the launcher's app cells. `on` fills the gem gold (Bluetooth on,
    audio playing, ...); `current` marks the cell resting at the dial's stop.
    Its name and value are shown by the fan's caption, not on the cell.
*/
import QtQuick
import org.kde.kirigami as Kirigami

MouseArea {
    id: tile

    property string icon
    property bool on: false
    property bool current: false
    // Whether the wheel adjusts this cell (volume, media) rather than
    // turning the fan's dial.
    property bool wheelable: false
    property real unit: 1
    property color ink
    property color bone
    property color gold

    signal wheelStep(int direction)

    function tint(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    readonly property bool lit: containsMouse || current

    width: Math.round(52 * unit)
    height: width
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onWheel: (wheel) => {
        if (tile.wheelable) {
            tile.wheelStep(wheel.angleDelta.y > 0 ? 1 : -1);
        } else {
            wheel.accepted = false;
        }
    }

    Item {
        anchors.fill: parent
        scale: tile.containsMouse ? 1.12 : tile.current ? 1.06 : 1
        Behavior on scale {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Shard {
            anchors.fill: parent
            cut: Math.round(9 * tile.unit)
            fill: tile.tint(tile.ink, tile.lit ? 0.96 : 0.8)
            rim: tile.lit ? tile.gold : tile.tint(tile.bone, 0.16)
        }

        Gem {
            width: Math.round(30 * tile.unit)
            height: width
            anchors.centerIn: parent
            fill: tile.on ? tile.gold : "transparent"
            rim: tile.on ? tile.gold : tile.tint(tile.bone, 0.4)
            Behavior on fill {
                ColorAnimation { duration: 180 }
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: Math.round(parent.width * 0.48)
                height: width
                source: tile.icon
                isMask: true
                color: tile.on ? tile.ink : tile.bone
                animated: false
            }
        }
    }
}
