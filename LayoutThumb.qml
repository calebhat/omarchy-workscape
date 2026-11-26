import QtQuick
import qs.Commons

Item {
    id: root
    property var geoms: []
    property color stroke: Color.foreground
    property real strength: 1.0

    readonly property int hairline: Math.max(1, Math.round(root.width / 12))
    readonly property int tileGap: Math.max(1, Math.round(root.width / 20))
    readonly property int tileCount: Math.max(1, (root.geoms && root.geoms.length) ? root.geoms.length : 0)

    Repeater {
        model: root.tileCount
        Rectangle {
            required property int index
            readonly property var g: (root.geoms && root.geoms[index])
                ? root.geoms[index]
                : { x: 0, y: 0, w: 1, h: 1 }
            readonly property real gx: Math.max(0, Math.min(1, Number(g.x) || 0))
            readonly property real gy: Math.max(0, Math.min(1, Number(g.y) || 0))
            readonly property real gx2: Math.max(gx, Math.min(1, gx + (Number(g.w) || 1)))
            readonly property real gy2: Math.max(gy, Math.min(1, gy + (Number(g.h) || 1)))
            readonly property int rx: Math.round(gx * root.width) + (gx > 0.01 ? root.tileGap : 0)
            readonly property int ry: Math.round(gy * root.height) + (gy > 0.01 ? root.tileGap : 0)
            readonly property int rx2: Math.round(gx2 * root.width) - (gx2 < 0.99 ? root.tileGap : 0)
            readonly property int ry2: Math.round(gy2 * root.height) - (gy2 < 0.99 ? root.tileGap : 0)
            x: rx
            y: ry
            width: Math.max(root.hairline * 2, rx2 - rx)
            height: Math.max(root.hairline * 2, ry2 - ry)
            radius: 0
            antialiasing: true
            color: Util.alpha(root.stroke, 0.30 * root.strength)
            border.width: root.hairline
            border.color: Util.alpha(root.stroke, 0.95 * root.strength)
        }
    }
}
