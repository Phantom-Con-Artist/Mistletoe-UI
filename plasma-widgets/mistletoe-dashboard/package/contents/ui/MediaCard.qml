/*
    Media card: optional and asleep until you open it.

    Closed, it is only a small prompt on the wallpaper (no plate) and the
    web engine isn't loaded at all.
    Opening loads MediaPlayer.qml (YouTube / YouTube Music); its close gem
    unloads it again, stopping playback and freeing the memory. Whether it
    is open is remembered across restarts.
*/
import QtQuick
import org.kde.kirigami as Kirigami
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

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

    // Asleep there is no plate (see Card.qml), only this prompt at the top
    // of the card's place: a gem and two lines, straight on the wallpaper,
    // black or white to suit what is behind it like the clock.
    readonly property bool quiet: !open
    property bool onLight: false
    readonly property color face: onLight ? "#0b0c0e" : card.dash.bone
    readonly property color shade: onLight ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(0, 0, 0, 0.6)

    P5Support.DataSource {
        id: probe
        engine: "executable"
        onNewData: (source, data) => {
            card.onLight = String(data.stdout || "").trim() === "light";
            disconnectSource(source);
        }
    }
    function measure() {
        const c = card.dash.container();
        if (!c || card.open) {
            return;
        }
        probe.connectSource("$HOME/.local/bin/mistletoe-menu backdrop " + [Math.round(c.x), Math.round(c.y),
            Math.round(c.width), 64, Screen.width, Screen.height].join(" ") + " #" + Date.now());
    }
    Timer {
        interval: 60000
        running: !card.open
        repeat: true
        triggeredOnStart: true
        onTriggered: card.measure()
    }

    MouseArea {
        id: prompt
        visible: !card.open
        x: 24
        y: 12
        width: promptRow.width + 12
        height: 40
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Plasmoid.configuration.mediaOpen = true

        Row {
            id: promptRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 34
                Gem {
                    anchors.fill: parent
                    scale: prompt.containsMouse ? 1.1 : 1
                    Behavior on scale {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    fill: prompt.containsMouse ? card.dash.gold : Qt.rgba(card.dash.ink.r, card.dash.ink.g, card.dash.ink.b, 0.6)
                    rim: card.dash.gold
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    source: "media-playback-start"
                    isMask: true
                    color: prompt.containsMouse ? card.dash.ink : card.dash.gold
                    animated: false
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: i18n("MEDIA")
                    color: card.face
                    style: Text.Raised
                    styleColor: card.shade
                    font.family: "Mistletoe Display"
                    font.pixelSize: 10
                    font.letterSpacing: 3
                    font.weight: Font.Medium
                }
                Text {
                    text: i18n("Open YouTube and Music")
                    color: Qt.rgba(card.face.r, card.face.g, card.face.b, 0.8)
                    style: Text.Raised
                    styleColor: card.shade
                    font.family: "Mistletoe Text"
                    font.pixelSize: 13
                }
            }
        }
    }
}
