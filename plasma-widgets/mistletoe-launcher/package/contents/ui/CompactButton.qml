/*
    The launcher's resting form: a shard plate holding the distro logo,
    tinted bone so it sits in the palette, gold while hovered or open.
*/
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

MouseArea {
    id: button

    property bool open: false

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    hoverEnabled: true
    Layout.minimumWidth: height
    Layout.preferredWidth: height
    Layout.minimumHeight: Kirigami.Units.iconSizes.small

    readonly property real side: Math.min(width, height)

    // Center of the button relative to its screen's top-left corner. Uses the
    // Screen attached property, which stays valid on Wayland where client
    // windows don't know their global position.
    function centerOnScreen() {
        const p = mapToGlobal(width / 2, height / 2);
        return Qt.point(p.x - Screen.virtualX, p.y - Screen.virtualY);
    }

    Shard {
        anchors.centerIn: parent
        width: button.side
        height: button.side
        fill: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g,
                      Kirigami.Theme.backgroundColor.b, button.containsMouse || button.open ? 0.9 : 0.55)
        rim: button.containsMouse || button.open
            ? Kirigami.Theme.focusColor
            : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
        Behavior on fill {
            ColorAnimation { duration: 140 }
        }
    }

    Kirigami.Icon {
        id: logo
        anchors.centerIn: parent
        width: Math.round(button.side * 0.86)
        height: width
        source: Plasmoid.configuration.icon || Plasmoid.icon
        visible: false
    }
    MultiEffect {
        anchors.fill: logo
        source: logo
        colorization: 1
        colorizationColor: button.containsMouse || button.open ? Kirigami.Theme.focusColor : Kirigami.Theme.textColor
        Behavior on colorizationColor {
            ColorAnimation { duration: 140 }
        }
    }
}
