/*
    A Mistletoe shard: a plate with its top-left and bottom-right corners cut
    on the diagonal, optionally traced by a rim.
*/
import QtQuick
import QtQuick.Shapes

Shape {
    id: shard

    property real cut: Math.round(Math.min(width, height) * 0.18)
    property color fill: "transparent"
    property color rim: "transparent"
    property real rimWidth: 1

    readonly property real h: rimWidth / 2

    preferredRendererType: Shape.CurveRenderer
    // Qt's curve renderer spins forever on degenerate (zero-size) paths,
    // which hangs plasmashell; skip drawing until there is real size.
    visible: width > 2 && height > 2

    ShapePath {
        fillColor: shard.fill
        strokeColor: shard.rim
        strokeWidth: shard.rimWidth
        joinStyle: ShapePath.MiterJoin

        startX: shard.cut; startY: shard.h
        PathLine { x: shard.width - shard.h; y: shard.h }
        PathLine { x: shard.width - shard.h; y: shard.height - shard.cut }
        PathLine { x: shard.width - shard.cut; y: shard.height - shard.h }
        PathLine { x: shard.h; y: shard.height - shard.h }
        PathLine { x: shard.h; y: shard.cut }
        PathLine { x: shard.cut; y: shard.h }
    }
}
