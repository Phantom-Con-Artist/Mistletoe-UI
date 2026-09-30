/*
    Mistletoe status fan: blooms out of a screen corner. A large faceted
    analog dial winds in first, then status tiles spiral out onto two gold
    orbits, and a caption along the edge carries the date.

    Pure view, like the launcher's RadialFan: main.qml supplies the tile
    data and reacts to the signals.
*/
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

Item {
    id: fan

    // ---- Inputs ---------------------------------------------------------
    property date now: new Date()
    // [{ id, icon, label, value, on, hint }]; read by index so a changing
    // value updates the tile in place instead of rebuilding it.
    property var tiles: []
    property point origin: Qt.point(width - 40, height - 40)

    signal tileClicked(string id)
    signal tileAltClicked(string id)
    signal tileWheel(string id, int direction)
    signal closed()

    // ---- Palette --------------------------------------------------------
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
    readonly property color ink: Kirigami.Theme.backgroundColor
    readonly property color bone: Kirigami.Theme.textColor
    readonly property color gold: Kirigami.Theme.focusColor

    function tint(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // ---- Geometry (same conventions as the launcher fan) -----------------
    readonly property int sx: origin.x < width / 2 ? 1 : -1
    readonly property int sy: origin.y > height / 2 ? -1 : 1
    readonly property real unit: Math.max(0.6, Math.min(1, (Math.min(width, height) - 120) / 860))
    readonly property real dialSize: 188 * unit
    readonly property real dialRadius: 165 * unit          // distance of the dial's center
    readonly property var orbits: [330 * unit, 480 * unit]
    // Tile angles per orbit, staggered between the orbits so wide tiles
    // near the edges never share a row (checked against 150x48 tiles).
    readonly property var orbitAngles: [[78, 50, 22], [70, 40, 8]]

    function point(r, theta) {
        const a = theta * Math.PI / 180;
        return Qt.point(origin.x + sx * r * Math.cos(a), origin.y + sy * r * Math.sin(a));
    }

    function screenAngle(theta) {
        const a = theta * Math.PI / 180;
        return Math.atan2(sy * Math.sin(a), sx * Math.cos(a)) * 180 / Math.PI;
    }

    function slot(i) {
        let k = 0;
        let start = 0;
        while (k < orbitAngles.length && i - start >= orbitAngles[k].length) {
            start += orbitAngles[k].length;
            ++k;
        }
        if (k >= orbitAngles.length) {
            return null;
        }
        const j = i - start;
        return {
            radius: orbits[k],
            theta: orbitAngles[k][j],
            delay: 180 + k * 90 + j * 60
        };
    }

    // ---- Motion ---------------------------------------------------------
    readonly property real itemDuration: 420
    readonly property real span: 180 + 90 + 2 * 60 + itemDuration
    property real bloom: 0
    property real veil: 0
    property bool closing: false

    function local(delay, duration) {
        return Math.max(0, Math.min(1, (bloom * span - delay) / (duration || itemDuration)));
    }

    function outBack(t) {
        const c1 = 1.2;
        const c3 = c1 + 1;
        return t <= 0 ? 0 : 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
    }

    function outCubic(t) {
        return 1 - Math.pow(1 - Math.max(0, Math.min(1, t)), 3);
    }

    NumberAnimation {
        id: bloomIn
        target: fan; property: "bloom"; to: 1
        duration: fan.span
    }
    NumberAnimation {
        id: veilIn
        target: fan; property: "veil"; to: 1
        duration: 420; easing.type: Easing.OutCubic
    }
    ParallelAnimation {
        id: foldAway
        NumberAnimation {
            target: fan; property: "bloom"; to: 0
            duration: fan.span * 0.45
        }
        SequentialAnimation {
            PauseAnimation { duration: fan.span * 0.2 }
            NumberAnimation {
                target: fan; property: "veil"; to: 0
                duration: 240; easing.type: Easing.InCubic
            }
        }
        onFinished: {
            fan.closing = false;
            fan.closed();
        }
    }

    function open() {
        foldAway.stop();
        closing = false;
        hint = "";
        bloom = 0;
        veil = 0;
        veilIn.restart();
        bloomIn.restart();
        forceActiveFocus();
    }

    function close() {
        if (closing) {
            return;
        }
        closing = true;
        bloomIn.stop();
        veilIn.stop();
        foldAway.restart();
    }

    property string hint: ""

    Keys.onEscapePressed: close()

    // ---- Backdrop -------------------------------------------------------
    MouseArea {
        anchors.fill: parent
        onClicked: fan.close()
    }

    Shape {
        anchors.fill: parent
        opacity: fan.veil
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: fan.origin.x; centerY: fan.origin.y
                focalX: fan.origin.x; focalY: fan.origin.y
                centerRadius: fan.orbits[1] + 240 * fan.unit
                GradientStop { position: 0; color: fan.tint(fan.ink, 0.94) }
                GradientStop { position: 0.5; color: fan.tint(fan.ink, 0.84) }
                GradientStop { position: 0.75; color: fan.tint(fan.ink, 0.45) }
                GradientStop { position: 1; color: fan.tint(fan.ink, 0) }
            }
            startX: 0; startY: 0
            PathLine { x: fan.width; y: 0 }
            PathLine { x: fan.width; y: fan.height }
            PathLine { x: 0; y: fan.height }
            PathLine { x: 0; y: 0 }
        }
    }

    // Gold orbits through the dial and the two tile rings.
    Repeater {
        model: [fan.dialRadius, fan.orbits[0], fan.orbits[1]]
        Shape {
            id: orbit
            required property int index
            required property real modelData
            readonly property real reveal: fan.outCubic(fan.veil * 1.7 - index * 0.15)
            anchors.fill: parent
            opacity: index === 0 ? 0.28 : 0.2
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: fan.gold
                strokeWidth: 1
                fillColor: "transparent"
                PathAngleArc {
                    centerX: fan.origin.x; centerY: fan.origin.y
                    radiusX: orbit.modelData
                    radiusY: orbit.modelData
                    startAngle: fan.screenAngle(0)
                    sweepAngle: 90 * fan.sx * fan.sy * orbit.reveal
                }
            }
        }
    }

    // ---- Dial -----------------------------------------------------------
    Dial {
        id: dial
        readonly property real t: fan.local(0, 560)
        readonly property real e: fan.outBack(t)
        readonly property point at: fan.point(fan.dialRadius * (0.35 + 0.65 * e), 45)
        width: fan.dialSize
        height: width
        x: at.x - width / 2
        y: at.y - height / 2
        opacity: Math.min(1, t * 2)
        scale: 0.55 + 0.45 * e
        rotation: (1 - Math.min(1, e)) * -30 * fan.sx * fan.sy
        time: fan.now
        wind: fan.outCubic(fan.local(80, 700))
        face: fan.tint(fan.ink, 0.96)
        hand: fan.bone
        gold: fan.gold
    }

    // ---- Tiles ----------------------------------------------------------
    Repeater {
        model: fan.tiles.length
        StatusTile {
            id: tileItem
            required property int index
            readonly property var info: fan.tiles[index] || ({})
            readonly property var slot: fan.slot(index)
            readonly property real t: slot ? fan.local(slot.delay) : 0
            readonly property real e: fan.outBack(t)
            readonly property point at: slot
                ? fan.point(slot.radius * (0.35 + 0.65 * e), slot.theta - (1 - Math.min(1, e)) * 14)
                : fan.origin

            visible: slot !== null && t > 0
            x: at.x - width / 2
            y: at.y - height / 2
            opacity: Math.min(1, t * 2.2)
            scale: 0.5 + 0.5 * e

            unit: fan.unit
            ink: fan.ink
            bone: fan.bone
            gold: fan.gold
            icon: info.icon || ""
            label: info.label || ""
            value: info.value || ""
            on: !!info.on

            onEntered: fan.hint = info.hint || ""
            onExited: fan.hint = ""
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    fan.tileAltClicked(info.id);
                } else {
                    fan.tileClicked(info.id);
                }
            }
            onWheelStep: (direction) => fan.tileWheel(info.id, direction)
        }
    }

    // ---- Core -----------------------------------------------------------
    Gem {
        width: Math.round(22 * fan.unit)
        height: width
        x: fan.origin.x - width / 2
        y: fan.origin.y - height / 2
        rotation: 90 * fan.outCubic(fan.veil)
        opacity: fan.veil
        fill: fan.gold
        rim: fan.gold
        MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            onClicked: fan.close()
        }
    }

    // ---- Caption: the date ----------------------------------------------
    Column {
        // Clear the outermost tile (not just its orbit) so the date never
        // runs under it: the lowest tile sits at theta 8 on the outer orbit.
        readonly property real reach: fan.orbits[1] * Math.cos(8 * Math.PI / 180) + 75 * fan.unit + 36 * fan.unit
        x: fan.sx < 0 ? fan.origin.x - reach - width : fan.origin.x + reach
        y: fan.sy < 0 ? fan.origin.y + 10 - height : fan.origin.y - 10
        width: Math.min(360 * fan.unit, fan.width / 3)
        opacity: fan.veil
        spacing: 2

        Text {
            width: parent.width
            horizontalAlignment: fan.sx < 0 ? Text.AlignRight : Text.AlignLeft
            text: Qt.formatDate(fan.now, "dddd").toUpperCase()
            color: fan.gold
            font.family: "Exo 2"
            font.pixelSize: Math.round(10 * fan.unit)
            font.letterSpacing: 3
            font.weight: Font.Medium
        }
        Text {
            width: parent.width
            horizontalAlignment: fan.sx < 0 ? Text.AlignRight : Text.AlignLeft
            text: Qt.formatDate(fan.now, "d MMMM")
            color: fan.bone
            font.family: "Exo 2"
            font.pixelSize: Math.round(28 * fan.unit)
            font.weight: Font.Light
        }
        Text {
            width: parent.width
            horizontalAlignment: fan.sx < 0 ? Text.AlignRight : Text.AlignLeft
            text: fan.hint || (Qt.formatDate(fan.now, "yyyy") + "   ·   " + Qt.formatTime(fan.now, "hh:mm:ss"))
            color: fan.tint(fan.bone, 0.6)
            font.family: "Exo 2"
            font.pixelSize: Math.round(12 * fan.unit)
        }
    }
}
