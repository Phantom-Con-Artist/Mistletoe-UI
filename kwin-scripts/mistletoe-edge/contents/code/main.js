// Mistletoe's KWin helper.
//
// Floating cards: a desktop card pinned to float is a plasmashell window
// titled "Mistletoe Float <id> @x,y". Keep it above other windows, out of
// the task switcher and pager, on every desktop, and open it at x,y (where
// the card sat on the desktop).
//
// (The script once opened the dial when the pointer hit the left screen edge.
// That fired by accident too easily; the dial opens from its gem in the strip
// or Meta+Space instead. The package keeps its name so installs carry over.)
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
