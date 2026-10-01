/*
    System card: how hard the machine is working right now, at a glance.

      - A live two-minute graph of total CPU (gold area) and memory (bone
        line), with the current values beside it.
      - The apps using the most CPU (ties broken by memory), each with a CPU
        bar relative to the busiest one.
      - A tip, only when there is something to act on: who is pinning the
        CPU, or who holds the most memory when RAM runs high.

    Compact by default; give it more height and the graph grows, then more
    apps appear. Click an app row to open System Monitor.
*/
import QtQuick
import QtQuick.Layouts
import org.kde.ksysguard.process as Process
import org.kde.ksysguard.sensors as Sensors
import org.kde.taskmanager as TaskManager
import org.kde.plasma.plasma5support as P5Support

ColumnLayout {
    id: card

    required property var dash

    spacing: 0

    // ---- Data -----------------------------------------------------------
    Sensors.Sensor {
        id: cpuTotal
        sensorId: "cpu/all/usage"
    }
    Sensors.Sensor {
        id: memPercent
        sensorId: "memory/physical/usedPercent"
    }
    Sensors.Sensor {
        id: memUsed
        sensorId: "memory/physical/used"
    }
    Sensors.Sensor {
        id: memTotal
        sensorId: "memory/physical/total"
    }
    Process.ApplicationDataModel {
        id: appStats
        enabledAttributes: ["appName", "iconName", "usage", "memory"]
    }
    // The application model only knows apps running in their own systemd
    // scope. Anything else with a window (started from a terminal, wrappers,
    // freshly installed apps) is totalled from its process tree instead, the
    // way the strip does it.
    Process.ProcessDataModel {
        id: procs
        enabledAttributes: ["pid", "usage", "memory"]
    }
    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupApplications
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
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
    function formatMem(kib) {
        const units = ["KB", "MB", "GB", "TB"];
        let v = kib;
        let u = 0;
        while (v >= 1024 && u < units.length - 1) {
            v /= 1024;
            ++u;
        }
        return (v < 10 && u > 0 ? v.toFixed(1) : Math.round(v)) + " " + units[u];
    }
    // Apps with windows that the application model doesn't list.
    function windowApps(known) {
        const out = [];
        for (let i = 0; i < tasks.count; ++i) {
            const row = tasks.makeModelIndex(i);
            const appId = String(tasks.data(row, TaskManager.AbstractTasksModel.AppId) || "");
            const name = String(tasks.data(row, TaskManager.AbstractTasksModel.AppName) || tasks.data(row, Qt.DisplayRole) || "");
            if (!name || tasks.data(row, TaskManager.AbstractTasksModel.IsLauncher) || /plasmashell/.test(appId)
                    || known[name.toLowerCase()]) {
                continue;
            }
            const pids = [];
            const add = (index) => {
                const pid = Number(tasks.data(index, TaskManager.AbstractTasksModel.AppPid)) || 0;
                if (pid > 0 && pids.indexOf(pid) < 0) {
                    pids.push(pid);
                }
            };
            add(row);
            for (let c = 0; c < tasks.rowCount(row); ++c) {
                add(tasks.makeModelIndex(i, c));
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
            if (found) {
                known[name.toLowerCase()] = true;
                out.push({ name: name, icon: tasks.data(row, Qt.DecorationRole), cpu: cpu, mem: mem, memText: formatMem(mem) });
            }
        }
        return out;
    }

    readonly property int samples: 60           // 60 x 2 s = two minutes
    // The heading and gaps take 40px and a tip, when shown, 44px. The graph
    // keeps at least 72px; the rest holds as many app rows as fit, and the
    // graph stretches into whatever the rows leave over.
    readonly property int rowHeight: 32
    readonly property real graphMin: 72
    readonly property var tip: tips.length > 0 && tips[0].level >= 1 ? tips[0] : null
    readonly property real flexible: height - 40 - (tip ? 44 : 0)
    readonly property int appsFit: Math.max(1, Math.min(8, Math.floor((flexible - graphMin) / rowHeight)))
    property var cpuHistory: []
    property var memHistory: []
    property var apps: []                        // busiest first
    property var tips: []

    function clean(s) {
        return String(s || "").replace(/​/g, "");
    }
    function shortMem(s) {
        return clean(s).replace(/\s*([KMGT])iB/, " $1B");
    }

    function sample() {
        // History, oldest first.
        // Sensors report nothing until their first update; skip until then
        // so the graph doesn't start with a false drop to zero.
        const push = (list, v) => list.concat([Math.max(0, Math.min(100, Number(v) || 0))]).slice(-samples);
        if (Number(memPercent.value) > 0) {
            cpuHistory = push(cpuHistory, cpuTotal.value);
            memHistory = push(memHistory, memPercent.value);
        }

        // Apps. Rebuilt on a timer rather than bound to the model, which
        // changes on every sample and would churn the delegates.
        const all = [];
        const known = {};
        for (let r = 0; r < appStats.rowCount(); ++r) {
            const name = clean(appStats.data(appStats.index(r, 0), Qt.DisplayRole));
            if (!name) {
                continue;
            }
            known[name.toLowerCase()] = true;
            all.push({
                name: name,
                icon: String(appStats.data(appStats.index(r, 1), Qt.DisplayRole) || "application-x-executable"),
                cpu: Number(appStats.data(appStats.index(r, 2), Process.ProcessDataModel.Value)) || 0,
                mem: Number(appStats.data(appStats.index(r, 3), Process.ProcessDataModel.Value)) || 0,
                memText: shortMem(appStats.data(appStats.index(r, 3), Qt.DisplayRole))
            });
        }
        // Only apps that are using something worth a row: idle background
        // helpers would just be a list of zeros.
        const rows = all.concat(windowApps(known)).filter(a => a.cpu >= 0.5 || a.mem >= 200 * 1024);   // KiB
        const byCpu = rows.slice().sort((a, b) => (b.cpu - a.cpu) || (b.mem - a.mem));
        const byMem = rows.slice().sort((a, b) => b.mem - a.mem);
        tips = makeTips(byCpu, byMem);
        apps = byCpu.slice(0, appsFit);
    }

    // Two tips at most, the most pressing first.
    function makeTips(byCpu, byMem) {
        const out = [];
        const cpu = Number(cpuTotal.value) || 0;
        const mem = Number(memPercent.value) || 0;
        const hog = byCpu[0];
        const fat = byMem[0];
        if (hog && hog.cpu >= 40) {
            out.push({ level: 2, text: i18n("%1 is using %2% CPU. If it isn't doing something for you, closing it will cool things down.", hog.name, Math.round(hog.cpu)) });
        }
        if (mem >= 80 && fat) {
            out.push({ level: 2, text: i18n("Memory is %1% full. %2 holds the most (%3); closing it frees the most room.", Math.round(mem), fat.name, fat.memText) });
        } else if (fat && fat.mem > 1.5 * 1024 * 1024) {  // KiB
            out.push({ level: 1, text: i18n("%1 is holding %2 of memory. Closing tabs or windows you don't need will trim it.", fat.name, fat.memText) });
        }
        if (cpu >= 70 && !(hog && hog.cpu >= 40)) {
            out.push({ level: 1, text: i18n("The CPU is busy (%1%) across several apps. Background work like updates or indexing can cause this.", Math.round(cpu)) });
        }
        if (out.length === 0) {
            out.push({ level: 0, text: cpu < 20 && mem < 60
                ? i18n("All calm. Plenty of headroom on both CPU and memory.")
                : i18n("Running comfortably. Nothing needs your attention.") });
        }
        return out.slice(0, 2);
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: card.sample()
    }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: (source) => disconnectSource(source)
    }

    // ---- Heading ------------------------------------------------------------
    SectionLabel {
        Layout.fillWidth: true
        // Clear of the pin, which appears top right on hover.
        Layout.rightMargin: 14
        text: i18n("System")
        note: i18n("last 2 min")
        gold: card.dash.gold
        bone: card.dash.bone
    }

    // ---- Graph and readouts ---------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: card.graphMin
        Layout.topMargin: 12
        spacing: 20

        Canvas {
            id: graph
            Layout.fillWidth: true
            Layout.fillHeight: true
            renderStrategy: Canvas.Cooperative

            readonly property var cpu: card.cpuHistory
            readonly property var mem: card.memHistory
            onCpuChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const w = width, h = height;
                const bone = card.dash.bone, gold = card.dash.gold;
                const rgba = (c, a) => `rgba(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)},${a})`;

                // Hairline grid at 0, 50 and 100%.
                ctx.strokeStyle = rgba(bone, 0.08);
                ctx.lineWidth = 1;
                for (const f of [0, 0.5, 1]) {
                    const y = Math.round(f * (h - 1)) + 0.5;
                    ctx.beginPath();
                    ctx.moveTo(0, y);
                    ctx.lineTo(w, y);
                    ctx.stroke();
                }

                const xAt = (i) => w - (card.samples - 1 - i) * (w / (card.samples - 1));
                const plot = (list) => {
                    const off = card.samples - list.length;
                    ctx.beginPath();
                    for (let i = 0; i < list.length; ++i) {
                        const x = xAt(i + off), y = h - 1 - list[i] / 100 * (h - 2);
                        i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
                    }
                    return off;
                };

                if (cpu.length > 1) {
                    // CPU: gold area with a crisp top line.
                    const off = plot(cpu);
                    ctx.lineTo(w, h);
                    ctx.lineTo(xAt(off), h);
                    ctx.closePath();
                    const g = ctx.createLinearGradient(0, 0, 0, h);
                    g.addColorStop(0, rgba(gold, 0.35));
                    g.addColorStop(1, rgba(gold, 0.02));
                    ctx.fillStyle = g;
                    ctx.fill();
                    plot(cpu);
                    ctx.strokeStyle = rgba(gold, 0.95);
                    ctx.lineWidth = 1.5;
                    ctx.stroke();
                }
                if (mem.length > 1) {
                    plot(mem);
                    ctx.strokeStyle = rgba(bone, 0.55);
                    ctx.lineWidth = 1;
                    ctx.stroke();
                }
            }
        }

        // CPU and memory side by side, each a key over its value.
        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: 18
            Repeater {
                model: [
                    { key: i18n("CPU"), value: Math.round(cpuTotal.value || 0) + "%", sub: "", gold: true },
                    { key: i18n("Memory"), value: Math.round(memPercent.value || 0) + "%",
                      sub: card.shortMem(memUsed.formattedValue), gold: false }
                ]
                Column {
                    required property var modelData
                    spacing: 0
                    Row {
                        spacing: 6
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 10
                            height: modelData.gold ? 3 : 1
                            color: modelData.gold ? card.dash.gold : card.dash.tint(card.dash.bone, 0.55)
                        }
                        Text {
                            text: modelData.key.toUpperCase()
                            color: card.dash.tint(card.dash.bone, 0.6)
                            font.family: "Mistletoe Display"
                            font.pixelSize: 9
                            font.letterSpacing: 2
                        }
                    }
                    Text {
                        id: readout
                        // Room for "100%", so the pair never shifts.
                        width: Math.ceil(widest.width)
                        text: modelData.value
                        color: card.dash.bone
                        font.family: "Mistletoe Accent"
                        font.pixelSize: 26
                        font.weight: Font.Light
                        font.features: { "tnum": 1 }
                        TextMetrics {
                            id: widest
                            font: readout.font
                            text: "100%"
                        }
                    }
                    Text {
                        // Always a line tall, so both values share a baseline.
                        text: modelData.sub || " "
                        color: card.dash.tint(card.dash.bone, 0.5)
                        font.family: "Mistletoe Text"
                        font.pixelSize: 10
                    }
                }
            }
        }
    }

    // ---- Busiest apps -------------------------------------------------------
    Item {
        Layout.preferredHeight: 14
    }
    Repeater {
        model: card.apps
        delegate: AppRow {
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: card.rowHeight
            iconSource: modelData.icon
            title: modelData.name
            value: (modelData.cpu < 10 ? modelData.cpu.toFixed(1) : Math.round(modelData.cpu)) + "%"
            detail: modelData.memText
            level: modelData.cpu / Math.max(10, card.apps.length > 0 ? card.apps[0].cpu : 0)
            ink: card.dash.ink
            bone: card.dash.bone
            gold: card.dash.gold
            onClicked: runner.connectSource("kstart plasma-systemmonitor")
        }
    }

    // ---- Tip (only when there is something to act on) ---------------------------
    RowLayout {
        visible: card.tip !== null
        Layout.fillWidth: true
        Layout.topMargin: 8
        Layout.preferredHeight: 36
        spacing: 10
        Gem {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 3
            Layout.preferredWidth: 10
            Layout.preferredHeight: 10
            fill: card.tip && card.tip.level >= 2 ? card.dash.gold : "transparent"
            rim: card.dash.gold
        }
        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: card.tip ? card.tip.text : ""
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: card.dash.tint(card.dash.bone, 0.85)
            font.family: "Mistletoe Text"
            font.pixelSize: 12
            lineHeight: 1.15
        }
    }

}
