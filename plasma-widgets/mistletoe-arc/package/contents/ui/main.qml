/*
    Mistletoe Arc.

    At rest it is a quiet strip: the current app's icon with its live CPU
    and memory use, dimmed so it never competes with your work. Hovering it
    brightens the strip and raises the arc above it: every open app on a
    semicircle, active app at the crest. The arc is a tooltip-type window
    that never takes keyboard focus, so peeking at it can't disturb the app
    you are typing in.

    Arc: click to activate (or minimize if already active), wheel to step
    through apps, middle-click for a new window.
*/
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import org.kde.ksysguard.process as Process

PlasmoidItem {
    id: root

    // Rows that are real app windows, in display order. Our own overlay
    // windows (plasmashell) and launcher placeholders are left out.
    property var order: []
    property int activeRow: -1
    readonly property int activeRank: Math.max(0, order.indexOf(activeRow))
    readonly property bool hasActive: order.indexOf(activeRow) >= 0

    readonly property string activeName: roleOf(activeRow, TaskManager.AbstractTasksModel.AppName)
        || roleOf(activeRow, Qt.DisplayRole)
    readonly property var activeIcon: activeRow >= 0 ? tasks.data(tasks.makeModelIndex(activeRow), Qt.DecorationRole) : ""
    readonly property string activeAppId: roleOf(activeRow, TaskManager.AbstractTasksModel.AppId)

    // Live usage of the active app, summed over all its processes.
    property string cpuText: "–"
    property string memText: "–"

    // Hover state: the strip or the raised arc.
    property bool stripHovered: false
    property bool arcHovered: false
    readonly property bool expanded: (stripHovered || arcHovered) && order.length > 0

    preferredRepresentation: fullRepresentation
    compactRepresentation: null
    // The panel reads fill from the applet root, not the representation.
    Layout.fillWidth: true
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    function roleOf(row, role) {
        if (row < 0 || row >= tasks.count) {
            return "";
        }
        return String(tasks.data(tasks.makeModelIndex(row), role) || "");
    }

    function rebuildOrder() {
        const rows = [];
        let active = -1;
        for (let i = 0; i < tasks.count; ++i) {
            const idx = tasks.makeModelIndex(i);
            const appId = String(tasks.data(idx, TaskManager.AbstractTasksModel.AppId) || "");
            if (tasks.data(idx, TaskManager.AbstractTasksModel.IsLauncher) || /plasmashell/.test(appId)) {
                continue;
            }
            rows.push(i);
            if (tasks.data(idx, TaskManager.AbstractTasksModel.IsActive)) {
                active = i;
            }
        }
        order = rows;
        // Keep the last real app when focus goes to the desktop or a shell
        // surface, so the strip doesn't flicker to nothing.
        if (active >= 0) {
            activeRow = active;
        } else if (rows.indexOf(activeRow) < 0) {
            activeRow = rows.length > 0 ? rows[0] : -1;
        }
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

    // Find the active app in System Monitor's per-application model. Match
    // the desktop file id (AppId + ".desktop") first, then the display
    // name, since some apps report a window id unlike their desktop file.
    function refreshUsage() {
        const id = activeAppId.toLowerCase();
        const name = activeName.toLowerCase();
        if (!id && !name) {
            cpuText = memText = "–";
            return;
        }
        const clean = (s) => String(s || "").replace(/\u200b/g, "");
        let hit = -1;
        for (let r = 0; r < appStats.rowCount() && hit < 0; ++r) {
            const menuId = String(appStats.data(appStats.index(r, 0), Qt.DisplayRole) || "").toLowerCase();
            if (id && (menuId === id + ".desktop" || menuId === id)) {
                hit = r;
            }
        }
        for (let r = 0; r < appStats.rowCount() && hit < 0; ++r) {
            if (name && String(appStats.data(appStats.index(r, 3), Qt.DisplayRole) || "").toLowerCase() === name) {
                hit = r;
            }
        }
        if (hit < 0) {
            cpuText = memText = "–";
            return;
        }
        const cpu = Number(appStats.data(appStats.index(hit, 1), Process.ProcessDataModel.Value)) || 0;
        cpuText = cpu < 10 ? cpu.toFixed(1) + "%" : Math.round(cpu) + "%";
        memText = clean(appStats.data(appStats.index(hit, 2), Qt.DisplayRole)).replace(/\s*([KMGT])iB/, "$1") || "–";
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
        onDataChanged: root.rebuildOrder()
        Component.onCompleted: root.rebuildOrder()
    }

    Process.ApplicationDataModel {
        id: appStats
        enabledAttributes: ["menuId", "usage", "memory", "appName"]
    }

    Timer {
        interval: 1500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshUsage()
    }
    onActiveAppIdChanged: refreshUsage()

    // The raised arc, above the strip. Tooltip-type and focus-less, so it
    // floats over apps without ever becoming the active window.
    PlasmaCore.Dialog {
        id: popup
        // Anchor to the centered content, not the whole (wide) strip.
        visualParent: root.fullRepresentationItem ? root.fullRepresentationItem.anchorItem : null
        location: PlasmaCore.Types.BottomEdge
        type: PlasmaCore.Dialog.Tooltip
        flags: Qt.WindowDoesNotAcceptFocus | Qt.WindowStaysOnTopHint
        backgroundHints: PlasmaCore.Dialog.NoBackground
        hideOnWindowDeactivate: false
        visible: hideDelay.expandedLatched

        mainItem: ArcView {
            tasks: tasks
            order: root.order
            activeRank: root.activeRank
            activeName: root.activeName
            onActivateRow: (row, isActive, isGroup, childCount) => root.activate(row, isActive, isGroup, childCount)
            onNewInstance: (row) => tasks.requestNewInstance(tasks.makeModelIndex(row))
            onStepRequested: (direction) => root.step(direction)

            HoverHandler {
                onHoveredChanged: root.arcHovered = hovered
            }
        }
    }

    // Short grace period so moving the pointer from the strip up into the
    // arc doesn't close it on the way.
    Timer {
        id: hideDelay
        property bool expandedLatched: false
        interval: 260
        onTriggered: expandedLatched = root.expanded
    }
    onExpandedChanged: {
        if (expanded) {
            hideDelay.stop();
            hideDelay.expandedLatched = true;
        } else {
            hideDelay.restart();
        }
    }

    // ---- Resting strip --------------------------------------------------
    // Fills the middle of the Mistletoe strip and keeps its content centered
    // on the screen (not just within itself), whatever sits either side.
    fullRepresentation: Item {
        id: strip

        property alias anchorItem: content

        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        Layout.fillWidth: true
        Layout.minimumWidth: content.width
        Layout.preferredWidth: content.width
        Layout.minimumHeight: 20

        readonly property real side: Math.min(height, 40)
        readonly property bool lit: root.expanded

        // The panel window spans the screen, so window-local x is screen x.
        // Our width changes whenever a neighbor resizes, which re-runs this.
        property real centerOffset: 0
        function recenter() {
            const w = strip.Window.window;
            if (!w) {
                return;
            }
            const left = strip.mapToItem(null, 0, 0).x;
            centerOffset = w.width / 2 - left - strip.width / 2;
        }
        onWidthChanged: Qt.callLater(recenter)
        Component.onCompleted: Qt.callLater(recenter)

        // Only the content (plus a little slack) reacts, not the whole strip.
        MouseArea {
            anchors.fill: content
            anchors.margins: -10
            anchors.topMargin: -strip.height
            anchors.bottomMargin: -strip.height
            hoverEnabled: true
            onContainsMouseChanged: root.stripHovered = containsMouse
            onClicked: if (root.hasActive) tasks.requestToggleMinimized(tasks.makeModelIndex(root.activeRow))
            onWheel: (wheel) => root.step(wheel.angleDelta.y > 0 ? -1 : 1)
        }

        Row {
            id: content
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(strip.width - width, (strip.width - width) / 2 + strip.centerOffset))
            spacing: 12
            opacity: strip.lit ? 1 : 0.8
            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            Kirigami.Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26
                source: root.activeIcon || "window-symbolic"
                animated: false
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 180)
                elide: Text.ElideRight
                text: root.activeName
                color: Kirigami.Theme.textColor
                font.family: "Mistletoe Text"
                font.pixelSize: 14
            }

            Repeater {
                model: [
                    { key: "CPU", value: root.cpuText },
                    { key: "RAM", value: root.memText }
                ]
                Row {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Text {
                        anchors.baseline: valueText.baseline
                        text: modelData.key
                        color: Kirigami.Theme.focusColor
                        font.family: "Mistletoe Text"
                        font.pixelSize: 10
                        font.letterSpacing: 1.5
                        font.weight: Font.Medium
                    }
                    Text {
                        id: valueText
                        // Fixed width so live numbers never make the row jitter.
                        width: 50
                        text: modelData.value
                        color: Kirigami.Theme.textColor
                        font.family: "Mistletoe Text"
                        font.pixelSize: 13
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }
    }
}
