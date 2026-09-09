import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
    id: root
    moduleName: "io.github.calebhat.workscape"

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    readonly property string pluginId: "io.github.calebhat.workscape"
    readonly property string home: Quickshell.env("HOME")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
    readonly property string configFile: stateHome + "/omarchy/workscape/config.json"
    readonly property string pluginDir: {
        var u = String(Qt.resolvedUrl("./manifest.json"))
        if (u.indexOf("file://") === 0) u = u.slice(7)
        try { u = decodeURIComponent(u) } catch (e) {}
        var i = u.lastIndexOf("/")
        return i > 0 ? u.slice(0, i) : u
    }
    readonly property string script: root.pluginDir + "/workscape.sh"
    readonly property string stateio: root.pluginDir + "/scripts/stateio"

    property int totalCount: 0
    property int enabledCount: 0
    property int profileCount: 0
    property bool pluginEnabled: true
    property string lastError: ""
    property bool pendingOpen: false
    property string configText: ""

    readonly property var barConfig: {
        var j = Model.parseCappedJson(root.configText)
        return j ? Model.sanitizeConfig(j) : Model.defaultConfig()
    }
    readonly property int focusedWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    readonly property var focusedProfile: Model.profileById(barConfig, barConfig.settings && barConfig.settings.activeProfileId) || Model.defaultProfile()
    readonly property var chipGeoms: Model.chipGeomsForWorkspace(focusedProfile, focusedWorkspaceId)

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    function ensurePanel() {
        if (!panelLoader.active) panelLoader.active = true
    }
    function open() {
        if (panelLoader.item) { panelLoader.item.open(); return }
        pendingOpen = true
        ensurePanel()
    }
    function close() { if (panelLoader.item) panelLoader.item.close() }
    function toggle() {
        if (panelLoader.item) { panelLoader.item.toggle(); return }
        pendingOpen = true
        ensurePanel()
    }
    function togglePanel() { toggle() }
    function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

    function injectPanel() {
        if (!panelLoader.item) return
        panelLoader.item.bar = root.bar
        panelLoader.item.anchorItem = button
        panelLoader.item.hostWidget = root
    }

    function refreshCounts() {
        if (!statusProc.running) statusProc.running = true
    }

    function applyMatching() {
        if (applyProc.running) return
        applyProc.command = ["python3", "-B", root.stateio, "run", "--timeout", "180", "--max-out", "65536", "--", "bash", root.script, "--apply-matching"]
        applyProc.running = true
    }

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    Process {
        id: statusProc
        command: ["python3", "-B", root.stateio, "run", "--timeout", "5", "--max-out", "8192", "--", "bash", root.script, "--status"]
        stdout: StdioCollector { id: statusOut; waitForEnd: true }
        onExited: function(code){
            try {
                var raw = statusOut.text || ""
                if (raw.length > 8192) return
                var j = JSON.parse(raw.trim() || "{}")
                root.totalCount = Number(j.total || 0)
                root.enabledCount = Number(j.enabled || 0)
                root.profileCount = Number(j.profiles || 0)
                root.pluginEnabled = j.pluginEnabled !== false
            } catch (e) {}
        }
    }

    FileView {
        id: configView
        path: root.configFile
        watchChanges: true
        printErrors: false
        onLoaded: {
            try { root.configText = text() } catch (e) { root.configText = "" }
        }
        onLoadFailed: root.configText = ""
        onFileChanged: reload()
    }
    Timer {
        interval: 1500
        running: root.configText === ""
        repeat: true
        onTriggered: configView.reload()
    }

    Process {
        id: applyProc
        stdout: SplitParser { onRead: function(d){ console.log("[workscape] " + d) } }
        stderr: SplitParser { onRead: function(d){ console.warn("[workscape] " + d) } }
    }

    Timer {
        id: pollTimer
        interval: 8000
        repeat: false
        running: false
        triggeredOnStart: false
        onTriggered: root.refreshCounts()
    }

    IpcHandler {
        target: root.pluginId + ".panel"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
    }

    Connections {
        target: panelLoader.item
        ignoreUnknownSignals: true
        function onCountsChanged() { root.refreshCounts() }
    }

    Loader {
        id: panelLoader
        active: false
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
            if (root.pendingOpen && panelLoader.item) {
                root.pendingOpen = false
                panelLoader.item.open()
            }
        }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        slotSize: Style.bar.statusSlot
        tooltipText: root.pluginEnabled
            ? ("WorkScape • WS " + root.focusedWorkspaceId + " • " + root.profileCount + " profiles • " + root.enabledCount + " apps • click to manage • middle-click apply matching")
            : "WorkScape • disabled • click to enable"
        iconComponent: Component {
            Item {
                LayoutThumb {
                    anchors.centerIn: parent
                    width: Math.round(parent.width)
                    height: Math.round(parent.width * 0.68)
                    geoms: root.chipGeoms
                    stroke: button.foreground
                    strength: root.opened ? 1.0 : 0.7
                }
            }
        }
        onPressed: function(btn){
            if (btn === Qt.LeftButton) root.toggle()
            else if (btn === Qt.MiddleButton) root.applyMatching()
        }
    }

    Component.onCompleted: refreshCounts()
}
