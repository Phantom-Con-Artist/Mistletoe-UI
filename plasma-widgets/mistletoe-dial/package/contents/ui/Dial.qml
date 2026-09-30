/*
    Mistletoe dial: a semicircle centred on the left screen edge.

    The inner ring holds categories (an app's menus, or System Settings
    groups); the outer ring holds the entries of the chosen category. Both
    rings scroll like a rotary dial: the focused item sits at the centre
    (pointing straight right) and the rest fan out above and below, fading
    toward the ends. Opening cascades the entries out from the edge.

    Pure view: main.qml supplies the lists and reacts to the signals.
*/
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

Item {
    id: dial

    // ---- Inputs ---------------------------------------------------------
    property var categories: []     // [{ name, icon }]
    property var entries: []        // [{ label, icon, detail, shortcut, hasChildren, enabled, checked }]
    property int categoryIndex: 0
    property int entryIndex: 0
    // Entry under the pointer (-1: none). Hover only highlights and fills
    // the caption; it never turns the dial. Only the wheel and keys do.
    property int hoverIndex: -1
    property string mode: ""        // "App", "Places" or "Settings"
    property var modes: []          // [{ name, enabled }] in Tab order
    property string context: ""     // e.g. "KWrite", "Places", "System Settings"
    property string trail: ""       // submenu path, e.g. "File › Open Recent"
    property string status: ""      // loading / empty messages
    readonly property alias query: queryInput.text
    readonly property alias keyTarget: queryInput

    signal categoryChosen(int index)
    signal entryActivated(int index)
    signal backRequested()
    signal modeToggled()
    signal modeChosen(string name)
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
    readonly property point origin: Qt.point(0, height / 2)
    readonly property real unit: Math.max(0.7, Math.min(1.1, height / 1000))
    readonly property real innerRadius: 190 * unit
    readonly property real outerRadius: 420 * unit
    readonly property real innerStep: 17       // degrees between categories
    readonly property real outerStep: 9.5      // degrees between entries
    readonly property real reach: 84           // visible half-angle

    // Smoothly animated scroll positions (float indices).
    property real innerPos: categoryIndex
    property real outerPos: entryIndex
    Behavior on innerPos {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }
    Behavior on outerPos {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    function point(r, deg) {
        const a = deg * Math.PI / 180;
        return Qt.point(origin.x + r * Math.cos(a), origin.y + r * Math.sin(a));
    }
    // 1 at the centre, easing to 0 at the ends of the visible arc.
    function fade(deg) {
        const t = Math.min(1, Math.abs(deg) / reach);
        return 1 - t * t * t;
    }

    // ---- Motion ---------------------------------------------------------
    property real bloom: 0
    property real veil: 0
    property bool closing: false

    NumberAnimation {
        id: bloomIn
        target: dial; property: "bloom"; to: 1
        duration: 620
    }
    NumberAnimation {
        id: veilIn
        target: dial; property: "veil"; to: 1
        duration: 380; easing.type: Easing.OutCubic
    }
    ParallelAnimation {
        id: foldAway
        NumberAnimation { target: dial; property: "bloom"; to: 0; duration: 260; easing.type: Easing.InCubic }
        NumberAnimation { target: dial; property: "veil"; to: 0; duration: 320; easing.type: Easing.InCubic }
        onFinished: {
            dial.closing = false;
            dial.closed();
        }
    }

    // Items nearer the focus arrive first; each rides out from the edge.
    function arrival(distance) {
        const t = Math.max(0, Math.min(1, (bloom * 620 - 60 - Math.abs(distance) * 28) / 320));
        return 1 - Math.pow(1 - t, 3);
    }

    function open() {
        foldAway.stop();
        closing = false;
        bloom = 0;
        veil = 0;
        queryInput.text = "";
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

    // Keep the focus inside the list whenever the list changes.
    onEntriesChanged: {
        entryIndex = Math.max(0, Math.min(entryIndex, entries.length - 1));
        hoverIndex = -1;
    }

    function stepEntry(d) {
        if (entries.length > 0) {
            entryIndex = Math.max(0, Math.min(entries.length - 1, entryIndex + d));
        }
    }
    function stepCategory(d) {
        if (categories.length > 0 && !query) {
            categoryChosen(Math.max(0, Math.min(categories.length - 1, categoryIndex + d)));
        }
    }

    // ---- Backdrop -------------------------------------------------------
    MouseArea {
        anchors.fill: parent
        onClicked: dial.close()
        // Wheel near the edge turns the categories, further out the entries.
        onWheel: (wheel) => {
            const d = wheel.angleDelta.y > 0 ? -1 : 1;
            const r = Math.hypot(wheel.x - dial.origin.x, wheel.y - dial.origin.y);
            if (r < (dial.innerRadius + dial.outerRadius) / 2) {
                dial.stepCategory(d);
            } else {
                dial.stepEntry(d);
            }
        }
    }

    Shape {
        anchors.fill: parent
        opacity: dial.veil
        visible: dial.veil > 0.01
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: dial.origin.x; centerY: dial.origin.y
                focalX: dial.origin.x; focalY: dial.origin.y
                centerRadius: dial.outerRadius + 520 * dial.unit
                GradientStop { position: 0; color: dial.tint(dial.ink, 0.985) }
                GradientStop { position: 1; color: dial.tint(dial.ink, 0.95) }
            }
            startX: 0; startY: 0
            PathLine { x: dial.width; y: 0 }
            PathLine { x: dial.width; y: dial.height }
            PathLine { x: 0; y: dial.height }
            PathLine { x: 0; y: 0 }
        }
    }

    // Gold rings through both tracks.
    Repeater {
        model: [dial.innerRadius, dial.outerRadius]
        Shape {
            id: ring
            required property int index
            required property real modelData
            readonly property real reveal: Math.max(0, Math.min(1, dial.veil * 1.6 - index * 0.2))
            anchors.fill: parent
            visible: reveal > 0.02
            opacity: index === 0 ? 0.3 : 0.22
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: dial.gold
                strokeWidth: 1
                fillColor: "transparent"
                PathAngleArc {
                    centerX: dial.origin.x; centerY: dial.origin.y
                    radiusX: ring.modelData; radiusY: ring.modelData
                    startAngle: -90 * ring.reveal
                    sweepAngle: 180 * ring.reveal
                }
            }
        }
    }

    // Focus pointer: a short gold tick on each ring at the centre line.
    Rectangle {
        x: dial.innerRadius - 10
        y: dial.origin.y - 0.5
        width: dial.outerRadius - dial.innerRadius + 20
        height: 1
        opacity: 0.25 * dial.veil
        color: dial.gold
    }

    // ---- Inner ring: categories ------------------------------------------
    Repeater {
        model: dial.categories.length
        Item {
            id: cat
            required property int index
            readonly property var info: dial.categories[index] || ({})
            readonly property real deg: (index - dial.innerPos) * dial.innerStep
            readonly property real e: dial.arrival(index - dial.categoryIndex)
            readonly property point at: dial.point(dial.innerRadius * (0.4 + 0.6 * e), deg)
            readonly property bool current: index === dial.categoryIndex && !dial.query
            readonly property real shown: dial.fade(deg) * e * (dial.query ? 0.35 : 1)

            visible: Math.abs(deg) <= dial.reach && shown > 0.01
            x: at.x - 13
            y: at.y - 13
            width: 26
            height: 26
            opacity: shown

            Gem {
                anchors.fill: parent
                scale: cat.current ? 1.15 : 1
                fill: cat.current ? dial.gold : dial.tint(dial.ink, 0.95)
                rim: cat.current || catMouse.containsMouse ? dial.gold : dial.tint(dial.bone, 0.35)
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: 13
                height: 13
                source: cat.info.icon || "folder"
                animated: false
            }
            Text {
                anchors.left: parent.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, dial.outerRadius - dial.innerRadius - 44)
                elide: Text.ElideRight
                text: cat.info.name || ""
                color: cat.current ? dial.gold : dial.tint(dial.bone, 0.75)
                font.family: dial.face
                font.pixelSize: cat.current ? 14 : 12
                font.letterSpacing: cat.current ? 1 : 0.5
                font.weight: cat.current ? Font.Medium : Font.Normal
            }
            MouseArea {
                id: catMouse
                anchors.fill: parent
                anchors.margins: -6
                anchors.rightMargin: -120
                hoverEnabled: true
                onClicked: dial.categoryChosen(cat.index)
            }
        }
    }

    // ---- Outer ring: entries ----------------------------------------------
    Repeater {
        model: dial.entries.length
        Item {
            id: entry
            required property int index
            readonly property var info: dial.entries[index] || ({})
            readonly property real deg: (index - dial.outerPos) * dial.outerStep
            readonly property real e: dial.arrival(index - dial.entryIndex)
            readonly property point at: dial.point(dial.outerRadius * (0.55 + 0.45 * e), deg - (1 - e) * 12)
            readonly property bool current: index === dial.entryIndex
            readonly property bool hot: entryMouse.containsMouse
            readonly property real shown: dial.fade(deg) * e

            visible: Math.abs(deg) <= dial.reach && shown > 0.01
            x: at.x - 9
            y: at.y - 16
            width: 18
            height: 32
            opacity: shown * (info.enabled === false ? 0.45 : 1)

            // Marker on the ring.
            Gem {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                fill: entry.current ? dial.gold : entry.info.checked ? dial.tint(dial.gold, 0.4) : dial.tint(dial.ink, 0.95)
                rim: entry.current || entry.hot ? dial.gold : dial.tint(dial.bone, 0.3)
            }

            // Label plate: only the focused entry gets a shard behind it.
            Item {
                id: label
                anchors.left: parent.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: row.implicitWidth + 28
                height: 34

                Shard {
                    anchors.fill: parent
                    cut: 9
                    visible: entry.current || entry.hot
                    fill: dial.tint(dial.ink, 0.96)
                    rim: entry.current ? dial.gold : dial.tint(dial.gold, 0.45)
                }
                Row {
                    id: row
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Kirigami.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        visible: !!entry.info.icon
                        source: entry.info.icon || ""
                        animated: false
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 300 * dial.unit)
                        elide: Text.ElideRight
                        text: entry.info.label || ""
                        color: entry.current ? dial.bone : dial.tint(dial.bone, 0.82)
                        font.family: dial.face
                        font.pixelSize: entry.current ? 15 : 13
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!entry.info.hasChildren
                        text: "›"
                        color: dial.gold
                        font.family: dial.face
                        font.pixelSize: 16
                    }
                }
            }

            MouseArea {
                id: entryMouse
                anchors.fill: parent
                anchors.rightMargin: -(label.width + 12)
                anchors.margins: -2
                hoverEnabled: true
                onContainsMouseChanged: {
                    if (containsMouse) {
                        dial.hoverIndex = entry.index;
                    } else if (dial.hoverIndex === entry.index) {
                        dial.hoverIndex = -1;
                    }
                }
                onClicked: dial.entryActivated(entry.index)
            }
        }
    }

    // ---- Caption ------------------------------------------------------------
    Column {
        readonly property var focused: dial.entries[dial.hoverIndex >= 0 ? dial.hoverIndex : dial.entryIndex] || ({})
        x: dial.outerRadius + 400 * dial.unit
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(560 * dial.unit, dial.width - x - 48)
        opacity: dial.veil
        spacing: 6

        // Mode switch: APP · PLACES · SETTINGS (Tab cycles).
        Row {
            spacing: 18
            Repeater {
                model: dial.modes
                Text {
                    required property var modelData
                    readonly property bool current: modelData.name === dial.mode
                    text: modelData.name.toUpperCase()
                    color: current ? dial.gold : dial.tint(dial.bone, modelData.enabled ? 0.4 : 0.15)
                    font.family: dial.face
                    font.pixelSize: 11
                    font.letterSpacing: 3
                    font.weight: current ? Font.DemiBold : Font.Normal
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        enabled: modelData.enabled && !parent.current
                        onClicked: dial.modeChosen(modelData.name)
                    }
                }
            }
        }
        Rectangle {
            width: parent.width
            height: 1
            color: dial.tint(dial.bone, 0.12)
        }
        Text {
            width: parent.width
            topPadding: 8
            elide: Text.ElideRight
            text: (dial.query ? i18n("Search") : dial.context + (dial.trail ? "  ›  " + dial.trail : "")).toUpperCase()
            color: dial.gold
            font.family: dial.face
            font.pixelSize: 11
            font.letterSpacing: 2.5
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: dial.status || parent.focused.label || ""
            color: dial.bone
            font.family: dial.face
            font.pixelSize: 34
            font.weight: Font.Light
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            visible: text.length > 0 && !dial.status
            text: parent.focused.detail || ""
            color: dial.tint(dial.bone, 0.65)
            font.family: dial.face
            font.pixelSize: 14
        }
        Text {
            visible: !!parent.focused.shortcut && !dial.status
            text: parent.focused.shortcut || ""
            color: dial.tint(dial.gold, 0.8)
            font.family: dial.face
            font.pixelSize: 12
            font.letterSpacing: 1
        }
        // Search line: what you've typed, or the hint.
        Text {
            topPadding: 18
            width: parent.width
            elide: Text.ElideRight
            text: dial.query
                ? "⌕  " + dial.query + (dial.entries.length === 0 ? "   —  " + i18n("nothing found") : "   ·   " + i18np("%1 match", "%1 matches", dial.entries.length))
                : i18n("Type to search  ·  ↑↓ scroll  ·  ←→ category  ·  Enter open  ·  Tab mode  ·  Esc close")
            color: dial.query ? dial.bone : dial.tint(dial.bone, 0.4)
            font.family: dial.face
            font.pixelSize: dial.query ? 15 : 11
            font.letterSpacing: dial.query ? 0.5 : 1
        }
    }

    // ---- Keyboard ---------------------------------------------------------
    TextInput {
        id: queryInput
        width: 1
        height: 1
        opacity: 0
        focus: true
        onTextChanged: dial.entryIndex = 0
        Keys.onPressed: (event) => {
            switch (event.key) {
            case Qt.Key_Up: dial.stepEntry(-1); break;
            case Qt.Key_Down: dial.stepEntry(1); break;
            case Qt.Key_PageUp: dial.stepEntry(-6); break;
            case Qt.Key_PageDown: dial.stepEntry(6); break;
            case Qt.Key_Left:
                if (dial.trail && !dial.query) {
                    dial.backRequested();
                } else {
                    dial.stepCategory(-1);
                }
                break;
            case Qt.Key_Right: dial.stepCategory(1); break;
            case Qt.Key_Return:
            case Qt.Key_Enter: dial.entryActivated(dial.entryIndex); break;
            case Qt.Key_Tab:
            case Qt.Key_Backtab:
                dial.modeToggled();
                break;
            case Qt.Key_Backspace:
                if (text.length > 0 || !dial.trail) {
                    return; // let the input delete
                }
                dial.backRequested();
                break;
            case Qt.Key_Escape:
                if (text.length > 0) {
                    text = "";
                } else if (dial.trail) {
                    dial.backRequested();
                } else {
                    dial.close();
                }
                break;
            default:
                return;
            }
            event.accepted = true;
        }
    }
}
