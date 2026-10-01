/*
    Mistletoe status fan: blooms out of a screen corner. A faceted analog
    dial sits nearest the corner, the status cells ride one gold orbit
    around it, and the power gems sit on an outer rail. A caption along the
    edge names the cell at the dial's stop (or under the pointer).

    Like the launcher's rail, the orbit is a rotary dial: the wheel turns
    the cells round one stop at a time, each leaving the arc at one end and
    returning at the other, so the layout stays evenly spread.

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
    // [{ id, icon, label, value, on, hint, wheel }]; read by index so a
    // changing value updates the cell in place instead of rebuilding it.
    property var tiles: []
    // [{ id, icon, label }] power actions on the outer rail.
    property var powers: []
    property point origin: Qt.point(width - 40, height - 40)

    signal tileClicked(string id)
    signal tileAltClicked(string id)
    signal tileWheel(string id, int direction)
    signal powerClicked(string id)
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
    readonly property real thetaMin: 6
    readonly property real thetaMax: 84
    readonly property real dialSize: 188 * unit
    readonly property real dialRadius: 165 * unit          // distance of the dial's center
    // Cells are upright squares, so on the diagonal two neighbours need
    // cell * sqrt(2) between centers to clear each other's corners. The
    // orbit is wide enough for six cells with a gap to spare.
    readonly property real orbit: 372 * unit               // status cells
    readonly property real railRadius: orbit + 96 * unit   // power gems

    function point(r, theta) {
        const a = theta * Math.PI / 180;
        return Qt.point(origin.x + sx * r * Math.cos(a), origin.y + sy * r * Math.sin(a));
    }

    function screenAngle(theta) {
        const a = theta * Math.PI / 180;
        return Math.atan2(sy * Math.sin(a), sx * Math.cos(a)) * 180 / Math.PI;
    }

    // ---- Rotary dial -----------------------------------------------------
    // `current` is the cell resting at the stop: the end of the arc along the
    // screen edge, right beside the caption that describes it. ringPos is the
    // (unwrapped) eased position of the dial.
    property int current: 0
    property real ringPos: 0
    property real ringTarget: 0
    property int hovered: -1
    property string powerHint: ""

    // Slot of cell i along the arc, wrapped: -0.5 .. tiles.length - 0.5.
    function ringSlot(i) {
        const n = Math.max(1, tiles.length);
        const s = i - ringPos + n - 1 + 0.5;
        return ((s % n) + n) % n - 0.5;
    }

    function dialBy(d) {
        const n = tiles.length;
        if (n < 2) {
            return;
        }
        current = (((current + d) % n) + n) % n;
        ringTarget += d;
        ringSpin.to = ringTarget;
        ringSpin.restart();
    }

    NumberAnimation {
        id: ringSpin
        target: fan; property: "ringPos"
        duration: 340
        easing.type: Easing.OutBack
        easing.overshoot: 1.1
    }

    // Clearance between the origin (a strip button) and anything laid
    // along the screen edge, so it sits above the strip.
    readonly property real edgeLift: 34

    // ---- Motion ---------------------------------------------------------
    readonly property real itemDuration: 280
    readonly property real span: 40 + 5 * 36 + itemDuration
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
        duration: 260; easing.type: Easing.OutCubic
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
                duration: 180; easing.type: Easing.InCubic
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
        hovered = -1;
        powerHint = "";
        ringSpin.stop();
        current = 0;
        ringTarget = 0;
        ringPos = 0;
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

    Keys.onPressed: (event) => {
        switch (event.key) {
        case Qt.Key_Escape:
            fan.close();
            break;
        case Qt.Key_Right:
        case Qt.Key_Down:
            fan.dialBy(1);
            break;
        case Qt.Key_Left:
        case Qt.Key_Up:
            fan.dialBy(-1);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (fan.tiles[fan.current]) {
                fan.tileClicked(fan.tiles[fan.current].id);
            }
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ---- Backdrop -------------------------------------------------------
    MouseArea {
        anchors.fill: parent
        onClicked: fan.close()
        onWheel: (wheel) => fan.dialBy((wheel.angleDelta.y || wheel.angleDelta.x) < 0 ? 1 : -1)
    }

    Shape {
        anchors.fill: parent
        opacity: fan.veil
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: fan.origin.x; centerY: fan.origin.y
                focalX: fan.origin.x; focalY: fan.origin.y
                centerRadius: fan.railRadius + 240 * fan.unit
                GradientStop { position: 0; color: fan.tint(fan.ink, 0.97) }
                GradientStop { position: 0.6; color: fan.tint(fan.ink, 0.95) }
                GradientStop { position: 1; color: fan.tint(fan.ink, 0.90) }
            }
            startX: 0; startY: 0
            PathLine { x: fan.width; y: 0 }
            PathLine { x: fan.width; y: fan.height }
            PathLine { x: 0; y: fan.height }
            PathLine { x: 0; y: 0 }
        }
    }

    // Gold orbits through the dial, the status cells and the power rail.
    Repeater {
        model: [fan.dialRadius, fan.orbit, fan.railRadius]
        Shape {
            id: orbitLine
            required property int index
            required property real modelData
            readonly property real reveal: fan.outCubic(fan.veil * 1.7 - index * 0.15)
            anchors.fill: parent
            opacity: index === 2 ? 0.5 : 0.2
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: fan.gold
                strokeWidth: 1
                fillColor: "transparent"
                PathAngleArc {
                    centerX: fan.origin.x; centerY: fan.origin.y
                    radiusX: orbitLine.modelData
                    radiusY: orbitLine.modelData
                    startAngle: fan.screenAngle(0)
                    sweepAngle: 90 * fan.sx * fan.sy * orbitLine.reveal
                }
            }
        }
    }

    // ---- Dial -----------------------------------------------------------
    // Slides out and fades in; it is never scaled or spun, which keeps the
    // faceted face from being redrawn on every frame of the bloom.
    Dial {
        id: dial
        readonly property real t: fan.local(0, 300)
        readonly property real e: fan.outCubic(t)
        readonly property point at: fan.point(fan.dialRadius * (0.6 + 0.4 * e), 45)
        width: fan.dialSize
        height: width
        x: Math.round(at.x - width / 2)
        y: Math.round(at.y - height / 2)
        opacity: Math.min(1, t * 2)
        time: fan.now
        wind: fan.outCubic(fan.local(40, 420))
        face: fan.tint(fan.ink, 0.96)
        hand: fan.bone
        gold: fan.gold
    }

    // ---- Status cells ---------------------------------------------------
    // The dial's finger stop: a fixed gold mark where the current cell rests.
    Rectangle {
        readonly property real theta: fan.thetaMin + 0.5 * (fan.thetaMax - fan.thetaMin) / Math.max(1, fan.tiles.length)
        readonly property point at: fan.point(fan.orbit + 46 * fan.unit, theta)
        visible: fan.tiles.length > 1
        width: Math.round(12 * fan.unit)
        height: 2
        x: at.x - width / 2
        y: at.y - height / 2
        rotation: fan.screenAngle(theta)
        color: fan.gold
        opacity: fan.veil
    }

    Repeater {
        model: fan.tiles.length
        StatusTile {
            id: tileItem
            required property int index
            readonly property var info: fan.tiles[index] || ({})
            // Where the dial has carried this cell; it fades through the
            // seam where it leaves one end of the arc and returns at the other.
            readonly property real along: fan.ringSlot(index)
            readonly property real seam: Math.max(0, Math.min(1, 2 * Math.min(along + 0.5, fan.tiles.length - 0.5 - along)))
            readonly property real theta: fan.thetaMax - (along + 0.5) * (fan.thetaMax - fan.thetaMin) / Math.max(1, fan.tiles.length)
            // Cells arrive in turn, starting from the stop.
            readonly property real t: fan.local(40 + Math.max(0, fan.tiles.length - 1 - along) * 36)
            readonly property real e: fan.outBack(t)
            readonly property point at: fan.point(fan.orbit * (0.55 + 0.45 * e), theta - (1 - Math.min(1, e)) * 10)

            visible: t > 0 && seam > 0.01
            enabled: seam > 0.5
            x: at.x - width / 2
            y: at.y - height / 2
            opacity: Math.min(1, t * 2.2) * seam
            scale: (0.6 + 0.4 * e) * (0.6 + 0.4 * seam)

            unit: fan.unit
            ink: fan.ink
            bone: fan.bone
            gold: fan.gold
            icon: info.icon || ""
            on: !!info.on
            wheelable: !!info.wheel
            current: fan.current === index

            onEntered: fan.hovered = index
            onExited: if (fan.hovered === index) fan.hovered = -1
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

    // ---- Power rail -----------------------------------------------------
    // Small gems on the outer arc, centered on the diagonal; the caption
    // names the one under the pointer. Shut down turns gold, the rest light
    // their rim.
    Repeater {
        model: fan.powers.length
        Item {
            id: powerItem
            required property int index
            readonly property var info: fan.powers[index] || ({})
            readonly property real theta: 45 - (index - (fan.powers.length - 1) / 2) * 11
            readonly property real t: fan.outCubic(fan.veil * 1.6 - 0.3 - index * 0.04)
            readonly property point at: fan.point(fan.railRadius, theta)
            readonly property bool hot: powerMouse.containsMouse

            width: Math.round(32 * fan.unit)
            height: width
            x: at.x - width / 2
            y: at.y - height / 2
            opacity: t
            scale: (0.4 + 0.6 * t) * (hot ? 1.15 : 1)
            Behavior on scale {
                enabled: fan.veil >= 1
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            Gem {
                anchors.fill: parent
                fill: powerItem.hot && powerItem.info.id === "shutdown" ? fan.gold : fan.tint(fan.ink, 0.92)
                rim: powerItem.hot ? fan.gold : fan.tint(fan.bone, 0.35)
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: Math.round(parent.width * 0.46)
                height: width
                source: powerItem.info.icon || ""
                isMask: true
                color: powerItem.hot && powerItem.info.id === "shutdown" ? fan.ink : fan.bone
                animated: false
            }
            MouseArea {
                id: powerMouse
                anchors.fill: parent
                hoverEnabled: true
                onEntered: fan.powerHint = powerItem.info.label || ""
                onExited: fan.powerHint = ""
                onClicked: fan.powerClicked(powerItem.info.id)
            }
        }
    }

    // ---- Caption ----------------------------------------------------------
    // Names the cell under the pointer, else the one at the stop; the date
    // and time sit quietly underneath until a cell has a hint to show.
    Column {
        id: caption
        readonly property var shown: fan.tiles[fan.hovered >= 0 ? fan.hovered : fan.current] || ({})
        readonly property real gap: 44 * fan.unit
        x: fan.sx < 0 ? fan.origin.x - fan.railRadius - gap - width : fan.origin.x + fan.railRadius + gap
        y: fan.sy < 0 ? fan.origin.y - fan.edgeLift - height : fan.origin.y + fan.edgeLift
        width: Math.min(420 * fan.unit, fan.width / 2)
        opacity: fan.veil
        spacing: 2

        Text {
            width: parent.width
            horizontalAlignment: fan.sx < 0 ? Text.AlignRight : Text.AlignLeft
            text: (fan.powerHint ? "Power" : caption.shown.label || "").toUpperCase()
            color: fan.gold
            font.family: "Mistletoe Display"
            font.pixelSize: Math.round(10 * fan.unit)
            font.letterSpacing: 3
            font.weight: Font.Medium
        }
        Text {
            width: parent.width
            horizontalAlignment: fan.sx < 0 ? Text.AlignRight : Text.AlignLeft
            elide: fan.sx < 0 ? Text.ElideLeft : Text.ElideRight
            text: fan.powerHint || caption.shown.value || ""
            color: fan.bone
            font.family: "Mistletoe Accent"
            font.pixelSize: Math.round(26 * fan.unit)
            font.weight: Font.Light
        }
        Text {
            width: parent.width
            horizontalAlignment: fan.sx < 0 ? Text.AlignRight : Text.AlignLeft
            elide: fan.sx < 0 ? Text.ElideLeft : Text.ElideRight
            text: (fan.hovered >= 0 && !fan.powerHint && caption.shown.hint)
                || (Qt.formatDate(fan.now, "dddd d MMMM") + "   ·   " + Qt.formatTime(fan.now, "hh:mm:ss"))
            color: fan.tint(fan.bone, 0.6)
            font.family: "Mistletoe Text"
            font.pixelSize: Math.round(12 * fan.unit)
        }
    }

}
