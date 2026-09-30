/*
    Media card: optional and asleep until you open it.

    Closed, it is only a prompt and the web engine isn't loaded at all.
    Opening loads MediaPlayer.qml (YouTube / YouTube Music); its close gem
    unloads it again, stopping playback and freeing the memory. Whether it
    is open is remembered across restarts.
*/
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: card

    required property var dash
    readonly property bool open: Plasmoid.configuration.mediaOpen

    // Load the player only while open (only then is QtWebEngine loaded);
    // clearing the source destroys it.
    function sync() {
        if (open) {
            player.setSource("MediaPlayer.qml", { dash: card.dash });
        } else {
            player.source = "";
        }
    }
    onOpenChanged: sync()
    Component.onCompleted: sync()

    Loader {
        id: player
        anchors.fill: parent
        Connections {
            target: player.item
            function onCloseRequested() {
                Plasmoid.configuration.mediaOpen = false;
            }
        }
    }

    // Asleep: a quiet prompt.
    MouseArea {
        id: prompt
        anchors.fill: parent
        visible: !card.open
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Plasmoid.configuration.mediaOpen = true

        Column {
            anchors.centerIn: parent
            spacing: 14
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 46
                height: 46
                Gem {
                    anchors.fill: parent
                    scale: prompt.containsMouse ? 1.08 : 1
                    fill: prompt.containsMouse ? card.dash.gold : "transparent"
                    rim: card.dash.gold
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    source: "media-playback-start"
                    isMask: true
                    color: prompt.containsMouse ? card.dash.ink : card.dash.gold
                    animated: false
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: i18n("MEDIA")
                color: card.dash.gold
                font.family: "Exo 2"
                font.pixelSize: 10
                font.letterSpacing: 3
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: i18n("Open YouTube and Music")
                color: card.dash.tint(card.dash.bone, 0.7)
                font.family: "Exo 2"
                font.pixelSize: 13
            }
        }
    }
}
