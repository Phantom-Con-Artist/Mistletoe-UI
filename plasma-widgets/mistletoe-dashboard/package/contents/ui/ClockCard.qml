/*
    Clock: no plate, drawn straight onto the wallpaper like a Rainmeter
    skin. The day in gold small caps, the time huge and thin, the date
    beneath, and a hairline that fills with gold as the minute passes.

    A 1px raised text style (no blur halo, no glass) keeps it legible if
    the wallpaper behind it is ever light. (A MultiEffect layer shadow was
    tried and renders nothing offscreen, so it is avoided.)
*/
import QtQuick

Item {
    id: card

    required property var dash

    readonly property color shade: Qt.rgba(0, 0, 0, 0.35)
    // Everything scales with the card: 112px time at the default 352px.
    readonly property real k: Math.max(0.45, Math.min(1.8, Math.min(width / 352, height / 224)))

    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: card.now = new Date()
    }

    Column {
        id: face
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
            text: Qt.formatDate(card.now, "dddd").toUpperCase()
            color: card.dash.gold
            style: Text.Raised
            styleColor: card.shade
            font.family: "Exo 2"
            font.pixelSize: Math.round(14 * card.k)
            font.letterSpacing: 7 * card.k
            font.weight: Font.Medium
        }
        Text {
            id: time
            text: Qt.formatTime(card.now, "hh:mm")
            color: card.dash.bone
            style: Text.Raised
            styleColor: card.shade
            font.family: "Exo 2"
            font.pixelSize: Math.round(112 * card.k)
            font.weight: Font.ExtraLight
            font.features: { "tnum": 1 }
        }
        // Minute hairline: bone track, gold fill for the seconds elapsed.
        Item {
            width: time.width - 8
            height: 1
            Rectangle {
                anchors.fill: parent
                color: card.dash.tint(card.dash.bone, 0.18)
            }
            Rectangle {
                width: parent.width * card.now.getSeconds() / 59
                height: 1
                color: card.dash.gold
                Behavior on width {
                    enabled: card.now.getSeconds() !== 0
                    NumberAnimation { duration: 900; easing.type: Easing.OutCubic }
                }
            }
        }
        Text {
            topPadding: Math.round(12 * card.k)
            text: Qt.formatDate(card.now, "d MMMM yyyy")
            color: card.dash.tint(card.dash.bone, 0.75)
            style: Text.Raised
            styleColor: card.shade
            font.family: "Exo 2"
            font.pixelSize: Math.round(17 * card.k)
            font.weight: Font.Light
            font.letterSpacing: 1
        }
    }

}
