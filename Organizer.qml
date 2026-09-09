import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
    id: root
    property var assignedApps: []
    property var appList: []
    property var bar: null
    property string hyprLayout: "dwindle"
    property real columnWidth: 0.49
    property int selectedIndex: 0
    property bool dragging: false
    property var liveGeoms: []
    property var splitModel: []
    property int dragFrom: -1
    property string dropHint: ""

    readonly property var appLibrary: root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
    readonly property int paneCount: (assignedApps || []).length

    signal layoutChanged(var tiles)
    signal layoutCleared()
    signal placeChanged(int index, string place)
    signal splitRequested(int index, string dir)
    signal gearRequested(int index)
    signal closeRequested()
    signal windowRemoved(string assignmentId)

    function iconSourceFor(exec) {
        for (var i = 0; i < appList.length; i++) {
            if (appList[i].exec === exec || appList[i].command === exec) {
                var a = appList[i]
                if (a.iconPath && a.iconPath !== "") return "file://" + a.iconPath
                var icon = String(a.icon || "")
                if (root.appLibrary && typeof root.appLibrary.iconSource === "function") return root.appLibrary.iconSource(icon)
                if (icon !== "" && icon.charAt(0) === "/") return "file://" + icon
                try { return Quickshell.iconPath(icon || "application-x-executable", true) } catch (e) { return "" }
            }
        }
        return ""
    }

    function packedFromApps() {
        return Model.packedGeomsForApps(assignedApps, hyprLayout, columnWidth)
    }

    function refreshSplits() {
        if (root.dragging) return
        splitModel = Model.listSplits(liveGeoms)
    }

    function rebuild() {
        if (root.dragging) return
        liveGeoms = packedFromApps()
        refreshSplits()
        if (selectedIndex >= paneCount) selectedIndex = Math.max(0, paneCount - 1)
    }

    function commitLive() {
        var apps = assignedApps || []
        var out = []
        for (var i = 0; i < liveGeoms.length && i < apps.length; i++) {
            var g = (apps[i] && apps[i].place === "float")
                ? Model.normalizeFloatGeom(liveGeoms[i])
                : Model.normalizeGeom(liveGeoms[i])
            if (!g) continue
            g.id = apps[i].id
            g.z = i
            out.push(g)
        }
        if (out.length) root.layoutChanged(out)
        refreshSplits()
    }

    function applyGeoms(next) {
        liveGeoms = next
        commitLive()
    }

    function selectedApp() {
        var list = assignedApps || []
        return list[selectedIndex] || null
    }

    function isFloat(i) {
        var list = assignedApps || []
        return list[i] && list[i].place === "float"
    }

    onAssignedAppsChanged: rebuild()
    onHyprLayoutChanged: rebuild()
    Component.onCompleted: rebuild()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(8)

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            Text {
                text: "Organizer"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                text: paneCount + " window" + (paneCount === 1 ? "" : "s") + " · drag edges · drop on a pane to swap or split"
                color: Qt.darker(Color.foreground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
            }
            Button {
                visible: paneCount > 0
                text: "Tile"
                selected: root.selectedApp() && root.selectedApp().place !== "float"
                onClicked: if (paneCount > 0) root.placeChanged(selectedIndex, "tile")
            }
            Button {
                visible: paneCount > 0
                text: "Float"
                selected: root.selectedApp() && root.selectedApp().place === "float"
                onClicked: if (paneCount > 0) root.placeChanged(selectedIndex, "float")
            }
            Button { visible: paneCount > 1; text: "←"; tooltipText: "Split selected with next app, incoming on the left"; onClicked: root.splitRequested(selectedIndex, "left") }
            Button { visible: paneCount > 1; text: "→"; tooltipText: "Split right"; onClicked: root.splitRequested(selectedIndex, "right") }
            Button { visible: paneCount > 1; text: "↑"; tooltipText: "Split up"; onClicked: root.splitRequested(selectedIndex, "top") }
            Button { visible: paneCount > 1; text: "↓"; tooltipText: "Split down"; onClicked: root.splitRequested(selectedIndex, "bottom") }
            Button { visible: paneCount > 0; text: "Reset"; onClicked: root.layoutCleared() }
            Button { visible: paneCount > 0; text: "⚙"; tooltipText: "Opacity and borders"; onClicked: root.gearRequested(selectedIndex) }
            Button { text: "Close"; onClicked: root.closeRequested() }
        }

        Item {
            id: board
            Layout.fillWidth: true
            Layout.fillHeight: true

            Repeater {
                model: root.assignedApps
                delegate: Item {
                    id: pane
                    required property var modelData
                    required property int index
                    readonly property int paneIndex: index
                    readonly property var geom: (root.liveGeoms && root.liveGeoms[index]) ? root.liveGeoms[index] : { x: 0, y: 0, w: 1, h: 1 }
                    readonly property bool floating: modelData && modelData.place === "float"
                    x: geom.x * board.width
                    y: geom.y * board.height
                    width: Math.max(24, geom.w * board.width)
                    height: Math.max(24, geom.h * board.height)
                    z: {
                        if (index === root.dragFrom) return 80
                        if (floating) return 30 + index
                        if (index === root.selectedIndex) return 8
                        return 1
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: 8
                        color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, index === root.selectedIndex ? 0.28 : 0.14)
                        border.width: index === root.selectedIndex ? 2 : 1
                        border.color: index === root.selectedIndex ? Color.accent
                            : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.35)
                        opacity: floating ? 0.95 : 1

                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 8
                            text: floating ? "FLOAT" : "TILE"
                            color: Color.accent
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption - 2
                            font.bold: true
                        }
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 16
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            text: (modelData && modelData.name) || "App"
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                            font.bold: true
                        }

                    }

                    Repeater {
                        model: floating ? ["l", "r", "t", "b"] : []
                        delegate: MouseArea {
                            required property string modelData
                            z: 5
                            anchors.left: modelData === "l" ? parent.left : (modelData === "r" ? undefined : parent.left)
                            anchors.right: modelData === "r" ? parent.right : (modelData === "l" ? undefined : parent.right)
                            anchors.top: modelData === "t" ? parent.top : (modelData === "b" ? undefined : parent.top)
                            anchors.bottom: modelData === "b" ? parent.bottom : (modelData === "t" ? undefined : parent.bottom)
                            width: (modelData === "l" || modelData === "r") ? 8 : undefined
                            height: (modelData === "t" || modelData === "b") ? 8 : undefined
                            cursorShape: (modelData === "l" || modelData === "r") ? Qt.SizeHorCursor : Qt.SizeVerCursor
                            property var startG: null
                            property real gx: 0
                            property real gy: 0
                            onPressed: function(mouse) {
                                startG = JSON.parse(JSON.stringify(root.liveGeoms[pane.paneIndex]))
                                gx = mouse.x
                                gy = mouse.y
                                root.dragging = true
                                root.selectedIndex = pane.paneIndex
                            }
                            onPositionChanged: function(mouse) {
                                if (!pressed || !startG) return
                                var dx = (mouse.x - gx) / Math.max(1, board.width)
                                var dy = (mouse.y - gy) / Math.max(1, board.height)
                                var next = JSON.parse(JSON.stringify(root.liveGeoms))
                                next[pane.paneIndex] = Model.resizeFloatGeom(startG, modelData, dx, dy)
                                root.liveGeoms = next
                            }
                            onReleased: {
                                root.commitLive()
                                root.dragging = false
                            }
                        }
                    }

                    MouseArea {
                        z: 40
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 4
                        width: 26
                        height: 26
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var id = modelData && modelData.id
                            if (id) root.windowRemoved(id)
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 4
                            color: Qt.rgba(0, 0, 0, parent.containsMouse ? 0.5 : 0.28)
                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: Color.foreground
                                font.pixelSize: 14
                                font.bold: true
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: 8
                        z: 1
                        cursorShape: Qt.SizeAllCursor
                        hoverEnabled: true
                        property real pressBX: 0
                        property real pressBY: 0
                        property var startG: null
                        property var startAll: null
                        onPressed: function(mouse) {
                            root.selectedIndex = pane.paneIndex
                            root.dragFrom = pane.paneIndex
                            root.dragging = true
                            var p = mapToItem(board, mouse.x, mouse.y)
                            pressBX = p.x
                            pressBY = p.y
                            startG = JSON.parse(JSON.stringify(geom))
                            startAll = JSON.parse(JSON.stringify(root.liveGeoms))
                        }
                        onPositionChanged: function(mouse) {
                            if (!pressed || !startG) return
                            var p = mapToItem(board, mouse.x, mouse.y)
                            if (floating) {
                                var dx = (p.x - pressBX) / Math.max(1, board.width)
                                var dy = (p.y - pressBY) / Math.max(1, board.height)
                                var next = JSON.parse(JSON.stringify(startAll))
                                next[pane.paneIndex] = Model.moveFloatGeom(startG, dx, dy)
                                root.liveGeoms = next
                                return
                            }
                            var hit = root.hitIndex(p.x, p.y, pane.paneIndex)
                            if (hit >= 0 && hit !== pane.paneIndex && !root.isFloat(hit) && startAll) {
                                var hg = startAll[hit]
                                var nx = (p.x / board.width - hg.x) / Math.max(0.001, hg.w)
                                var ny = (p.y / board.height - hg.y) / Math.max(0.001, hg.h)
                                var zone = Model.dropZone(nx, ny)
                                if (zone === "center")
                                    root.liveGeoms = Model.swapGeoms(startAll, pane.paneIndex, hit)
                                else
                                    root.liveGeoms = Model.splitDrop(startAll, pane.paneIndex, hit, zone)
                            } else if (startAll) {
                                root.liveGeoms = JSON.parse(JSON.stringify(startAll))
                            }
                        }
                        onReleased: function(mouse) {
                            root.commitLive()
                            root.dragFrom = -1
                            root.dragging = false
                            root.refreshSplits()
                        }
                    }
                }
            }

            Repeater {
                model: root.splitModel
                delegate: MouseArea {
                    required property var modelData
                    z: 30
                    visible: {
                        var ids = ((modelData && modelData.aIds) || []).concat((modelData && modelData.bIds) || [])
                        for (var i = 0; i < ids.length; i++) if (root.isFloat(ids[i])) return false
                        return true
                    }
                    readonly property bool vertical: modelData && modelData.axis === "v"
                    readonly property real livePos: {
                        var ids = (modelData && modelData.aIds) || []
                        var g = ids.length ? root.liveGeoms[ids[0]] : null
                        if (!g) return modelData ? modelData.pos : 0
                        return vertical ? (g.x + g.w) : (g.y + g.h)
                    }
                    x: vertical ? livePos * board.width - 6 : modelData.s0 * board.width
                    y: vertical ? modelData.s0 * board.height : livePos * board.height - 6
                    width: vertical ? 12 : Math.max(12, (modelData.s1 - modelData.s0) * board.width)
                    height: vertical ? Math.max(12, (modelData.s1 - modelData.s0) * board.height) : 12
                    cursorShape: vertical ? Qt.SizeHorCursor : Qt.SizeVerCursor
                    hoverEnabled: true
                    preventStealing: true
                    property real grab: 0
                    property var startGeoms: []
                    property var startSplit: null
                    property bool moved: false
                    Rectangle {
                        anchors.centerIn: parent
                        width: vertical ? (parent.containsMouse || parent.pressed ? 4 : 2) : parent.width
                        height: vertical ? parent.height : (parent.containsMouse || parent.pressed ? 4 : 2)
                        radius: 1
                        color: parent.containsMouse || parent.pressed ? Color.accent
                               : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.5)
                    }
                    onPressed: function(mouse) {
                        var p = mapToItem(board, mouse.x, mouse.y)
                        grab = vertical ? p.x : p.y
                        startGeoms = JSON.parse(JSON.stringify(root.liveGeoms))
                        startSplit = JSON.parse(JSON.stringify(modelData))
                        moved = false
                        root.dragging = true
                    }
                    onPositionChanged: function(mouse) {
                        if (!pressed || !startSplit) return
                        var p = mapToItem(board, mouse.x, mouse.y)
                        var now = vertical ? p.x : p.y
                        var span = vertical ? Math.max(1, board.width) : Math.max(1, board.height)
                        var delta = (now - grab) / span
                        if (Math.abs(delta) > 0.002) moved = true
                        root.liveGeoms = Model.nudgeSplit(startGeoms, startSplit, delta, {
                            snap: !(mouse.modifiers & Qt.ShiftModifier)
                        })
                    }
                    onDoubleClicked: {
                        root.liveGeoms = Model.evenSplit(root.liveGeoms, modelData)
                        root.commitLive()
                        root.dragging = false
                        root.refreshSplits()
                    }
                    onReleased: {
                        if (moved) root.commitLive()
                        root.dragging = false
                        moved = false
                        root.refreshSplits()
                    }
                }
            }
        }
    }

    function hitIndex(px, py, except) {
        var list = liveGeoms || []
        for (var i = list.length - 1; i >= 0; i--) {
            if (i === except) continue
            var g = list[i]
            if (!g) continue
            var x0 = g.x * board.width, y0 = g.y * board.height
            var x1 = x0 + g.w * board.width, y1 = y0 + g.h * board.height
            if (px >= x0 && px <= x1 && py >= y0 && py <= y1) return i
        }
        return -1
    }
}
