/*
    A list row: optional rank, icon, name, and on the right an optional
    value with a detail line. `level` (0..1) draws a thin gold bar under
    the name, used for CPU share.
*/
import QtQuick
import org.kde.kirigami as Kirigami

MouseArea {
    id: row

    property int rank: 0
    property var iconSource
    property string title
    property string value
    property string detail
    property real level: -1
    property color ink
    property color bone
    property color gold

    function tint(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    implicitHeight: 38
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Shard {
        anchors.fill: parent
        anchors.leftMargin: -8
        anchors.rightMargin: -8
        cut: 7
        opacity: row.containsMouse ? 1 : 0
        fill: row.tint(row.bone, 0.06)
        rim: row.tint(row.gold, 0.5)
        Behavior on opacity {
            NumberAnimation { duration: 140 }
        }
    }

    Text {
        id: rankText
        visible: row.rank > 0
        width: visible ? 22 : 0
        anchors.verticalCenter: parent.verticalCenter
        text: (row.rank < 10 ? "0" : "") + row.rank
        color: row.gold
        font.family: "Exo 2"
        font.pixelSize: 10
        font.letterSpacing: 1
    }
    Kirigami.Icon {
        id: icon
        anchors.left: rankText.right
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        source: row.iconSource
        animated: false
    }
    Text {
        id: valueText
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: row.detail ? 3 : 0
        anchors.verticalCenter: row.detail ? undefined : parent.verticalCenter
        text: row.value
        color: row.bone
        font.family: "Exo 2"
        font.pixelSize: 13
    }
    Text {
        anchors.right: parent.right
        anchors.top: valueText.bottom
        visible: row.detail.length > 0
        text: row.detail
        color: row.tint(row.bone, 0.5)
        font.family: "Exo 2"
        font.pixelSize: 10
    }
    Text {
        id: titleText
        anchors.left: icon.right
        anchors.leftMargin: 12
        anchors.right: valueText.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: row.level >= 0 ? -3 : 0
        text: row.title
        elide: Text.ElideRight
        color: row.containsMouse ? row.bone : row.tint(row.bone, 0.88)
        font.family: "Exo 2"
        font.pixelSize: 13
    }
    // CPU bar: slate track, gold fill.
    Rectangle {
        visible: row.level >= 0
        anchors.left: titleText.left
        anchors.right: titleText.right
        anchors.top: titleText.bottom
        anchors.topMargin: 4
        height: 2
        color: row.tint(row.bone, 0.1)
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, row.level))
            height: parent.height
            color: row.gold
            Behavior on width {
                NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
            }
        }
    }
}
