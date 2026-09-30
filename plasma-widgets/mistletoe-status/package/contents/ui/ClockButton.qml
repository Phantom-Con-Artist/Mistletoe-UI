/*
    The status widget's resting form: the digital time beside a small
    faceted analog dial.
*/
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

MouseArea {
    id: button

    property date time: new Date()
    property bool open: false
    // Always-visible indicators: [{ icon, label, on }]
    property var indicators: []

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    readonly property bool horizontal: Plasmoid.formFactor !== PlasmaCore.Types.Vertical
    readonly property real side: horizontal ? height : width
    readonly property bool showTime: horizontal && Plasmoid.configuration.showDigitalTime

    hoverEnabled: true
    Layout.minimumWidth: horizontal ? row.implicitWidth : side
    Layout.preferredWidth: Layout.minimumWidth
    Layout.minimumHeight: side

    // Center of the dial relative to its screen's top-left corner (see the
    // launcher's CompactButton for why this uses the Screen attached type).
    function centerOnScreen() {
        const p = dial.mapToGlobal(dial.width / 2, dial.height / 2);
        return Qt.point(p.x - Screen.virtualX, p.y - Screen.virtualY);
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Math.round(button.side * 0.22)
        layoutDirection: Qt.RightToLeft   // dial hugs the corner

        Dial {
            id: dial
            width: Math.round(button.side * 0.86)
            height: width
            seconds: false
            detailed: false
            time: button.time
            face: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g,
                          Kirigami.Theme.backgroundColor.b, button.containsMouse || button.open ? 0.95 : 0.6)
            hand: Kirigami.Theme.textColor
            gold: Kirigami.Theme.focusColor
            rim: button.containsMouse || button.open
                ? Kirigami.Theme.focusColor
                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
        }

        Column {
            visible: button.showTime
            anchors.verticalCenter: parent.verticalCenter
            Text {
                anchors.right: parent.right
                text: Qt.formatTime(button.time, "hh:mm")
                color: Kirigami.Theme.textColor
                font.family: "Exo 2"
                font.pixelSize: Math.round(button.side * 0.4)
                font.weight: Font.Normal
            }
            Text {
                anchors.right: parent.right
                visible: button.side >= 36
                text: Qt.formatDate(button.time, "ddd d MMM").toUpperCase()
                color: Kirigami.Theme.focusColor
                font.family: "Exo 2"
                font.pixelSize: Math.round(button.side * 0.2)
                font.letterSpacing: 1
            }
        }

        Repeater {
            model: button.horizontal ? button.indicators.length : 0
            Row {
                id: chip
                required property int index
                readonly property var info: button.indicators[index] || ({})
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(button.side * 0.12)
                Kirigami.Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(button.side * 0.36)
                    height: width
                    source: chip.info.icon || ""
                    isMask: true
                    color: chip.info.on ? Kirigami.Theme.focusColor
                        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.4)
                    animated: false
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, button.side * 2.6)
                    text: chip.info.label || ""
                    elide: Text.ElideRight
                    color: chip.info.on ? Kirigami.Theme.textColor
                        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.45)
                    font.family: "Exo 2"
                    font.pixelSize: Math.round(button.side * 0.27)
                }
            }
        }
    }
}
