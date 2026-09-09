import QtQuick
import qs.Commons

Item {
    id: root
    property var geoms: []
    property color stroke: Color.foreground
    property real strength: 1.0

    readonly property int hairline: Math.max(1, Math.round(Style.space(1)))
    readonly property int tileCount: Math.max(1, (root.geoms && root.geoms.length) ? root.geoms.length : 0)

    Repeater {
        model: root.tileCount
        Rectangle {
            required property int index
            readonly property var g: (root.geoms && root.geoms[index])
                ? root.geoms[index]
                : { x: 0, y: 0, w: 1, h: 1 }
            x: Math.round(Number(g.x) * root.width)
            y: Math.round(Number(g.y) * root.height)
            width: Math.max(1, Math.round((Number(g.x) + Number(g.w)) * root.width) - Math.round(Number(g.x) * root.width) - root.hairline)
            height: Math.max(1, Math.round((Number(g.y) + Number(g.h)) * root.height) - Math.round(Number(g.y) * root.height) - root.hairline)
            radius: 0
            color: Util.alpha(root.stroke, 0.35 * root.strength)
            border.width: root.hairline
            border.color: Util.alpha(root.stroke, 0.85 * root.strength)
        }
    }
}
