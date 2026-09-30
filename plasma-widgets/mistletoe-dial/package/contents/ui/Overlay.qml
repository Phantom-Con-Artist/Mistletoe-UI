/*
    Fullscreen, transparent overlay window that hosts a fan.

    A plain window on purpose: kicker's DashboardWindow asks KWin to blur
    everything behind it, and Mistletoe wants a matte veil, not glass.
*/
import QtQuick
import QtQuick.Window
import org.kde.plasma.private.kicker as Kicker

Window {
    id: overlay

    // The overlay opens on this item's screen.
    property Item anchorItem: null
    // Receives focus once the window is active.
    property Item focusItem: null

    signal deactivated()

    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    title: "Mistletoe"

    function open() {
        const host = anchorItem ? anchorItem.Window.window : null;
        if (host && host.screen) {
            screen = host.screen;
        }
        showFullScreen();
        raise();
        requestActivate();
        if (focusItem) {
            windowSystem.forceActive(focusItem);
            focusItem.forceActiveFocus();
        }
    }

    onActiveChanged: {
        if (!active && visible) {
            deactivated();
        }
    }

    Kicker.WindowSystem {
        id: windowSystem
    }
}
