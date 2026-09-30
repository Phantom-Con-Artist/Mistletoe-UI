/*
    Mistletoe analog dial: a twelve-sided faceted face, gold gem hour marks,
    and shard-shaped hands. `wind` (0..1) sweeps the hands in from twelve.
*/
import QtQuick
import QtQuick.Shapes

Item {
    id: dial

    property date time: new Date()
    property bool seconds: true
    property bool detailed: true        // minute ticks
    property real wind: 1
    property color face: "#111316"
    property color hand: "#e9e4d6"
    property color gold: "#d4ac70"
    property color rim: Qt.rgba(hand.r, hand.g, hand.b, 0.16)

    readonly property real r: Math.min(width, height) / 2
    readonly property real hourAngle: ((time.getHours() % 12) + time.getMinutes() / 60) * 30
    readonly property real minuteAngle: (time.getMinutes() + time.getSeconds() / 60) * 6
    readonly property real secondAngle: time.getSeconds() * 6

    function vertex(i, radius) {
        const a = (i * 30 - 90) * Math.PI / 180;
        return Qt.point(dial.width / 2 + radius * Math.cos(a), dial.height / 2 + radius * Math.sin(a));
    }

    // Face: a dodecagon with one vertex per hour.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: dial.face
            strokeColor: dial.rim
            strokeWidth: 1
            joinStyle: ShapePath.MiterJoin
            PathPolyline {
                path: {
                    const pts = [];
                    for (let i = 0; i <= 12; ++i) {
                        pts.push(dial.vertex(i % 12, dial.r - 0.5));
                    }
                    return pts;
                }
            }
        }
    }

    // Minute ticks.
    Repeater {
        model: dial.detailed ? 60 : 0
        Rectangle {
            required property int index
            visible: index % 5 !== 0
            width: 1
            height: dial.r * 0.05
            color: Qt.rgba(dial.hand.r, dial.hand.g, dial.hand.b, 0.3)
            x: dial.width / 2 - width / 2
            y: dial.height / 2 - dial.r * 0.9
            transform: Rotation {
                origin.x: 0.5
                origin.y: dial.r * 0.9
                angle: index * 6
            }
        }
    }

    // Hour marks: gold gems, larger at the quarters.
    Repeater {
        model: 12
        Gem {
            required property int index
            readonly property bool quarter: index % 3 === 0
            readonly property point at: dial.vertex(index, dial.r * (dial.detailed ? 0.8 : 0.72))
            width: dial.r * (quarter ? 0.14 : 0.08)
            height: width * (quarter ? 1.5 : 1)
            x: at.x - width / 2
            y: at.y - height / 2
            rotation: index * 30
            fill: quarter ? dial.gold : Qt.rgba(dial.hand.r, dial.hand.g, dial.hand.b, 0.55)
            visible: dial.detailed || quarter
        }
    }

    // A tapered shard hand pointing at twelve; the Item rotates it.
    component Hand: Item {
        id: handItem
        property real length: 0.6
        property real breadth: 0.06
        property color color: dial.hand
        property real angle: 0
        anchors.fill: parent
        rotation: angle
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                id: blade
                readonly property real cx: dial.width / 2
                readonly property real cy: dial.height / 2
                readonly property real l: dial.r * handItem.length
                readonly property real w: dial.r * handItem.breadth
                fillColor: handItem.color
                strokeColor: "transparent"
                startX: blade.cx; startY: blade.cy - blade.l
                PathLine { x: blade.cx + blade.w; y: blade.cy - blade.l * 0.18 }
                PathLine { x: blade.cx; y: blade.cy + blade.l * 0.14 }
                PathLine { x: blade.cx - blade.w; y: blade.cy - blade.l * 0.18 }
                PathLine { x: blade.cx; y: blade.cy - blade.l }
            }
        }
    }

    Hand {
        length: 0.52
        breadth: 0.075
        angle: dial.hourAngle * dial.wind
    }
    Hand {
        length: 0.78
        breadth: 0.055
        angle: dial.minuteAngle * dial.wind
    }

    // Second hand: a gold thread with a gem, ticking with a small spring.
    Item {
        anchors.fill: parent
        visible: dial.seconds
        rotation: dial.secondAngle * dial.wind
        Behavior on rotation {
            enabled: dial.wind >= 1
            RotationAnimation {
                direction: RotationAnimation.Clockwise
                duration: 280
                easing.type: Easing.OutBack
                easing.overshoot: 2
            }
        }
        Rectangle {
            width: 1.5
            height: dial.r * 0.98
            color: dial.gold
            x: dial.width / 2 - width / 2
            y: dial.height / 2 - dial.r * 0.84
            antialiasing: true
        }
        Gem {
            width: dial.r * 0.09
            height: width * 1.4
            x: dial.width / 2 - width / 2
            y: dial.height / 2 - dial.r * 0.66 - height / 2
            fill: dial.gold
        }
    }

    Gem {
        width: dial.r * 0.12
        height: width
        anchors.centerIn: parent
        fill: dial.gold
        rim: dial.face
        rimWidth: 1.5
    }
}
