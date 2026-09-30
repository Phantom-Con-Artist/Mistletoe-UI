/*
    A Mistletoe gem: a diamond outline, used for category markers and the
    core of the fan.
*/
import QtQuick
import QtQuick.Shapes

Shape {
    id: gem

    property color fill: "transparent"
    property color rim: "transparent"
    property real rimWidth: 1

    readonly property real h: rimWidth / 2

    preferredRendererType: Shape.CurveRenderer
    // Qt's curve renderer spins forever on degenerate (zero-size) paths,
    // which hangs plasmashell; skip drawing until there is real size.
    visible: width > 2 && height > 2

    ShapePath {
        fillColor: gem.fill
        strokeColor: gem.rim
        strokeWidth: gem.rimWidth
        joinStyle: ShapePath.MiterJoin

        startX: gem.width / 2; startY: gem.h
        PathLine { x: gem.width - gem.h; y: gem.height / 2 }
        PathLine { x: gem.width / 2; y: gem.height - gem.h }
        PathLine { x: gem.h; y: gem.height / 2 }
        PathLine { x: gem.width / 2; y: gem.h }
    }
}
