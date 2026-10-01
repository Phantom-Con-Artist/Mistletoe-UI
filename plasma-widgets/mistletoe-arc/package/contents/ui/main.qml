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

    // Total CPU and memory (KiB) of one process row and everything below it.
    function subtree(parentIndex, row) {
        const idx = procs.index(row, 0, parentIndex);
        let cpu = Number(procs.data(procs.index(row, 1, parentIndex), Process.ProcessDataModel.Value)) || 0;
        let mem = Number(procs.data(procs.index(row, 2, parentIndex), Process.ProcessDataModel.Value)) || 0;
        for (let c = 0; c < procs.rowCount(idx); ++c) {
            const sub = subtree(idx, c);
            cpu += sub.cpu;
            mem += sub.mem;
        }
        return { cpu: cpu, mem: mem };
    }

    // Find a pid anywhere in the process tree; null when absent.
    function findPid(parentIndex, pid) {
        for (let r = 0; r < procs.rowCount(parentIndex); ++r) {
            if (Number(procs.data(procs.index(r, 0, parentIndex), Qt.DisplayRole)) === pid) {
                return subtree(parentIndex, r);
            }
            const deeper = findPid(procs.index(r, 0, parentIndex), pid);
            if (deeper) {
                return deeper;
            }
        }
        return null;
    }

    // Pids of the active app's windows (a grouped row keeps them on its
    // children and may report none itself).
    function windowPids() {
        const pids = [];
        const add = (index) => {
            const pid = Number(tasks.data(index, TaskManager.AbstractTasksModel.AppPid)) || 0;
            if (pid > 0 && pids.indexOf(pid) < 0) {
                pids.push(pid);
            }
        };
        if (activeRow >= 0 && activeRow < tasks.count) {
            const row = tasks.makeModelIndex(activeRow);
            add(row);
            for (let c = 0; c < tasks.rowCount(row); ++c) {
                add(tasks.makeModelIndex(activeRow, c));
            }
        }
        return pids;
    }

    // Sum CPU and memory over the app's window pids and their descendants.
    // Works for any app with a window, installed or not, scoped or not.
    function usageByPid() {
        const pids = windowPids();
        if (pids.length === 0 || procs.rowCount() === 0) {
            return false;
        }
        let cpu = 0;
        let mem = 0;
        let found = false;
        for (const pid of pids) {
            const total = findPid(procs.index(-1, -1), pid);
            if (total) {
                found = true;
                cpu += total.cpu;
                mem += total.mem;
            }
        }
        if (!found) {
            return false;
        }
        cpuText = cpu < 10 ? cpu.toFixed(1) + "%" : Math.round(cpu) + "%";
        memText = formatMem(mem);
        return true;
    }

    function formatMem(kib) {
        const units = ["K", "M", "G", "T"];
        let v = kib;
        let u = 0;
        while (v >= 1024 && u < units.length - 1) {
            v /= 1024;
            ++u;
        }
        return (v < 10 && u > 0 ? v.toFixed(1) : Math.round(v)) + units[u];
    }

    // Find the active app in System Monitor's per-application model. Windows
    // often report an id unlike their desktop file (firefox vs
    // org.mozilla.firefox.desktop, a bare "code", a translated name), so try
    // several keys, strictest first: exact id, launcher file, last segment of
    // a reverse-DNS id, then the display name.
    function refreshUsage() {
        const keys = [];
        const add = (s) => {
            const k = String(s || "").toLowerCase().replace(/\.desktop$/, "").trim();
            if (k && keys.indexOf(k) < 0) {
                keys.push(k);
            }
        };
        add(activeAppId);
        const launcher = activeRow >= 0
            ? String(tasks.data(tasks.makeModelIndex(activeRow), TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon) || "") : "";
        add(launcher.replace(/^.*\//, ""));
        const tail = (s) => String(s || "").toLowerCase().replace(/\.desktop$/, "").split(".").pop();
        const clean = (s) => String(s || "").replace(/\u200b/g, "");
        const name = activeName.toLowerCase();
        const n = appStats.rowCount();
        const menuIds = [];
        const names = [];
        for (let r = 0; r < n; ++r) {
            menuIds.push(String(appStats.data(appStats.index(r, 0), Qt.DisplayRole) || "").toLowerCase().replace(/\.desktop$/, ""));
            names.push(String(appStats.data(appStats.index(r, 3), Qt.DisplayRole) || "").toLowerCase());
        }
        let hit = -1;
        for (let k = 0; k < keys.length && hit < 0; ++k) {
            hit = menuIds.indexOf(keys[k]);
        }
        for (let k = 0; k < keys.length && hit < 0; ++k) {
            for (let r = 0; r < n && hit < 0; ++r) {
                if (tail(menuIds[r]) === keys[k] || menuIds[r] === tail(keys[k])) {
                    hit = r;
                }
            }
        }
        if (hit < 0 && name) {
            hit = names.indexOf(name);
        }
        if (hit < 0) {
            // Apps that don't run in their own systemd scope (started from a
            // terminal, wrappers, some autostarts) are missing from the app
            // model; total the window's process tree instead.
            if (!usageByPid()) {
                // Keep the last reading while the models are still filling in.
                if (n > 0 && procs.rowCount() > 0) {
                    cpuText = memText = "–";
                }
            }
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

    Process.ProcessDataModel {
        id: procs
        enabledAttributes: ["pid", "usage", "memory"]
    }

    Timer {
        interval: 1500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshUsage()
    }
    onActiveAppIdChanged: {
        cpuText = memText = "–";
        refreshUsage();
    }
    onActiveRowChanged: refreshUsage()
    Connections {
        target: appStats
        function onRowsInserted() { Qt.callLater(root.refreshUsage) }
    }

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
