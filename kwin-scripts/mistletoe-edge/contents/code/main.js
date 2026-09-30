// Mistletoe Edge: pushing the pointer against the left screen edge opens the
// Mistletoe dial. The dial writes its global-shortcut action name (e.g.
// "activate widget 100") to kwinrc [Script-mistletoe-edge] action when it
// loads, and this script invokes that shortcut through kglobalaccel.
function openDial() {
    const action = readConfig("action", "");
    if (!action) {
        return;
    }
    callDBus("org.kde.kglobalaccel", "/component/plasmashell",
             "org.kde.kglobalaccel.Component", "invokeShortcut", action);
}

registerScreenEdge(KWin.ElectricLeft, openDial);
