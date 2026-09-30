/*
    Mistletoe radial fan: items bloom out of a screen corner onto concentric
    gold arcs, categories sit on an outer rail, and a caption along the edge
    names whatever has focus.

    This is a pure view. main.qml supplies the models and reacts to the
    signals, which keeps the fan testable with plain ListModels.
*/
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

Item {
    id: fan

    // ---- Inputs ---------------------------------------------------------
    property var model: null            // items on the arcs
    property var rail: []               // [{ name, icon }] category gems
    property int railIndex: 0
    property string title: ""           // name of what the arcs show
    property point origin: Qt.point(40, height - 40)
    readonly property alias query: queryInput.text
    readonly property alias keyTarget: queryInput

    signal itemActivated(int index, bool hasChildren)
    signal itemAltActivated(int index, string favoriteId)
    signal railActivated(int index)
    signal backRequested()
    signal escapePressed()
    signal closed()

    // ---- Palette --------------------------------------------------------
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
    readonly property color ink: Kirigami.Theme.backgroundColor
    readonly property color bone: Kirigami.Theme.textColor
    readonly property color gold: Kirigami.Theme.focusColor
    readonly property string face: "Exo 2"

    function tint(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // ---- Geometry -------------------------------------------------------
    // theta runs from the edge the corner sits on (0) to the perpendicular
    // edge (90); sx/sy point the fan into the screen from whichever corner
    // the origin is nearest, so the same fan works from any corner.
    readonly property int sx: origin.x < width / 2 ? 1 : -1
    readonly property int sy: origin.y > height / 2 ? -1 : 1
    readonly property real thetaMin: 6
    readonly property real thetaMax: 84
    readonly property real unit: Math.max(0.6, Math.min(1, (Math.min(width, height) - 120) / 860))
    readonly property int rings: 5
    readonly property real r0: 132 * unit
    readonly property real step: 76 * unit
    readonly property real cell: 54 * unit
    readonly property real railRadius: ringRadius(rings - 1) + 80 * unit
    readonly property var capacities: {
        const caps = [];
        for (let k = 0; k < rings; ++k) {
            const arc = ringRadius(k) * (thetaMax - thetaMin) * Math.PI / 180;
            caps.push(Math.max(1, Math.floor(arc / (68 * unit))));
        }
        return caps;
    }
    readonly property int pageSize: capacities.reduce((a, b) => a + b, 0)
    readonly property int count: model && model.count !== undefined ? model.count : 0
    readonly property int pages: Math.max(1, Math.ceil(count / pageSize))
    readonly property int shown: Math.max(0, Math.min(pageSize, count - page * pageSize))
    property int page: 0

    function ringRadius(k) {
        return r0 + k * step;
    }

    function point(r, theta) {
        const a = theta * Math.PI / 180;
        return Qt.point(origin.x + sx * r * Math.cos(a), origin.y + sy * r * Math.sin(a));
    }

    // Degrees clockwise from 3 o'clock, as PathAngleArc wants them.
    function screenAngle(theta) {
        const a = theta * Math.PI / 180;
        return Math.atan2(sy * Math.sin(a), sx * Math.cos(a)) * 180 / Math.PI;
    }

    // Where the i-th item of the current page sits, and when it arrives.
    // Rings fill from the inside out; a partly filled ring spreads evenly.
    function slot(i) {
        if (i < 0 || i >= shown) {
            return null;
        }
        let k = 0;
        let start = 0;
        while (i - start >= capacities[k]) {
            start += capacities[k];
            ++k;
        }
        const n = Math.min(capacities[k], shown - start);
        const j = i - start;
        return {
            radius: ringRadius(k),
            theta: thetaMax - (j + 0.5) * (thetaMax - thetaMin) / n,
            delay: k * 55 + j * 18
        };
    }

    // Clearance between the origin (a strip button) and anything laid
    // along the screen edge, so it sits above the strip.
    readonly property real edgeLift: 34

    // ---- Motion ---------------------------------------------------------
    // One clock drives the whole cascade: each item maps `bloom` through its
    // own delay window, so running the clock backwards folds the outer rings
    // away first.
    readonly property real itemDuration: 380
    readonly property real span: itemDuration + (rings - 1) * 55 + 10 * 18
    property real bloom: 0      // items
    property real veil: 0       // backdrop, arcs, rail, caption
    property bool closing: false

    function local(delay) {
        return Math.max(0, Math.min(1, (bloom * span - delay) / itemDuration));
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
        page = 0;
        focusIndex(-1);
        queryInput.text = "";
        bloom = 0;
        veil = 0;
        veilIn.restart();
        bloomIn.restart();
        queryInput.forceActiveFocus();
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

    // New content re-blooms from the corner; the frame stays put.
    onModelChanged: {
        page = 0;
        focusIndex(-1);
        if (!closing && veil > 0) {
            bloom = 0;
            bloomIn.restart();
        }
    }

    onPageChanged: {
        if (!closing && veil > 0) {
            bloom = 0.35;
            bloomIn.restart();
        }
    }

    // ---- Focus ----------------------------------------------------------
    property int current: -1
    property string hoverTitle: ""
    property string hoverSub: ""

    function focusIndex(i) {
        current = i;
        const c = i >= 0 ? items.itemAt(i) : null;
        hoverTitle = c ? c.model.display || "" : "";
        hoverSub = c ? c.model.description || "" : "";
    }

    function move(delta) {
        if (count === 0) {
            return;
        }
        const next = current < 0 ? page * pageSize : Math.max(0, Math.min(count - 1, current + delta));
        page = Math.floor(next / pageSize);
        focusIndex(next);
    }

    function activate(i) {
        const c = items.itemAt(i);
        if (c) {
            itemActivated(i, !!c.model.hasChildren);
        }
    }

    // ---- Backdrop -------------------------------------------------------
    MouseArea {
        anchors.fill: parent
        onClicked: fan.close()
        onWheel: (wheel) => {
            const d = wheel.angleDelta.y < 0 ? 1 : -1;
            fan.page = Math.max(0, Math.min(fan.pages - 1, fan.page + d));
        }
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

    // Gold orbit lines: one per ring plus the rail, swept open in turn.
    Repeater {
        model: fan.rings + 1
        Shape {
            required property int index
            readonly property bool isRail: index === fan.rings
            readonly property real reveal: fan.outCubic(fan.veil * 1.7 - index * 0.12)
            anchors.fill: parent
            opacity: isRail ? 0.5 : 0.16
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: fan.gold
                strokeWidth: 1
                fillColor: "transparent"
                PathAngleArc {
                    centerX: fan.origin.x; centerY: fan.origin.y
                    radiusX: isRail ? fan.railRadius : fan.ringRadius(index)
                    radiusY: radiusX
                    startAngle: fan.screenAngle(0)
                    sweepAngle: 90 * fan.sx * fan.sy * reveal
                }
            }
        }
    }

    // ---- Items ----------------------------------------------------------
    Repeater {
        id: items
        model: fan.model
        delegate: Item {
            id: cellItem
            required property int index
            required property var model

            readonly property var slot: fan.slot(index - fan.page * fan.pageSize)
            readonly property real t: slot ? fan.local(slot.delay) : 0
            readonly property real e: fan.outBack(t)
            readonly property bool hot: fan.current === index
            // Items unfurl along a short spiral rather than a straight ray.
            readonly property point at: slot
                ? fan.point(slot.radius * (0.3 + 0.7 * e), slot.theta - (1 - Math.min(1, e)) * 14)
                : fan.origin

            visible: slot !== null && t > 0
            width: fan.cell
            height: fan.cell
            x: at.x - width / 2
            y: at.y - height / 2
            opacity: Math.min(1, t * 2.2)
            scale: 0.5 + 0.5 * e

            Item {
                anchors.fill: parent
                scale: cellItem.hot ? 1.12 : 1
                Behavior on scale {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                Shard {
                    anchors.fill: parent
                    fill: fan.tint(fan.ink, cellItem.hot ? 0.95 : 0.78)
                    rim: cellItem.hot ? fan.gold : fan.tint(fan.bone, 0.16)
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Math.round(parent.width * 0.66)
                    height: width
                    source: cellItem.model.decoration
                    animated: false
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onEntered: fan.focusIndex(cellItem.index)
                onExited: if (fan.current === cellItem.index) fan.focusIndex(-1)
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        fan.itemAltActivated(cellItem.index, cellItem.model.favoriteId || "");
                    } else {
                        fan.activate(cellItem.index);
                    }
                }
            }
        }
    }

    // ---- Category rail --------------------------------------------------
    Repeater {
        model: fan.rail
        delegate: Item {
            id: railItem
            required property int index
            required property var modelData

            readonly property real theta: fan.thetaMax - (index + 0.5) * (fan.thetaMax - fan.thetaMin) / Math.max(1, fan.rail.length)
            readonly property real t: fan.outCubic(fan.veil * 1.6 - 0.35 - index * 0.03)
            readonly property point at: fan.point(fan.railRadius, theta)
            readonly property bool active: fan.railIndex === index && !fan.query

            width: Math.round(32 * fan.unit)
            height: width
            x: at.x - width / 2
            y: at.y - height / 2
            opacity: t
            scale: (0.4 + 0.6 * t) * (railMouse.containsMouse ? 1.15 : 1)
            Behavior on scale {
                enabled: fan.veil >= 1
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            Gem {
                anchors.fill: parent
                fill: railItem.active ? fan.gold : fan.tint(fan.ink, 0.92)
                rim: railItem.active || railMouse.containsMouse ? fan.gold : fan.tint(fan.bone, 0.35)
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: Math.round(parent.width * 0.46)
                height: width
                source: railItem.modelData.icon
                isMask: true
                color: railItem.active ? fan.ink : fan.bone
                animated: false
            }

            MouseArea {
                id: railMouse
                anchors.fill: parent
                hoverEnabled: true
                onEntered: {
                    fan.hoverTitle = railItem.modelData.name;
                    fan.hoverSub = "";
                }
                onExited: fan.focusIndex(fan.current)
                onClicked: fan.railActivated(railItem.index)
            }
        }
    }


    // ---- Caption --------------------------------------------------------
    Column {
        readonly property real gap: 44 * fan.unit
        x: fan.sx > 0 ? fan.origin.x + fan.railRadius + gap : fan.origin.x - fan.railRadius - gap - width
        y: fan.sy < 0 ? fan.origin.y - fan.edgeLift - height : fan.origin.y + fan.edgeLift
        width: Math.min(420 * fan.unit, fan.width / 2)
        opacity: fan.veil
        spacing: 2

        Text {
            width: parent.width
            horizontalAlignment: fan.sx > 0 ? Text.AlignLeft : Text.AlignRight
            text: (fan.query ? "Search" : fan.title).toUpperCase()
                + (fan.pages > 1 && !fan.query ? "   ·   " + (fan.page + 1) + " / " + fan.pages : "")
            color: fan.gold
            font.family: fan.face
            font.pixelSize: Math.round(10 * fan.unit)
            font.letterSpacing: 3
            font.weight: Font.Medium
        }
        Text {
            width: parent.width
            horizontalAlignment: fan.sx > 0 ? Text.AlignLeft : Text.AlignRight
            elide: Text.ElideRight
            text: fan.query && !fan.hoverTitle
                ? fan.query + (fan.count === 0 ? "  —  nothing found" : "")
                : fan.hoverTitle || fan.title
            color: fan.bone
            font.family: fan.face
            font.pixelSize: Math.round(26 * fan.unit)
            font.weight: Font.Light
        }
        Text {
            width: parent.width
            horizontalAlignment: fan.sx > 0 ? Text.AlignLeft : Text.AlignRight
            elide: Text.ElideRight
            text: fan.hoverSub
            visible: text.length > 0
            color: fan.tint(fan.bone, 0.6)
            font.family: fan.face
            font.pixelSize: Math.round(12 * fan.unit)
        }
    }

    // ---- Keyboard -------------------------------------------------------
    // Receives keys from the overlay window; typing searches.
    TextInput {
        id: queryInput
        width: 1
        height: 1
        opacity: 0
        Keys.onPressed: (event) => {
            switch (event.key) {
            case Qt.Key_Right:
            case Qt.Key_Down:
                fan.move(1);
                break;
            case Qt.Key_Left:
            case Qt.Key_Up:
                fan.move(-1);
                break;
            case Qt.Key_PageDown:
                fan.page = Math.min(fan.pages - 1, fan.page + 1);
                break;
            case Qt.Key_PageUp:
                fan.page = Math.max(0, fan.page - 1);
                break;
            case Qt.Key_Tab:
                fan.railActivated((fan.railIndex + 1) % Math.max(1, fan.rail.length));
                break;
            case Qt.Key_Backtab:
                fan.railActivated((fan.railIndex + fan.rail.length - 1) % Math.max(1, fan.rail.length));
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                fan.activate(fan.current >= 0 ? fan.current : fan.page * fan.pageSize);
                break;
            case Qt.Key_Escape:
                fan.escapePressed();
                break;
            case Qt.Key_Backspace:
                if (text.length > 0) {
                    return;
                }
                fan.backRequested();
                break;
            default:
                return;
            }
            event.accepted = true;
        }
        onTextChanged: fan.focusIndex(-1)
    }
}
