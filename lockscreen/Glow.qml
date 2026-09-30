/*
    A soft dark glow that fades to nothing at its edges: keeps text readable
    over bright wallpapers without a visible plate or any blur. Drawn as a
    circle and squashed into the item's ellipse.
*/
import QtQuick
import QtQuick.Shapes

Item {
    id: glow

    property color color: "black"
    property real strength: 0.7

    Shape {
        width: glow.width
        height: glow.width
        y: (glow.height - height) / 2
        visible: glow.width > 4 && glow.height > 4
        transform: Scale {
            origin.x: glow.width / 2
            origin.y: glow.width / 2
            yScale: glow.height / Math.max(1, glow.width)
        }
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: glow.width / 2; centerY: glow.width / 2
                focalX: centerX; focalY: centerY
                centerRadius: glow.width / 2
                GradientStop { position: 0; color: Qt.rgba(glow.color.r, glow.color.g, glow.color.b, glow.strength) }
                GradientStop { position: 0.6; color: Qt.rgba(glow.color.r, glow.color.g, glow.color.b, glow.strength * 0.6) }
                GradientStop { position: 1; color: Qt.rgba(glow.color.r, glow.color.g, glow.color.b, 0) }
            }
            startX: 0; startY: 0
            PathLine { x: glow.width; y: 0 }
            PathLine { x: glow.width; y: glow.width }
            PathLine { x: 0; y: glow.width }
            PathLine { x: 0; y: 0 }
        }
    }
}
