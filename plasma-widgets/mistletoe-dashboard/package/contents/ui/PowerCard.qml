/*
    Power card: gems for lock, sleep, restart, shut down and log out, with
    the hovered action named in the middle. Restart, shut down and log out
    go through Plasma's confirmation.
*/
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.sessions as Sessions

RowLayout {
    id: card

    required property var dash

    spacing: 0

    Sessions.SessionManagement {
        id: session
    }
    readonly property var powers: [
        { id: "lock", icon: "system-lock-screen-symbolic", label: i18n("Lock") },
        { id: "suspend", icon: "system-suspend-symbolic", label: i18n("Sleep") },
        { id: "reboot", icon: "system-reboot-symbolic", label: i18n("Restart") },
        { id: "shutdown", icon: "system-shutdown-symbolic", label: i18n("Shut down") },
        { id: "logout", icon: "system-log-out-symbolic", label: i18n("Log out") }
    ].filter(p => p.id !== "suspend" || session.canSuspend)

    function run(id) {
        switch (id) {
        case "lock": session.lock(); break;
        case "suspend": session.suspend(); break;
        case "reboot": session.requestReboot(); break;
        case "shutdown": session.requestShutdown(); break;
        case "logout": session.requestLogout(); break;
        }
    }

    Repeater {
        model: card.powers
        delegate: Item {
            id: cell
            required property var modelData
            Layout.fillWidth: true
            Layout.fillHeight: true
            readonly property bool hot: mouse.containsMouse
            readonly property bool danger: modelData.id === "shutdown"

            Gem {
                anchors.centerIn: parent
                width: 34
                height: 34
                scale: cell.hot ? 1.12 : 1
                Behavior on scale {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                fill: cell.hot && cell.danger ? card.dash.gold : "transparent"
                rim: cell.hot ? card.dash.gold : card.dash.tint(card.dash.bone, 0.3)
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: cell.modelData.icon
                    isMask: true
                    color: cell.hot && cell.danger ? card.dash.ink : cell.hot ? card.dash.gold : card.dash.bone
                    animated: false
                }
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: card.run(cell.modelData.id)
            }
            // Name under the gem while hovered.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1
                opacity: cell.hot ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 120 }
                }
                text: cell.modelData.label.toUpperCase()
                color: card.dash.gold
                font.family: "Mistletoe Display"
                font.pixelSize: 8
                font.letterSpacing: 1.5
            }
        }
    }
}
