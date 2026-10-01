/*
    Mistletoe lock screen: cinematic and quiet.

    The wallpaper stays (dimmed, never blurred). On the left, the clock as
    on the desktop: the time large in Ad Astra, a hairline that fills with
    gold through the minute, then the day and the date on one line.
    Low in the centre, one chamfered password shard with a gold hairline:
    it always has focus, so you can just start typing. A wrong password
    shakes the shard and shows the message beneath it. Sleep and Switch
    User gems appear, with the name and the hint, only while you're
    active, and fade after ten idle seconds. Top right, the branding:
    "Fedora Linux 44 using <mark> Mistletoe UI". Text straight on the
    wallpaper is black or white to suit what is behind it.

    Uses kscreenlocker's context objects: authenticator (startAuthenticating,
    respond, failed/succeeded, messages) and kscreenlocker_userName.
*/
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.sessions
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import "backdrop.js" as Backdrop

Item {
    id: ui

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
    readonly property color ink: Kirigami.Theme.backgroundColor
    readonly property color bone: Kirigami.Theme.textColor
    readonly property color gold: Kirigami.Theme.focusColor
    function tint(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // Text straight on the wallpaper is black or white, whichever reads
    // against what is behind it (measured by mistletoe-menu when the
    // wallpaper changes; see backdrop.js). No glows, no plates.
    readonly property color black: "#0b0c0e"
    readonly property color white: "#f4f1ea"
    // (Not named "ink": that is the theme background colour above, and the
    // clash made every call fail and the text fall back to black.)
    function textOn(onLight) {
        return onLight ? black : white;
    }
    function shadowOn(onLight) {
        return onLight ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(0, 0, 0, 0.6);
    }
    readonly property bool clockLight: Backdrop.clockOnLight
    readonly property bool promptLight: Backdrop.promptOnLight
    readonly property bool badgeLight: Backdrop.badgeOnLight

    // Shown while you're active; the clock is always there.
    property bool active: false
    property bool unlocked: false   // no-password sessions: show "Unlock"
    property string message: ""

    // Show the prompt. Authentication starts only when it appears (as in
    // Plasma's own lock screen): restarting it on every mouse move or key
    // aborted PAM's conversation mid-password.
    function wake() {
        idle.restart();
        if (!active) {
            active = true;
            authenticator.startAuthenticating();
        }
    }

    SessionManagement {
        id: session
    }
    KeyboardIndicator.KeyState {
        id: capsLock
        key: Qt.Key_CapsLock
    }

    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind !== 0) {
                return;   // fingerprint and other non-interactive methods
            }
            ui.message = i18nd("plasma_shell_org.kde.plasma.desktop", "Unlocking failed");
            password.text = "";
            shake.restart();
            graceLock.restart();
        }
        function onSucceeded() {
            if (authenticator.hadPrompt) {
                Qt.quit();
            } else {
                ui.unlocked = true;
            }
        }
        function onInfoMessageChanged() {
            ui.message = authenticator.infoMessage;
        }
        function onErrorMessageChanged() {
            ui.message = authenticator.errorMessage;
        }
        function onPromptForSecretChanged() {
            password.forceActiveFocus();
        }
    }
    Connections {
        target: root
        function onClearPassword() {
            password.text = "";
        }
    }

    Timer {
        id: idle
        interval: 10000
        onTriggered: if (!password.text) ui.active = false
    }
    // After a failure, a short pause before the next try.
    Timer {
        id: graceLock
        interval: 3000
        onTriggered: {
            ui.message = "";
            authenticator.startAuthenticating();
        }
    }

    Component.onCompleted: authenticator.startAuthenticating()

    // ---- Wallpaper veil: matte, deeper while active ---------------------
    Rectangle {
        anchors.fill: parent
        color: ui.ink
        opacity: ui.active ? 0.62 : 0.38
        Behavior on opacity {
            NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: ui.active ? Qt.ArrowCursor : Qt.BlankCursor
        property point last
        onPositionChanged: (mouse) => {
            // Ignore the synthetic move when the screen first appears.
            if (Math.abs(mouse.x - last.x) + Math.abs(mouse.y - last.y) > 3 && last.x !== 0) {
                ui.wake();
            }
            last = Qt.point(mouse.x, mouse.y);
        }
        onPressed: ui.wake()
    }

    // ---- Clock -------------------------------------------------------------
    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: ui.now = new Date()
    }

    Column {
        id: clockColumn
        x: Math.round(ui.width * 0.07)
        y: Math.round(ui.height * 0.3)
        spacing: 0
        // The same arrangement as the desktop clock: the time, a hairline
        // that fills with gold as the minute passes, then the day and date
        // on one line.
        Text {
            id: clockTime
            text: Qt.formatTime(ui.now, "hh:mm")
            color: ui.textOn(ui.clockLight)
            style: Text.Raised
            styleColor: ui.shadowOn(ui.clockLight)
            font.family: "Mistletoe Display"
            font.pixelSize: Math.round(ui.height * 0.2)
        }
        Item {
            width: clockTime.width
            height: 1
            Rectangle {
                anchors.fill: parent
                color: ui.tint(ui.textOn(ui.clockLight), 0.22)
            }
            Rectangle {
                width: parent.width * ui.now.getSeconds() / 59
                height: 2
                y: -0.5
                color: ui.gold
                Behavior on width {
                    enabled: ui.now.getSeconds() !== 0
                    NumberAnimation { duration: 900; easing.type: Easing.OutCubic }
                }
            }
        }
        Row {
            topPadding: Math.round(ui.height * 0.016)
            spacing: Math.round(ui.height * 0.012)
            Text {
                anchors.baseline: clockDate.baseline
                text: Qt.formatDate(ui.now, "dddd").toUpperCase()
                color: ui.textOn(ui.clockLight)
                style: Text.Raised
                styleColor: ui.shadowOn(ui.clockLight)
                font.family: "Mistletoe Display"
                font.pixelSize: Math.round(ui.height * 0.02)
                font.letterSpacing: Math.round(ui.height * 0.005)
            }
            Rectangle {
                anchors.verticalCenter: clockDate.verticalCenter
                width: Math.max(5, Math.round(ui.height * 0.007))
                height: width
                rotation: 45
                color: ui.gold
            }
            Text {
                id: clockDate
                text: Qt.formatDate(ui.now, "d MMMM yyyy")
                color: ui.textOn(ui.clockLight)
                style: Text.Raised
                styleColor: ui.shadowOn(ui.clockLight)
                font.family: "Mistletoe Accent"
                font.pixelSize: Math.round(ui.height * 0.03)
            }
        }
    }

    // ---- Password shard -------------------------------------------------------
    Item {
        id: prompt
        readonly property real w: Math.round(Math.min(420, ui.width * 0.8))
        x: (ui.width - w) / 2
        y: Math.round(ui.height * 0.68)
        width: w
        height: column.height
        opacity: ui.active || password.text ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }

        // A short horizontal shake on failure.
        transform: Translate { id: shakeX }
        SequentialAnimation {
            id: shake
            loops: 1
            NumberAnimation { target: shakeX; property: "x"; to: -14; duration: 50 }
            NumberAnimation { target: shakeX; property: "x"; to: 12; duration: 70 }
            NumberAnimation { target: shakeX; property: "x"; to: -8; duration: 60 }
            NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 60 }
        }

        Column {
            id: column
            width: parent.width
            spacing: 14

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: String(kscreenlocker_userName || "").toUpperCase()
                color: ui.textOn(ui.promptLight)
                style: Text.Raised
                styleColor: ui.shadowOn(ui.promptLight)
                font.family: "Mistletoe Display"
                font.pixelSize: 14
                font.letterSpacing: 4
            }

            Item {
                width: parent.width
                height: 54
                visible: !ui.unlocked
                Shard {
                    anchors.fill: parent
                    cut: 14
                    fill: ui.tint(ui.ink, 0.9)
                    rim: password.activeFocus ? ui.gold : ui.tint(ui.bone, 0.2)
                }
                TextInput {
                    id: password
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "◆"
                    color: ui.gold
                    selectionColor: ui.gold
                    selectedTextColor: ui.ink
                    font.family: "Mistletoe Display"
                    font.pixelSize: 16
                    font.letterSpacing: 6
                    focus: true
                    enabled: !graceLock.running
                    // Typing anywhere lands here and wakes the screen.
                    onTextChanged: ui.wake()
                    onAccepted: {
                        if (text.length > 0) {
                            authenticator.respond(text);
                        }
                    }
                    Keys.onEscapePressed: {
                        text = "";
                        ui.active = false;
                    }
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        visible: !password.text
                        text: graceLock.running ? i18n("One moment…") : i18n("Password")
                        color: ui.tint(ui.bone, 0.45)
                        font.family: "Mistletoe Accent"
                        font.pixelSize: 17
                    }
                }
            }

            // No-password session: a single Unlock shard.
            MouseArea {
                width: parent.width
                height: 54
                visible: ui.unlocked
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.quit()
                Shard {
                    anchors.fill: parent
                    cut: 14
                    fill: ui.gold
                    rim: ui.gold
                }
                Text {
                    anchors.centerIn: parent
                    text: i18n("UNLOCK")
                    color: ui.ink
                    font.family: "Mistletoe Display"
                    font.pixelSize: 15
                    font.letterSpacing: 4
                }
            }

            // Messages: failures, fingerprint prompts, Caps Lock.
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: [capsLock.locked ? i18n("Caps Lock is on") : "", ui.message].filter(s => s).join("  ·  ")
                color: ui.textOn(ui.promptLight)
                style: Text.Raised
                styleColor: ui.shadowOn(ui.promptLight)
                font.family: "Mistletoe Text"
                font.pixelSize: 13
            }
        }
    }

    // ---- Branding, top right: "Fedora Linux 44 using <mark> Mistletoe UI" ----
    Row {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: Math.round(ui.height * 0.045)
        anchors.topMargin: Math.round(ui.height * 0.035)
        spacing: 8
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String(Backdrop.distro || "Fedora Linux").toUpperCase()
            color: ui.tint(ui.textOn(ui.badgeLight), 0.8)
            style: Text.Raised
            styleColor: ui.shadowOn(ui.badgeLight)
            font.family: "Mistletoe Display"
            font.pixelSize: 11
            font.letterSpacing: 2
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: i18n("using")
            color: ui.tint(ui.textOn(ui.badgeLight), 0.6)
            style: Text.Raised
            styleColor: ui.shadowOn(ui.badgeLight)
            font.family: "Mistletoe Accent"
            font.pixelSize: 13
        }
        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            sourceSize: Qt.size(44, 44)
            source: Qt.resolvedUrl("mistletoe-mark.svg")
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.StyledText
            text: "Mistletoe <font color=\"" + ui.gold + "\">UI</font>"
            color: ui.textOn(ui.badgeLight)
            style: Text.Raised
            styleColor: ui.shadowOn(ui.badgeLight)
            font.family: "Mistletoe Text"
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }

    // ---- Session gems, bottom right -----------------------------------------------
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Math.round(ui.height * 0.05)
        spacing: 18
        opacity: ui.active ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 320 }
        }
        Repeater {
            model: [
                { icon: "system-suspend", label: i18n("Sleep"), on: session.canSuspend, act: () => session.suspend() },
                { icon: "system-switch-user", label: i18n("Switch user"), on: session.canSwitchUser, act: () => session.switchUser() }
            ]
            MouseArea {
                id: gemButton
                required property var modelData
                visible: modelData.on
                width: 78
                height: 62
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: modelData.act()
                Shard {
                    // A diamond: a square shard rotated.
                    width: 30
                    height: 30
                    x: (parent.width - width) / 2
                    y: 4
                    rotation: 45
                    cut: 1   // never 0: a zero cut is degenerate geometry
                    fill: gemButton.containsMouse ? ui.gold : ui.tint(ui.ink, 0.85)
                    rim: gemButton.containsMouse ? ui.gold : ui.tint(ui.bone, 0.4)
                }
                Kirigami.Icon {
                    x: (parent.width - width) / 2
                    y: 11
                    width: 16
                    height: 16
                    source: gemButton.modelData.icon
                    isMask: true
                    color: gemButton.containsMouse ? ui.ink : ui.bone
                    animated: false
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    text: gemButton.modelData.label.toUpperCase()
                    color: gemButton.containsMouse ? ui.gold : ui.tint(ui.bone, 0.6)
                    font.family: "Mistletoe Display"
                    font.pixelSize: 9
                    font.letterSpacing: 1.5
                }
            }
        }
    }
}
