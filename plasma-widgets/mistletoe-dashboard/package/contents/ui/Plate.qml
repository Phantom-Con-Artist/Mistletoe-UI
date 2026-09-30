/*
    A dashboard card's surface: a matte facet with any of its four corners
    cut on the diagonal (0 = square), a faint 1px hairline, and a gold
    thread along every cut. Cuts near half the height turn that side into
    a point, which is how the power bar gets its hexagon ends.

    The outline is built as a de-duplicated polyline and the cuts are
    clamped short of meeting: Qt's curve renderer spins forever on
    zero-length or folded-back edges, which hung plasmashell once.
*/
import QtQuick
import QtQuick.Shapes

Item {
    id: plate

    property real cutTL: 0
    property real cutTR: 0
    property real cutBR: 0
    property real cutBL: 0
    property color fill
    property color hairline
    property color thread

    // Half-pixel inset so 1px strokes land on whole pixels.
    readonly property real x0: 0.5
    readonly property real y0: 0.5
    readonly property real x1: width - 0.5
    readonly property real y1: height - 0.5
    readonly property real maxCut: Math.max(0, Math.min(x1 - x0, y1 - y0) / 2 - 1)
    readonly property real tl: Math.min(cutTL, maxCut)
    readonly property real tr: Math.min(cutTR, maxCut)
    readonly property real br: Math.min(cutBR, maxCut)
    readonly property real bl: Math.min(cutBL, maxCut)

    readonly property var outline: {
        const pts = [
            Qt.point(x0 + tl, y0), Qt.point(x1 - tr, y0), Qt.point(x1, y0 + tr),
            Qt.point(x1, y1 - br), Qt.point(x1 - br, y1), Qt.point(x0 + bl, y1),
            Qt.point(x0, y1 - bl), Qt.point(x0, y0 + tl)
        ];
        const out = [];
        for (const p of pts) {
            const last = out[out.length - 1];
            if (!last || Math.abs(last.x - p.x) > 0.01 || Math.abs(last.y - p.y) > 0.01) {
                out.push(p);
            }
        }
        if (out.length > 1 && Math.abs(out[0].x - out[out.length - 1].x) < 0.01
                && Math.abs(out[0].y - out[out.length - 1].y) < 0.01) {
            out.pop();
        }
        out.push(out[0]); // close
        return out;
    }

    readonly property var cuts: {
        const segs = [];
        if (tl > 0) segs.push([Qt.point(x0, y0 + tl), Qt.point(x0 + tl, y0)]);
        if (tr > 0) segs.push([Qt.point(x1 - tr, y0), Qt.point(x1, y0 + tr)]);
        if (br > 0) segs.push([Qt.point(x1, y1 - br), Qt.point(x1 - br, y1)]);
        if (bl > 0) segs.push([Qt.point(x0 + bl, y1), Qt.point(x0, y1 - bl)]);
        return segs;
    }

    Shape {
        anchors.fill: parent
        visible: plate.width > 4 && plate.height > 4
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: plate.fill
            strokeColor: plate.hairline
            strokeWidth: 1
            joinStyle: ShapePath.MiterJoin
            PathPolyline {
                path: plate.outline
            }
        }
    }

    // Threads drawn as plain strokes, no fill to process.
    Shape {
        anchors.fill: parent
        visible: plate.cuts.length > 0 && plate.width > 4 && plate.height > 4
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: plate.thread
            strokeWidth: 1
            capStyle: ShapePath.FlatCap
            PathMultiline {
                paths: plate.cuts
            }
        }
    }
}
