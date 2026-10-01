/*
    Mistletoe Dial: one radial way into every app.

    A gem in the strip, or Meta+Space, opens a semicircle dial from the left
    screen edge with three modes:

      App       the menus of the window you were just using: its menus on
                the inner ring, their entries on the outer ring, submenus
                drill in. Read and clicked through the mistletoe-menu
                bridge (com.canonical.dbusmenu), so it works for any app
                that exports its menu bar: KDE/Qt apps, and GTK apps with
                appmenu-gtk-module.
      Places    Dolphin's places and bookmarks, folders you used lately,
                mounted drives, network and trash; opens Dolphin there.
      Settings  first the Mistletoe choices (edition, and the display,
                accent and text fonts; the current one is marked), then
                every System Settings page, grouped as System Settings
                groups them; each opens alone in its own window.

    Other widgets open the dial in a given mode by writing it to
    mistletoerc [Dial] nextMode and invoking the dial's shortcut, whose
    name the dial records in mistletoerc [Dial] action.

    Typing searches the whole current mode.
*/
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    compactRepresentation: null
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    activationTogglesExpanded: false
    // A square button as tall as the strip.
    Layout.minimumWidth: height
    Layout.preferredWidth: height
    Layout.maximumWidth: height

    property string mode: "App"
    readonly property bool appAvailable: target.service.length > 0

    // ---- The window the dial acts on ------------------------------------
    // The last active real app window (the dial's own overlay and other
    // shell surfaces don't count), with its menu's D-Bus address.
    property var target: ({ row: -1, name: "", service: "", path: "" })

    TaskManager.VirtualDesktopInfo {
        id: desktops
    }
    TaskManager.ActivityInfo {
        id: activities
    }
    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: true
        virtualDesktop: desktops.currentDesktop
        filterByActivity: true
        activity: activities.currentActivity
        onDataChanged: root.trackActive()
        onCountChanged: root.trackActive()
        Component.onCompleted: root.trackActive()
    }

    function trackActive() {
        for (let i = 0; i < tasks.count; ++i) {
            const idx = tasks.makeModelIndex(i);
            if (!tasks.data(idx, TaskManager.AbstractTasksModel.IsActive)) {
                continue;
            }
            const appId = String(tasks.data(idx, TaskManager.AbstractTasksModel.AppId) || "");
            if (/plasmashell/.test(appId)) {
                return; // keep the previous target
            }
            target = {
                row: i,
                name: String(tasks.data(idx, TaskManager.AbstractTasksModel.AppName) || tasks.data(idx, Qt.DisplayRole) || ""),
                service: String(tasks.data(idx, TaskManager.AbstractTasksModel.ApplicationMenuServiceName) || ""),
                path: String(tasks.data(idx, TaskManager.AbstractTasksModel.ApplicationMenuObjectPath) || "")
            };
            return;
        }
    }

    // ---- Running helpers --------------------------------------------------
    // Commands go through Plasma's executable engine; each gets a callback
    // for its stdout.
    property var pending: ({})
    P5Support.DataSource {
        id: shell
        engine: "executable"
        onNewData: (source, data) => {
            const done = root.pending[source];
            delete root.pending[source];
            disconnectSource(source);
            if (done) {
                done(String(data.stdout || ""));
            }
        }
    }
    function run(command, done) {
        // A counter keeps identical commands distinct.
        const source = command + " #" + (++runCounter);
        pending[source] = done || null;
        shell.connectSource(source);
    }
    property int runCounter: 0
    function q(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }
    readonly property string bridge: Plasmoid.configuration.bridge
    readonly property string settingsIndex: Plasmoid.configuration.settingsIndex

    // ---- App mode: menus ----------------------------------------------------
    property var menu: []          // top-level menus (trees)
    property var stack: []         // submenu nodes drilled into
    property bool menuLoading: false

    function loadMenu() {
        menu = [];
        stack = [];
        if (!appAvailable) {
            return;
        }
        menuLoading = true;
        const t = target;
        run(bridge + " dump " + q(t.service) + " " + q(t.path), (out) => {
            menuLoading = false;
            try {
                const parsed = JSON.parse(out);
                menu = Array.isArray(parsed) ? parsed.filter(m => m.children.length > 0) : [];
            } catch (e) {
                menu = [];
            }
            appCategory = 0;
        });
    }
    property int appCategory: 0

    readonly property var menuIcons: ({
        file: "document-open", edit: "edit-copy", selection: "edit-select-all", view: "view-visible",
        go: "go-next", bookmarks: "bookmarks", tools: "tools", settings: "configure",
        help: "help-about", window: "window", tabs: "tab-new", session: "utilities-terminal",
        image: "image-x-generic", format: "format-text-bold", insert: "insert-text", search: "edit-find",
        history: "view-history", plugins: "plugins", project: "project-open", build: "run-build"
    })

    function toEntry(n, path) {
        return {
            label: n.label, icon: n.icon, enabled: n.enabled, checked: n.checked,
            shortcut: n.shortcut, hasChildren: n.children.length > 0,
            detail: path || "", node: n
        };
    }
    function flatten(nodes, path, out) {
        for (const n of nodes) {
            if (n.children.length > 0) {
                flatten(n.children, path ? path + " › " + n.label : n.label, out);
            } else {
                out.push(toEntry(n, path));
            }
        }
        return out;
    }

    // ---- Places mode ----------------------------------------------------------
    property var places: []        // [{ name, icon, entries: [{ label, icon, detail, url }] }]
    property int placesCategory: 0
    function loadPlaces() {
        run(bridge + " places", (out) => {
            try {
                places = JSON.parse(out);
            } catch (e) {
                places = [];
            }
            placesCategory = Math.min(placesCategory, Math.max(0, places.length - 1));
        });
    }

    // ---- Mistletoe options (top of Settings mode) --------------------------
    // [{ name, icon, entries: [{ label, detail, checked, command }] }]
    property var options: []
    function loadOptions() {
        run(bridge + " options", (out) => {
            try {
                options = JSON.parse(out);
            } catch (e) {
                options = [];
            }
        });
    }

    // ---- Settings mode ----------------------------------------------------
    property var settings: ({ categories: [], modules: [] })
    property int settingsCategory: 0
    function loadSettings() {
        run("cat " + settingsIndex, (out) => {
            try {
                settings = JSON.parse(out);
            } catch (e) {
                settings = { categories: [], modules: [] };
            }
        });
    }
    // A Global Theme switch changes the colour scheme; when it does, give a
    // Mistletoe edition its own wallpaper (Plasma won't replace one you've
    // set). See `mistletoe-menu sync-wallpaper`.
    readonly property color schemeAccent: Kirigami.Theme.focusColor
    onSchemeAccentChanged: run(bridge + " sync-wallpaper")

    Component.onCompleted: {
        loadSettings();
        register();
        run(bridge + " sync-wallpaper");
    }

    function moduleEntry(m) {
        return {
            label: m.name, icon: m.icon, enabled: true,
            detail: (m.sub ? m.sub + "  ·  " : "") + m.description,
            hasChildren: false, module: m.id
        };
    }

    // ---- What the dial shows ------------------------------------------------
    readonly property string query: fan.query.trim().toLowerCase()

    readonly property var categories: mode === "App"
        ? menu.map(m => ({ name: m.label, icon: menuIcons[m.label.toLowerCase()] || "application-menu" }))
        : mode === "Places" ? places.map(g => ({ name: g.name, icon: g.icon }))
        : options.map(o => ({ name: o.name, icon: o.icon }))
            .concat(settings.categories.map(c => ({ name: c.name, icon: c.icon })))
    readonly property int categoryIndex: mode === "App" ? appCategory
        : mode === "Places" ? placesCategory : settingsCategory

    readonly property var entries: {
        if (mode === "App") {
            if (query) {
                return flatten(menu, "", []).filter(e => e.label.toLowerCase().includes(query)
                    || e.detail.toLowerCase().includes(query));
            }
            const list = stack.length > 0 ? stack[stack.length - 1].children
                : (menu[appCategory] ? menu[appCategory].children : []);
            return list.map(n => toEntry(n, ""));
        }
        if (mode === "Places") {
            const all = query ? places.reduce((acc, g) => acc.concat(g.entries), [])
                : (places[placesCategory] ? places[placesCategory].entries : []);
            return all.filter(e => !query || (e.label + " " + e.detail).toLowerCase().includes(query))
                .map(e => ({ label: e.label, icon: e.icon, detail: e.detail, enabled: true, hasChildren: false, url: e.url }));
        }
        const optionEntry = (o, e) => ({
            label: e.label, icon: e.checked ? "checkmark" : "", detail: o.name + "  ·  " + e.detail,
            enabled: true, checked: e.checked, hasChildren: false, command: e.command
        });
        if (!query && settingsCategory < options.length) {
            const o = options[settingsCategory];
            return o.entries.map(e => optionEntry(o, e));
        }
        if (query) {
            const words = query.split(/\s+/);
            const fromOptions = options.reduce((acc, o) => acc.concat(o.entries
                .filter(e => words.every(w => (o.name + " " + e.label + " " + e.detail).toLowerCase().includes(w)))
                .map(e => optionEntry(o, e))), []);
            return fromOptions.concat(settings.modules.filter(m => {
                const hay = (m.name + " " + m.description + " " + m.sub + " " + m.keywords).toLowerCase();
                return words.every(w => hay.includes(w));
            }).map(moduleEntry));
        }
        const cat = settings.categories[settingsCategory - options.length];
        return cat ? settings.modules.filter(m => m.category === cat.id).map(moduleEntry) : [];
    }

    readonly property string trail: mode === "App" && !query
        ? (menu[appCategory] ? [menu[appCategory].label].concat(stack.map(n => n.label)).join(" › ") : "")
        : ""

    // ---- Actions ----------------------------------------------------------------
    function chooseCategory(i) {
        if (mode === "App") {
            appCategory = i;
            stack = [];
        } else if (mode === "Places") {
            placesCategory = i;
        } else {
            settingsCategory = i;
        }
        fan.entryIndex = 0;
    }

    function activate(i) {
        const e = entries[i];
        if (!e || e.enabled === false) {
            return;
        }
        if (mode === "App") {
            if (e.hasChildren) {
                stack = stack.concat([e.node]);
                fan.entryIndex = 0;
                return;
            }
            const t = target;
            fan.close();
            // Bring the app forward, then fire the entry.
            if (t.row >= 0 && t.row < tasks.count) {
                tasks.requestActivate(tasks.makeModelIndex(t.row));
            }
            run(bridge + " click " + q(t.service) + " " + q(t.path) + " " + e.node.id);
        } else if (mode === "Places") {
            fan.close();
            run("dolphin " + q(e.url));
        } else if (e.command) {
            // A Mistletoe option: switch edition or font role.
            fan.close();
            run(bridge + " " + e.command);
        } else {
            fan.close();
            run("kcmshell6 " + q(e.module));
        }
    }

    readonly property var modes: [
        { name: "App", enabled: appAvailable },
        { name: "Places", enabled: true },
        { name: "Settings", enabled: true }
    ]
    function chooseMode(name) {
        if (!modes.some(m => m.name === name && m.enabled)) {
            return;
        }
        mode = name;
        fan.entryIndex = 0;
        fan.keyTarget.text = "";
    }
    // Tab: the next available mode, wrapping round.
    function nextMode() {
        const names = modes.filter(m => m.enabled).map(m => m.name);
        chooseMode(names[(names.indexOf(mode) + 1) % names.length]);
    }

    // Opening reads (and clears) a one-shot mode request left by another
    // widget, e.g. the status fan's Settings tile.
    function toggle() {
        if (overlay.visible) {
            fan.close();
            return;
        }
        run("kreadconfig6 --file mistletoerc --group Dial --key nextMode"
            + " && kwriteconfig6 --file mistletoerc --group Dial --key nextMode ''", (out) => {
            const wanted = out.trim();
            mode = modes.some(m => m.name === wanted && m.enabled) ? wanted : (appAvailable ? "App" : "Places");
            // Each open starts at the first group of every mode.
            placesCategory = 0;
            settingsCategory = 0;
            loadMenu();
            loadPlaces();
            loadOptions();
            if (settings.modules.length === 0) {
                loadSettings();
            }
            fan.entryIndex = 0;
            overlay.open();
            Qt.callLater(fan.open);
        });
    }

    // Tell other widgets how to open the dial.
    function register() {
        const action = q("activate widget " + Plasmoid.id);
        run("kwriteconfig6 --file mistletoerc --group Dial --key action " + action);
    }

    Connections {
        target: Plasmoid
        function onActivated() {
            root.toggle();
        }
    }

    // ---- Strip button: a gem within a gem --------------------------------------
    property Item button: null
    fullRepresentation: MouseArea {
        id: button
        hoverEnabled: true
        Layout.minimumWidth: height
        Layout.preferredWidth: height
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false
        readonly property bool lit: containsMouse || overlay.visible
        readonly property real side: Math.min(width, height)
        onClicked: root.toggle()
        Component.onCompleted: root.button = button

        Gem {
            anchors.centerIn: parent
            width: Math.round(button.side * 0.7)
            height: width
            fill: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g,
                          Kirigami.Theme.backgroundColor.b, button.lit ? 0.95 : 0.6)
            rim: button.lit ? Kirigami.Theme.focusColor
                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.35)
        }
        Gem {
            anchors.centerIn: parent
            width: Math.round(button.side * 0.26)
            height: width
            fill: button.lit ? Kirigami.Theme.focusColor
                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7)
            rim: "transparent"
        }
    }
    toolTipMainText: i18n("Dial")
    toolTipSubText: i18n("The active app's menus, your places and every settings page (Meta+Space)")

    Overlay {
        id: overlay
        anchorItem: root.button
        focusItem: fan.keyTarget
        onDeactivated: fan.close()

        Dial {
            id: fan
            anchors.fill: parent
            mode: root.mode
            modes: root.modes
            context: root.mode === "App" ? root.target.name
                : root.mode === "Places" ? i18n("Places") : i18n("System Settings")
            trail: root.trail
            status: root.mode === "App" && root.menuLoading ? i18n("Reading %1's menus…", root.target.name)
                : root.mode === "App" && root.menu.length === 0 && !root.menuLoading
                    ? i18n("%1 doesn't share its menus", root.target.name || i18n("This app"))
                : ""
            categories: root.categories
            categoryIndex: root.categoryIndex
            entries: root.entries
            onCategoryChosen: (i) => root.chooseCategory(i)
            onEntryActivated: (i) => root.activate(i)
            onBackRequested: {
                if (root.stack.length > 0) {
                    root.stack = root.stack.slice(0, -1);
                    fan.entryIndex = 0;
                }
            }
            onModeToggled: root.nextMode()
            onModeChosen: (name) => root.chooseMode(name)
            onClosed: overlay.hide()
        }
    }
}
