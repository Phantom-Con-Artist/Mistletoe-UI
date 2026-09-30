/*
    Power card: how hard the machine is working right now.

      - A live two-minute graph of total CPU (gold area) and memory (bone
        line), with the current values large on the right.
      - The open apps using the most CPU (ties broken by memory), each with
        a CPU bar relative to the busiest one.
      - Tips worked out from those numbers every two seconds: who is
        pinning the CPU, who holds the most memory when RAM runs high, or
        that everything is calm.

    Click an app row to open System Monitor.
*/
import QtQuick
import QtQuick.Layouts
import org.kde.ksysguard.process as Process
import org.kde.ksysguard.sensors as Sensors
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

    readonly property int samples: 60           // 60 x 2 s = two minutes
    // Headings, gaps and two lines of tips take about 230px; of the rest,
    // five app rows come first, then the graph grows (90-260px), then any
    // height left over becomes more rows.
    readonly property real flexible: height - 230
    readonly property real graphHeight: Math.max(90, Math.min(260, flexible - 5 * 40))
    readonly property int appsFit: Math.max(3, Math.min(10, Math.floor((flexible - graphHeight) / 40)))
    property var cpuHistory: []
    property var memHistory: []
    property var apps: []                        // top 5 by CPU
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
        const rows = [];
        for (let r = 0; r < appStats.rowCount(); ++r) {
            const name = clean(appStats.data(appStats.index(r, 0), Qt.DisplayRole));
            if (!name) {
                continue;
            }
            rows.push({
                name: name,
                icon: String(appStats.data(appStats.index(r, 1), Qt.DisplayRole) || "application-x-executable"),
                cpu: Number(appStats.data(appStats.index(r, 2), Process.ProcessDataModel.Value)) || 0,
                mem: Number(appStats.data(appStats.index(r, 3), Process.ProcessDataModel.Value)) || 0,
                memText: shortMem(appStats.data(appStats.index(r, 3), Qt.DisplayRole))
            });
        }
        const byCpu = rows.slice().sort((a, b) => (b.cpu - a.cpu) || (b.mem - a.mem));
        const byMem = rows.slice().sort((a, b) => b.mem - a.mem);
        apps = byCpu.slice(0, appsFit);
        tips = makeTips(byCpu, byMem);
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
        // Stay clear of the deep top-right cut.
        Layout.rightMargin: 36
        text: i18n("Power")
        note: i18n("last 2 min")
        gold: card.dash.gold
        bone: card.dash.bone
    }

    // ---- Graph and readouts ---------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 16
        spacing: 20

        Canvas {
            id: graph
            Layout.fillWidth: true
            Layout.preferredHeight: card.graphHeight
            renderStrategy: Canvas.Cooperative

            readonly property var cpu: card.cpuHistory
            readonly property var mem: card.memHistory
            onCpuChanged: requestPaint()
            onWidthChanged: requestPaint()

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

        Column {
            Layout.alignment: Qt.AlignVCenter
            spacing: 14
            Repeater {
                model: [
                    { key: i18n("CPU"), value: Math.round(cpuTotal.value || 0) + "%", sub: "", gold: true },
                    { key: i18n("Memory"), value: Math.round(memPercent.value || 0) + "%",
                      sub: card.shortMem(memUsed.formattedValue) + " / " + card.shortMem(memTotal.formattedValue), gold: false }
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
                            font.family: "Exo 2"
                            font.pixelSize: 9
                            font.letterSpacing: 2
                        }
                    }
                    Text {
                        text: modelData.value
                        color: card.dash.bone
                        font.family: "Exo 2"
                        font.pixelSize: 26
                        font.weight: Font.Light
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        visible: modelData.sub.length > 0
                        text: modelData.sub
                        color: card.dash.tint(card.dash.bone, 0.5)
                        font.family: "Exo 2"
                        font.pixelSize: 10
                    }
                }
            }
        }
    }

    // ---- Top apps -----------------------------------------------------------
    SectionLabel {
        Layout.fillWidth: true
        Layout.topMargin: 22
        Layout.bottomMargin: 6
        text: i18n("Hungriest apps")
        note: i18n("CPU · RAM")
        gold: card.dash.gold
        bone: card.dash.bone
    }
    Repeater {
        model: card.apps
        delegate: AppRow {
            required property var modelData
            Layout.fillWidth: true
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

    // ---- Tips -----------------------------------------------------------------
    SectionLabel {
        Layout.fillWidth: true
        Layout.topMargin: 22
        Layout.bottomMargin: 8
        text: i18n("Tips")
        gold: card.dash.gold
        bone: card.dash.bone
    }
    Repeater {
        model: card.tips
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            spacing: 10
            // Gold gem for something to act on, a hollow one otherwise.
            Gem {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 3
                Layout.preferredWidth: 10
                Layout.preferredHeight: 10
                fill: modelData.level >= 2 ? card.dash.gold : "transparent"
                rim: modelData.level >= 1 ? card.dash.gold : card.dash.tint(card.dash.bone, 0.45)
            }
            Text {
                Layout.fillWidth: true
                text: modelData.text
                wrapMode: Text.WordWrap
                color: card.dash.tint(card.dash.bone, 0.85)
                font.family: "Exo 2"
                font.pixelSize: 13
                lineHeight: 1.2
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
