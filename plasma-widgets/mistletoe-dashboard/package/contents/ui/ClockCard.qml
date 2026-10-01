/*
    Clock: the desktop's hero. No plate, drawn straight onto the wallpaper
    like a Rainmeter skin: the time huge and thin, a hairline that fills with
    gold as the minute passes, and the day and date on one line beneath, big
    enough to read from across the room. It sits on the card's bottom-left
    corner, so the card's edges line up with the desktop margins.

    A 1px raised text style (no blur halo, no glass) keeps it legible if
    the wallpaper behind it is ever light. (A MultiEffect layer shadow was
    tried and renders nothing offscreen, so it is avoided.)
*/
import QtQuick
import QtQuick.Window
import org.kde.plasma.plasma5support as P5Support

Item {
    id: card

    required property var dash

    // Black or white, whichever reads against the wallpaper behind the
    // clock (measured by the bridge from the card's desktop position; again
    // every minute, in case the wallpaper changes). No glow, no plate.
    property bool onLight: false
    readonly property color face: onLight ? "#0b0c0e" : card.dash.bone
    readonly property color shade: onLight ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(0, 0, 0, 0.6)
    // The small line gets a full 1px outline, not just a raised edge: thin
    // letters need it on a busy or mid-bright wallpaper.
    readonly property color edge: onLight ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.7)

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
        if (!c) {
            return;
        }
        probe.connectSource("$HOME/.local/bin/mistletoe-menu backdrop " + [Math.round(c.x), Math.round(c.y),
            Math.round(c.width), Math.round(c.height), Screen.width, Screen.height].join(" ") + " #" + Date.now());
    }
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: card.measure()
    }
    // Everything scales with the card: at the default 704x288 the time is
    // set at 264px, which makes its digits about 185px tall.
    readonly property real k: Math.max(0.3, Math.min(2, Math.min(width / 704, height / 288)))

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
        anchors.bottom: parent.bottom
        spacing: 0

        // The digits, cropped to their ink: a text line this size carries
        // a lot of empty ascent and descent that would throw the layout off.
        Item {
            width: time.width
            height: Math.ceil(digits.tightBoundingRect.height)
            TextMetrics {
                id: digits
                font: time.font
                text: "0123456789"
            }
            Text {
                id: time
                y: Math.round(parent.height - baselineOffset)
                text: Qt.formatTime(card.now, "hh:mm")
                color: card.face
                style: Text.Raised
                styleColor: card.shade
                font.family: "Mistletoe Display"
                font.pixelSize: Math.round(264 * card.k)
                font.weight: Font.ExtraLight
                font.features: { "tnum": 1 }
            }
        }
        // Minute hairline: a quiet track, gold fill for the seconds elapsed.
        Item {
            width: time.width
            height: Math.round(22 * card.k) * 2 + 1
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: Qt.rgba(card.face.r, card.face.g, card.face.b, 0.22)
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * card.now.getSeconds() / 59
                height: Math.max(1, Math.round(2 * card.k))
                color: card.dash.gold
                Behavior on width {
                    enabled: card.now.getSeconds() !== 0
                    NumberAnimation { duration: 900; easing.type: Easing.OutCubic }
                }
            }
        }
        // Day and date on one line, in the face colour so both stay legible
        // on any wallpaper; only the gem between them is gold.
        Row {
            spacing: Math.round(16 * card.k)
            Text {
                id: day
                text: Qt.formatDate(card.now, "dddd").toUpperCase()
                color: card.face
                style: Text.Outline
                styleColor: card.edge
                font.family: "Mistletoe Display"
                font.pixelSize: Math.round(22 * card.k)
                font.letterSpacing: 6 * card.k
                font.weight: Font.Medium
                anchors.baseline: date.baseline
            }
            Gem {
                anchors.verticalCenter: date.verticalCenter
                width: Math.max(6, Math.round(9 * card.k))
                height: width
                fill: card.dash.gold
                rim: card.edge
            }
            Text {
                id: date
                text: Qt.formatDate(card.now, "d MMMM yyyy")
                color: card.face
                style: Text.Outline
                styleColor: card.edge
                font.family: "Mistletoe Accent"
                font.pixelSize: Math.round(34 * card.k)
                font.weight: Font.Light
                font.letterSpacing: 1
            }
        }
    }
}
