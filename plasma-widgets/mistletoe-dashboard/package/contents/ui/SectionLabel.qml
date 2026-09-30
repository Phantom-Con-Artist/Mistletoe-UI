/*
    A section heading: gold small caps, a hairline running to the right
    edge, and an optional note at the end (e.g. the hovered app's name).
*/
import QtQuick

Item {
    id: label

    property string text
    property string note
    property color gold
    property color bone

    implicitHeight: 14

    Text {
        id: title
        anchors.verticalCenter: parent.verticalCenter
        text: label.text.toUpperCase()
        color: label.gold
        font.family: "Exo 2"
        font.pixelSize: 10
        font.letterSpacing: 2.5
        font.weight: Font.Medium
    }
    Rectangle {
        anchors.left: title.right
        anchors.leftMargin: 10
        anchors.right: noteText.left
        anchors.rightMargin: noteText.text ? 10 : 0
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: Qt.rgba(label.bone.r, label.bone.g, label.bone.b, 0.12)
    }
    Text {
        id: noteText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: text ? Math.min(implicitWidth, label.width * 0.5) : 0
        elide: Text.ElideRight
        text: label.note
        color: Qt.rgba(label.bone.r, label.bone.g, label.bone.b, 0.7)
        font.family: "Exo 2"
        font.pixelSize: 11
    }
}
