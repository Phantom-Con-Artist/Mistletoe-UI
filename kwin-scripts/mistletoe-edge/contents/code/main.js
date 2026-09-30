// Mistletoe's KWin helpers.
//
// 1. Left edge: pushing the pointer against the left screen edge opens the
//    Mistletoe dial. The dial writes its global-shortcut action name (e.g.
//    "activate widget 100") to kwinrc [Script-mistletoe-edge] action when it
//    loads, and this script invokes that shortcut through kglobalaccel.
//
// 2. Floating cards: a desktop card pinned to float is a plasmashell window
//    titled "Mistletoe Float <id> @x,y". Keep it above other windows, out of
//    the task switcher and pager, on every desktop, and open it at x,y (where
//    the card sat on the desktop).
function openDial() {
    const action = readConfig("action", "");
    if (!action) {
        return;
    }
    callDBus("org.kde.kglobalaccel", "/component/plasmashell",
             "org.kde.kglobalaccel.Component", "invokeShortcut", action);
}
registerScreenEdge(KWin.ElectricLeft, openDial);

function floatCard(w) {
    const m = /^Mistletoe Float \d+ @(-?\d+),(-?\d+)$/.exec(w.caption || "");
    if (!m) {
        return;
    }
    w.keepAbove = true;
    w.skipTaskbar = true;
    w.skipSwitcher = true;
    w.skipPager = true;
    w.onAllDesktops = true;
    // Keep it fully on the screen it opened on, whatever the title says.
    const g = w.frameGeometry;
    const area = workspace.clientArea(KWin.MaximizeArea, w);
    const x = Math.min(Math.max(parseInt(m[1]), area.x), area.x + area.width - g.width);
    const y = Math.min(Math.max(parseInt(m[2]), area.y), area.y + area.height - g.height);
    w.frameGeometry = { x: x, y: y, width: g.width, height: g.height };
}
workspace.windowAdded.connect(floatCard);
workspace.windowList().forEach(floatCard);
