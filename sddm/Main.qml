// SDDM backend for the existing Mistletoe lock screen presentation.
import QtQuick
import QtQml.Models
import "settings.js" as Settings

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: Settings.ink

    readonly property color ink: Settings.ink
    readonly property color bone: Settings.bone
    readonly property color gold: Settings.gold
    readonly property string displayFont: displayFontLoader.name
    readonly property string accentFont: accentFontLoader.name
    readonly property string textFont: textFontLoader.name
    readonly property bool capsLocked: keyboard.capsLock
    readonly property bool canSuspend: sddm.canSuspend
    property string username: userModel.lastUser || Settings.defaultUser
    property int sessionIndex: Math.max(0, sessionModel.lastIndex)
    property bool selectingUser: false
    readonly property string userLabel: {
        for (let i = 0; i < users.count; ++i) {
            const user = users.objectAt(i);
            if (user && user.name === username) return user.realName || user.name;
        }
        return username;
    }
    signal clearPassword()

    FontLoader { id: displayFontLoader; source: Qt.resolvedUrl(Settings.displayFont) }
    FontLoader { id: accentFontLoader; source: Qt.resolvedUrl(Settings.accentFont) }
    FontLoader { id: textFontLoader; source: Qt.resolvedUrl(Settings.textFont) }

    Instantiator {
        id: users
        model: userModel
        delegate: QtObject {
            required property string name
            required property string realName
        }
    }

    // Match the locker's conversation interface. SDDM starts authentication
    // only on submit; its native loginSucceeded signal closes the greeter.
    readonly property QtObject authenticator: QtObject {
        property bool busy: false
        property bool hadPrompt: true
        property string infoMessage: ""
        property string errorMessage: ""
        signal failed(int kind)
        signal succeeded()
        signal promptForSecretChanged()
        function startAuthenticating() {}
        function respond(secret) {
            if (busy || !root.username) return;
            busy = true;
            sddm.login(root.username, secret, root.sessionIndex);
        }
    }
    Connections {
        target: sddm
        function onLoginFailed() {
            root.authenticator.busy = false;
            root.authenticator.failed(0);
        }
        function onInformationMessage(message) {
            root.authenticator.infoMessage = message;
        }
    }

    function suspend() { sddm.suspend(); }
    function chooseUser() {
        if (authenticator.busy) return;
        clearPassword();
        selectingUser = true;
        otherUser.text = username;
        otherUser.forceActiveFocus();
    }
    function selectUser(name) {
        username = name;
        selectingUser = false;
        authenticator.infoMessage = "";
        authenticator.errorMessage = "";
        clearPassword();
        authenticator.promptForSecretChanged();
        loginUi.wake();
    }

    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("wallpaper.png")
        fillMode: Image.PreserveAspectCrop
    }
    LockScreenUi {
        id: loginUi
        anchors.fill: parent
        greeter: root
        enabled: !root.selectingUser
    }

    // The existing Switch User gem opens this picker. It is absent from the
    // normal login view, keeping the clock, prompt and gems in their places.
    FocusScope {
        visible: root.selectingUser
        focus: visible
        x: (parent.width - width) / 2
        y: Math.round(parent.height * 0.45)
        width: Math.round(Math.min(420, parent.width * 0.8))
        height: choices.height
        Keys.onEscapePressed: root.selectUser(root.username)
        Column {
            id: choices
            width: parent.width
            spacing: 14
            Repeater {
                model: userModel
                delegate: MouseArea {
                    required property string name
                    required property string realName
                    width: choices.width
                    height: 54
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectUser(name)
                    Shard {
                        anchors.fill: parent
                        cut: 14
                        fill: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.9)
                        rim: parent.containsMouse ? root.gold : root.bone
                    }
                    Text {
                        anchors.centerIn: parent
                        text: (parent.realName || parent.name).toUpperCase()
                        color: root.gold
                        font.family: root.displayFont
                        font.pixelSize: 14
                        font.letterSpacing: 4
                    }
                }
            }
            Item {
                width: choices.width
                height: 54
                Shard {
                    anchors.fill: parent
                    cut: 14
                    fill: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.9)
                    rim: otherUser.activeFocus ? root.gold : root.bone
                }
                TextInput {
                    id: otherUser
                    anchors.fill: parent
                    anchors.margins: 16
                    color: root.gold
                    font.family: root.textFont
                    font.pixelSize: 16
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    onAccepted: if (text.trim()) root.selectUser(text.trim())
                }
            }
            Repeater {
                model: sessionModel.count > 1 ? sessionModel : null
                delegate: MouseArea {
                    required property int index
                    required property string name
                    width: choices.width
                    height: 40
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sessionIndex = index
                    Shard {
                        anchors.fill: parent
                        cut: 10
                        fill: root.ink
                        rim: root.sessionIndex === parent.index ? root.gold : root.bone
                    }
                    Text {
                        anchors.centerIn: parent
                        text: parent.name
                        color: root.bone
                        font.family: root.textFont
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
