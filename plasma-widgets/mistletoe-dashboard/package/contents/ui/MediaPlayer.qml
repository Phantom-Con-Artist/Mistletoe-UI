/*
    Media player (loaded by MediaCard only while it is open): YouTube and
    YouTube Music in a Mistletoe frame.

    A web view (persistent profile, so a sign-in survives restarts) with
    Mistletoe controls that drive the page's own <video> element: play or
    pause, jump 10 s, seek along a gold hairline, volume, and theatre mode
    (hides the chrome). Search goes to whichever service is selected. Pin
    the card and it floats above your windows while it keeps playing.
*/
import QtQuick
import QtQuick.Layouts
import QtWebEngine
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

ColumnLayout {
    id: card

    required property var dash
    signal closeRequested()

    spacing: 10

    // ---- State read back from the page -----------------------------------
    property bool playing: false
    property bool hasMedia: false
    property real position: 0
    property real duration: 0
    property real volume: 1
    property bool muted: false
    property string nowPlaying: ""
    property bool theatre: false
    readonly property bool music: web.url.toString().indexOf("music.youtube.com") >= 0

    function clock(s) {
        s = Math.max(0, Math.floor(s || 0));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60;
        const mm = h > 0 ? String(m).padStart(2, "0") : String(m);
        return (h > 0 ? h + ":" : "") + mm + ":" + String(sec).padStart(2, "0");
    }

    // One call to the page per action; `v` is the page's main media element.
    function page(js, done) {
        web.runJavaScript("(function(){ const v = document.querySelector('video, audio'); " + js + " })()",
                          done || (() => {}));
    }
    function togglePlay() {
        page("if (v) { v.paused ? v.play() : v.pause(); }");
    }
    function jump(sec) {
        page("if (v) { v.currentTime = Math.max(0, v.currentTime + (" + sec + ")); }");
    }
    function seekTo(fraction) {
        page("if (v && v.duration) { v.currentTime = v.duration * " + fraction + "; }");
    }
    function setVolume(x) {
        page("if (v) { v.muted = false; v.volume = " + Math.max(0, Math.min(1, x)) + "; }");
    }
    function toggleMute() {
        page("if (v) { v.muted = !v.muted; }");
    }
    function search(text) {
        const q = encodeURIComponent(text.trim());
        if (!q) {
            return;
        }
        web.url = card.music ? "https://music.youtube.com/search?q=" + q
                             : "https://www.youtube.com/results?search_query=" + q;
    }

    Timer {
        interval: 500
        running: web.visible
        repeat: true
        onTriggered: card.page("return v ? [!v.paused, v.currentTime, v.duration || 0, v.volume, v.muted, document.title] : null;",
            (r) => {
                card.hasMedia = !!r;
                if (r) {
                    card.playing = r[0];
                    card.position = r[1];
                    card.duration = isFinite(r[2]) ? r[2] : 0;
                    card.volume = r[3];
                    card.muted = r[4];
                    card.nowPlaying = String(r[5] || "").replace(/ - YouTube( Music)?$/, "").replace(/^\(\d+\)\s*/, "");
                }
            })
    }

    // ---- Header: service tabs and search ---------------------------------
    RowLayout {
        Layout.fillWidth: true
        visible: !card.theatre
        spacing: 12

        Repeater {
            model: [
                { name: i18n("YouTube"), url: "https://www.youtube.com/", music: false },
                { name: i18n("Music"), url: "https://music.youtube.com/", music: true }
            ]
            Text {
                required property var modelData
                readonly property bool current: modelData.music === card.music
                text: modelData.name.toUpperCase()
                color: current ? card.dash.gold : card.dash.tint(card.dash.bone, 0.5)
                font.family: "Exo 2"
                font.pixelSize: 10
                font.letterSpacing: 2.5
                font.weight: current ? Font.DemiBold : Font.Normal
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: web.url = modelData.url
                }
            }
        }

        // Search: a small shard field.
        Item {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 0
            implicitHeight: 26
            Shard {
                anchors.fill: parent
                cut: 7
                fill: card.dash.tint(card.dash.bone, 0.05)
                rim: query.activeFocus ? card.dash.gold : card.dash.tint(card.dash.bone, 0.14)
            }
            TextInput {
                id: query
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: card.dash.bone
                selectionColor: card.dash.gold
                selectedTextColor: card.dash.ink
                font.family: "Exo 2"
                font.pixelSize: 12
                onAccepted: {
                    card.search(text);
                    text = "";
                }
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: !query.text && !query.activeFocus
                    text: card.music ? i18n("Search songs, artists…") : i18n("Search YouTube…")
                    color: card.dash.tint(card.dash.bone, 0.4)
                    font: query.font
                }
            }
        }

        // Close: unloads the player entirely (stops playback, frees memory).
        MouseArea {
            implicitWidth: 22
            implicitHeight: 22
            Layout.rightMargin: 30   // clear of the pin
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.closeRequested()
            Gem {
                anchors.fill: parent
                fill: "transparent"
                rim: parent.containsMouse ? card.dash.gold : card.dash.tint(card.dash.bone, 0.3)
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: 10
                height: 10
                source: "window-close"
                isMask: true
                color: parent.containsMouse ? card.dash.gold : card.dash.bone
                animated: false
            }
        }
    }

    // ---- The page ----------------------------------------------------------
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        WebEngineView {
            id: web
            anchors.fill: parent
            url: Plasmoid.configuration.mediaUrl || "https://www.youtube.com/"
            backgroundColor: card.dash.ink
            // Persistent profile: cookies and cache survive restarts, so a
            // sign-in sticks. (WebEngineProfilePrototype, the 6.9 replacement,
            // segfaults inside plasmashell here, so this form stays.)
            profile: WebEngineProfile {
                storageName: "mistletoe-media"
                offTheRecord: false
                persistentCookiesPolicy: WebEngineProfile.AllowPersistentCookies
                httpCacheType: WebEngineProfile.DiskHttpCache
            }
            settings.playbackRequiresUserGesture: false
            settings.showScrollBars: false
            // Remember where you were, but not every intermediate page.
            onLoadingChanged: (request) => {
                if (request.status === WebEngineView.LoadSucceededStatus) {
                    Plasmoid.configuration.mediaUrl = url.toString();
                }
            }
            // Links that want a new window open in the same view.
            onNewWindowRequested: (request) => web.url = request.requestedUrl
            // YouTube's own fullscreen button becomes theatre mode.
            onFullScreenRequested: (request) => {
                card.theatre = request.toggleOn;
                request.accept();
            }
        }
    }

    // ---- Transport -----------------------------------------------------------
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: card.hasMedia || !card.theatre

        // Seek hairline: bone track, gold progress; click or drag to seek.
        Item {
            Layout.fillWidth: true
            implicitHeight: 12
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: card.dash.tint(card.dash.bone, 0.2)
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * (card.duration > 0 ? card.position / card.duration : 0)
                height: seekMouse.containsMouse ? 3 : 2
                color: card.dash.gold
            }
            MouseArea {
                id: seekMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: card.duration > 0
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => card.seekTo(mouse.x / width)
                onPositionChanged: (mouse) => {
                    if (pressed) {
                        card.seekTo(Math.max(0, Math.min(1, mouse.x / width)));
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { icon: "go-previous", tip: i18n("Back"), act: () => web.goBack(), on: web.canGoBack },
                    { icon: "media-seek-backward", tip: i18n("Back 10 s"), act: () => card.jump(-10), on: card.hasMedia },
                    { icon: card.playing ? "media-playback-pause" : "media-playback-start", tip: i18n("Play / pause"),
                      act: () => card.togglePlay(), on: card.hasMedia, big: true },
                    { icon: "media-seek-forward", tip: i18n("Forward 10 s"), act: () => card.jump(10), on: card.hasMedia }
                ]
                MouseArea {
                    id: button
                    required property var modelData
                    implicitWidth: modelData.big ? 32 : 26
                    implicitHeight: implicitWidth
                    enabled: modelData.on
                    opacity: enabled ? 1 : 0.35
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.act()
                    Gem {
                        anchors.fill: parent
                        fill: button.modelData.big ? card.dash.gold : "transparent"
                        rim: button.containsMouse || button.modelData.big ? card.dash.gold : card.dash.tint(card.dash.bone, 0.3)
                    }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: button.modelData.big ? 14 : 11
                        height: width
                        source: button.modelData.icon
                        isMask: true
                        color: button.modelData.big ? card.dash.ink : button.containsMouse ? card.dash.gold : card.dash.bone
                        animated: false
                    }
                }
            }

            // Title and time.
            Column {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: card.nowPlaying || (card.music ? i18n("YouTube Music") : i18n("YouTube"))
                    color: card.dash.bone
                    font.family: "Exo 2"
                    font.pixelSize: 12
                }
                Text {
                    visible: card.duration > 0
                    text: card.clock(card.position) + "  /  " + card.clock(card.duration)
                    color: card.dash.tint(card.dash.bone, 0.55)
                    font.family: "Exo 2"
                    font.pixelSize: 10
                    font.features: { "tnum": 1 }
                }
            }

            // Volume: speaker toggles mute, the wheel or a drag sets the level.
            MouseArea {
                implicitWidth: 26
                implicitHeight: 26
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: card.toggleMute()
                onWheel: (wheel) => card.setVolume(card.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    source: card.muted || card.volume === 0 ? "audio-volume-muted"
                        : card.volume < 0.34 ? "audio-volume-low" : card.volume < 0.67 ? "audio-volume-medium" : "audio-volume-high"
                    isMask: true
                    color: parent.containsMouse ? card.dash.gold : card.dash.bone
                    animated: false
                }
            }
            Item {
                implicitWidth: 56
                implicitHeight: 26
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 1
                    color: card.dash.tint(card.dash.bone, 0.2)
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * (card.muted ? 0 : card.volume)
                    height: 2
                    color: card.dash.gold
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: (mouse) => card.setVolume(mouse.x / width)
                    onPositionChanged: (mouse) => card.setVolume(mouse.x / width)
                    onWheel: (wheel) => card.setVolume(card.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
                }
            }

            // Theatre: hide the header and let the page fill the card.
            MouseArea {
                implicitWidth: 26
                implicitHeight: 26
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: card.theatre = !card.theatre
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    source: card.theatre ? "view-restore" : "view-fullscreen"
                    isMask: true
                    color: parent.containsMouse || card.theatre ? card.dash.gold : card.dash.bone
                    animated: false
                }
            }
        }
    }
}
