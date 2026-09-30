/*
    The expanded arc: open apps on a shallow semicircle with the active app
    at its crest. Apps keep a stable order; when the active app changes the
    arc slides, so the new one glides to the center and the rest step aside.
*/
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: arc

    // Inputs from main.qml
    property var tasks: null            // TaskManager.TasksModel
    property var order: []              // visible rows, display order
    property int activeRank: 0
    property string activeName: ""
    property var appRoles: ({})         // { IsActive, AppName, ... } role ids

    signal activateRow(int row, bool isActive, bool isGroup, int childCount)
    signal newInstance(int row)
    signal stepRequested(int direction)

    readonly property real radius: 170
    readonly property real stepAngle: 11
    readonly property int reach: 3
    readonly property real iconCenter: 34
    readonly property real iconSide: 24
    readonly property real topPad: 10

    readonly property real halfSpan: radius * Math.sin((reach + 0.5) * stepAngle * Math.PI / 180)
    width: Math.ceil(2 * halfSpan + iconSide + 36)
    height: 86

    property string hoverName: ""

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
    readonly property color ink: Kirigami.Theme.backgroundColor
    readonly property color bone: Kirigami.Theme.textColor
    readonly property color gold: Kirigami.Theme.focusColor

    function spot(pos) {
        const a = pos * stepAngle * Math.PI / 180;
        return Qt.point(width / 2 + radius * Math.sin(a),
                        topPad + iconCenter / 2 + radius * (1 - Math.cos(a)));
    }

    // Matte plate: the arc floats over app content, so it needs its own
    // ground to stay readable (no blur by design).
    Shard {
        anchors.fill: parent
        cut: 12
        fill: Qt.rgba(arc.ink.r, arc.ink.g, arc.ink.b, 0.96)
        rim: Qt.rgba(arc.gold.r, arc.gold.g, arc.gold.b, 0.5)
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => arc.stepRequested(event.angleDelta.y > 0 ? -1 : 1)
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
            // Animated slot relative to the crest: 0 = center.
            property real pos: rank - arc.activeRank
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
        font.family: "Exo 2"
        font.pixelSize: 9
        font.letterSpacing: 1.5
        font.weight: Font.Medium
    }
}
