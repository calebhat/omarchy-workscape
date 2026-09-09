import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Mini monitor preview. Tiles tessellate the workspace; drag a shared
// splitter to resize both sides. Windows cannot overlap.
Item {
    id: root
    property int workspace: 1
    property var assignedApps: []
    property bool lockAll: false
    property var appList: []
    property bool isExpanded: false
    property int screenW: 0
    property int screenH: 0
    property var bar: null
    property string hyprLayout: "dwindle"
    property real columnWidth: 0.49
    property bool dragging: false
    property var liveGeoms: []
    // Frozen while dragging — rebuilding this Repeater mid-drag destroys the
    // MouseArea and the grab dies after a few pixels.
    property var splitModel: []

    readonly property real screenAspect: screenW > 0 && screenH > 0 ? screenH / screenW : 0.5625
    readonly property var appLibrary: root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
    readonly property bool customLayout: Model.workspaceUsesCustomLayout(assignedApps)
    // One entry per assignment: null when ungrouped, {rep, tabs, active}
    // otherwise. A group is one tile, so only the representative is drawn and it
    // carries the tab strip.
    readonly property var groupPreview: Model.groupPreviewTiles(assignedApps)
    readonly property string layoutLabel: {
        if (customLayout) return "tiled · drag the splitters"
        if (hyprLayout === "scrolling") return "scrolling • " + Math.round(columnWidth * 100) + "% columns"
        if (hyprLayout === "master") return "master · large pane + stack"
        if (hyprLayout === "dwindle") return "dwindle · split tree"
        return hyprLayout
    }

    signal layoutChanged(var tiles)
    signal layoutCleared()
    signal appLockToggled(string assignmentId)
    signal organizerRequested()
    signal windowRemoved(string assignmentId)

    function iconSourceFor(exec) {
        for (var i = 0; i < appList.length; i++) {
            if (appList[i].exec === exec || appList[i].command === exec) {
                var a = appList[i]
                if (a.iconPath && a.iconPath !== "") return "file://" + a.iconPath
                var icon = String(a.icon || "")
                if (root.appLibrary && typeof root.appLibrary.iconSource === "function") return root.appLibrary.iconSource(icon)
                if (icon !== "" && icon.charAt(0) === "/") return "file://" + icon
                var themed = ""
                try { themed = Quickshell.iconPath(icon, true) } catch (e) { themed = "" }
                if (themed && themed.length > 0) return themed
                try { return Quickshell.iconPath("application-x-executable", true) } catch (e) { return "" }
            }
        }
        var base = String(exec || "").split(" ")[0].split("/").pop()
        if (root.appLibrary && typeof root.appLibrary.iconSource === "function") return root.appLibrary.iconSource(base)
        var fb = ""
        try { fb = Quickshell.iconPath(base, true) } catch (e) { fb = "" }
        if (fb && fb.length > 0 && fb.indexOf("image://icon/application-x-executable") === -1) return fb
        try { return Quickshell.iconPath("application-x-executable", true) } catch (e) { return "" }
    }

    function packedFromApps() {
        return Model.packedGeomsForApps(assignedApps, hyprLayout, columnWidth)
    }

    function rawGeoms() {
        var list = assignedApps || []
        var out = []
        for (var i = 0; i < list.length; i++) out.push(Model.normalizeGeom(list[i].geom))
        return out
    }

    function refreshSplits() {
        if (root.dragging) return
        splitModel = Model.listSplits(liveGeoms)
    }

    function rebuild(force) {
        if (root.dragging && !force) return
        liveGeoms = packedFromApps()
        refreshSplits()
    }

    function commitLive() {
        var apps = assignedApps || []
        var out = []
        for (var i = 0; i < liveGeoms.length && i < apps.length; i++) {
            var g = Model.normalizeGeom(liveGeoms[i])
            if (!g) continue
            g.id = apps[i].id
            g.z = i
            out.push(g)
        }
        if (out.length) root.layoutChanged(out)
    }

    onAssignedAppsChanged: rebuild()
    onHyprLayoutChanged: rebuild()
    Component.onCompleted: rebuild()

    implicitWidth: 320
    implicitHeight: previewBox.implicitHeight + 28

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
                text: "WS " + root.workspace
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
            }
            Text {
                text: root.assignedApps.length + " app" + (root.assignedApps.length === 1 ? "" : "s")
                color: Qt.darker(Color.foreground, 1.3)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption - 1
            }
            Text {
                visible: root.assignedApps.length > 0
                text: "· " + root.layoutLabel
                color: Qt.darker(Color.foreground, 1.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption - 2
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Button {
                visible: root.assignedApps.length > 1
                text: "Reset"
                tooltipText: "Clear pinned sizes and restore the default split"
                verticalPadding: Style.space(2)
                horizontalPadding: Style.space(8)
                onClicked: root.layoutCleared()
            }
        }

        Rectangle {
            id: previewBox
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: Style.space(92)
            Layout.preferredHeight: width > 0 ? Math.round(width * root.screenAspect) : Style.space(92)
            Layout.maximumHeight: width > 0 ? Math.round(width * root.screenAspect) : 4096
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: width > 0 ? Math.round(width * root.screenAspect) : Style.space(92)
            radius: Style.cornerRadius
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
            border.width: 1
            border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
            clip: true

            Text {
                visible: root.assignedApps.length === 0
                anchors.centerIn: parent
                text: "Empty — search or add a custom command"
                color: Qt.darker(Color.foreground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption - 1
                horizontalAlignment: Text.AlignHCenter
            }

            Item {
                id: tilesContainer
                anchors.fill: parent
                anchors.margins: 6
                visible: root.assignedApps.length > 0

                Repeater {
                    id: tileRepeater
                    model: root.assignedApps
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property var geom: (root.liveGeoms && root.liveGeoms[index]) ? root.liveGeoms[index] : { x: 0, y: 0, w: 1, h: 1 }
                        readonly property var groupInfo: (root.groupPreview && root.groupPreview[index]) ? root.groupPreview[index] : null
                        // Members of a group share one tile; the first one draws it.
                        visible: !groupInfo || groupInfo.rep
                        // The pane shows whichever tab was on top at capture time.
                        readonly property var faceApp: (groupInfo && groupInfo.active) ? groupInfo.active : modelData
                        readonly property int tabStripH: (groupInfo && groupInfo.rep) ? 13 : 0
                        x: geom.x * tilesContainer.width + 3
                        y: geom.y * tilesContainer.height + 3
                        width: Math.max(24, geom.w * tilesContainer.width - 6)
                        height: Math.max(24, geom.h * tilesContainer.height - 6)
                        radius: 6
                        z: 1
                        color: (modelData && modelData.enabled !== false)
                               ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                               : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
                        border.width: 1
                        border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.45)

                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.verticalCenter
                            anchors.bottomMargin: 2 + parent.tabStripH / 2
                            width: 16
                            height: 16
                            visible: source !== ""
                            source: root.iconSourceFor(parent.faceApp ? (parent.faceApp.exec || parent.faceApp.command) : "")
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                            onStatusChanged: if (status === Image.Error) source = ""
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.verticalCenter
                            anchors.topMargin: 4 + parent.tabStripH / 2
                            width: parent.width - 12
                            textFormat: Text.PlainText
                            text: ((root.lockAll || (modelData && modelData.lockPlace)) ? "🔒 " : "") + (parent.faceApp ? (parent.faceApp.name || "App") : "")
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption - 1
                            font.bold: true
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                        // Groupbar stand-in: one chip per member, in capture order,
                        // with the tab that was on top picked out. Inset so the lock
                        // and close hit areas in the corners stay reachable.
                        Row {
                            id: tabStrip
                            // Repeater counts as a child of this Row, so widths come
                            // from the tab list itself rather than children.length.
                            readonly property var tabs: (parent.groupInfo && parent.groupInfo.tabs) ? parent.groupInfo.tabs : []
                            readonly property real chipW: Math.max(0, (width - (tabs.length - 1) * 2) / Math.max(1, tabs.length))
                            visible: parent.tabStripH > 0 && tabs.length > 0
                            z: 3
                            anchors.top: parent.top
                            anchors.topMargin: 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            // Inset so the lock and close hit areas in the corners stay reachable.
                            width: Math.max(0, parent.width - 40)
                            height: 11
                            spacing: 2
                            Repeater {
                                model: tabStrip.tabs
                                delegate: Rectangle {
                                    required property var modelData
                                    width: tabStrip.chipW
                                    height: tabStrip.height
                                    radius: 3
                                    color: modelData.active
                                           ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.55)
                                           : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14)
                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: 3
                                        anchors.rightMargin: 3
                                        textFormat: Text.PlainText
                                        text: modelData.name
                                        color: Color.foreground
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.caption - 3
                                        font.bold: modelData.active
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }
                        }
                        MouseArea {
                            z: 4
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: if (modelData && modelData.id) root.appLockToggled(modelData.id)
                        }
                        MouseArea {
                            z: 6
                            anchors.top: parent.top
                            anchors.left: parent.left
                            width: 18
                            height: 18
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (modelData && modelData.id) root.appLockToggled(modelData.id)
                            Rectangle {
                                anchors.fill: parent
                                radius: 4
                                color: Qt.rgba(0, 0, 0, parent.containsMouse ? 0.45 : 0.25)
                                Text {
                                    anchors.centerIn: parent
                                    text: (root.lockAll || (modelData && modelData.lockPlace)) ? "🔒" : "🔓"
                                    color: Color.foreground
                                    font.pixelSize: 10
                                }
                            }
                        }
                        MouseArea {
                            z: 5
                            anchors.top: parent.top
                            anchors.right: parent.right
                            width: 18
                            height: 18
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData && modelData.id) root.windowRemoved(modelData.id)
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: 4
                                color: Qt.rgba(0, 0, 0, parent.containsMouse ? 0.45 : 0.25)
                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    color: Color.foreground
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                            }
                        }
                    }
                }

                Repeater {
                    id: splitRepeater
                    model: root.splitModel
                    delegate: MouseArea {
                        required property var modelData
                        z: 20
                        readonly property bool vertical: modelData && modelData.axis === "v"
                        readonly property real livePos: {
                            var ids = (modelData && modelData.aIds) || []
                            var g = ids.length ? root.liveGeoms[ids[0]] : null
                            if (!g) return modelData ? modelData.pos : 0
                            return vertical ? (g.x + g.w) : (g.y + g.h)
                        }
                        x: vertical ? livePos * tilesContainer.width - 6 : modelData.s0 * tilesContainer.width
                        y: vertical ? modelData.s0 * tilesContainer.height : livePos * tilesContainer.height - 6
                        width: vertical ? 12 : Math.max(12, (modelData.s1 - modelData.s0) * tilesContainer.width)
                        height: vertical ? Math.max(12, (modelData.s1 - modelData.s0) * tilesContainer.height) : 12
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
                                   : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.45)
                        }

                        onPressed: function(mouse) {
                            var p = mapToItem(tilesContainer, mouse.x, mouse.y)
                            grab = vertical ? p.x : p.y
                            startGeoms = JSON.parse(JSON.stringify(root.liveGeoms))
                            startSplit = JSON.parse(JSON.stringify(modelData))
                            moved = false
                            root.dragging = true
                            mouse.accepted = true
                        }
                        onPositionChanged: function(mouse) {
                            if (!pressed || !startSplit) return
                            var p = mapToItem(tilesContainer, mouse.x, mouse.y)
                            var now = vertical ? p.x : p.y
                            var span = vertical ? Math.max(1, tilesContainer.width) : Math.max(1, tilesContainer.height)
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

        Item { Layout.fillHeight: true; Layout.minimumHeight: 0 }
    }
}
