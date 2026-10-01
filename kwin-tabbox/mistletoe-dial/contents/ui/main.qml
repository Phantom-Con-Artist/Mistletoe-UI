/*
    Mistletoe Dial: a rotary window switcher (Alt+Tab).

    The windows ride a dial as icon cells. The chosen one rests at the stop
    at the top; each Tab turns the dial one detent, bringing the next window
    up to it, and the dial is a loop, so it wraps. The middle shows the
    chosen window itself, with its title underneath.

    This runs inside KWin, so it draws with plain rectangles only: a Shape
    with bad geometry can hang the renderer, and here that would freeze the
    whole session rather than one widget.
*/
import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.kwin as KWin
import org.kde.kirigami as Kirigami

KWin.TabBoxSwitcher {
    id: tabBox

    Instantiator {
        active: tabBox.visible
        delegate: PlasmaCore.Dialog {
            location: PlasmaCore.Types.Floating
            visible: true
            flags: Qt.Popup | Qt.X11BypassWindowManagerHint
            backgroundHints: PlasmaCore.Dialog.NoBackground
            x: tabBox.screenGeometry.x + (tabBox.screenGeometry.width - dial.width) / 2
            y: tabBox.screenGeometry.y + (tabBox.screenGeometry.height - dial.height) / 2

            mainItem: FocusScope {
                id: dial

                focus: true

                Kirigami.Theme.colorSet: Kirigami.Theme.Window
                Kirigami.Theme.inherit: false
                readonly property color ink: Kirigami.Theme.backgroundColor
                readonly property color bone: Kirigami.Theme.textColor
                readonly property color gold: Kirigami.Theme.focusColor
                function tint(c, a) {
                    return Qt.rgba(c.r, c.g, c.b, a);
                }

                // ---- Geometry ---------------------------------------------
                readonly property real unit: Math.max(0.7, Math.min(1.2, tabBox.screenGeometry.height / 1080))
                readonly property real radius: Math.round(250 * unit)
                readonly property real cell: Math.round(52 * unit)
                readonly property int count: cells.count
                // The windows are spread evenly round the whole dial, so it is
                // balanced however many there are.
                readonly property real step: 360 / Math.max(1, count)

                width: 2 * (radius + cell)
                height: width

                // ---- The dial's turn --------------------------------------------
                // Unwrapped position in steps, eased; it follows the chosen
                // window the short way round.
                property real pos: 0
                property real target: 0
                readonly property int chosen: tabBox.currentIndex
                function follow(animate) {
                    const n = Math.max(1, count);
                    const at = ((Math.round(target) % n) + n) % n;
                    let d = (((chosen - at) % n) + n) % n;
                    if (d > n / 2) {
                        d -= n;
                    }
                    target = Math.round(target) + d;
                    if (animate) {
                        spin.to = target;
                        spin.restart();
                    } else {
                        spin.stop();
                        pos = target;
                    }
                }
                onChosenChanged: follow(true)
                onCountChanged: follow(false)
                Component.onCompleted: follow(false)
                NumberAnimation {
                    id: spin
                    target: dial; property: "pos"
                    duration: 220
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.1
                }

                function step_(direction) {
                    const n = Math.max(1, count);
                    tabBox.currentIndex = (tabBox.currentIndex + direction + n) % n;
                }
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                        step_(-1);
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                        step_(1);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                // ---- Face ------------------------------------------------------
                // Matte disc, hairline orbit, and the fixed stop at the top.
                Rectangle {
                    anchors.centerIn: parent
                    width: 2 * (dial.radius + dial.cell * 0.9)
                    height: width
                    radius: width / 2
                    color: dial.tint(dial.ink, 0.98)
                    border.width: 1
                    border.color: dial.tint(dial.bone, 0.12)
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 2 * dial.radius
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: dial.tint(dial.gold, 0.4)
                }
                Rectangle {
                    width: 2
                    height: Math.round(10 * dial.unit)
                    x: Math.round(dial.width / 2 - 1)
                    y: Math.round(dial.height / 2 - dial.radius - dial.cell / 2 - height - 6)
                    color: dial.gold
                }

                // Scrolling turns the dial too.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: (wheel) => dial.step_((wheel.angleDelta.y || wheel.angleDelta.x) > 0 ? -1 : 1)
                }

                // ---- Windows -------------------------------------------------------
                Repeater {
                    id: cells
                    model: tabBox.model
                    delegate: Item {
                        id: entry

                        required property int index
                        required property var model

                        readonly property bool isChosen: dial.chosen === index
                        readonly property real n: Math.max(1, dial.count)
                        // Steps from the stop, the short way round.
                        readonly property real p: {
                            const d = index - dial.pos + n / 2;
                            return ((d % n) + n) % n - n / 2;
                        }
                        readonly property real angle: p * dial.step * Math.PI / 180

                        anchors.fill: parent

                        // The cell on the orbit.
                        MouseArea {
                            id: cellMouse
                            width: dial.cell
                            height: dial.cell
                            x: Math.round(dial.width / 2 + dial.radius * Math.sin(entry.angle) - width / 2)
                            y: Math.round(dial.height / 2 - dial.radius * Math.cos(entry.angle) - height / 2)
                            hoverEnabled: true
                            onClicked: tabBox.model.activate(entry.index)
                            scale: entry.isChosen ? 1.18 : 1
                            Behavior on scale {
                                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: entry.isChosen ? dial.tint(dial.gold, 0.22) : dial.tint(dial.ink, 0.96)
                                border.width: 1
                                border.color: entry.isChosen || cellMouse.containsMouse ? dial.gold : dial.tint(dial.bone, 0.18)
                            }
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: Math.round(parent.width * 0.64)
                                height: width
                                source: entry.model.icon
                                animated: false
                            }
                        }

                        // The window itself, in the middle, while it is chosen.
                        Item {
                            id: preview
                            readonly property real w: Math.round(dial.radius * 1.18)
                            readonly property real h: Math.round(w * tabBox.screenGeometry.height / tabBox.screenGeometry.width)
                            width: w
                            height: h
                            x: Math.round((dial.width - w) / 2)
                            y: Math.round((dial.height - h) / 2 - 14 * dial.unit)
                            visible: opacity > 0.01
                            opacity: entry.isChosen ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation { duration: 140 }
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -1
                                color: dial.tint(dial.ink, 1)
                                border.width: 1
                                border.color: dial.tint(dial.gold, 0.7)
                            }
                            KWin.WindowThumbnail {
                                anchors.fill: parent
                                wId: entry.model.windowId
                            }
                            // Its title, underneath.
                            Text {
                                width: Math.round(dial.radius * 1.5)
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.bottom
                                anchors.topMargin: Math.round(14 * dial.unit)
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                text: entry.model.caption || ""
                                color: dial.bone
                                font.family: "Mistletoe Text"
                                font.pixelSize: Math.round(14 * dial.unit)
                            }
                        }
                    }
                }

                Text {
                    width: Math.round(dial.radius * 1.5)
                    x: Math.round((dial.width - width) / 2)
                    y: Math.round(dial.height / 2 - 10 * dial.unit)
                    horizontalAlignment: Text.AlignHCenter
                    visible: dial.count === 0
                    text: i18ndc("kwin", "@info:placeholder no entries in the task switcher", "No open windows")
                    color: dial.tint(dial.bone, 0.6)
                    font.family: "Mistletoe Text"
                    font.pixelSize: Math.round(13 * dial.unit)
                }
            }

            onSceneGraphError: () => {
                // Left blank on purpose: otherwise QtQuick may abort on a graphics reset.
            }
        }
    }
}
