/*
    A favorite: a bare icon that gains a shard plate and gold rim on hover.
*/
import QtQuick
import org.kde.kirigami as Kirigami

MouseArea {
    id: button

    property var iconSource
    property color ink
    property color bone
    property color gold
    readonly property bool hovered: containsMouse

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Item {
        anchors.fill: parent
        scale: button.pressed ? 0.94 : button.containsMouse ? 1.06 : 1
        Behavior on scale {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Shard {
            anchors.fill: parent
            cut: 9
            fill: Qt.rgba(button.bone.r, button.bone.g, button.bone.b, button.containsMouse ? 0.08 : 0.03)
            rim: button.containsMouse ? button.gold : Qt.rgba(button.bone.r, button.bone.g, button.bone.b, 0.08)
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: 32
            height: 32
            source: button.iconSource
            animated: false
        }
    }
}
