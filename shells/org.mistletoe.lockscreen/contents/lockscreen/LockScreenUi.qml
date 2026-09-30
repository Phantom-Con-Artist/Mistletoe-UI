/*
    Mistletoe lock screen: cinematic and quiet.

    The wallpaper stays (dimmed, never blurred). On the left, the day in
    Ad Astra small caps, the time large in Ad Astra, the date in Mythril.
    Low in the centre, one chamfered password shard with a gold hairline:
    it always has focus, so you can just start typing. A wrong password
    shakes the shard and shows the message beneath it. Sleep and Switch
    User gems appear, with the name and the hint, only while you're
    active, and fade after ten idle seconds.

    Uses kscreenlocker's context objects: authenticator (startAuthenticating,
    respond, failed/succeeded, messages) and kscreenlocker_userName.
*/
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.sessions
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator

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
        x: Math.round(ui.width * 0.07)
        y: Math.round(ui.height * 0.3)
        spacing: 0
        Text {
            text: Qt.formatDate(ui.now, "dddd").toUpperCase()
            color: ui.gold
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.6)
            font.family: "Mistletoe Display"
            font.pixelSize: Math.round(ui.height * 0.022)
            font.letterSpacing: Math.round(ui.height * 0.008)
        }
        Text {
            text: Qt.formatTime(ui.now, "hh:mm")
            color: ui.bone
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.6)
            font.family: "Mistletoe Display"
            font.pixelSize: Math.round(ui.height * 0.2)
        }
        Rectangle {
            width: parent.width * 0.62
            height: 1
            color: ui.tint(ui.gold, 0.8)
        }
        Text {
            topPadding: Math.round(ui.height * 0.014)
            text: Qt.formatDate(ui.now, "d MMMM yyyy")
            color: ui.tint(ui.bone, 0.85)
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.6)
            font.family: "Mistletoe Accent"
            font.pixelSize: Math.round(ui.height * 0.03)
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
                color: ui.gold
                font.family: "Mistletoe Display"
                font.pixelSize: 13
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
                color: ui.gold
                font.family: "Mistletoe Text"
                font.pixelSize: 13
            }
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
