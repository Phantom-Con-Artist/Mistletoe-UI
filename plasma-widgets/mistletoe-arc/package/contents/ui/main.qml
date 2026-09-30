/*
    Mistletoe Arc: open apps on a shallow semicircle, with the active app
    always at its crest. Apps keep a stable order; switching windows slides
    the arc so the newly active app glides into the center and the others
    step aside left or right.

    Click: activate (or minimize if already active). Wheel: step to the
    neighbouring app. Middle-click: open a new window of that app.
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    // ---- Geometry -------------------------------------------------------
    readonly property real radius: 170
    readonly property real stepAngle: 11        // degrees between neighbours
    readonly property int reach: 3              // apps shown on each side
    readonly property real iconCenter: 34
    readonly property real iconSide: 24
    readonly property real topPad: 3

    // Rows that are real app windows, in display order. Our own overlay
    // windows (plasmashell) and launcher placeholders are left out.
    property var order: []
    property int activeRow: -1
    readonly property int activeRank: Math.max(0, order.indexOf(activeRow))
    property string hoverName: ""

    preferredRepresentation: fullRepresentation
    compactRepresentation: null
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    function rebuildOrder() {
        const rows = [];
        for (let i = 0; i < tasks.count; ++i) {
            const idx = tasks.makeModelIndex(i);
            const appId = String(tasks.data(idx, TaskManager.AbstractTasksModel.AppId) || "");
            if (tasks.data(idx, TaskManager.AbstractTasksModel.IsLauncher) || /plasmashell/.test(appId)) {
                continue;
            }
            rows.push(i);
        }
        order = rows;
    }

    function activate(row, isActive, isGroup, childCount) {
        if (isGroup) {
            // Cycle through the app's windows, starting after the active one.
            let current = -1;
            for (let c = 0; c < childCount; ++c) {
                if (tasks.data(tasks.makeModelIndex(row, c), TaskManager.AbstractTasksModel.IsActive)) {
                    current = c;
                }
            }
            tasks.requestActivate(tasks.makeModelIndex(row, (current + 1) % childCount));
        } else if (isActive) {
            tasks.requestToggleMinimized(tasks.makeModelIndex(row));
        } else {
            tasks.requestActivate(tasks.makeModelIndex(row));
        }
    }

    function step(direction) {
        const rank = Math.max(0, Math.min(order.length - 1, activeRank + direction));
        if (order.length > 0 && rank !== activeRank) {
            tasks.requestActivate(tasks.makeModelIndex(order[rank]));
        }
    }

    TaskManager.VirtualDesktopInfo {
        id: desktops
    }
    TaskManager.ActivityInfo {
        id: activities
    }
    TaskManager.TasksModel {
        id: tasks
        sortMode: TaskManager.TasksModel.SortManual
        groupMode: TaskManager.TasksModel.GroupApplications
        filterByVirtualDesktop: true
        virtualDesktop: desktops.currentDesktop
        filterByActivity: true
        activity: activities.currentActivity
        filterByScreen: false

        onCountChanged: root.rebuildOrder()
        onRowsMoved: root.rebuildOrder()
        onModelReset: root.rebuildOrder()
        Component.onCompleted: root.rebuildOrder()
    }

    fullRepresentation: Item {
        id: arc

        readonly property real halfSpan: root.radius * Math.sin((root.reach + 0.5) * root.stepAngle * Math.PI / 180)
        Layout.minimumWidth: Math.ceil(2 * halfSpan + root.iconSide + 8)
        Layout.preferredWidth: Layout.minimumWidth
        Layout.minimumHeight: 60
        Layout.preferredHeight: 64

        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false
        readonly property color ink: Kirigami.Theme.backgroundColor
        readonly property color bone: Kirigami.Theme.textColor
        readonly property color gold: Kirigami.Theme.focusColor

        function spot(pos) {
            const a = pos * root.stepAngle * Math.PI / 180;
            return Qt.point(width / 2 + root.radius * Math.sin(a),
                            root.topPad + root.iconCenter / 2 + root.radius * (1 - Math.cos(a)));
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => root.step(event.angleDelta.y > 0 ? -1 : 1)
        }

        // Hairline gold orbit through the icons.
        Canvas {
            anchors.fill: parent
            opacity: root.order.length > 1 ? 0.35 : 0
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = arc.gold;
                ctx.lineWidth = 1;
                ctx.beginPath();
                const span = (root.reach + 0.4) * root.stepAngle * Math.PI / 180;
                ctx.arc(width / 2, root.topPad + root.iconCenter / 2 + root.radius, root.radius,
                        -Math.PI / 2 - span, -Math.PI / 2 + span);
                ctx.stroke();
            }
            onWidthChanged: requestPaint()
        }

        Repeater {
            model: tasks
            delegate: Item {
                id: task

                required property int index
                required property var model

                readonly property int rank: root.order.indexOf(index)
                readonly property bool isActive: model.IsActive === true
                // Animated slot relative to the crest: 0 = center.
                property real pos: rank - root.activeRank
                Behavior on pos {
                    NumberAnimation { duration: 360; easing.type: Easing.OutCubic }
                }
                readonly property real away: Math.min(1, Math.abs(pos))
                readonly property real size: root.iconCenter + (root.iconSide - root.iconCenter) * away
                readonly property point at: arc.spot(pos)

                onIsActiveChanged: if (isActive && rank >= 0) root.activeRow = index
                Component.onCompleted: if (isActive && rank >= 0) root.activeRow = index

                visible: rank >= 0 && Math.abs(pos) <= root.reach + 0.6
                width: size
                height: size
                x: at.x - width / 2
                y: at.y - height / 2
                z: 10 - Math.abs(pos)
                opacity: (model.IsMinimized ? 0.45 : 1) * Math.max(0, Math.min(1, (root.reach + 0.6 - Math.abs(pos)) / 1.1))

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
                    onEntered: root.hoverName = task.model.AppName || task.model.display || ""
                    onExited: root.hoverName = ""
                    onClicked: (event) => {
                        if (event.button === Qt.MiddleButton) {
                            tasks.requestNewInstance(tasks.makeModelIndex(task.index));
                        } else {
                            root.activate(task.index, task.isActive, task.model.IsGroupParent === true,
                                          task.model.ChildCount || 0);
                        }
                    }
                }
            }
        }

        // Name of the app at the crest (or the one under the pointer).
        Text {
            readonly property string activeName: {
                const r = root.order[root.activeRank];
                if (r === undefined) {
                    return "";
                }
                return String(tasks.data(tasks.makeModelIndex(r), TaskManager.AbstractTasksModel.AppName)
                              || tasks.data(tasks.makeModelIndex(r), Qt.DisplayRole) || "");
            }
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.topPad + root.iconCenter + 3
            width: 96
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: (root.hoverName || activeName).toUpperCase()
            color: arc.gold
            font.family: "Exo 2"
            font.pixelSize: 9
            font.letterSpacing: 1.5
            font.weight: Font.Medium
        }
    }
}
