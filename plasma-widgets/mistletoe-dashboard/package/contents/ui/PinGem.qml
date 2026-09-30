/*
    Pin toggle: a small gem with a pin; gold when the card floats.
*/
import QtQuick
import org.kde.kirigami as Kirigami

MouseArea {
    id: pin

    required property var dash
    property bool pinned: false
    signal toggled()

    width: 22
    height: 22
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: toggled()

    Gem {
        anchors.fill: parent
        scale: pin.containsMouse ? 1.12 : 1
        fill: pin.pinned ? pin.dash.gold : pin.dash.tint(pin.dash.ink, 0.95)
        rim: pin.pinned || pin.containsMouse ? pin.dash.gold : pin.dash.tint(pin.dash.bone, 0.35)
    }
    Kirigami.Icon {
        anchors.centerIn: parent
        width: 11
        height: 11
        source: "window-pin"
        isMask: true
        color: pin.pinned ? pin.dash.ink : pin.dash.bone
        animated: false
    }
}
