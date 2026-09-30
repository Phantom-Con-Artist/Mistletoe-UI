/*
    Mistletoe lock screen entry point. kscreenlocker looks for these
    properties and signals on the root item; the UI lives in LockScreenUi.
*/
import QtQuick

Item {
    id: root
    property bool debug: false
    property string notification
    signal clearPassword()
    signal notificationRepeated()

    // kscreenlocker sets this while the lock screen is on screen.
    property bool viewVisible: false

    implicitWidth: 800
    implicitHeight: 600

    LockScreenUi {
        anchors.fill: parent
    }
}
