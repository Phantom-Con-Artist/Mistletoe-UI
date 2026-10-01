/*
    Mistletoe Status: a corner clock that opens a fullscreen, transparent
    overlay where a large analog dial and status tiles bloom radially.

    Tiles: Bluetooth, network, volume, media, notifications, settings.
    Left-click acts, right-click opens the matching settings page, and the
    wheel adjusts the volume. An outer rail of gems holds the power
    actions (lock, sleep, restart, shut down, log out).
*/
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils
import org.kde.bluezqt as BluezQt
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.plasma.private.volume
import org.kde.plasma.private.mpris as Mpris
import org.kde.plasma.private.sessions as Sessions
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    property Item button: null
    property date now: new Date()

    // The button is the *full* representation, shown inline: with a null
    // full representation Plasma never instantiates a compact one. This
    // is the same arrangement Plasma's Application Dashboard uses.
    preferredRepresentation: fullRepresentation
    compactRepresentation: null
    fullRepresentation: ClockButton {
        id: cornerButton
        time: root.now
        open: overlay.visible
        indicators: [
            { icon: root.netIcon, label: root.netOn ? root.netValue : i18n("Offline"), on: root.netOn },
            { icon: root.btOn ? "network-bluetooth-activated-symbolic" : "network-bluetooth-inactive-symbolic",
              label: root.btOn ? (root.bt.connectedDevices.length > 0 ? root.bt.connectedDevices[0].name : i18n("On")) : i18n("Off"),
              on: root.btOn }
        ]
        onClicked: root.toggle()
        Component.onCompleted: root.button = cornerButton
    }
    activationTogglesExpanded: false
    toolTipMainText: Qt.formatDate(now, Qt.locale().dateFormat(Locale.LongFormat))
    toolTipSubText: Qt.formatTime(now, Qt.locale().timeFormat(Locale.ShortFormat))

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    // ---- Bluetooth ------------------------------------------------------
    readonly property var bt: BluezQt.Manager
    readonly property bool btOn: bt.operational && bt.bluetoothOperational && !bt.bluetoothBlocked
    readonly property string btValue: {
        if (!bt.operational || bt.adapters.length === 0) {
            return i18n("Unavailable");
        }
        if (!btOn) {
            return i18n("Off");
        }
        const n = bt.connectedDevices.length;
        return n === 0 ? i18n("On") : bt.connectedDevices[0].name + (n > 1 ? "  +" + (n - 1) : "");
    }

    function toggleBluetooth() {
        const enable = !btOn;
        bt.bluetoothBlocked = !enable;
        for (let i = 0; i < bt.adapters.length; ++i) {
            bt.adapters[i].powered = enable;
        }
    }

    // ---- Network --------------------------------------------------------
    PlasmaNM.NetworkStatus {
        id: network
    }
    // activeConnections reads like "Wi-Fi: Connected to Home\nWired: ...".
    readonly property string netLine: (network.activeConnections || "").split("\n")[0]
    readonly property bool netOn: netLine.indexOf(":") > 0
    readonly property string netValue: netOn
        ? netLine.substring(netLine.indexOf(":") + 1).trim().replace(/^Connected to /, "")
        : i18n("Disconnected")
    readonly property string netIcon: !netOn ? "network-offline-symbolic"
        : /wi-?fi|wireless/i.test(netLine) ? "network-wireless-symbolic" : "network-wired-symbolic"

    // ---- Volume ---------------------------------------------------------
    readonly property var sink: PreferredDevice.sink
    readonly property int volumePercent: sink ? Math.round(sink.volume / PulseAudio.NormalVolume * 100) : 0
    readonly property string volumeIcon: !sink || sink.muted || volumePercent === 0 ? "audio-volume-muted-symbolic"
        : volumePercent < 34 ? "audio-volume-low-symbolic"
        : volumePercent < 67 ? "audio-volume-medium-symbolic" : "audio-volume-high-symbolic"

    function stepVolume(direction) {
        if (!sink) {
            return;
        }
        const stepSize = PulseAudio.NormalVolume * 0.05;
        sink.volume = Math.max(PulseAudio.MinimalVolume,
                               Math.min(PulseAudio.NormalVolume * 1.5, sink.volume + direction * stepSize));
        if (direction > 0 && sink.muted) {
            sink.muted = false;
        }
    }

    // ---- Media ----------------------------------------------------------
    Mpris.Mpris2Model {
        id: mpris
    }
    readonly property var player: mpris.currentPlayer
    readonly property bool playing: !!player && player.playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property string mediaValue: !player ? i18n("Nothing playing")
        : [player.artist, player.track].filter(s => s && s.length > 0).join(" — ") || player.identity

    // ---- Notifications --------------------------------------------------
    // Popups and history stay with Plasma's notifications applet (in the
    // strip's tray); the fan shows the unread count and owns Do Not Disturb.
    NotificationManager.Settings {
        id: notificationSettings
    }
    NotificationManager.Notifications {
        id: notifications
        showExpired: true
        showDismissed: true
        showJobs: false
        showNotifications: true
        // Remembered across restarts so old history doesn't count as unread.
        lastRead: Plasmoid.configuration.lastRead ? new Date(Plasmoid.configuration.lastRead) : new Date(0)
    }

    function markAllRead() {
        Plasmoid.configuration.lastRead = new Date().toISOString();
    }
    readonly property bool dnd: notificationSettings.notificationsInhibitedUntil > now
    readonly property int unread: notifications.unreadNotificationsCount

    function toggleDoNotDisturb() {
        if (dnd) {
            notificationSettings.notificationsInhibitedUntil = undefined; // reset
            notificationSettings.revokeApplicationInhibitions();
        } else {
            const until = new Date();
            until.setFullYear(until.getFullYear() + 1);
            notificationSettings.notificationsInhibitedUntil = until;
        }
        notificationSettings.save();
    }

    // ---- Settings ------------------------------------------------------------
    // The Settings tile opens the Mistletoe dial in Settings mode (it records
    // its shortcut in mistletoerc); without a dial, plain System Settings.
    P5Support.DataSource {
        id: shell
        engine: "executable"
        onNewData: (source) => disconnectSource(source)
    }
    function openSettings() {
        shell.connectSource("a=$(kreadconfig6 --file mistletoerc --group Dial --key action); "
            + "if [ -n \"$a\" ]; then kwriteconfig6 --file mistletoerc --group Dial --key nextMode Settings"
            + " && qdbus org.kde.kglobalaccel /component/plasmashell org.kde.kglobalaccel.Component.invokeShortcut \"$a\"; "
            + "else systemsettings; fi #" + Date.now());
    }

    // ---- Session --------------------------------------------------------
    Sessions.SessionManagement {
        id: session
    }

    readonly property var powers: [
        { id: "lock", icon: "system-lock-screen-symbolic", label: i18n("Lock") },
        { id: "suspend", icon: "system-suspend-symbolic", label: i18n("Sleep") },
        { id: "reboot", icon: "system-reboot-symbolic", label: i18n("Restart") },
        { id: "shutdown", icon: "system-shutdown-symbolic", label: i18n("Shut down") },
        { id: "logout", icon: "system-log-out-symbolic", label: i18n("Log out") }
    ].filter(p => p.id !== "suspend" || session.canSuspend)

    // Restart, shut down and log out go through Plasma's confirmation.
    function power(id) {
        fan.close();
        switch (id) {
        case "lock": session.lock(); break;
        case "suspend": session.suspend(); break;
        case "reboot": session.requestReboot(); break;
        case "shutdown": session.requestShutdown(); break;
        case "logout": session.requestLogout(); break;
        }
    }

    readonly property var tiles: [
        { id: "bluetooth", icon: btOn ? "network-bluetooth-activated-symbolic" : "network-bluetooth-inactive-symbolic",
          label: i18n("Bluetooth"), value: btValue, on: btOn,
          hint: i18n("Click to toggle  ·  right-click for devices") },
        { id: "network", icon: netIcon, label: i18n("Network"), value: netValue, on: netOn,
          hint: i18n("Click for network settings") },
        { id: "volume", icon: volumeIcon, label: i18n("Volume"),
          value: sink ? (sink.muted ? i18n("Muted") : volumePercent + "%") : i18n("No output"),
          on: !!sink && !sink.muted, wheel: true,
          hint: i18n("Scroll to adjust  ·  click to mute") },
        { id: "media", icon: playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic",
          label: player ? player.identity : i18n("Media"), value: mediaValue, on: playing, wheel: !!player,
          hint: player ? i18n("Click to play or pause  ·  scroll to skip  ·  right-click to show") : "" },
        { id: "notifications", icon: dnd ? "notifications-disabled-symbolic" : "notification-active-symbolic",
          label: i18n("Notifications"),
          value: dnd ? i18n("Do not disturb") : unread > 0 ? i18np("%1 unread", "%1 unread", unread) : i18n("All caught up"),
          on: !dnd && unread > 0,
          hint: i18n("Click for Do Not Disturb  ·  right-click to mark all read") },
        { id: "settings", icon: "configure-symbolic", label: i18n("System"), value: i18n("Settings"),
          hint: i18n("Click for the settings dial  ·  right-click for System Settings"),
          on: false }
    ]

    function act(id) {
        switch (id) {
        case "bluetooth": toggleBluetooth(); return;
        case "network": KCMUtils.KCMLauncher.openSystemSettings("kcm_networkmanagement"); break;
        case "volume": if (sink) sink.muted = !sink.muted; return;
        case "media": if (player) player.PlayPause(); return;
        case "notifications": toggleDoNotDisturb(); return;
        case "settings": openSettings(); break;
        }
        fan.close();
    }

    function actAlt(id) {
        switch (id) {
        case "bluetooth": KCMUtils.KCMLauncher.openSystemSettings("kcm_bluetooth"); break;
        case "network": KCMUtils.KCMLauncher.openSystemSettings("kcm_networkmanagement"); break;
        case "volume": KCMUtils.KCMLauncher.openSystemSettings("kcm_pulseaudio"); break;
        case "media": if (player) player.Raise(); break;
        case "notifications": markAllRead(); return;
        case "settings": KCMUtils.KCMLauncher.openSystemSettings(""); break;
        default: return;
        }
        fan.close();
    }

    function wheel(id, direction) {
        if (id === "volume") {
            stepVolume(direction);
        } else if (id === "media" && player) {
            direction > 0 ? player.Previous() : player.Next();
        }
    }

    function toggle() {
        if (overlay.visible) {
            fan.close();
            return;
        }
        overlay.open();
        Qt.callLater(() => {
            if (button) {
                fan.origin = button.centerOnScreen();
            }
            fan.open();
        });
    }

    Connections {
        target: Plasmoid
        function onActivated() {
            root.toggle();
        }
    }

    Overlay {
        id: overlay

        anchorItem: root.button
        focusItem: fan
        onDeactivated: fan.close()

        StatusFan {
            id: fan
            anchors.fill: parent
            now: root.now
            tiles: root.tiles
            powers: root.powers
            onPowerClicked: (id) => root.power(id)
            onTileClicked: (id) => root.act(id)
            onTileAltClicked: (id) => root.actAlt(id)
            onTileWheel: (id, direction) => root.wheel(id, direction)
            onClosed: overlay.hide()
        }
    }
}
