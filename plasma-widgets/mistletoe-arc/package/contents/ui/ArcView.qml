/*
    The expanded arc: open apps on a shallow semicircle with the active app
    at its crest. Apps keep a stable order; when the active app changes the
    arc slides, so the new one glides to the center and the rest step aside.
    The order is a loop, so apps fill both sides of the crest evenly.

    When the app at the crest has several windows, a second, concentric arc
    rises above the first with a plate per window. It is a rotary dial: the
    window in use rests at the crest, straight above the pointer, and the
    wheel turns the others round to it, switching to each as it arrives. The
    windows form a loop, most used nearest the crest, so both sides of the
    arc are always filled alike.
*/
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

Item {
    id: arc

    // Inputs from main.qml
    property var tasks: null            // TaskManager.TasksModel
    property var order: []              // visible rows, display order
    property int activeRank: 0
    property string activeName: ""
    property var appRoles: ({})         // { IsActive, AppName, ... } role ids
    // Windows of the active app when it has several:
    // [{ child, id, title, active, minimized, slot }]; slot orders them
    // left to right, most used in the middle.
    property var windows: []
    // Whether the popup is showing; while hidden the dial snaps, not spins.
    property bool open: true

    signal activateRow(int row, bool isActive, bool isGroup, int childCount)
    signal newInstance(int row)
    signal stepRequested(int direction)
    signal windowActivated(int child, string id, bool clicked)

    readonly property real radius: 170
    readonly property real stepAngle: 11
    readonly property int reach: 3
    readonly property real iconCenter: 40
    readonly property real iconSide: 28
    readonly property real topPad: 10

    readonly property real halfSpan: radius * Math.sin((reach + 0.5) * stepAngle * Math.PI / 180)
    readonly property real appsWidth: Math.ceil(2 * halfSpan + iconSide + 36)
    readonly property real appsHeight: 96

    // ---- Window arc geometry -------------------------------------------------
    // Concentric with the app arc and evenly stepped, so the two read as one
    // fan. Plates are all one size; the step leaves a clear gap between them.
    readonly property bool hasWindows: windows.length > 1
    readonly property real winRadius: radius + 80
    readonly property real winStep: 30
    readonly property int maxReach: 2
    readonly property real plateWidth: 116
    readonly property real plateHeight: 24
    // A plate under the pointer opens up to show its whole title.
    readonly property real plateMax: 320
    readonly property real winHeight: hasWindows ? 76 : 0
    readonly property real winWidth: Math.ceil(2 * winRadius * Math.sin(maxReach * winStep * Math.PI / 180) + plateWidth + 16)
    // Shared center of both arcs, far below the popup.
    readonly property point hub: Qt.point(width / 2, winHeight + topPad + iconCenter / 2 + radius)

    width: hasWindows ? Math.max(appsWidth, winWidth) : appsWidth
    height: appsHeight + winHeight

    property string hoverName: ""

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
    readonly property color ink: Kirigami.Theme.backgroundColor
    readonly property color bone: Kirigami.Theme.textColor
    readonly property color gold: Kirigami.Theme.focusColor

    function spot(pos) {
        const a = pos * stepAngle * Math.PI / 180;
        return Qt.point(apps.width / 2 + radius * Math.sin(a),
                        topPad + iconCenter / 2 + radius * (1 - Math.cos(a)));
    }

    // ---- Window dial --------------------------------------------------------
    // The windows in loop order (indexes into `windows`), left to right.
    readonly property var ring: {
        const idx = [];
        for (let i = 0; i < windows.length; ++i) {
            idx.push(i);
        }
        return idx.sort((a, b) => windows[a].slot - windows[b].slot);
    }
    // Plates either side of the crest. The loop wraps, so with two or four
    // windows the far one shows at both ends: it is the next stop both ways.
    readonly property int winReach: Math.min(maxReach, Math.floor(ring.length / 2))
    // Position of the dial in loop steps (unwrapped, eased) and its target.
    property real winPos: 0
    property real winTarget: 0
    property string dialKey: ""
    property double lastStep: 0

    function wrapIndex(i) {
        const n = Math.max(1, ring.length);
        return ((Math.round(i) % n) + n) % n;
    }

    function spinTo(target, animate) {
        winTarget = target;
        if (animate) {
            winSpin.to = target;
            winSpin.restart();
        } else {
            winSpin.stop();
            winPos = target;
        }
    }

    NumberAnimation {
        id: winSpin
        target: arc; property: "winPos"
        duration: 340
        easing.type: Easing.OutBack
        easing.overshoot: 1.1
    }

    // Bring the window in use to the crest, the short way round. While the
    // wheel is mid-walk the dial is already ahead of the window manager, so
    // wait for it to settle.
    function sync() {
        const n = ring.length;
        if (n < 2) {
            dialKey = "";
            spinTo(0, false);
            return;
        }
        if (Date.now() - lastStep < 600) {
            resync.restart();
            return;
        }
        let active = -1;
        for (let r = 0; r < n; ++r) {
            if (windows[ring[r]].active) {
                active = r;
            }
        }
        // A different set or order of windows: place the dial, don't spin it.
        const key = ring.map(i => windows[i].id).join("|");
        const fresh = dialKey !== key;
        dialKey = key;
        if (active < 0) {
            return;
        }
        let d = (((active - wrapIndex(winTarget)) % n) + n) % n;
        if (d > n / 2) {
            d -= n;
        }
        if (d !== 0 || fresh) {
            spinTo(Math.round(winTarget) + d, open && !fresh);
        }
    }
    // On the ring, not the windows: it is derived from them, and has to be
    // current before the dial is read.
    onRingChanged: sync()
    onOpenChanged: if (open) spinTo(winTarget, false)
    Timer {
        id: resync
        interval: 650
        onTriggered: arc.sync()
    }

    // Turn the dial by whole steps and switch to the window that arrives.
    function turnWindows(steps, clicked) {
        if (ring.length < 2 || steps === 0) {
            return;
        }
        lastStep = Date.now();
        resync.restart();
        spinTo(Math.round(winTarget) + steps, true);
        const w = windows[ring[wrapIndex(winTarget)]];
        windowActivated(w.child, w.id, clicked);
    }

    // Wheel out on the window arc walks the windows; over the app arc below
    // it (or anywhere, with a single window) it steps apps.
    WheelHandler {
        id: wheelHandler
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            const direction = (event.angleDelta.y || event.angleDelta.x) > 0 ? -1 : 1;
            const at = wheelHandler.point.position;
            const out = Math.hypot(at.x - arc.hub.x, at.y - arc.hub.y);
            if (arc.hasWindows && out > (arc.radius + arc.winRadius) / 2) {
                arc.turnWindows(direction, false);
            } else {
                arc.stepRequested(direction);
            }
        }
    }

    // ---- Window plates ------------------------------------------------------
    Item {
        id: wins
        visible: arc.hasWindows
        width: arc.width
        height: arc.height

        // Hairline gold arc through the plates, only as long as they need.
        Canvas {
            id: winOrbit
            anchors.fill: parent
            opacity: 0.35
            readonly property real extent: arc.winReach
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = arc.gold;
                ctx.lineWidth = 1;
                ctx.beginPath();
                const span = (extent + 0.3) * arc.winStep * Math.PI / 180;
                ctx.arc(arc.hub.x, arc.hub.y, arc.winRadius, -Math.PI / 2 - span, -Math.PI / 2 + span);
                ctx.stroke();
            }
            onExtentChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }

        // The dial's finger stop: a fixed mark above the crest.
        Rectangle {
            width: 2
            height: 8
            x: Math.round(arc.hub.x - 1)
            y: Math.round(arc.hub.y - arc.winRadius - arc.plateHeight / 2 - 11)
            color: arc.gold
        }

        Repeater {
            // Two plates per window: the second is the same window seen the
            // other way round the loop, which is what fills the far side when
            // there are only two or four. By count, not by the array, so a
            // title or focus change updates a plate in place.
            model: arc.windows.length * 2
            delegate: Item {
                id: label

                required property int index
                readonly property int which: Math.floor(index / 2)
                readonly property var info: arc.windows[which] || ({})
                readonly property real n: Math.max(1, arc.ring.length)
                // Steps from the crest, the short way round (-n/2 .. n/2).
                readonly property real near: {
                    const d = arc.ring.indexOf(which) - arc.winPos + n / 2;
                    return ((d % n) + n) % n - n / 2;
                }
                readonly property real p: index % 2 === 0 ? near : (near < 0 ? near + n : near - n)
                readonly property real away: Math.abs(p)
                readonly property real angle: p * arc.winStep * Math.PI / 180
                readonly property bool hot: labelMouse.containsMouse
                readonly property bool isActive: info.active === true && away < 0.5

                width: hot ? Math.max(arc.plateWidth, Math.min(arc.plateMax, Math.ceil(title.implicitWidth) + 24)) : arc.plateWidth
                Behavior on width {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                height: arc.plateHeight
                x: Math.round(arc.hub.x + arc.winRadius * Math.sin(angle) - width / 2)
                y: Math.round(arc.hub.y - arc.winRadius * Math.cos(angle) - height / 2)
                visible: opacity > 0.01
                opacity: Math.max(0, Math.min(1, (arc.winReach + 0.5 - away) / 0.5))
                z: hot ? 20 : 10 - away

                // Matte plate so the title reads over any window behind it;
                // the window in use is filled, like the launcher's rail.
                Shard {
                    anchors.fill: parent
                    cut: 7
                    fill: label.isActive ? arc.gold : Qt.rgba(arc.ink.r, arc.ink.g, arc.ink.b, label.hot ? 0.97 : 0.9)
                    rim: label.isActive || label.hot ? arc.gold : Qt.rgba(arc.bone.r, arc.bone.g, arc.bone.b, 0.2)
                }

                Text {
                    id: title
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: label.info.title || ""
                    color: label.isActive ? arc.ink : arc.bone
                    opacity: label.info.minimized && !label.isActive ? 0.55 : 1
                    font.family: "Mistletoe Text"
                    font.pixelSize: 12
                    font.weight: label.isActive ? Font.Medium : Font.Normal
                }

                MouseArea {
                    id: labelMouse
                    anchors.fill: parent
                    enabled: label.opacity > 0.5
                    hoverEnabled: true
                    // Turn the dial the way this plate sits, so it comes
                    // straight up to the crest.
                    onClicked: {
                        if (Math.round(label.p) === 0) {
                            arc.windowActivated(label.info.child, label.info.id, true);
                        } else {
                            arc.turnWindows(Math.round(label.p), true);
                        }
                    }
                }
            }
        }
    }

    // ---- App arc ------------------------------------------------------------
    Item {
        id: apps
        width: arc.appsWidth
        height: arc.appsHeight
        anchors.horizontalCenter: parent.horizontalCenter
        y: arc.winHeight

        // No plate: instead a soft dark glow that fades to nothing at the
        // edges, so the icons and gold orbit read over bright wallpapers and
        // busy windows alike without a visible shape behind them.
        // Drawn as a circle, then squashed into an ellipse that fades to zero
        // exactly at the edges (so no rectangle ever shows).
        Shape {
            width: apps.width
            height: apps.width
            y: (apps.height - height) / 2
            transform: Scale {
                origin.x: apps.width / 2
                origin.y: apps.width / 2
                yScale: apps.height / apps.width
            }
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: apps.width / 2; centerY: apps.width / 2
                    focalX: centerX; focalY: centerY
                    centerRadius: apps.width / 2
                    GradientStop { position: 0; color: Qt.rgba(arc.ink.r, arc.ink.g, arc.ink.b, 0.85) }
                    GradientStop { position: 0.6; color: Qt.rgba(arc.ink.r, arc.ink.g, arc.ink.b, 0.55) }
                    GradientStop { position: 1; color: Qt.rgba(arc.ink.r, arc.ink.g, arc.ink.b, 0) }
                }
                startX: 0; startY: 0
                PathLine { x: apps.width; y: 0 }
                PathLine { x: apps.width; y: apps.width }
                PathLine { x: 0; y: apps.width }
                PathLine { x: 0; y: 0 }
            }
        }

        // Hairline gold orbit through the icons.
        Canvas {
            anchors.fill: parent
            opacity: arc.order.length > 1 ? 0.35 : 0
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = arc.gold;
                ctx.lineWidth = 1;
                ctx.beginPath();
                const span = (arc.reach + 0.4) * arc.stepAngle * Math.PI / 180;
                ctx.arc(width / 2, arc.topPad + arc.iconCenter / 2 + arc.radius, arc.radius,
                        -Math.PI / 2 - span, -Math.PI / 2 + span);
                ctx.stroke();
            }
            onWidthChanged: requestPaint()
        }

        Repeater {
            model: arc.tasks
            delegate: Item {
                id: task

                required property int index
                required property var model

                readonly property int rank: arc.order.indexOf(index)
                readonly property bool isActive: model.IsActive === true
                // Animated slot relative to the crest: 0 = center. The order
                // is a loop, so each app takes the shorter way round and the
                // arc fills evenly on both sides.
                readonly property real n: Math.max(1, arc.order.length)
                property real pos: rank < 0 ? 0 : ((rank - arc.activeRank + Math.floor(n / 2)) % n + n) % n - Math.floor(n / 2)
                Behavior on pos {
                    NumberAnimation { duration: 360; easing.type: Easing.OutCubic }
                }
                readonly property real away: Math.min(1, Math.abs(pos))
                readonly property real size: arc.iconCenter + (arc.iconSide - arc.iconCenter) * away
                readonly property point at: arc.spot(pos)

                visible: rank >= 0 && Math.abs(pos) <= arc.reach + 0.6
                width: size
                height: size
                x: at.x - width / 2
                y: at.y - height / 2
                z: 10 - Math.abs(pos)
                opacity: (model.IsMinimized ? 0.45 : 1) * Math.max(0, Math.min(1, (arc.reach + 0.6 - Math.abs(pos)) / 1.1))

                Kirigami.Icon {
                    anchors.fill: parent
                    source: task.model.decoration
                    active: mouse.containsMouse
                    animated: false
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onEntered: arc.hoverName = task.model.AppName || task.model.display || ""
                    onExited: arc.hoverName = ""
                    onClicked: (event) => {
                        if (event.button === Qt.MiddleButton) {
                            arc.newInstance(task.index);
                        } else {
                            arc.activateRow(task.index, task.isActive, task.model.IsGroupParent === true,
                                            task.model.ChildCount || 0);
                        }
                    }
                }
            }
        }

        // Name of the app at the crest (or the one under the pointer).
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: arc.topPad + arc.iconCenter + 4
            width: 110
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: (arc.hoverName || arc.activeName).toUpperCase()
            color: arc.gold
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.6)
            font.family: "Mistletoe Display"
            font.pixelSize: 10
            font.letterSpacing: 1.5
            font.weight: Font.Medium
        }
    }
}
