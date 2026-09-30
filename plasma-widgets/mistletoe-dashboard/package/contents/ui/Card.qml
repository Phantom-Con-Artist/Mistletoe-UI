/*
    One dashboard card: its facet plate, its content, and the controls that
    appear while the pointer is over it:

      grip (top centre)      drag to move the card
      pin (top right)        float the card above all windows, or dock it
      corner (bottom right)  drag to resize; the content reflows live

    Dragging is measured in screen coordinates from the press point, so the
    card tracks the pointer exactly. On the desktop the card only moves
    visually while you drag (a translate and a live size), and the result
    is committed to Plasma's layout once, on release: moving the real
    layout item every frame made it re-lay-out and stutter. A floating card
    moves its window directly.
*/
import QtQuick

Item {
    id: card

    required property var dash
    property bool floating: false

    signal pinToggled()
    // Floating: live window offsets from where the drag started.
    signal windowDragStarted()
    signal windowMoveTo(real dx, real dy)
    signal windowResizeTo(real dw, real dh)
    // Both: the drag finished with this total move / size change.
    signal placed(real dx, real dy, real dw, real dh)

    // Visual offset and size change while a docked drag is in progress.
    property real dragX: 0
    property real dragY: 0
    property real growW: 0
    property real growH: 0
    transform: Translate { x: card.dragX; y: card.dragY }
    // Anchored to the slot, plus any live resize (never below the minimums).
    width: Math.max(240, parent ? parent.width + growW : 0)
    height: Math.max(64, parent ? parent.height + growH : 0)

    function startDrag() {
        dragX = dragY = growW = growH = 0;
        if (floating) {
            windowDragStarted();
        }
    }
    function dragTo(dx, dy, resizing) {
        if (floating) {
            resizing ? windowResizeTo(dx, dy) : windowMoveTo(dx, dy);
        } else if (resizing) {
            growW = dx;
            growH = dy;
        } else {
            dragX = dx;
            dragY = dy;
        }
    }
    function endDrag(dx, dy, resizing) {
        // Clear the visual offset in the same step the real geometry moves,
        // so there is no flicker between the two.
        const move = resizing ? [0, 0] : [dx, dy];
        const size = resizing ? [dx, dy] : [0, 0];
        dragX = dragY = growW = growH = 0;
        placed(move[0], move[1], size[0], size[1]);
    }

    readonly property var spec: dash.card
    readonly property bool bare: !!spec.bare
    readonly property bool pointed: dash.section === "power"
    readonly property bool active: hover.hovered || gripMouse.pressed || cornerMouse.pressed

    HoverHandler {
        id: hover
    }

    Plate {
        anchors.fill: parent
        // The bare clock gets a plate only while you're handling it.
        visible: !card.bare || card.active
        opacity: card.bare ? 0.6 : 1
        cutTL: card.pointed ? height / 2 : card.spec.cuts[0]
        cutTR: card.pointed ? height / 2 : card.spec.cuts[1]
        cutBR: card.pointed ? height / 2 : card.spec.cuts[2]
        cutBL: card.pointed ? height / 2 : card.spec.cuts[3]
        fill: card.dash.tint(card.dash.ink, card.bare ? 0.5 : 0.97)
        hairline: card.dash.tint(card.dash.bone, card.floating ? 0.22 : 0.10)
        thread: card.dash.tint(card.dash.gold, 0.85)
    }

    // The section is often written right after the widget is created (by
    // the layout script), so reload when it changes.
    Connections {
        target: card.dash
        function onCardChanged() {
            loader.load();
        }
    }
    Loader {
        id: loader
        function load() {
            // Pass the dashboard in up front so no binding sees it unset.
            setSource(card.spec.file, { dash: card.dash });
        }
        anchors.fill: parent
        anchors.leftMargin: card.bare ? 0 : card.pointed ? parent.height / 2 : 28
        anchors.rightMargin: card.pointed ? parent.height / 2 : 28
        anchors.topMargin: card.bare || card.pointed ? 0 : 26
        anchors.bottomMargin: card.bare || card.pointed ? 0 : 26
        Component.onCompleted: load()
    }

    // ---- Handling controls (fade in on hover) ---------------------------
    // Drags use the press point in item coordinates: as the card moves under
    // the pointer, (current - press) is exactly the distance still to go.
    Item {
        anchors.fill: parent
        opacity: card.active ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: 160 }
        }

        // Grip: three small gems.
        MouseArea {
            id: gripMouse
            property point press
            function offset(mouse) {
                const g = mapToGlobal(mouse.x, mouse.y);
                return Qt.point(g.x - press.x, g.y - press.y);
            }
            anchors.horizontalCenter: parent.horizontalCenter
            y: card.pointed ? 2 : 6
            width: 64
            height: 16
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            preventStealing: true
            onPressed: (mouse) => {
                press = mapToGlobal(mouse.x, mouse.y);
                card.startDrag();
            }
            onPositionChanged: (mouse) => {
                const d = offset(mouse);
                card.dragTo(d.x, d.y, false);
            }
            onReleased: (mouse) => {
                const d = offset(mouse);
                card.endDrag(d.x, d.y, false);
            }
            Row {
                anchors.centerIn: parent
                spacing: 6
                Repeater {
                    model: 3
                    Gem {
                        width: 7
                        height: 7
                        fill: gripMouse.pressed ? card.dash.gold : card.dash.tint(card.dash.gold, 0.7)
                        rim: "transparent"
                    }
                }
            }
        }

        PinGem {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: card.pointed ? parent.height / 2 - 11 : (card.spec.cuts[1] > 30 ? card.spec.cuts[1] - 8 : 10)
            anchors.topMargin: card.pointed ? (parent.height - 22) / 2 : (card.spec.cuts[1] > 30 ? 10 : 8)
            dash: card.dash
            pinned: card.floating
            onToggled: card.pinToggled()
        }

        // Resize corner: a gold wedge along the bottom-right.
        MouseArea {
            id: cornerMouse
            property point press
            function offset(mouse) {
                const g = mapToGlobal(mouse.x, mouse.y);
                return Qt.point(g.x - press.x, g.y - press.y);
            }
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 22
            height: 22
            cursorShape: Qt.SizeFDiagCursor
            preventStealing: true
            onPressed: (mouse) => {
                press = mapToGlobal(mouse.x, mouse.y);
                card.startDrag();
            }
            onPositionChanged: (mouse) => {
                const d = offset(mouse);
                card.dragTo(d.x, d.y, true);
            }
            onReleased: (mouse) => {
                const d = offset(mouse);
                card.endDrag(d.x, d.y, true);
            }
            Canvas {
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const g = card.dash.gold;
                    ctx.strokeStyle = Qt.rgba(g.r, g.g, g.b, 0.9);
                    ctx.lineWidth = 1;
                    for (const o of [6, 11, 16]) {
                        ctx.beginPath();
                        ctx.moveTo(width - 3, height - o);
                        ctx.lineTo(width - o, height - 3);
                        ctx.stroke();
                    }
                }
            }
        }
    }
}
