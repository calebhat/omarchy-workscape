import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
    id: root
    moduleName: "io.github.calebhat.workscape"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null

    readonly property string home: Quickshell.env("HOME")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
    readonly property string pluginId: "io.github.calebhat.workscape"
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

    function helperRun(args, timeoutSec, maxOut) {
        var cmd = ["python3", "-B", root.stateio, "run", "--timeout", String(timeoutSec), "--max-out", String(maxOut), "--"]
        return cmd.concat(args)
    }

    signal countsChanged()

    property var config: Model.defaultConfig()
    property var assignments: []
    property bool loading: true
    property string errorText: ""
    property string statusText: ""
    property var appList: []
    property string appFilter: ""
    property bool adding: false
    property int formWorkspace: 1
    property bool workspacePicked: false
    property string formName: ""
    property string formCommand: ""
    property string formType: "app"
    property string formExecPreview: ""
    property bool formNameEdited: false
    property string autoName: ""
    property bool fillingName: false
    property string mainView: "profiles"
    property string customCommand: ""
    property string customName: ""
    property var liveStatus: ({ live: [], profiles: [], matchedProfileId: "", bindings: {} })
    property var liveMonitors: []
    property bool applyBusy: false
    property string lastFollowedMatchId: ""
    onFormTypeChanged: { updateFormPreview(); updateAutofillName() }

    property string hyprLayout: "dwindle"
    property real hyprColumnWidth: 0.49

    property bool cursorActive: false
    property int selectedRow: 0
    property int selectedButton: 0

    readonly property color foreground: root.barForeground
    readonly property color dim: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.55)
    readonly property string fontFamily: Style.font.family

    readonly property string activeProfileId: (config.settings && config.settings.activeProfileId) ? config.settings.activeProfileId : "default"
    readonly property var activeProfile: Model.profileById(config, activeProfileId) || Model.defaultProfile()
    readonly property var profileOptions: {
        var list = config.profiles || []
        var out = []
        for (var i = 0; i < list.length; i++) out.push({ value: list[i].id, label: list[i].name })
        return out
    }
    readonly property var monitorOptions: Model.monitorOptions(config, activeProfile, liveMonitors)
    readonly property bool showMonitorPicker: monitorOptions.length > 1
    property string copyTargetId: ""
    property bool transferOpen: false
    property bool newProfileOpen: false
    property string newProfileName: ""
    property bool newProfileBindNetwork: true
    property bool editNetworkOpen: false
    property string editNetworkProfileId: ""
    property string editNetworkSsids: ""
    property string editNetworkSubnets: ""
    property string editNetworkConnections: ""
    property var liveNetwork: ({})
    property string lastLiveJson: ""
    property bool visibleCountBusy: false
    property bool organizerOpen: false
    property bool chromeOpen: false
    property int chromeIndex: 0
    property real chromeOpA: 1
    property real chromeOpI: 1
    property bool chromeBorderA: true
    property bool chromeBorderI: true
    property string chromeColorA: ""
    property string chromeColorI: ""
    property int chromeBorderSize: -1
    property string hotkeyCapture: ""
    readonly property var currentHotkeys: Model.normalizeHotkeys(config.settings && config.settings.hotkeys)
    property bool overflowOpen: false
    property var overflowDraft: []
    property int overflowDraftMax: 1
    property string transferMode: "copy"
    property string transferFromWs: "1"
    property string transferToWs: "1"
    property string transferToProfileId: ""
    readonly property var copyProfileOptions: {
        var list = config.profiles || []
        var out = []
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === activeProfileId) continue
            out.push({ value: list[i].id, label: list[i].name })
        }
        return out
    }
    readonly property var workspaceOptions: {
        var out = []
        for (var i = 1; i <= 10; i++) out.push({ value: String(i), label: "WS " + i })
        return out
    }
    readonly property var transferToProfileOptions: transferMode === "move"
        ? [{ value: activeProfileId, label: activeProfile.name }]
        : root.profileOptions
    readonly property var currentWsPref: Model.effectiveWorkspacePref(activeProfile, formWorkspace)
    readonly property var currentWsUi: Model.workspaceControlFlags(activeProfile, formWorkspace)
    readonly property string workspaceMonitorId: {
        var map = activeProfile.workspaceMonitors || {}
        return String(map[String(formWorkspace)] || "")
    }
    readonly property string workspaceMonitorSummary: {
        var map = activeProfile.workspaceMonitors || {}
        var opts = monitorOptions
        var labelFor = function(id) {
            for (var i = 0; i < opts.length; i++) if (opts[i].value === id) return opts[i].label
            var m = Model.monitorById(config, id)
            return m ? m.label : id
        }
        var parts = []
        for (var ws = 1; ws <= 10; ws++) {
            var id = String(map[String(ws)] || "")
            if (!id) continue
            parts.push(ws + ":" + labelFor(id))
        }
        return parts.length ? parts.join("  ·  ") : "No workspace → monitor pins yet"
    }
    onFormWorkspaceChanged: {
        Qt.callLater(syncMonitorDropdown)
        root.syncVisibleCountField()
        Qt.callLater(function() { })
    }
    onAnyLockOnWsChanged: Qt.callLater(function() { })
    onActiveProfileIdChanged: Qt.callLater(syncMonitorDropdown)
    readonly property string matchedLabel: liveStatus.matchedProfileName ? ("matches " + liveStatus.matchedProfileName) : "no layout match"
    readonly property var activeApplyHint: Model.applyHint(config, activeProfile, liveMonitors, liveNetwork, liveStatus)
    readonly property int totalCount: {
        var n = 0
        var list = config.profiles || []
        for (var i = 0; i < list.length; i++) n += (list[i].assignments || []).length
        return n
    }
    readonly property int enabledCount: (function(){
        var n = 0
        for (var i = 0; i < assignments.length; i++) if (assignments[i].enabled !== false) n++
        return n
    })()

    function open() {
        root.controller.show()
        loadConfig()
        appsProc.running = true
        layoutProc.running = true
        liveProc.running = true
        root.workspacePicked = true
        Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }
    function close() {
        saveConfig()
        root.controller.hide()
    }
    function dismissOrClose() {
        if (root.hotkeyCapture) { root.hotkeyCapture = ""; return }
        if (root.chromeOpen) { root.chromeOpen = false; return }
        if (root.organizerOpen) { root.organizerOpen = false; return }
        if (root.overflowOpen) { root.closeOverflow(); return }
        if (root.editNetworkOpen) { root.closeEditNetwork(); return }
        if (root.newProfileOpen) { root.closeNewProfile(); return }
        if (root.transferOpen) { root.closeTransfer(); return }
        root.close()
    }
    function followLiveMatch() {
        var id = Model.nextFollowedMatch((liveStatus && liveStatus.matchedProfileId) || "", lastFollowedMatchId)
        if (!id) return
        lastFollowedMatchId = id
        if (id === activeProfileId) return
        if (!Model.profileById(config, id)) return
        setActiveProfile(id)
    }
    function toggle() { root.opened ? root.close() : root.open() }
    function closeForPopoutSwitch() { root.close() }
    function switchPanel(dir) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.hostWidget || root, dir)
        return false
    }

    function loadConfig() { loading=true; errorText=""; loadProc.running=true; if (!layoutProc.running) layoutProc.running = true; liveProc.running = true }
    function currentConfig() {
        var cfg = Model.sanitizeConfig(config)
        cfg.settings.lastFormWorkspace = formWorkspace
        cfg.settings.lastMainView = Model.allowedMainView(mainView)
        var pid = cfg.settings.activeProfileId
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id === pid) {
                cfg.profiles[i].assignments = assignments.slice(0, 50)
                for (var j = 0; j < cfg.profiles[i].assignments.length; j++) {
                    var a = cfg.profiles[i].assignments[j]
                    if (a.type === "webapp" && a.command.indexOf("http") === 0) {
                        a.exec = "omarchy-launch-webapp '" + a.command.replace(/'/g, "'\\''") + "'"
                        if (!a.name || a.name === a.command) a.name = Model.displayNameForExec(a.exec, "Web App")
                    } else if (a.exec === "" && a.command !== "") a.exec = a.command
                    cfg.profiles[i].assignments[j] = a
                }
            }
        }
        return cfg
    }
    function saveConfig() {
        var cfg = root.currentConfig()
        config = cfg
        assignments = (Model.profileById(cfg, cfg.settings.activeProfileId) || { assignments: [] }).assignments.slice()
        saveProc.pendingJson = JSON.stringify(cfg, null, 2)
        if (saveProc.pendingJson.length > Model.maxConfigBytes()) {
            root.errorText = "Config too large to save"
            return
        }
        if (saveProc.running) { saveProc.wantsSave = true; return }
        saveProc.command = ["python3", "-B", root.stateio, "write-config"]
        saveProc.stdinEnabled = true
        saveProc.running = true
    }
    function setActiveProfile(id) {
        var cfg = root.currentConfig()
        if (!Model.profileById(cfg, id)) return
        cfg.settings.activeProfileId = id
        config = cfg
        assignments = Model.profileById(cfg, id).assignments.slice()
        var opts = []
        var list = cfg.profiles || []
        for (var i = 0; i < list.length; i++) if (list[i].id !== id) opts.push(list[i].id)
        if (opts.length && (root.copyTargetId === id || !root.copyTargetId)) root.copyTargetId = opts[0]
        saveConfig()
    }
    function openTransfer(mode) {
        transferMode = mode === "move" ? "move" : "copy"
        transferFromWs = String(formWorkspace)
        transferToWs = transferMode === "move" ? (formWorkspace === 10 ? "1" : String(formWorkspace + 1)) : String(formWorkspace)
        transferToProfileId = transferMode === "move" ? activeProfileId : (copyTargetId || (copyProfileOptions[0] ? copyProfileOptions[0].value : ""))
        transferOpen = true
    }
    function closeTransfer() { transferOpen = false }
    function closeNewProfile() { newProfileOpen = false }
    function closeEditNetwork() { editNetworkOpen = false }
    function profileRecord(id) {
        return Model.profileById(root.config, id) || {}
    }
    function openEditNetwork(id) {
        var p = root.profileRecord(id)
        if (!p.id) return
        var fields = Model.networkFieldText(p.network)
        editNetworkProfileId = id
        editNetworkSsids = fields.ssids
        editNetworkSubnets = fields.subnets
        editNetworkConnections = fields.connections
        editNetworkOpen = true
        Qt.callLater(function() {
            if (editNetworkSsidField) editNetworkSsidField.forceActiveFocus()
        })
    }
    function confirmEditNetwork() {
        var id = editNetworkProfileId
        var net = Model.parseNetworkText(editNetworkSsids, editNetworkSubnets, editNetworkConnections)
        var cfg = root.currentConfig()
        var prof = Model.profileById(cfg, id)
        if (!prof) { editNetworkOpen = false; return }
        if (!Model.networkConfigured(net)) {
            var owner = Model.environmentOwner(cfg, Model.monitorKey(prof), Model.emptyNetwork(), id)
            if (owner) {
                errorText = owner.name + " is already the fallback for this layout. Keep one unbound profile per layout."
                return
            }
        }
        var claimed = Model.claimEnvironment(cfg, id, net)
        config = claimed.config
        saveConfig()
        editNetworkOpen = false
        statusText = Model.networkConfigured(net)
            ? ("Bound " + Model.networkSummary(net) + "." + root.stolenStatus(claimed.stolen))
            : "This profile matches any network for its displays"
        clearStatusTimer.restart()
        liveProc.running = true
    }
    function stolenStatus(stolen) {
        if (!stolen || !stolen.length) return ""
        var names = []
        for (var i = 0; i < stolen.length; i++) names.push(stolen[i].name || stolen[i].id)
        return " Took this network from " + names.join(", ") + "."
    }
    function confirmTransfer() {
        var fromWs = parseInt(transferFromWs, 10)
        var toWs = parseInt(transferToWs, 10)
        var cfg = root.currentConfig()
        if (transferMode === "move") {
            if (fromWs === toWs) { errorText = "Pick a different destination workspace"; return }
            cfg = Model.moveWorkspace(cfg, activeProfileId, fromWs, toWs)
            config = cfg
            assignments = (Model.profileById(cfg, activeProfileId) || { assignments: [] }).assignments.slice()
            formWorkspace = toWs
            persistFormWorkspace()
            statusText = "Moved WS" + fromWs + " → WS" + toWs
        } else {
            var toId = transferToProfileId
            if (!toId) { errorText = "Pick a destination profile"; return }
            cfg = Model.copyWorkspace(cfg, activeProfileId, fromWs, toId, toWs)
            var dest = Model.profileById(cfg, toId)
            if (!dest) { errorText = "Profile not found"; return }
            config = cfg
            saveConfig()
            statusText = "Copied WS" + fromWs + " → " + dest.name + " WS" + toWs
            clearStatusTimer.restart()
            closeTransfer()
            return
        }
        saveConfig()
        clearStatusTimer.restart()
        closeTransfer()
    }
    function syncMonitorDropdown() {
        if (monitorDropdown) monitorDropdown.value = root.workspaceMonitorId
    }
    function selectWorkspace(n) {
        formWorkspace = n
        workspacePicked = true
        persistWsTimer.restart()
        syncMonitorDropdown()
    }
    function applyWorkspaceShape(shapeId) {
        var apps = root.addedApps || []
        var tiled = 0
        for (var i = 0; i < apps.length; i++) if (apps[i].place !== "float") tiled++
        if (!tiled) {
            root.errorText = "Add a tiled app before picking a split shape"
            return
        }
        var packed = Model.applyShapeToApps(apps, shapeId)
        var byId = {}
        for (var t = 0; t < packed.length; t++) if (packed[t] && packed[t].id) byId[packed[t].id] = packed[t]
        var next = []
        for (var a = 0; a < assignments.length; a++) {
            var item = Model.clone(assignments[a])
            var src = byId[item.id]
            if (src) {
                if (src.geom) item.geom = src.geom
                if (src.lockPlace === true) item.lockPlace = true
            }
            next.push(item)
        }
        assignments = next
        saveConfig()
        var shape = Model.findShape(shapeId)
        root.statusText = shape ? (shape.name + " · " + Model.describeShape(shape)) : "Applied split shape"
        clearStatusTimer.restart()
    }
    function setWorkspaceMonitor(monitorId) {
        monitorId = String(monitorId || "")
        if (monitorId === root.workspaceMonitorId) return
        var cfg = root.currentConfig()
        if (monitorId && !Model.monitorById(cfg, monitorId)) {
            var live = root.liveMonitors || []
            for (var n = 0; n < live.length; n++) {
                var tmp = Model.normalizeMonitor(live[n])
                if (tmp && tmp.id === monitorId) {
                    var up = Model.upsertLiveMonitor(cfg, live[n])
                    cfg = up.config
                    monitorId = up.id
                    break
                }
            }
        }
        var pid = cfg.settings.activeProfileId
        var wsKey = String(formWorkspace)
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id !== pid) continue
            var allowed = cfg.profiles[i].monitors || []
            if (monitorId && allowed.length && allowed.indexOf(monitorId) < 0) return
            var map = {}
            var prev = cfg.profiles[i].workspaceMonitors || {}
            var keys = Object.keys(prev)
            for (var k = 0; k < keys.length; k++) map[keys[k]] = prev[keys[k]]
            if (!monitorId) delete map[wsKey]
            else map[wsKey] = monitorId
            cfg.profiles[i].workspaceMonitors = map
        }
        config = cfg
        saveConfig()
        statusText = "WS" + formWorkspace + (monitorId ? " → " + (Model.monitorById(cfg, monitorId) || { label: monitorId }).label : " unpinned")
        clearStatusTimer.restart()
        Qt.callLater(syncMonitorDropdown)
    }
    function addAssignment() {
        var name = formName.trim(), cmd = formCommand.trim()
        if (!cmd.length) { errorText = "Command / URL is required"; return }
        if (!name.length) {
            if (formType === "webapp") name = Model.displayNameForExec("omarchy-launch-webapp '" + cmd + "'", "Web App")
            else name = Model.displayNameForExec(cmd, "App")
        }
        var execStr = cmd
        if (formType === "webapp" && (cmd.indexOf("http://") === 0 || cmd.indexOf("https://") === 0))
            execStr = "omarchy-launch-webapp '" + cmd.replace(/'/g, "'\\''") + "'"
        var item = Model.normalizeAssignment({ workspace: formWorkspace, name: name, command: cmd, exec: execStr, type: formType, enabled: true, onlyOnBoot: true })
        assignments = assignments.concat([item])
        formName = ""; formCommand = ""; formType = "app"; formNameEdited = false
        saveConfig(); statusText = "Added " + item.name + " → WS" + item.workspace; clearStatusTimer.restart()
        if (root.bar && typeof root.bar.broadcast === "function") root.bar.broadcast("refreshCounts")
        root.countsChanged()
    }
    function addCustomCommand() {
        var cmd = customCommand.trim()
        if (!cmd.length) { errorText = "Command is required"; return }
        var name = customName.trim() || Model.displayNameForExec(cmd, "App")
        var item = Model.normalizeAssignment({ workspace: formWorkspace, name: name, command: cmd, exec: cmd, type: "custom", enabled: true, onlyOnBoot: false })
        assignments = assignments.concat([item])
        customCommand = ""; customName = ""
        saveConfig(); statusText = "Added " + item.name + " → WS" + item.workspace; clearStatusTimer.restart()
        root.countsChanged()
    }
    function updateFormPreview() {
        if (formType === "webapp" && (formCommand.indexOf("http://") === 0 || formCommand.indexOf("https://") === 0)) formExecPreview = "omarchy-launch-webapp '" + formCommand + "'"
        else formExecPreview = formCommand
    }
    function assignmentForExec(execStr) {
        var ws = formWorkspace
        for (var i = 0; i < assignments.length; i++) {
            if (assignments[i].workspace !== ws) continue
            if (Model.sameAppExec(assignments[i].exec, execStr) || Model.sameAppExec(assignments[i].command, execStr))
                return assignments[i]
        }
        return null
    }
    function isAppLocked(execStr) {
        var a = root.assignmentForExec(execStr)
        return Model.assignmentIsLocked(a, root.activeProfile)
    }
    function toggleAppLock(execStr) {
        if (root.currentWsPref.layout === "set-width") return
        var a = root.assignmentForExec(execStr)
        if (!a) return
        var cfg = root.currentConfig()
        var pid = cfg.settings.activeProfileId
        var ws = formWorkspace
        var pref = Model.workspacePref(Model.profileById(cfg, pid), ws)
        var unlockingFromAll = pref.lockSizes === true
        var next = []
        for (var i = 0; i < assignments.length; i++) {
            var item = Model.clone(assignments[i])
            if (unlockingFromAll && item.workspace === ws) {
                item.lockPlace = item.id !== a.id
            } else if (item.id === a.id) {
                item.lockPlace = !(item.lockPlace === true)
            }
            next.push(item)
        }
        if (unlockingFromAll) {
            for (var p = 0; p < cfg.profiles.length; p++) {
                if (cfg.profiles[p].id !== pid) continue
                var prefs = cfg.profiles[p].workspacePrefs || {}
                var pr = Model.normalizeWorkspacePref(prefs[String(ws)])
                pr.lockSizes = false
                prefs[String(ws)] = pr
                cfg.profiles[p].workspacePrefs = prefs
            }
            config = cfg
        }
        var anyLock = unlockingFromAll
        if (!anyLock) {
            for (var n = 0; n < next.length; n++) {
                if (next[n].workspace === ws && next[n].lockPlace === true) { anyLock = true; break }
            }
        }
        if (anyLock) next = Model.ensureAssignmentGeoms(next, ws, pref)
        assignments = next
        saveConfig()
        statusText = (root.isAppLocked(execStr) ? "Locked " : "Unlocked ") + a.name
        clearStatusTimer.restart()
    }
    function toggleAppLockById(id) {
        for (var i = 0; i < assignments.length; i++) {
            if (assignments[i].id === id) {
                root.toggleAppLock(assignments[i].exec || assignments[i].command)
                return
            }
        }
    }
    function setWorkspacePref(field, value) {
        if (!Model.canEditWorkspacePref(root.activeProfile, formWorkspace, field)) return
        var cfg = root.currentConfig()
        var pid = cfg.settings.activeProfileId
        var ws = String(formWorkspace)
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id !== pid) continue
            var prefs = Model.clone(cfg.profiles[i].workspacePrefs || {})
            var pref = Model.normalizeWorkspacePref(prefs[ws])
            if (field === "visibleCount") value = Model.clampVisibleCount(value)
            pref[field] = value
            prefs[ws] = Model.normalizeWorkspacePref(pref)
            cfg.profiles[i].workspacePrefs = prefs
            if (field === "lockSizes") {
                var next = []
                for (var a = 0; a < assignments.length; a++) {
                    var item = Model.clone(assignments[a])
                    if (item.workspace === formWorkspace) item.lockPlace = value === true
                    next.push(item)
                }
                if (value === true) next = Model.ensureAssignmentGeoms(next, formWorkspace, prefs[ws])
                assignments = next
            }
        }
        config = cfg
        saveConfig()
        if (field === "visibleCount") root.syncVisibleCountField()
    }
    function syncVisibleCountField() {
        if (!visibleCountField || visibleCountField.activeFocus) return
        var s = String(root.currentWsPref.visibleCount)
        if (visibleCountField.text !== s) visibleCountField.text = s
    }
    function bumpVisibleCount(delta) {
        root.visibleCountBusy = true
        var n = Model.clampVisibleCount(root.currentWsPref.visibleCount + delta)
        if (visibleCountField) visibleCountField.text = String(n)
        root.setWorkspacePref("visibleCount", n)
        Qt.callLater(function() { root.visibleCountBusy = false })
    }
    function commitVisibleCount() {
        if (root.visibleCountBusy || !visibleCountField) return
        var n = Model.clampVisibleCount(visibleCountField.text)
        visibleCountField.text = String(n)
        if (n !== root.currentWsPref.visibleCount) root.setWorkspacePref("visibleCount", n)
    }
    function persistFormWorkspace() {
        persistWsTimer.restart()
    }
    Timer { id: persistWsTimer; interval: 400; onTriggered: root.saveConfig() }
    function removeAssignment(id) {
        root.assignments = Model.removeAppAndFill(root.assignments, id)
        root.saveConfig()
        root.statusText = "Removed"; clearStatusTimer.restart()
    }
    function isInList(list, exec) {
        return root.countInWorkspace(exec) > 0
    }
    function countInWorkspace(exec) {
        var n = 0
        var list = root.addedApps || []
        for (var i = 0; i < list.length; i++) {
            if (Model.sameAppExec(list[i].exec, exec) || Model.sameAppExec(list[i].command, exec)) n++
        }
        return n
    }
    function addInstance(exec, name) {
        var ws = root.formWorkspace
        var onWs = 0
        for (var n = 0; n < root.assignments.length; n++) if (root.assignments[n].workspace === ws) onWs++
        if (onWs >= Model.maxOrganizerPanes()) { errorText = "This workspace already has " + Model.maxOrganizerPanes() + " windows"; return }
        var count = root.countInWorkspace(exec)
        var type = /herdr/.test(exec) || exec.indexOf("/") === 0 || exec.indexOf(" ") >= 0 ? "custom" : "app"
        var label = name
        if (count >= 1) label = name + " " + (count + 1)
        var item = Model.normalizeAssignment({ workspace: ws, name: label, command: exec, exec: exec, type: type, enabled: true, onlyOnBoot: true })
        root.assignments = root.assignments.concat([item])
        root.saveConfig()
        root.statusText = "Added " + item.name + " → WS" + item.workspace
        clearStatusTimer.restart()
        if (root.bar && typeof root.bar.broadcast === "function") root.bar.broadcast("refreshCounts")
        root.countsChanged()
    }
    function toggleInWorkspace(exec, name) {
        var ws = root.formWorkspace
        var last = -1
        for (var i = 0; i < root.assignments.length; i++) {
            var a = root.assignments[i]
            if (a.workspace === ws && (Model.sameAppExec(a.exec, exec) || Model.sameAppExec(a.command, exec))) last = i
        }
        if (last >= 0) {
            var gone = root.assignments[last]
            root.removeAssignment(gone.id)
            root.statusText = "Removed " + gone.name + " from WS" + ws; clearStatusTimer.restart()
            return
        }
        root.addInstance(exec, name)
    }
    function captureWorkspace() {
        captureProc.command = root.helperRun(["python3", root.pluginDir + "/scripts/capture", "--workspace", String(root.formWorkspace)], 8, 262144)
        captureProc.running = true
        statusText = "Capturing WS" + root.formWorkspace + "…"
        clearStatusTimer.restart()
    }
    function applyCapture(rows) {
        var ws = root.formWorkspace
        var kept = []
        for (var i = 0; i < assignments.length; i++) if (assignments[i].workspace !== ws) kept.push(assignments[i])
        var added = []
        var maxN = Model.maxOrganizerPanes()
        var sorted = (rows || []).slice()
        sorted.sort(function(a, b) {
            var ga = (a && a.geom) || {}
            var gb = (b && b.geom) || {}
            var ax = Number(ga.x); if (isNaN(ax)) ax = 0
            var bx = Number(gb.x); if (isNaN(bx)) bx = 0
            if (ax !== bx) return ax - bx
            var ay = Number(ga.y); if (isNaN(ay)) ay = 0
            var by = Number(gb.y); if (isNaN(by)) by = 0
            return ay - by
        })
        for (var r = 0; r < sorted.length && added.length < maxN; r++) {
            var item = Model.normalizeAssignment(sorted[r])
            if (!item.exec) continue
            item.workspace = ws
            added.push(item)
        }
        var tiled = 0
        for (var t = 0; t < added.length; t++) if (added[t].place !== "float") tiled++
        if (tiled >= 2) {
            for (var k = 0; k < added.length; k++) {
                if (added[k].place !== "float") added[k].lockPlace = true
            }
        }
        assignments = kept.concat(added)
        saveConfig()
        statusText = "Captured " + added.length + " window" + (added.length === 1 ? "" : "s") + " on WS" + ws
        clearStatusTimer.restart()
        root.countsChanged()
    }
    function updateAutofillName() {
        var cmd = formCommand.trim()
        if (!cmd.length) { autoName = ""; if (!formNameEdited) { fillingName = true; formName = ""; fillingName = false } return }
        var n
        if (formType === "webapp" && (cmd.indexOf("http://") === 0 || cmd.indexOf("https://") === 0)) n = Model.displayNameForExec("omarchy-launch-webapp '" + cmd + "'", "Web App")
        else n = Model.displayNameForExec(cmd, "App")
        autoName = n
        if (!formNameEdited) { fillingName = true; formName = n; fillingName = false }
    }
    function applyMatching() {
        if (root.applyBusy || applyProc.running) return
        root.applyBusy = true
        applyProc.command = root.helperRun(["bash", root.script, "--apply-matching"], 180, 65536)
        applyProc.running = true
        statusText = "Applying matching profile…"
        clearStatusTimer.restart()
    }
    readonly property var currentGestures: {
        if ((config.settings && config.settings.gestureSource) === "profile")
            return Model.normalizeGestures(activeProfile.gestures)
        return Model.normalizeGestures(config.settings && config.settings.gestures)
    }
    function setGestureSource(src) {
        var cfg = root.currentConfig()
        cfg.settings.gestureSource = src === "profile" ? "profile" : "global"
        config = cfg
        saveProc.wantsGestures = true
        saveConfig()
    }
    function setGestureField(field, value) {
        var cur = root.currentGestures
        if (cur && cur[field] === value) return
        var cfg = root.currentConfig()
        var g
        if (cfg.settings.gestureSource !== "profile") {
            g = Model.normalizeGestures(cfg.settings.gestures)
            g[field] = value
            cfg.settings.gestures = Model.normalizeGestures(g)
        } else {
            var pid = cfg.settings.activeProfileId
            for (var i = 0; i < cfg.profiles.length; i++) {
                if (cfg.profiles[i].id !== pid) continue
                g = Model.normalizeGestures(cfg.profiles[i].gestures)
                g[field] = value
                cfg.profiles[i].gestures = Model.normalizeGestures(g)
            }
        }
        config = cfg
        if (field === "invert")
            root.liveEval("hl.config({ gestures = { workspace_swipe_invert = " + (value ? "true" : "false") + " } })")
        if (field === "fingers") {
            var other = value === 4 ? 3 : 4
            root.liveEval("hl.gesture({ fingers = " + other + ", direction = \"horizontal\", action = \"unset\" })")
            Qt.callLater(function() {
                root.liveEval("hl.gesture({ fingers = " + value + ", direction = \"horizontal\", action = \"workspace\" })")
            })
        }
        saveProc.wantsGestures = true
        saveConfig()
    }
    function setWorkspaceName(ws, name) {
        var cfg = root.currentConfig()
        var pid = cfg.settings.activeProfileId
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id !== pid) continue
            var names = Model.normalizeWorkspaceNames(cfg.profiles[i].workspaceNames)
            var key = String(ws)
            var n = String(name || "").trim()
            if (n) names[key] = n
            else delete names[key]
            cfg.profiles[i].workspaceNames = names
        }
        config = cfg
        saveConfig()
    }
    function setProfileField(field, value) {
        var cfg = root.currentConfig()
        var pid = cfg.settings.activeProfileId
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id !== pid) continue
            cfg.profiles[i][field] = value
        }
        config = cfg
        saveConfig()
    }
    function applyGestures() {
        gestureProc.running = true
        statusText = "Applying gestures…"
        clearStatusTimer.restart()
    }
    function liveEval(lua) {
        liveEvalProc.command = ["hyprctl", "eval", lua]
        liveEvalProc.running = true
    }
    function profileCanApply(id) {
        var p = Model.profileById(config, id) || {}
        var h = Model.applyHint(config, p, liveMonitors, liveNetwork, liveStatus)
        if (h && h.canApply) return true
        var msg = (h && h.refuseText) ? h.refuseText : "This profile doesn't match the connected displays"
        statusText = msg
        errorText = msg
        clearStatusTimer.restart()
        return false
    }
    function applyProfile(id) {
        if (root.applyBusy || applyProc.running) return
        if (!root.profileCanApply(id)) return
        root.applyBusy = true
        applyProc.command = root.helperRun(["bash", root.script, "--apply-profile", id], 180, 65536)
        applyProc.running = true
        statusText = "Applying profile…"
        clearStatusTimer.restart()
    }
    function applyFreshProfile(id) {
        if (root.applyBusy || applyProc.running) return
        var matchId = String((liveStatus && liveStatus.matchedProfileId) || "")
        var target = id
        if (matchId && Model.profileById(config, matchId)) target = matchId
        if (target !== activeProfileId) setActiveProfile(target)
        if (!root.profileCanApply(target)) return
        root.applyBusy = true
        applyProc.command = root.helperRun(["bash", root.script, "--fresh-apply-profile", target], 180, 65536)
        applyProc.running = true
        statusText = "Closing workspaces that have apps in this profile, then applying fresh…"
        clearStatusTimer.restart()
        root.close()
    }
    function resetEmptyWorkspaces() {
        if (root.applyBusy || applyProc.running) return
        root.applyBusy = true
        applyProc.command = root.helperRun(["bash", root.script, "--reset-empty-workspaces", root.activeProfileId], 30, 65536)
        applyProc.running = true
        statusText = "Restoring Omarchy defaults on workspaces with no apps in this profile…"
        clearStatusTimer.restart()
    }
    function openNewProfile() {
        liveProc.running = true
        var live = root.liveMonitors || []
        if (!live.length) { errorText = "No monitors detected"; return }
        newProfileName = Model.suggestedProfileName(live)
        newProfileBindNetwork = true
        newProfileOpen = true
        Qt.callLater(function() {
            if (newProfileNameField) newProfileNameField.forceActiveFocus()
        })
    }
    function confirmNewProfile() {
        var name = String(newProfileName || "").trim().slice(0, 48)
        if (!name) { errorText = "Name this profile first"; return }
        var cfg = root.currentConfig()
        var live = root.liveMonitors || []
        if (!live.length) { errorText = "No monitors detected"; return }
        var ids = []
        for (var i = 0; i < live.length; i++) {
            var up = Model.upsertLiveMonitor(cfg, live[i])
            cfg = up.config
            if (up.id) ids.push(up.id)
        }
        var net = newProfileBindNetwork ? Model.captureNetwork(root.liveNetwork) : Model.emptyNetwork()
        var key = ids.slice().sort().join(",")
        var owner = Model.environmentOwner(cfg, key, net, "")
        if (!Model.networkConfigured(net) && owner) {
            errorText = owner.name + " is already the fallback for this layout. Bind the current network, or edit that profile."
            return
        }
        var prof = Model.defaultProfile()
        prof.id = Model.makeId("pr")
        prof.name = name
        prof.monitors = ids
        prof.matchMode = "exact"
        prof.network = net
        var layout = {}
        var scales = {}
        var modes = {}
        for (var j = 0; j < live.length; j++) {
            if (!ids[j]) continue
            layout[ids[j]] = { x: Number(live[j].x) || 0, y: Number(live[j].y) || 0 }
            var sc = Number(live[j].scale) || 0
            if (sc > 0) scales[ids[j]] = sc
            if (Number(live[j].width) > 0 && Number(live[j].height) > 0) {
                modes[ids[j]] = {
                    width: Number(live[j].width),
                    height: Number(live[j].height),
                    refreshRate: Number(live[j].refreshRate) || 60
                }
            }
        }
        prof.monitorLayout = Model.normalizeMonitorLayout(layout)
        prof.monitorScales = Model.normalizeMonitorScales(scales, ids)
        prof.monitorModes = Model.normalizeMonitorModes(modes, ids)
        cfg.profiles = cfg.profiles.concat([prof])
        cfg.settings.activeProfileId = prof.id
        var claimed = Model.claimEnvironment(cfg, prof.id, net)
        cfg = claimed.config
        config = cfg
        assignments = []
        saveConfig()
        newProfileOpen = false
        statusText = "Saved " + prof.name + root.stolenStatus(claimed.stolen)
        clearStatusTimer.restart()
        mainView = "workspaces"
    }
    function bindProfileNetwork(id) {
        var net = Model.captureNetwork(root.liveNetwork)
        if (!Model.networkConfigured(net)) {
            errorText = "No Wi-Fi / LAN to bind yet"
            return
        }
        var claimed = Model.claimEnvironment(root.currentConfig(), id, net)
        config = claimed.config
        saveConfig()
        statusText = "Bound " + Model.networkSummary(net) + " to this profile." + root.stolenStatus(claimed.stolen)
        clearStatusTimer.restart()
        liveProc.running = true
    }
    function clearProfileNetwork(id) {
        var cfg = root.currentConfig()
        var prof = Model.profileById(cfg, id)
        if (!prof) return
        var owner = Model.environmentOwner(cfg, Model.monitorKey(prof), Model.emptyNetwork(), id)
        if (owner) {
            errorText = owner.name + " is already the fallback for this layout. Keep one unbound profile per layout."
            return
        }
        var claimed = Model.claimEnvironment(cfg, id, Model.emptyNetwork())
        config = claimed.config
        saveConfig()
        statusText = "This profile matches any network for its displays"
        clearStatusTimer.restart()
    }
    function renameProfile(id, name) {
        var cfg = root.currentConfig()
        for (var i = 0; i < cfg.profiles.length; i++) if (cfg.profiles[i].id === id) cfg.profiles[i].name = String(name).slice(0, 48)
        config = cfg; saveConfig()
    }
    function setMonitorDisabled(profileId, monitorId, off) {
        var cfg = root.currentConfig()
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id !== profileId) continue
            var mons = cfg.profiles[i].monitors || []
            if (mons.length < 2) {
                cfg.profiles[i].disabledMonitors = []
                errorText = "Can't turn off the only display in this profile"
                return
            }
            var offList = []
            var raw = cfg.profiles[i].disabledMonitors || []
            for (var d = 0; d < raw.length; d++) offList.push(raw[d])
            var idx = offList.indexOf(monitorId)
            if ((off && idx >= 0) || (!off && idx < 0)) return
            if (off) {
                if (mons.length - offList.length <= 1 && idx < 0) {
                    errorText = "Keep at least one display on"
                    return
                }
                if (idx < 0) offList.push(monitorId)
            } else if (idx >= 0) {
                offList.splice(idx, 1)
            }
            cfg.profiles[i].disabledMonitors = offList
        }
        config = cfg
        saveConfig()
        statusText = off ? "Display off for this profile" : "Display on for this profile"
        clearStatusTimer.restart()
    }
    function setMonitorScale(profileId, monitorId, value) {
        var cfg = root.currentConfig()
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id !== profileId) continue
            var scales = {}
            var prev = cfg.profiles[i].monitorScales || {}
            var keys = Object.keys(prev)
            for (var k = 0; k < keys.length; k++) {
                if (keys[k] !== monitorId) scales[keys[k]] = prev[keys[k]]
            }
            var n = Number(value)
            if (value !== null && value !== undefined && n > 0) scales[monitorId] = n
            cfg.profiles[i].monitorScales = Model.normalizeMonitorScales(scales, cfg.profiles[i].monitors)
        }
        config = cfg
        saveConfig()
        statusText = "Scale saved — applies when this profile applies"
        clearStatusTimer.restart()
    }
    function setMonitorMode(profileId, monitorId, mode) {
        var cfg = root.currentConfig()
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id !== profileId) continue
            var modes = {}
            var prev = cfg.profiles[i].monitorModes || {}
            var keys = Object.keys(prev)
            for (var k = 0; k < keys.length; k++) {
                if (keys[k] !== monitorId) modes[keys[k]] = prev[keys[k]]
            }
            if (mode && Number(mode.width) > 0 && Number(mode.height) > 0) modes[monitorId] = mode
            cfg.profiles[i].monitorModes = Model.normalizeMonitorModes(modes, cfg.profiles[i].monitors)
        }
        config = cfg
        saveConfig()
        statusText = "Resolution saved — applies when this profile applies"
        clearStatusTimer.restart()
    }
    function setMonitorLayout(positions) {
        var cfg = root.currentConfig()
        var pid = cfg.settings.activeProfileId
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id !== pid) continue
            cfg.profiles[i].monitorLayout = Model.normalizeMonitorLayout(positions)
        }
        config = cfg
        saveConfig()
        statusText = "Saved display arrangement"
        clearStatusTimer.restart()
    }
    function captureLiveMonitorLayout() {
        var cfg = root.currentConfig()
        var pid = cfg.settings.activeProfileId
        var prof = Model.profileById(cfg, pid)
        if (!prof) return
        var layout = {}
        var scales = {}
        var modes = {}
        var live = root.liveMonitors || []
        var ids = prof.monitors || []
        if (!ids.length) {
            // A profile with no saved displays adopts the connected ones here.
            for (var c = 0; c < live.length; c++) {
                var got = Model.captureLiveMonitorIntoProfile(cfg, pid, live[c])
                cfg = got.config
                if (got.id && ids.indexOf(got.id) < 0) ids.push(got.id)
            }
            prof = Model.profileById(cfg, pid) || prof
        }
        for (var i = 0; i < ids.length; i++) {
            var saved = Model.monitorById(cfg, ids[i])
            var hit = Model.findLive(saved, live)
            if (!hit) continue
            layout[ids[i]] = { x: Number(hit.x) || 0, y: Number(hit.y) || 0 }
            var sc = Number(hit.scale) || 0
            if (sc > 0) scales[ids[i]] = sc
            if (Number(hit.width) > 0 && Number(hit.height) > 0) {
                modes[ids[i]] = {
                    width: Number(hit.width),
                    height: Number(hit.height),
                    refreshRate: Number(hit.refreshRate) || 60
                }
            }
        }
        for (var p = 0; p < cfg.profiles.length; p++) {
            if (cfg.profiles[p].id === pid) {
                cfg.profiles[p].monitorLayout = Model.normalizeMonitorLayout(layout)
                cfg.profiles[p].monitorScales = Model.normalizeMonitorScales(scales, ids)
                cfg.profiles[p].monitorModes = Model.normalizeMonitorModes(modes, ids)
            }
        }
        config = cfg
        saveConfig()
        statusText = "Captured current arrangement"
        clearStatusTimer.restart()
    }
    function setMatchMode(id, mode) {
        var cfg = root.currentConfig()
        for (var i = 0; i < cfg.profiles.length; i++) if (cfg.profiles[i].id === id) cfg.profiles[i].matchMode = mode === "all-present" ? "all-present" : "exact"
        config = cfg; saveConfig()
    }
    function deleteProfile(id) {
        var cfg = root.currentConfig()
        if ((cfg.profiles || []).length <= 1) { errorText = "Keep at least one profile"; return }
        cfg.profiles = cfg.profiles.filter(function(p){ return p.id !== id })
        if (cfg.settings.activeProfileId === id) cfg.settings.activeProfileId = cfg.profiles[0].id
        config = cfg
        assignments = (Model.profileById(cfg, cfg.settings.activeProfileId) || { assignments: [] }).assignments.slice()
        saveConfig()
    }
    function setApplyOnBoot(on) {
        var cfg = root.currentConfig()
        cfg.settings.applyOnBoot = !!on
        config = cfg
        saveConfig()
    }
    function overflowEnabled() {
        var ov = Model.normalizeOverflow(root.activeProfile.overflow)
        return ov.enabled === true
    }
    function setOverflowEnabled(on) {
        var cfg = root.currentConfig()
        var pid = cfg.settings.activeProfileId
        var last = Model.emptyOverflow()
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id !== pid) continue
            var ov = Model.normalizeOverflow(cfg.profiles[i].overflow)
            ov.enabled = !!on
            if (ov.enabled && !ov.workspaces.length)
                ov.workspaces = Model.unsetWorkspaces(cfg.profiles[i])
            cfg.profiles[i].overflow = ov
            last = ov
        }
        config = cfg
        saveConfig()
        statusText = last.enabled
            ? ("Overflow on · WS " + last.workspaces.join(" → "))
            : "Overflow off"
        clearStatusTimer.restart()
    }
    function overflowMaxWindows() {
        return Model.normalizeOverflow(root.activeProfile.overflow).maxWindows
    }
    function setOverflowMax(n) {
        n = Model.clampVisibleCount(n)
        var cfg = root.currentConfig()
        var pid = cfg.settings.activeProfileId
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id !== pid) continue
            var ov = Model.normalizeOverflow(cfg.profiles[i].overflow)
            ov.maxWindows = n
            cfg.profiles[i].overflow = ov
        }
        config = cfg
        saveConfig()
        overflowDraftMax = n
    }
    function bumpOverflowMax(delta) {
        root.setOverflowMax(root.overflowMaxWindows() + delta)
    }
    function openOverflow() {
        var ov = Model.normalizeOverflow(root.activeProfile.overflow)
        overflowDraft = ov.workspaces.slice()
        overflowDraftMax = ov.maxWindows
        overflowOpen = true
    }
    function closeOverflow() { overflowOpen = false }
    function overflowDraftHas(n) {
        var list = overflowDraft || []
        for (var i = 0; i < list.length; i++) if (Number(list[i]) === Number(n)) return true
        return false
    }
    function toggleOverflowDraft(n) {
        n = Number(n)
        var next = []
        var had = false
        var list = overflowDraft || []
        for (var i = 0; i < list.length; i++) {
            var v = Number(list[i])
            if (v === n) { had = true; continue }
            next.push(v)
        }
        if (!had) next.push(n)
        next.sort(function(a, b) { return a - b })
        overflowDraft = next
    }
    function overflowDraftSetStage() {
        overflowDraft = Model.unsetWorkspaces(root.activeProfile)
    }
    function overflowDraftNone() { overflowDraft = [] }
    function confirmOverflow() {
        var cfg = root.currentConfig()
        var pid = cfg.settings.activeProfileId
        var used = Model.assignedWorkspaceSet(root.activeProfile)
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id !== pid) continue
            var ov = Model.normalizeOverflow({
                enabled: true,
                workspaces: overflowDraft,
                maxWindows: overflowDraftMax
            })
            ov.enabled = true
            cfg.profiles[i].overflow = ov
            var prefs = Model.normalizeWorkspacePrefs(cfg.profiles[i].workspacePrefs)
            var list = ov.workspaces
            for (var w = 0; w < list.length; w++) {
                var ws = String(list[w])
                if (used[list[w]] === true || used[ws] === true) continue
                var pref = Model.normalizeWorkspacePref(prefs[ws])
                pref.layout = "scrolling"
                pref.extras = "block"
                prefs[ws] = pref
            }
            cfg.profiles[i].workspacePrefs = prefs
        }
        config = cfg
        saveConfig()
        overflowOpen = false
        statusText = "Overflow · WS " + (overflowDraft.length ? overflowDraft.join(" → ") : "(empty)")
        clearStatusTimer.restart()
    }
    function setPersistHyprGestures(on) {
        var cfg = root.currentConfig()
        cfg.settings.persistHyprGestures = !!on
        config = cfg
        saveProc.wantsGestures = true
        saveConfig()
    }
    function workspaceHotkey(ws) {
        var map = root.currentHotkeys.workspaces || {}
        return String(map[String(ws)] || "")
    }
    function chordFromEvent(event) {
        var key = event.key
        if (key === Qt.Key_Shift || key === Qt.Key_Control || key === Qt.Key_Alt || key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R)
            return ""
        var mods = []
        if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
        if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
        if (event.modifiers & Qt.AltModifier) mods.push("ALT")
        if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
        var name = Model.qtKeyToHypr(key, event.text)
        if (!name) return ""
        // Hyprland consumes Super+… binds, so a plain/shifted key here means Super.
        if (mods.indexOf("SUPER") < 0 && mods.indexOf("CTRL") < 0 && mods.indexOf("ALT") < 0)
            mods.unshift("SUPER")
        return Model.normalizeChord(mods.concat([name]).join(" + "))
    }
    function startHotkeyCapture(slot) {
        root.hotkeyCapture = String(slot || "")
        statusText = "Press a key (Shift/Ctrl/Alt extra). Super is added. Esc cancels."
        Qt.callLater(function() { if (hotkeyOverlay) hotkeyOverlay.forceActiveFocus() })
    }
    function commitHotkey(slot, chord) {
        var cfg = root.currentConfig()
        cfg.settings.hotkeys = Model.assignHotkey(cfg.settings.hotkeys, slot, chord)
        config = cfg
        saveProc.wantsHotkeys = true
        saveConfig()
        statusText = chord ? ("Hotkey " + chord) : "Hotkey cleared"
        clearStatusTimer.restart()
    }
    function applyHotkeys() {
        hotkeyProc.running = true
        statusText = "Applying hotkeys…"
        clearStatusTimer.restart()
    }
    function applyPreviewLayout(tiles) {
        if (!tiles || !tiles.length) return
        var byId = {}
        for (var t = 0; t < tiles.length; t++) if (tiles[t] && tiles[t].id) byId[tiles[t].id] = tiles[t]
        var next = []
        for (var i = 0; i < assignments.length; i++) {
            var a = Model.clone(assignments[i])
            if (byId[a.id]) {
                var raw = byId[a.id]
                var g = a.place === "float" ? Model.normalizeFloatGeom(raw) : Model.normalizeGeom(raw)
                if (g) a.geom = g
            }
            next.push(a)
        }
        assignments = next
        saveConfig()
        statusText = "Saved window layout on WS" + formWorkspace
        clearStatusTimer.restart()
    }
    function setAssignmentPlace(index, place) {
        var apps = root.addedApps || []
        if (!apps[index]) return
        var packed = Model.setAppsPlace(apps, index, place === "float" ? "float" : "tile", root.currentWsPref.layout, 1 / Math.max(1, root.currentWsPref.visibleCount))
        var byId = {}
        for (var p = 0; p < packed.length; p++) if (packed[p] && packed[p].id) byId[packed[p].id] = packed[p]
        var next = []
        for (var i = 0; i < assignments.length; i++) {
            var a = Model.clone(assignments[i])
            var src = byId[a.id]
            if (src) {
                a.place = src.place
                if (src.geom) a.geom = src.geom
                if (src.geomTiled) a.geomTiled = src.geomTiled
                else delete a.geomTiled
            }
            next.push(a)
        }
        assignments = next
        saveConfig()
        statusText = place === "float" ? "Floated — other tiles filled the gap" : "Tiled — snapped back into the layout"
        clearStatusTimer.restart()
    }
    function applyOrganizerSplit(index, dir) {
        var apps = root.addedApps || []
        if (apps.length < 2) { errorText = "Add another app before splitting"; return }
        if (apps[index] && apps[index].place === "float") { errorText = "Split is for tiled panes"; return }
        var geoms = []
        for (var i = 0; i < apps.length; i++) {
            var raw = apps[i].geom
            geoms.push(apps[i].place === "float" ? (Model.normalizeFloatGeom(raw) || { x: 0.12, y: 0.12, w: 0.4, h: 0.4 }) : (Model.normalizeGeom(raw) || { x: 0, y: 0, w: 1, h: 1 }))
        }
        var other = (index + 1) % apps.length
        if (apps[other] && apps[other].place === "float") {
            other = -1
            for (var j = 0; j < apps.length; j++) {
                if (j !== index && apps[j].place !== "float") { other = j; break }
            }
            if (other < 0) { errorText = "Need another tiled pane to split with"; return }
        }
        if (other === index) return
        var nextG = Model.splitDrop(geoms, other, index, dir)
        var tiles = []
        for (var t = 0; t < apps.length; t++) {
            var g = nextG[t]
            if (g) { g.id = apps[t].id; tiles.push(g) }
        }
        root.applyPreviewLayout(tiles)
    }
    function openChrome(index) {
        var apps = root.addedApps || []
        if (!apps[index]) return
        var c = Model.normalizeChrome(apps[index].chrome)
        chromeIndex = index
        chromeOpA = c.opacityActive
        chromeOpI = c.opacityInactive
        chromeBorderA = c.borderActive
        chromeBorderI = c.borderInactive
        chromeColorA = c.borderColorActive
        chromeColorI = c.borderColorInactive
        chromeBorderSize = c.borderSize
        chromeOpen = true
    }
    function saveChrome() {
        var apps = root.addedApps || []
        if (!apps[chromeIndex]) { chromeOpen = false; return }
        var id = apps[chromeIndex].id
        var chrome = Model.normalizeChrome({
            opacityActive: chromeOpA,
            opacityInactive: chromeOpI,
            borderActive: chromeBorderA,
            borderInactive: chromeBorderI,
            borderColorActive: chromeColorA,
            borderColorInactive: chromeColorI,
            borderSize: chromeBorderSize
        })
        var next = []
        for (var i = 0; i < assignments.length; i++) {
            var a = Model.clone(assignments[i])
            if (a.id === id) {
                if (Model.chromeIsDefault(chrome)) delete a.chrome
                else a.chrome = chrome
            }
            next.push(a)
        }
        assignments = next
        saveConfig()
        chromeOpen = false
        statusText = "Saved window chrome"
        clearStatusTimer.restart()
    }

    function resetPreviewLayout() {
        var next = []
        for (var i = 0; i < assignments.length; i++) {
            var a = Model.clone(assignments[i])
            if (a.workspace === formWorkspace) delete a.geom
            next.push(a)
        }
        assignments = next
        saveConfig()
        statusText = "Reset WS" + formWorkspace + " to tiling"
        clearStatusTimer.restart()
    }
    onFormCommandChanged: { updateFormPreview(); updateAutofillName() }
    Timer { id: clearStatusTimer; interval: 3000; onTriggered: root.statusText = "" }

    function actionCount(app) { return 1 }
    function clampCursor() {
        var rows = filteredApps
        if (rows.length === 0) { selectedRow = 0; selectedButton = 0; return }
        selectedRow = Math.max(0, Math.min(selectedRow, rows.length - 1))
        selectedButton = Math.max(0, Math.min(selectedButton, actionCount(rows[selectedRow]) - 1))
    }
    function setCursor(row, button) { cursorActive = true; selectedRow = row; selectedButton = button; clampCursor() }
    function moveCursor(dx, dy) {
        var rows = filteredApps
        if (rows.length === 0) return
        if (!cursorActive) { setCursor(0, 0); return }
        if (dy !== 0) {
            if (dy < 0 && selectedRow === 0) { cursorActive = false; filterField.forceActiveFocus(); return }
            if (dy > 0 && selectedRow === rows.length - 1) { cursorActive = false; filterField.forceActiveFocus(); return }
            selectedRow = Math.max(0, Math.min(rows.length - 1, selectedRow + dy))
            selectedButton = Math.min(selectedButton, actionCount(rows[selectedRow]) - 1)
        } else if (dx !== 0) {
            selectedButton = Math.max(0, Math.min(actionCount(rows[selectedRow]) - 1, selectedButton + dx))
        }
        cursorActive = true
    }
    function moveTabCursor(direction) {
        var rows = filteredApps
        if (rows.length === 0) return
        if (!cursorActive) { if (direction > 0) setCursor(0, 0); return }
        if (direction > 0) {
            if (selectedRow === rows.length - 1) { cursorActive = false; filterField.forceActiveFocus(); return }
            selectedRow++; selectedButton = 0
        } else {
            if (selectedRow === 0) { cursorActive = false; filterField.forceActiveFocus(); return }
            selectedRow--; selectedButton = actionCount(rows[selectedRow]) - 1
        }
        cursorActive = true
    }
    function activateCursor() {
        var app = filteredApps[selectedRow]
        if (!app) return
        toggleInWorkspace(app.exec, app.name)
    }
    function ensureCursorVisible(item) {
        if (!item || !resultsScroll) return
        var flick = resultsScroll.contentItem
        var point = item.mapToItem(flick.contentItem || flick, 0, 0)
        var top = point.y
        var bottom = top + item.height
        if (top < flick.contentY) flick.contentY = Math.max(0, top - Style.space(8))
        else if (bottom > flick.contentY + flick.height)
            flick.contentY = bottom - flick.height + Style.space(8)
    }

    Process {
        id: loadProc
        command: root.helperRun(["bash", root.script, "--ensure-config"], 8, Model.maxConfigBytes())
        stdout: StdioCollector { id: loadOut; waitForEnd: true }
        stderr: StdioCollector { id: loadErr; waitForEnd: true }
        onExited: function(code){
            root.loading = false; var txt = loadOut.text || ""
            if (code !== 0) { root.errorText = "Failed to load config (" + code + ")"; return }
            try {
                var j = Model.parseCappedJson(txt)
                if (!j) { root.errorText = "Invalid or oversized config JSON"; return }
                var sane = Model.sanitizeConfig(j)
                var repaired = Model.repairOverlappingLayouts(sane, "dwindle", 0.49)
                sane = repaired.config
                root.config = sane
                var prof = Model.profileById(sane, sane.settings.activeProfileId)
                root.assignments = (prof && prof.assignments) ? prof.assignments.slice() : []
                root.formWorkspace = sane.settings.lastFormWorkspace
                root.mainView = Model.allowedMainView(sane.settings.lastMainView)
                var others = []
                for (var p = 0; p < sane.profiles.length; p++)
                    if (sane.profiles[p].id !== sane.settings.activeProfileId) others.push(sane.profiles[p].id)
                if (others.length) root.copyTargetId = others[0]
                root.countsChanged()
                if (repaired.changed) root.saveConfig()
                Qt.callLater(root.syncMonitorDropdown)
            } catch (e) { root.errorText = "Invalid config JSON: " + e }
        }
    }
    Process {
        id: saveProc
        property string pendingJson: ""
        property bool wantsSave: false
        property bool wantsGestures: false
        property bool wantsHotkeys: false
        stdinEnabled: true
        stdout: StdioCollector { id: saveOut; waitForEnd: true }
        stderr: StdioCollector { id: saveErr; waitForEnd: true }
        onStarted: {
            write(saveProc.pendingJson)
            stdinEnabled = false
        }
        onExited: function(code){
            if (code !== 0) { root.errorText = "Save failed (" + code + "): " + (saveErr.text || "") }
            else root.errorText = ""
            if (saveProc.wantsSave) {
                saveProc.wantsSave = false
                saveProc.command = ["python3", "-B", root.stateio, "write-config"]
                saveProc.stdinEnabled = true
                saveProc.running = true
            } else if (code === 0) {
                root.countsChanged(); refreshServiceProc.running = true
                if (saveProc.wantsGestures) {
                    saveProc.wantsGestures = false
                    root.applyGestures()
                }
                if (saveProc.wantsHotkeys) {
                    saveProc.wantsHotkeys = false
                    root.applyHotkeys()
                }
            }
        }
    }
    Process { id: refreshServiceProc; command: ["omarchy-shell", "-q", "io.github.calebhat.workscape", "refreshConfig"] }
    Process {
        id: applyProc
        stdout: SplitParser { onRead: function(d){ console.log("[workscape] " + d) } }
        stderr: SplitParser { onRead: function(d){ console.warn("[workscape] " + d) } }
        onExited: function(code) {
            root.applyBusy = false
            root.statusText = code === 0 ? "Applied" : "Apply failed"
            clearStatusTimer.restart()
            liveProc.running = true
        }
    }
    Process {
        id: captureProc
        stdout: StdioCollector { id: captureOut; waitForEnd: true }
        stderr: StdioCollector { id: captureErr; waitForEnd: true }
        onExited: function(code) {
            if (code !== 0) { errorText = "Capture failed: " + (captureErr.text || code); return }
            try {
                var rows = Model.parseCappedJson(captureOut.text || "[]", 262144)
                if (!Array.isArray(rows)) throw "bad json"
                root.applyCapture(rows)
            } catch (e) {
                errorText = "Capture parse failed"
            }
        }
    }
    Process {
        id: layoutProc
        command: root.helperRun(["bash", root.script, "--hypr-layout"], 5, 256)
        stdout: StdioCollector { id: layoutOut; waitForEnd: true }
        onExited: function(code) {
            if (code !== 0) return
            var txt = (layoutOut.text || "").trim()
            if (!txt) return
            var parts = txt.split("|")
            if (parts[0]) root.hyprLayout = parts[0].trim()
            var cw = parseFloat(parts[1])
            if (!isNaN(cw) && cw > 0.1 && cw < 1.0) root.hyprColumnWidth = cw
        }
    }
    Process {
        id: liveEvalProc
        stdout: StdioCollector { waitForEnd: true }
    }
    Process {
        id: gestureProc
        command: root.helperRun(["python3", root.pluginDir + "/scripts/gestures", "--config", root.configFile, "--profile-id", root.activeProfileId, "--apply"], 8, 8192)
        stdout: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            statusText = code === 0 ? "Gestures applied" : "Gesture apply failed"
            clearStatusTimer.restart()
        }
    }
    Process {
        id: hotkeyProc
        command: root.helperRun(["python3", root.pluginDir + "/scripts/hotkeys", "--config", root.configFile, "--plugin-dir", root.pluginDir, "--apply"], 8, 8192)
        stdout: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            statusText = code === 0 ? "Hotkeys applied" : "Hotkey apply failed"
            clearStatusTimer.restart()
        }
    }
    Process {
        id: liveProc
        command: root.helperRun(["bash", root.script, "--live-status"], 8, Model.maxConfigBytes())
        stdout: StdioCollector { id: liveOut; waitForEnd: true }
        onExited: function(code) {
            if (code !== 0) return
            try {
                var raw = liveOut.text || "{}"
                if (raw === root.lastLiveJson) return
                var j = Model.parseCappedJson(raw)
                if (!j) return
                root.lastLiveJson = raw
                root.liveStatus = j
                root.liveMonitors = j.live || []
                root.liveNetwork = j.network || {}
                root.followLiveMatch()
            } catch (e) {}
        }
    }
    Timer {
        interval: 2500
        running: root.opened
        repeat: true
        onTriggered: if (!liveProc.running) liveProc.running = true
    }
    Process {
        id: appsProc
        command: root.helperRun(["bash", root.script, "--list-apps"], 8, 262144)
        stdout: StdioCollector { id: appsOut; waitForEnd: true }
        onExited: function(code){
            if (code !== 0) return
            var txt = appsOut.text || "", lines = txt.split("\n"), list = []
            for (var i = 0; i < lines.length; i++) {
                var l = lines[i].trim(); if (!l) continue
                var p = l.split("\t"); if (p.length < 2) continue
                list.push({ name: p[0], exec: p[1], icon: p[2] || "", iconPath: p[3] || "", score: Number(p[5]) || 0 })
                if (list.length > 600) break
            }
            root.appList = list
        }
    }
    function alphabeticalCompare(a, b) {
        var na = a.name.toLowerCase(), nb = b.name.toLowerCase()
        return na.localeCompare(nb, undefined, { numeric: true })
    }
    readonly property var appLibrary: root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
    function iconSourceFor(app) {
        if (!app) return ""
        if (app.iconPath && app.iconPath !== "") return "file://" + app.iconPath
        var icon = String(app.icon || "")
        if (root.appLibrary && typeof root.appLibrary.iconSource === "function") return root.appLibrary.iconSource(icon)
        if (icon !== "" && icon.charAt(0) === "/") return "file://" + icon
        var themed = ""
        try { themed = Quickshell.iconPath(icon, true) } catch (e) { themed = "" }
        if (themed && themed.length > 0) return themed
        try { return Quickshell.iconPath("application-x-executable", true) } catch (e) { return "" }
    }
    property var filteredApps: {
        var f = appFilter.trim().toLowerCase()
        var list = []
        for (var i = 0; i < appList.length; i++) list.push(appList[i])
        if (!f) {
            var seen = {}
            var uniq = []
            for (var u = 0; u < list.length; u++) {
                var key = String(list[u].exec || "")
                var nkey = "name:" + String(list[u].name || "").toLowerCase()
                if (seen[key] || seen[nkey]) continue
                seen[key] = true
                seen[nkey] = true
                uniq.push(list[u])
            }
            uniq.sort(function(a, b){
                var aOn = root.isInList(root.addedApps, a.exec) ? 1 : 0
                var bOn = root.isInList(root.addedApps, b.exec) ? 1 : 0
                if (bOn !== aOn) return bOn - aOn
                if (b.score !== a.score) return b.score - a.score
                return root.alphabeticalCompare(a, b)
            })
            return uniq.slice(0, 24)
        }
        var exact = [], prefix = [], sub = []
        var seen = {}
        for (var j = 0; j < list.length; j++) {
            var b = list[j]
            var n = b.name.toLowerCase(), e = b.exec.toLowerCase()
            var nkey = "name:" + n
            if (seen[e] || seen[nkey]) continue
            if (n === f || e === f) exact.push(b)
            else if (n.indexOf(f) === 0) prefix.push(b)
            else if (n.indexOf(f) !== -1 || e.indexOf(f) !== -1) sub.push(b)
            else continue
            seen[e] = true
            seen[nkey] = true
        }
        exact.sort(root.alphabeticalCompare)
        prefix.sort(root.alphabeticalCompare)
        sub.sort(root.alphabeticalCompare)
        return exact.concat(prefix, sub).slice(0, 24)
    }
    function getAppsForWs(ws) {
        var out = []
        for (var i = 0; i < assignments.length; i++) if (assignments[i].workspace === ws) out.push(assignments[i])
        return out
    }
    property var addedApps: {
        var out = []
        for (var i = 0; i < assignments.length; i++) if (assignments[i].workspace === formWorkspace) out.push(assignments[i])
        return out
    }
    readonly property bool lockUiEnabled: currentWsPref.layout !== "set-width"
    readonly property bool lockAllViable: lockUiEnabled && addedApps.length >= 2
    readonly property bool anyLockOnWs: currentWsPref.lockSizes === true || Model.workspaceHasLockedApp(activeProfile, formWorkspace)
    readonly property bool allAssignedLocked: {
        if (currentWsPref.lockSizes === true) return addedApps.length >= 2
        if (addedApps.length < 2) return false
        for (var i = 0; i < addedApps.length; i++) {
            if (addedApps[i].lockPlace !== true) return false
        }
        return true
    }
    function profileMatchBadge(id) {
        var list = (liveStatus.profiles || [])
        for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
        return null
    }
    readonly property string activeMatchLabel: {
        var h = root.activeApplyHint
        return (h && h.text) ? h.text : ""
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.opened && root.hotkeyCapture === ""
        context: Qt.ApplicationShortcut
        onActivated: root.dismissOrClose()
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        centerOnBar: true
        focusTarget: keyCatcher
        padding: Style.space(18)
        contentWidth: panel.fittedContentWidth(Style.space(980))
        contentHeight: panel.fittedContentHeight(Math.round(panel.screenH * 0.78), panel.screenH - Style.gapsOut * 2 - Style.space(12))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            blocked: root.hotkeyCapture !== "" || root.transferOpen || root.newProfileOpen || root.editNetworkOpen || root.overflowOpen || root.organizerOpen || root.chromeOpen || filterField.activeFocus || customField.activeFocus || customNameField.activeFocus || (typeof visibleCountField !== "undefined" && visibleCountField.activeFocus) || (typeof newProfileNameField !== "undefined" && newProfileNameField.activeFocus) || (typeof editNetworkSsidField !== "undefined" && (editNetworkSsidField.activeFocus || editNetworkSubnetField.activeFocus || editNetworkConnField.activeFocus))
            onMoveRequested: function(dx, dy) { if (!root.transferOpen && !root.newProfileOpen && !root.editNetworkOpen && !root.overflowOpen && !root.organizerOpen && !root.chromeOpen) root.moveCursor(dx, dy) }
            onActivateRequested: { if (!root.transferOpen && !root.newProfileOpen && !root.editNetworkOpen && !root.overflowOpen && !root.organizerOpen && !root.chromeOpen) root.activateCursor() }
            onCloseRequested: root.dismissOrClose()
            onTabRequested: function(direction) { root.moveTabCursor(direction) }
            onTextKey: function(t) {
                if (t === "/") {
                    cursorActive = false
                    filterField.forceActiveFocus()
                    filterField.selectAll()
                }
            }

            ColumnLayout {
                id: content
                anchors.fill: parent
                spacing: Style.space(8)

                PanelHero {
                    Layout.fillWidth: true
                    title: "WorkScape"
                    meta: (root.activeProfile.name || "Profile") + " · " + root.totalCount + " apps · " + (root.config.profiles || []).length + " profiles"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    iconComponent: Component {
                        Text {
                            text: "󱂬"
                            color: Color.accent
                            font.family: Style.font.family
                            font.pixelSize: Style.font.display
                        }
                    }
                    trailingControl: Component {
                        Row {
                            spacing: Style.space(6)
                            Button {
                                text: root.applyBusy ? "Applying…" : "Apply matching"
                                tooltipText: "Load the profile for the connected displays. Moves existing workspaces onto that layout’s monitors. Does not close windows — use Fresh to relaunch."
                                enabled: !root.applyBusy
                                onClicked: root.applyMatching()
                            }
                            Button {
                                text: "Fresh Workscape"
                                tooltipText: (root.activeApplyHint && !root.activeApplyHint.canApply)
                                    ? (root.activeApplyHint.refuseText || "This profile doesn't match the connected displays")
                                    : "Close workspaces that have apps in this profile, then apply from scratch. Refused if this profile's displays aren't connected."
                                enabled: !root.applyBusy && root.activeProfileId !== "" && !!(root.activeApplyHint && root.activeApplyHint.canApply)
                                onClicked: root.applyFreshProfile(root.activeProfileId)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(10)
                    Text {
                        text: "PROFILE"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: 1.2
                    }
                    Dropdown {
                        Layout.fillWidth: true
                        label: "Profile"
                        showLabel: false
                        foreground: root.foreground
                        value: root.activeProfileId
                        options: root.profileOptions
                        onChanged: function(v) { if (v && v !== root.activeProfileId) root.setActiveProfile(v) }
                    }
                    Text {
                        visible: root.activeMatchLabel !== ""
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                        text: root.activeMatchLabel
                        color: (root.activeApplyHint && root.activeApplyHint.matches) ? Color.accent : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                    }
                }

                ButtonGroup {
                    Layout.fillWidth: true
                    foreground: root.foreground
                    options: [
                        { value: "profiles", label: "Profiles" },
                        { value: "workspaces", label: "Workspaces" },
                        { value: "displays", label: "Displays" },
                        { value: "gestures", label: "Gestures" }
                    ]
                    value: root.mainView
                    onChanged: function(v) {
                        if (!v || v === root.mainView) return
                        root.mainView = v
                        liveProc.running = true
                        saveConfig()
                    }
                }

                // ——— Workspaces ———
                ColumnLayout {
                    visible: root.mainView === "workspaces"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: Style.space(360)
                    spacing: Style.space(10)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Style.space(12)

                    ColumnLayout {
                        id: leftStack
                        Layout.fillWidth: false
                        Layout.preferredWidth: Math.round(content.width * 0.38)
                        Layout.minimumWidth: Style.space(280)
                        Layout.fillHeight: true
                        spacing: Style.space(10)

                        SectionCard {
                            title: "LAYOUT"
                            hint: Model.layoutDescription(root.currentWsPref.layout, root.currentWsUi.forcedBlock || root.anyLockOnWs)
                            foreground: root.foreground
                            fontFamily: root.fontFamily

                        GridLayout {
                            visible: root.currentWsUi.showLayoutPicker
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: Style.space(4)
                            rowSpacing: Style.space(4)
                            Repeater {
                                model: {
                                    var rows = [{ value: "dwindle", label: "Dwindle" }]
                                    if (root.currentWsUi.showScrollingLayout)
                                        rows.push({ value: "scrolling", label: "Scrolling" })
                                    if (root.currentWsUi.showMasterLayout)
                                        rows.push({ value: "master", label: "Master" })
                                    return rows
                                }
                                delegate: Button {
                                    required property var modelData
                                    text: modelData.label
                                    selected: root.currentWsPref.layout === modelData.value
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Style.space(28)
                                    onClicked: {
                                        if (modelData.value !== root.currentWsPref.layout)
                                            root.setWorkspacePref("layout", modelData.value)
                                    }
                                }
                            }
                        }
                        Text {
                            visible: root.addedApps.length > 0
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            textFormat: Text.PlainText
                            text: "Split shapes stamp pane sizes (and lock them when two or more). Does not change dwindle/scrolling/master."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption - 1
                        }
                        GridLayout {
                            visible: root.addedApps.length > 0
                            Layout.fillWidth: true
                            columns: 3
                            columnSpacing: Style.space(4)
                            rowSpacing: Style.space(4)
                            Repeater {
                                model: Model.shapePresets()
                                delegate: Button {
                                    required property var modelData
                                    text: modelData.name
                                    tooltipText: Model.describeShape(modelData)
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Style.space(28)
                                    onClicked: root.applyWorkspaceShape(modelData.id)
                                }
                            }
                        }
                        RowLayout {
                            visible: root.currentWsUi.showVisibleCount
                            Layout.fillWidth: true
                            spacing: Style.space(6)
                            Text {
                                text: "Visible columns"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                            }
                            HintMark {
                                tooltipText: Model.visibleCountHelp(root.currentWsPref.visibleCount, root.anyLockOnWs, root.currentWsPref.layout)
                            }
                            Button {
                                text: "−"
                                enabled: root.currentWsPref.visibleCount > 1
                                Layout.preferredHeight: Style.space(28)
                                Layout.preferredWidth: Style.space(28)
                                onClicked: root.bumpVisibleCount(-1)
                            }
                            TextField {
                                id: visibleCountField
                                Layout.preferredWidth: Style.space(52)
                                Layout.preferredHeight: Style.space(28)
                                foreground: root.foreground
                                horizontalAlignment: Text.AlignHCenter
                                validator: IntValidator { bottom: 1; top: 20 }
                                inputMethodHints: Qt.ImhDigitsOnly
                                text: String(root.currentWsPref.visibleCount)
                                onAccepted: root.commitVisibleCount()
                                onEditingFinished: root.commitVisibleCount()
                            }
                            Button {
                                text: "+"
                                enabled: root.currentWsPref.visibleCount < 20
                                Layout.preferredHeight: Style.space(28)
                                Layout.preferredWidth: Style.space(28)
                                onClicked: root.bumpVisibleCount(1)
                            }
                        }
                        }

                        SectionCard {
                            title: "APPS"
                            hint: "Toggle apps onto this workspace. Custom command adds something that is not in the list."
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            fillAvailable: true
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(6)
                            TextField {
                                id: filterField
                                Layout.fillWidth: true
                                verticalPadding: Style.space(6)
                                placeholderText: "Search apps"
                                foreground: root.foreground
                                accent: Color.accent
                                font.family: root.fontFamily
                                text: root.appFilter
                                onTextChanged: { root.appFilter = text; root.cursorActive = false }
                                Keys.onPressed: function(event) {
                                    if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
                                    else if (event.key === Qt.Key_Down) { root.setCursor(0, 0); keyCatcher.forceActiveFocus(); event.accepted = true }
                                }
                            }
                            Button { text: "⟳"; tooltipText: "Refresh app list"; verticalPadding: Style.space(6); onClicked: { appsProc.running = true; liveProc.running = true } }
                        }

                        Text {
                            visible: root.filteredApps.length === 0 && root.appFilter.trim().length > 0
                            Layout.fillWidth: true
                            text: "No matches — add a custom command below"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }

                        ScrollView {
                            id: resultsScroll
                            visible: root.filteredApps.length > 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: Style.space(240)
                            clip: true
                            rightPadding: Style.space(16)
                            contentWidth: availableWidth
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            ScrollBar.vertical.policy: ScrollBar.AsNeeded
                            Column {
                                width: resultsScroll.availableWidth
                                spacing: Style.space(3)
                                Repeater {
                                    model: root.filteredApps
                                    delegate: AppRow {
                                        app: modelData
                                        rowIndex: index
                                        width: parent.width
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(6)
                            TextField {
                                id: customNameField
                                Layout.preferredWidth: Style.space(88)
                                placeholderText: "Name"
                                foreground: root.foreground
                                text: root.customName
                                onTextChanged: root.customName = text
                            }
                            TextField {
                                id: customField
                                Layout.fillWidth: true
                                placeholderText: "Custom command"
                                foreground: root.foreground
                                text: root.customCommand
                                onTextChanged: root.customCommand = text
                                Keys.onReturnPressed: root.addCustomCommand()
                            }
                            Button { text: "Add"; onClicked: root.addCustomCommand() }
                        }
                        }
                    }

                    ColumnLayout {
                        id: rightStack
                        Layout.fillWidth: true
                        Layout.preferredWidth: Math.round(content.width * 0.62)
                        Layout.fillHeight: true
                        spacing: Style.space(10)

                        SectionCard {
                            title: "WORKSPACE " + root.formWorkspace
                            hint: "Settings on this card apply only to the selected workspace number."
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            tools: Button {
                                text: "Restore defaults"
                                tooltipText: "On empty workspaces in this profile: restore Omarchy dwindle and drop leftover scroll rules. Does not close windows. Occupied unassigned workspaces keep their layout until empty. Fill next overflow workspaces stay in that chain."
                                onClicked: root.resetEmptyWorkspaces()
                            }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 10
                            columnSpacing: Style.space(3)
                            rowSpacing: Style.space(3)
                            Repeater {
                                model: 10
                                delegate: Button {
                                    required property int index
                                    text: String(index + 1)
                                    selected: root.workspacePicked && root.formWorkspace === (index + 1)
                                    horizontalPadding: 0
                                    verticalPadding: 0
                                    tooltipText: "Edit WS " + (index + 1)
                                    onClicked: root.selectWorkspace(index + 1)
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Style.space(30)
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Text {
                                text: "WS " + root.formWorkspace
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }
                            Dropdown {
                                id: monitorDropdown
                                visible: root.showMonitorPicker
                                Layout.fillWidth: true
                                label: ""
                                showLabel: false
                                foreground: root.foreground
                                value: root.workspaceMonitorId
                                options: root.monitorOptions
                                onChanged: function(v) {
                                    if (v === root.workspaceMonitorId) return
                                    root.setWorkspaceMonitor(v)
                                }
                            }
                            Text {
                                visible: !root.showMonitorPicker
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                                text: root.monitorOptions.length ? ("All workspaces → " + root.monitorOptions[0].label) : ""
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                            }
                            TextField {
                                Layout.preferredWidth: Style.space(120)
                                placeholderText: "Name"
                                foreground: root.foreground
                                text: (root.activeProfile.workspaceNames && root.activeProfile.workspaceNames[String(root.formWorkspace)]) || ""
                                onEditingFinished: root.setWorkspaceName(root.formWorkspace, text)
                            }
                            Button {
                                text: "Capture WS"
                                tooltipText: "Replace this workspace’s presets with the windows that are open now, including the live split ratios (cwd for terminals, URL for web apps when exposed)"
                                onClicked: root.captureWorkspace()
                            }
                            Button {
                                text: "Copy / move"
                                tooltipText: "Copy this workspace to another profile or move it to another number"
                                onClicked: root.openTransfer("copy")
                            }
                        }
                        RowLayout {
                            visible: root.currentWsUi.showExtrasToggle
                            Layout.fillWidth: true
                            spacing: Style.space(4)
                            WrapToggle {
                                id: extrasToggle
                                Layout.fillWidth: true
                                label: "Keep extra windows on this workspace"
                                checked: root.currentWsPref.extras !== "block"
                                foreground: root.foreground
                                onClicked: root.setWorkspacePref("extras", root.currentWsPref.extras === "block" ? "around" : "block")
                            }
                            HintMark {
                                tooltipText: "On: extras stay on this workspace (Hyprland tiling). Off: extras still open, then move to the next unused workspace. Assigned workspaces and leave-alone pins are skipped."
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(6)
                            Text {
                                text: "Hotkey"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                            }
                            HintMark {
                                tooltipText: "Opens this workspace’s saved apps and split on whatever workspace is focused. Skips if that workspace already has windows. Replaces any existing Hyprland bind for the chord."
                            }
                            Text {
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: root.hotkeyCapture === ("ws:" + root.formWorkspace)
                                    ? "Press a chord…"
                                    : (root.workspaceHotkey(root.formWorkspace) || "Not set")
                                color: root.hotkeyCapture === ("ws:" + root.formWorkspace) ? Color.accent : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                elide: Text.ElideRight
                            }
                            Button {
                                bordered: true
                                selected: root.hotkeyCapture === ("ws:" + root.formWorkspace)
                                text: root.hotkeyCapture === ("ws:" + root.formWorkspace)
                                    ? "Press a key…"
                                    : (root.workspaceHotkey(root.formWorkspace) ? "Change" : "Set")
                                tooltipText: "Click, then press the key. Super is included; hold Shift/Ctrl/Alt for extra mods. Esc cancels."
                                onClicked: {
                                    if (root.hotkeyCapture === ("ws:" + root.formWorkspace)) root.hotkeyCapture = ""
                                    else root.startHotkeyCapture("ws:" + root.formWorkspace)
                                }
                            }
                            Button {
                                visible: root.workspaceHotkey(root.formWorkspace) !== ""
                                bordered: true
                                text: "Clear"
                                onClicked: root.commitHotkey(String(root.formWorkspace), "")
                            }
                        }
                        Text {
                            visible: root.showMonitorPicker
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            textFormat: Text.PlainText
                            text: root.workspaceMonitorSummary
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption - 1
                        }
                        }

                        SectionCard {
                            title: "PREVIEW · " + root.activeProfile.name
                            hint: root.addedApps.length > 1
                                ? "Drag splitters (snap; Shift free; double-click evens). 🔓 locks pane size. Apply keeps locked widths."
                                : (root.addedApps.length === 1 ? "Add another app to split this workspace." : "Toggle apps in the list to place them on this workspace.")
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            fillAvailable: true
                            tools: Button {
                                text: "Expand"
                                tooltipText: "Full organizer: split, drag-and-drop, float, opacity"
                                onClicked: root.organizerOpen = true
                            }
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: Style.space(140)
                            clip: true
                            WorkspacePreview {
                                anchors.fill: parent
                                bar: root.bar
                                workspace: root.formWorkspace
                                assignedApps: root.addedApps
                                lockAll: root.lockUiEnabled && (root.currentWsPref.lockSizes === true || root.allAssignedLocked)
                                appList: root.appList
                                screenW: panel.screenW
                                screenH: panel.screenH
                                hyprLayout: root.currentWsPref.layout
                                columnWidth: 1 / Math.max(1, root.currentWsPref.visibleCount)
                                onLayoutChanged: function(tiles) { root.applyPreviewLayout(tiles) }
                                onLayoutCleared: root.resetPreviewLayout()
                                onAppLockToggled: function(id) { root.toggleAppLockById(id) }
                                onOrganizerRequested: root.organizerOpen = true
                                onWindowRemoved: function(id) { root.removeAssignment(id) }
                            }
                        }
                        }
                    }
                }
                }

                // ——— Displays (selected profile) ———
                ColumnLayout {
                    visible: root.mainView === "displays"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Style.space(10)
                    SectionCard {
                        title: "MATCH AND APPLY"
                        hint: "Displays for “" + root.activeProfile.name + "”. Exact needs every saved monitor and no extras. All-present allows extra displays. At least one display must stay on."
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(8)
                        Button { text: "Use current arrangement"; onClicked: root.captureLiveMonitorLayout() }
                        Button {
                            text: root.activeProfile.matchMode === "all-present" ? "Match: all present" : "Match: exact"
                            onClicked: root.setMatchMode(root.activeProfileId, root.activeProfile.matchMode === "all-present" ? "exact" : "all-present")
                        }
                        Item { Layout.fillWidth: true }
                        Button {
                            text: "Apply this profile"
                            enabled: !root.applyBusy && !!(root.activeApplyHint && root.activeApplyHint.canApply)
                            tooltipText: (root.activeApplyHint && !root.activeApplyHint.canApply)
                                ? (root.activeApplyHint.refuseText || "This profile doesn't match the connected displays")
                                : "Bind workspaces and launch this profile. Refused if its displays aren't connected."
                            onClicked: root.applyProfile(root.activeProfileId)
                        }
                        Button {
                            text: "Fresh Workscape"
                            enabled: !root.applyBusy && !!(root.activeApplyHint && root.activeApplyHint.canApply)
                            tooltipText: (root.activeApplyHint && !root.activeApplyHint.canApply)
                                ? (root.activeApplyHint.refuseText || "This profile doesn't match the connected displays")
                                : "Close only workspaces that have apps in this profile, then apply empty. Workspaces with no assigned apps are not closed."
                            onClicked: root.applyFreshProfile(root.activeProfileId)
                        }
                    }
                    }
                    SectionCard {
                        title: "ARRANGEMENT"
                        hint: "Drag displays to arrange; edges snap. Toggle a display off only when at least one stays on. Scale and resolution are saved per display and re-applied with this profile. Connected displays this profile does not know about are listed too — on a laptop that always includes the built-in panel — and picking a scale or resolution adopts them."
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        fillAvailable: true
                    Repeater {
                        id: arrangeRows
                        model: Model.profileDisplayRows(root.config, root.activeProfile, root.liveMonitors)
                        delegate: ColumnLayout {
                            required property var modelData
                            readonly property string monitorId: String(modelData.id)
                            readonly property string rowLabel: String(modelData.label || monitorId)
                            readonly property bool pending: modelData.pending === true
                            readonly property var profile: root.activeProfile
                            readonly property int onCount: (profile.monitors || []).length - (profile.disabledMonitors || []).length
                            readonly property bool isOff: (profile.disabledMonitors || []).indexOf(monitorId) >= 0
                            readonly property bool canTurnOff: onCount > 1
                            readonly property var liveHit: modelData.live || null
                            readonly property real liveScale: liveHit ? (Number(liveHit.scale) || 0) : 0
                            readonly property var savedScale: profile.monitorScales ? profile.monitorScales[monitorId] : undefined
                            readonly property var savedMode: profile.monitorModes ? profile.monitorModes[monitorId] : undefined
                            readonly property var scaleSteps: [0, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
                            readonly property var modeSteps: {
                                var list = []
                                var seen = {}
                                var modes = (liveHit && liveHit.availableModes) || []
                                for (var i = 0; i < modes.length; i++) {
                                    var p = Model.parseModeString(modes[i])
                                    if (!p) continue
                                    var key = p.width + "x" + p.height + "@" + Math.round(p.refreshRate)
                                    if (seen[key]) continue
                                    seen[key] = true
                                    list.push(p)
                                }
                                list.sort(function(a, b) {
                                    return (b.width * b.height) - (a.width * a.height) || (b.refreshRate - a.refreshRate)
                                })
                                return [null].concat(list.slice(0, 12))
                            }
                            function modeLabel(p) {
                                if (!p) return liveHit ? "Auto (" + liveHit.width + "x" + liveHit.height + ")" : "Auto"
                                return p.width + "x" + p.height + "@" + (Math.round(p.refreshRate * 100) / 100) + "Hz"
                            }
                            function captureId() {
                                if ((profile.monitors || []).indexOf(monitorId) >= 0) return monitorId
                                if (!liveHit) return ""
                                var res = Model.captureLiveMonitorIntoProfile(root.currentConfig(), root.activeProfileId, liveHit)
                                if (!res.id) return ""
                                root.config = res.config
                                return res.id
                            }
                            function cycleScale() {
                                var id = captureId()
                                if (!id) return
                                var cur = (savedScale === undefined || savedScale === null) ? 0 : Number(savedScale)
                                var idx = -1
                                for (var s = 0; s < scaleSteps.length; s++) {
                                    if (Math.abs(scaleSteps[s] - cur) < 0.001) { idx = s; break }
                                }
                                var next = idx < 0 ? 0 : scaleSteps[(idx + 1) % scaleSteps.length]
                                root.setMonitorScale(root.activeProfileId, id, next === 0 ? null : next)
                            }
                            function cycleMode() {
                                var id = captureId()
                                if (!id) return
                                var idx = -1
                                for (var s = 0; s < modeSteps.length; s++) {
                                    var p = modeSteps[s]
                                    if (savedMode && p && p.width === Number(savedMode.width)
                                            && p.height === Number(savedMode.height)
                                            && Math.abs(p.refreshRate - Number(savedMode.refreshRate)) < 0.5) { idx = s; break }
                                }
                                var next = idx < 0 ? 0 : modeSteps[(idx + 1) % modeSteps.length]
                                root.setMonitorMode(root.activeProfileId, id, next)
                            }
                            Layout.fillWidth: true
                            spacing: Style.space(4)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(8)
                                Text {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: rowLabel + (isOff ? " — off" : "") + (pending ? " — connected, not saved in this profile yet" : "")
                                    color: (isOff || pending) ? root.dim : root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    wrapMode: Text.WordWrap
                                }
                                ToggleSwitch {
                                    visible: onCount > 1 || isOff
                                    checked: !isOff
                                    foreground: root.foreground
                                    accent: Color.accent
                                    opacity: (isOff || canTurnOff) ? 1 : 0.4
                                    onToggled: {
                                        if (!isOff && !canTurnOff) return
                                        root.setMonitorDisabled(root.activeProfileId, monitorId, checked === false)
                                    }
                                }
                            }
                            RowLayout {
                                visible: !isOff
                                Layout.fillWidth: true
                                spacing: Style.space(8)
                                Text {
                                    text: "Scale · Res"
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                }
                                Button {
                                    text: {
                                        if (savedScale !== undefined && savedScale !== null)
                                            return "Scale: " + savedScale + "×"
                                        return liveScale > 0 ? "Scale: Auto (" + liveScale + "×)" : "Scale: Auto"
                                    }
                                    selected: savedScale !== undefined && savedScale !== null
                                    onClicked: cycleScale()
                                }
                                Button {
                                    visible: modeSteps.length > 1
                                    text: "Res: " + modeLabel(savedMode || null)
                                    selected: savedMode !== undefined && savedMode !== null
                                    onClicked: cycleMode()
                                }
                                HintMark {
                                    tooltipText: "Auto keeps whatever the display runs now. A picked scale or resolution is re-applied to this display every time the profile applies. Saved per profile — the same display can run different settings elsewhere."
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                    Text {
                        visible: arrangeRows.count === 0
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: "No displays detected — the live list loads when the panel opens."
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                    }
                    MonitorLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: Style.space(320)
                        tiles: Model.monitorLayoutTiles(root.config, root.activeProfile, root.liveMonitors)
                        onLayoutChanged: function(positions) { root.setMonitorLayout(positions) }
                    }
                    }
                }

                // ——— Gestures ———
                ScrollView {
                    id: gestureScroll
                    visible: root.mainView === "gestures"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    rightPadding: Style.space(16)
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ColumnLayout {
                        id: gestureCol
                        width: gestureScroll.availableWidth
                        spacing: Style.space(14)

                        SectionCard {
                            title: "SCOPE"
                            hint: "Global is the default and applies for every profile. This profile is a separate set for the header profile only — those edits do not change Global."
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            ButtonGroup {
                                Layout.fillWidth: true
                                foreground: root.foreground
                                value: (root.config.settings && root.config.settings.gestureSource) === "profile" ? "profile" : "global"
                                options: [
                                    { value: "global", label: "Global" },
                                    { value: "profile", label: "This profile" }
                                ]
                                onChanged: function(v) {
                                    var cur = (root.config.settings && root.config.settings.gestureSource) === "profile" ? "profile" : "global"
                                    if (v !== cur) root.setGestureSource(v)
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                WrapToggle {
                                    Layout.fillWidth: true
                                    label: "Keep swipes after Hyprland reload"
                                    checked: root.config.settings && root.config.settings.persistHyprGestures === true
                                    foreground: root.foreground
                                    onClicked: root.setPersistHyprGestures(!(root.config.settings && root.config.settings.persistHyprGestures === true))
                                }
                                HintMark { tooltipText: "Off by default. On writes ~/.config/hypr/workscape-gestures.lua and a require in hyprland.lua (backed up). Undo with workscape.sh --restore-hypr. Session swipe still evals without this." }
                            }
                        }

                        SectionCard {
                            title: "TRACKPAD SWIPE"
                            hint: "Horizontal swipe switches workspaces. Finger count sits on the same row as the master toggle."
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(8)
                                WrapToggle {
                                    Layout.fillWidth: true
                                    label: "Workspace swipe"
                                    checked: root.currentGestures.workspaceSwipe
                                    foreground: root.foreground
                                    onClicked: root.setGestureField("workspaceSwipe", !root.currentGestures.workspaceSwipe)
                                }
                                HintMark { tooltipText: "Horizontal swipe switches workspaces." }
                                RowLayout {
                                    visible: root.currentGestures.workspaceSwipe
                                    spacing: Style.space(4)
                                    Text {
                                        text: "Fingers"
                                        color: root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                    }
                                    Button { text: "3"; selected: root.currentGestures.fingers === 3; onClicked: { if (root.currentGestures.fingers !== 3) root.setGestureField("fingers", 3) } }
                                    Button { text: "4"; selected: root.currentGestures.fingers === 4; onClicked: { if (root.currentGestures.fingers !== 4) root.setGestureField("fingers", 4) } }
                                }
                            }
                            ColumnLayout {
                                visible: root.currentGestures.workspaceSwipe
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(8)
                                    Text {
                                        text: "Swipe method"
                                        color: root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                    }
                                    ButtonGroup {
                                        Layout.fillWidth: true
                                        foreground: root.foreground
                                        value: root.currentGestures.invert === false ? "swap" : "natural"
                                        options: [
                                            { value: "natural", label: "Natural" },
                                            { value: "swap", label: "Swap left / right" }
                                        ]
                                        onChanged: function(v) {
                                            var invert = v !== "swap"
                                            if (root.currentGestures.invert !== invert)
                                                root.setGestureField("invert", invert)
                                        }
                                    }
                                    HintMark {
                                        tooltipText: root.currentGestures.invert
                                            ? "Natural: swipe the workspace strip with your fingers (Hyprland default)."
                                            : "Swapped: reverse which workspace a left or right swipe selects."
                                    }
                                }
                            }
                            RowLayout {
                                visible: root.currentGestures.workspaceSwipe
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                WrapToggle {
                                    Layout.fillWidth: true
                                    label: "Skip empty workspaces"
                                    checked: root.currentGestures.skipEmpty
                                    foreground: root.foreground
                                    onClicked: root.setGestureField("skipEmpty", !root.currentGestures.skipEmpty)
                                }
                                HintMark { tooltipText: "On: only workspaces with windows. Off: every number, empty included. Keyboard SUPER+,/. follows this." }
                            }
                            RowLayout {
                                visible: root.currentGestures.workspaceSwipe
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                WrapToggle {
                                    Layout.fillWidth: true
                                    label: "Keep workspaces 1–10 even when empty"
                                    checked: root.activeProfile.persistentWorkspaces === true
                                    foreground: root.foreground
                                    onClicked: root.setProfileField("persistentWorkspaces", !(root.activeProfile.persistentWorkspaces === true))
                                }
                                HintMark { tooltipText: "So “include empty” has a full row of workspaces to land on." }
                            }
                            RowLayout {
                                visible: root.currentGestures.workspaceSwipe
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                WrapToggle {
                                    Layout.fillWidth: true
                                    label: "Include empty workspaces on touchscreen"
                                    checked: root.currentGestures.touch
                                    foreground: root.foreground
                                    onClicked: root.setGestureField("touch", !root.currentGestures.touch)
                                }
                                HintMark { tooltipText: "Also swipe from the display edge (Hyprland workspace_swipe_touch)." }
                            }
                            RowLayout {
                                visible: root.currentGestures.workspaceSwipe
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                WrapToggle {
                                    Layout.fillWidth: true
                                    label: "Create a new workspace past the last one"
                                    checked: root.currentGestures.createNew
                                    foreground: root.foreground
                                    onClicked: root.setGestureField("createNew", !root.currentGestures.createNew)
                                }
                                HintMark { tooltipText: "Swiping off the end opens a fresh empty workspace." }
                            }
                            RowLayout {
                                visible: root.currentGestures.workspaceSwipe
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                WrapToggle {
                                    Layout.fillWidth: true
                                    label: "Keep swiping beyond the next workspace"
                                    checked: root.currentGestures.forever
                                    foreground: root.foreground
                                    onClicked: root.setGestureField("forever", !root.currentGestures.forever)
                                }
                                HintMark { tooltipText: "One swipe can pass several workspaces instead of stopping at the next." }
                            }
                        }

                        SectionCard {
                            title: "KEYBOARD"
                            hint: "SUPER+, / . is previous and next workspace (follows Skip empty). On scrolling, Super+Left/Right pan columns on this workspace."
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                WrapToggle {
                                    Layout.fillWidth: true
                                    label: "SUPER + , / .  previous and next workspace"
                                    checked: root.currentGestures.keyboard
                                    foreground: root.foreground
                                    onClicked: root.setGestureField("keyboard", !root.currentGestures.keyboard)
                                }
                                HintMark { tooltipText: "Comma and period (the < > keys). Follows Skip empty above." }
                            }
                        }

                        SectionCard {
                            title: "HOTKEYS"
                            hint: "Global chords. Apply matching restores the saved layout (occupied workspaces stay). Fresh matching closes this layout’s preset workspaces, then applies empty. Per-workspace chords are on the Workspaces tab."
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(6)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(6)
                                    Text {
                                        text: "Apply matching"
                                        color: root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        Layout.preferredWidth: Style.space(120)
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: root.hotkeyCapture === "applyMatching" ? "Press a chord…" : (root.currentHotkeys.applyMatching || "Not set")
                                        color: root.hotkeyCapture === "applyMatching" ? Color.accent : root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        elide: Text.ElideRight
                                    }
                                    Button {
                                        bordered: true
                                        selected: root.hotkeyCapture === "applyMatching"
                                        text: root.hotkeyCapture === "applyMatching" ? "Press a key…" : (root.currentHotkeys.applyMatching ? "Change" : "Set")
                                        tooltipText: "Click, then press the key. Super is included; hold Shift/Ctrl/Alt for extra mods."
                                        onClicked: {
                                            if (root.hotkeyCapture === "applyMatching") root.hotkeyCapture = ""
                                            else root.startHotkeyCapture("applyMatching")
                                        }
                                    }
                                    Button {
                                        visible: root.currentHotkeys.applyMatching !== ""
                                        text: "Clear"
                                        onClicked: root.commitHotkey("applyMatching", "")
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(6)
                                    Text {
                                        text: "Fresh matching"
                                        color: root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        Layout.preferredWidth: Style.space(120)
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: root.hotkeyCapture === "applyFresh" ? "Press a chord…" : (root.currentHotkeys.applyFresh || "Not set")
                                        color: root.hotkeyCapture === "applyFresh" ? Color.accent : root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        elide: Text.ElideRight
                                    }
                                    Button {
                                        bordered: true
                                        selected: root.hotkeyCapture === "applyFresh"
                                        text: root.hotkeyCapture === "applyFresh" ? "Press a key…" : (root.currentHotkeys.applyFresh ? "Change" : "Set")
                                        tooltipText: "Click, then press the key. Super is included; hold Shift/Ctrl/Alt for extra mods."
                                        onClicked: {
                                            if (root.hotkeyCapture === "applyFresh") root.hotkeyCapture = ""
                                            else root.startHotkeyCapture("applyFresh")
                                        }
                                    }
                                    Button {
                                        visible: root.currentHotkeys.applyFresh !== ""
                                        text: "Clear"
                                        onClicked: root.commitHotkey("applyFresh", "")
                                    }
                                }
                            }
                        }

                        SectionCard {
                            title: "SCRATCHPAD"
                            hint: "Opens Omarchy’s special:scratchpad (same as SUPER+S)."
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(8)
                                WrapToggle {
                                    Layout.fillWidth: true
                                    label: "Swipe down for scratchpad"
                                    checked: root.currentGestures.scratchpadSwipe
                                    foreground: root.foreground
                                    onClicked: root.setGestureField("scratchpadSwipe", !root.currentGestures.scratchpadSwipe)
                                }
                                HintMark { tooltipText: "Opens Omarchy’s special:scratchpad (same as SUPER+S)." }
                                RowLayout {
                                    visible: root.currentGestures.scratchpadSwipe
                                    spacing: Style.space(4)
                                    Text {
                                        text: "Fingers"
                                        color: root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                    }
                                    Button { text: "3"; selected: root.currentGestures.scratchpadFingers === 3; onClicked: root.setGestureField("scratchpadFingers", 3) }
                                    Button { text: "4"; selected: root.currentGestures.scratchpadFingers === 4; onClicked: root.setGestureField("scratchpadFingers", 4) }
                                }
                            }
                        }

                        SectionCard {
                            title: "AFTER APPLY"
                            hint: "Which workspace to focus after Apply matching. Stay leaves the current workspace."
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            Flow {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Button {
                                    text: "Stay"
                                    selected: (root.activeProfile.defaultWorkspace || 0) === 0
                                    onClicked: root.setProfileField("defaultWorkspace", 0)
                                }
                                Repeater {
                                    model: 10
                                    delegate: Button {
                                        required property int index
                                        text: String(index + 1)
                                        selected: root.activeProfile.defaultWorkspace === (index + 1)
                                        onClicked: root.setProfileField("defaultWorkspace", index + 1)
                                    }
                                }
                            }
                        }
                    }
                }

                // ——— Profiles catalog ———
                ColumnLayout {
                    visible: root.mainView === "profiles"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Style.space(10)

                    SectionCard {
                        title: "LOGIN"
                        hint: "Picks one profile from connected displays, then Wi-Fi name / LAN subnet if you bound a network. One layout per environment. Middle-click the bar chip or Apply matching any time."
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        WrapToggle {
                            Layout.fillWidth: true
                            label: "Apply matching profile at login"
                            checked: root.config.settings && root.config.settings.applyOnBoot === true
                            foreground: root.foreground
                            onClicked: root.setApplyOnBoot(!(root.config.settings && root.config.settings.applyOnBoot === true))
                        }
                    }

                    SectionCard {
                        visible: Model.profileControlFlags(root.activeProfile).showOverflowCard
                        title: "STAGE OVERFLOW · " + (root.activeProfile.name || "Profile")
                        hint: "Profile-wide chain of unused workspaces. When this is on, extras bounced from a block workspace fill the chosen workspaces in order, up to a max per workspace."
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            WrapToggle {
                                Layout.fillWidth: true
                                label: "Fill next open workspace"
                                description: Model.overflowSummary(root.activeProfile)
                                checked: root.overflowEnabled()
                                foreground: root.foreground
                                onClicked: root.setOverflowEnabled(!root.overflowEnabled())
                            }
                            HintMark {
                                visible: root.overflowEnabled()
                                tooltipText: "Max windows is for this overflow chain only — not Visible columns on a scrolling workspace. Choose… picks which of 1–20 are in the chain; Fill unused selects workspaces with no pinned apps."
                            }
                            Button {
                                visible: root.overflowEnabled()
                                text: "−"
                                enabled: root.overflowMaxWindows() > 1
                                Layout.preferredHeight: Style.space(28)
                                Layout.preferredWidth: Style.space(28)
                                tooltipText: "Global max windows per overflow workspace (not Visible columns on a scrolling workspace)"
                                onClicked: root.bumpOverflowMax(-1)
                            }
                            Text {
                                visible: root.overflowEnabled()
                                text: String(root.overflowMaxWindows())
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }
                            Button {
                                visible: root.overflowEnabled()
                                text: "+"
                                enabled: root.overflowMaxWindows() < 20
                                Layout.preferredHeight: Style.space(28)
                                Layout.preferredWidth: Style.space(28)
                                tooltipText: "Global max windows per overflow workspace"
                                onClicked: root.bumpOverflowMax(1)
                            }
                            Button {
                                visible: root.overflowEnabled()
                                text: "Choose…"
                                tooltipText: "Pick which of 1–20 are in this profile’s overflow chain. Fill unused selects unused workspaces."
                                onClicked: root.openOverflow()
                            }
                        }
                    }

                    SectionCard {
                        title: "PROFILES"
                        hint: "Save the current monitor and window layout as a new profile, or refresh live displays and network."
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        fillAvailable: true
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Button { text: "Save current layout as profile"; onClicked: root.openNewProfile() }
                            Button { text: "Refresh layout"; onClicked: liveProc.running = true }
                        }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                        text: {
                            var live = root.liveMonitors || []
                            var mon = "No monitors reported by Hyprland."
                            if (live.length) {
                                var parts = []
                                for (var i = 0; i < live.length; i++) parts.push(live[i].label || live[i].description || live[i].name)
                                mon = "Connected now: " + parts.join(" · ")
                            }
                            return mon + "  ·  " + Model.liveNetworkSummary(root.liveNetwork)
                        }
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                    Text {
                        visible: root.liveStatus.conflict === true
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                        text: {
                            var ids = root.liveStatus.conflictProfileIds || []
                            var names = []
                            var list = root.config.profiles || []
                            for (var i = 0; i < ids.length; i++) {
                                for (var p = 0; p < list.length; p++) if (list[p].id === ids[i]) names.push(list[p].name)
                            }
                            return "Also matches " + names.join(", ") + ". Bound-network profiles win; only one layout applies."
                        }
                        color: Color.urgent || "#ff4444"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                    ScrollView {
                        id: profilesScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        rightPadding: Style.space(16)
                        contentWidth: availableWidth
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        Column {
                            width: profilesScroll.availableWidth
                            spacing: Style.space(8)
                            Repeater {
                                model: root.config.profiles || []
                                delegate: Rectangle {
                                    id: profileCard
                                    required property var modelData
                                    readonly property bool selected: modelData.id === root.activeProfileId
                                    readonly property bool hot: cardHover.hovered
                                    width: parent.width
                                    implicitHeight: col.implicitHeight + Style.space(16)
                                    radius: Style.cornerRadius
                                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, selected ? (hot ? 0.18 : 0.10) : (hot ? 0.12 : 0.05))
                                    border.width: 1
                                    border.color: hot
                                        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.65)
                                        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, selected ? 0.35 : 0.12)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on border.color { ColorAnimation { duration: 120 } }
                                    HoverHandler {
                                        id: cardHover
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        z: 0
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.setActiveProfile(modelData.id)
                                            root.mainView = "workspaces"
                                            saveConfig()
                                        }
                                    }
                                    ColumnLayout {
                                        id: col
                                        z: 1
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.margins: Style.space(10)
                                        spacing: Style.space(6)
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: modelData.name
                                                textFormat: Text.PlainText
                                                color: root.foreground
                                                font.family: root.fontFamily
                                                font.bold: true
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                Layout.preferredWidth: Style.space(220)
                                                wrapMode: Text.WordWrap
                                                horizontalAlignment: Text.AlignRight
                                                textFormat: Text.PlainText
                                                text: {
                                                    var h = Model.applyHint(root.config, modelData, root.liveMonitors, root.liveNetwork, root.liveStatus)
                                                    return h.text || ""
                                                }
                                                color: {
                                                    var h = Model.applyHint(root.config, modelData, root.liveMonitors, root.liveNetwork, root.liveStatus)
                                                    return h.matches ? Color.accent : root.dim
                                                }
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: (modelData.monitors || []).length + " monitors · " + (modelData.assignments || []).length + " apps · " + (modelData.matchMode === "all-present" ? "all required present" : "exact layout")
                                            color: root.dim
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            textFormat: Text.PlainText
                                            text: Model.boundNetworkLine(root.profileRecord(modelData.id), root.liveNetwork)
                                            color: {
                                                var p = root.profileRecord(modelData.id)
                                                var hit = Model.networkMatches(p.network, root.liveNetwork)
                                                return (Model.networkConfigured(p.network) && hit.matches) ? Color.accent : root.dim
                                            }
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.space(6)
                                            Button { text: "Workspaces"; onClicked: { root.setActiveProfile(modelData.id); root.mainView = "workspaces" } }
                                            Button { text: "Displays"; onClicked: { root.setActiveProfile(modelData.id); root.mainView = "displays" } }
                                            Button {
                                                text: "Apply"
                                                enabled: {
                                                    var h = Model.applyHint(root.config, modelData, root.liveMonitors, root.liveNetwork, root.liveStatus)
                                                    return !root.applyBusy && !!(h && h.canApply)
                                                }
                                                tooltipText: {
                                                    var h = Model.applyHint(root.config, modelData, root.liveMonitors, root.liveNetwork, root.liveStatus)
                                                    return (h && !h.canApply) ? (h.refuseText || "Doesn't match connected displays") : "Apply this profile"
                                                }
                                                onClicked: root.applyProfile(modelData.id)
                                            }
                                            Button {
                                                text: "Fresh Workscape"
                                                enabled: {
                                                    var h = Model.applyHint(root.config, modelData, root.liveMonitors, root.liveNetwork, root.liveStatus)
                                                    return !root.applyBusy && !!(h && h.canApply)
                                                }
                                                tooltipText: {
                                                    var h = Model.applyHint(root.config, modelData, root.liveMonitors, root.liveNetwork, root.liveStatus)
                                                    return (h && !h.canApply)
                                                        ? (h.refuseText || "Doesn't match connected displays")
                                                        : "Close only workspaces that have apps in this profile, then apply from scratch. Other workspaces stay put."
                                                }
                                                onClicked: root.applyFreshProfile(modelData.id)
                                            }
                                            Item { Layout.fillWidth: true }
                                            Button {
                                                text: Model.networkConfigured(root.profileRecord(modelData.id).network) ? "Rebind now" : "Bind this network"
                                                onClicked: root.bindProfileNetwork(modelData.id)
                                            }
                                            Button {
                                                text: "Edit network"
                                                onClicked: root.openEditNetwork(modelData.id)
                                            }
                                            Button {
                                                visible: Model.networkConfigured(root.profileRecord(modelData.id).network)
                                                text: "Clear network"
                                                onClicked: root.clearProfileNetwork(modelData.id)
                                            }
                                            Button { text: "Delete"; onClicked: root.deleteProfile(modelData.id) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    }

                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(12)
                    Text {
                        visible: root.statusText !== ""
                        textFormat: Text.PlainText
                        text: "✓ " + root.statusText
                        color: Color.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Text {
                        visible: root.errorText !== ""
                        textFormat: Text.PlainText
                        text: root.errorText
                        color: Color.urgent || "#ff4444"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            Item {
                id: hotkeyOverlay
                width: 0
                height: 0
                focus: root.hotkeyCapture !== ""
                Keys.onPressed: function(event) {
                    if (root.hotkeyCapture === "") return
                    event.accepted = true
                    var bareEsc = event.key === Qt.Key_Escape && !(event.modifiers & (Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier))
                    if (bareEsc) {
                        root.hotkeyCapture = ""
                        root.statusText = ""
                        return
                    }
                    var chord = root.chordFromEvent(event)
                    if (!chord) return
                    var slot = root.hotkeyCapture
                    if (slot.indexOf("ws:") === 0) slot = slot.slice(3)
                    root.hotkeyCapture = ""
                    root.commitHotkey(slot, chord)
                }
            }
            Timer {
                interval: 40
                repeat: true
                running: root.opened && root.hotkeyCapture !== ""
                onTriggered: {
                    if (hotkeyOverlay && !hotkeyOverlay.activeFocus)
                        hotkeyOverlay.forceActiveFocus()
                }
            }

            Rectangle {
                id: transferScrim
                visible: root.transferOpen
                z: 200
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)
                MouseArea { anchors.fill: parent; onClicked: root.closeTransfer() }

                Rectangle {
                    width: Math.min(parent.width - Style.space(28), Style.space(420))
                    implicitHeight: transferCol.implicitHeight + Style.space(28)
                    height: implicitHeight
                    anchors.centerIn: parent
                    radius: Style.cornerRadius
                    color: Color.background
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                    MouseArea { anchors.fill: parent; onClicked: function(e) { e.accepted = true } }

                    ColumnLayout {
                        id: transferCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Style.space(16)
                        spacing: Style.space(10)

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: "Move / copy workspace"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                            }
                            HintMark {
                                tooltipText: root.transferMode === "move"
                                      ? "Move apps and the split to another workspace on this profile. If that workspace already has apps, the two swap."
                                      : "Copy apps and the split onto another profile. Pick the destination workspace number."
                            }
                        }

                        ButtonGroup {
                            Layout.fillWidth: true
                            foreground: root.foreground
                            options: [
                                { value: "copy", label: "Copy" },
                                { value: "move", label: "Move" }
                            ]
                            value: root.transferMode
                            onChanged: function(v) {
                                root.transferMode = v
                                if (v === "move") root.transferToProfileId = root.activeProfileId
                                else if (root.copyProfileOptions.length) root.transferToProfileId = root.copyTargetId || root.copyProfileOptions[0].value
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Text { text: "From"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(48) }
                            Text {
                                text: root.activeProfile.name
                                textFormat: Text.PlainText
                                color: root.foreground
                                font.family: root.fontFamily
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            Dropdown {
                                Layout.preferredWidth: Style.space(110)
                                label: ""
                                showLabel: false
                                foreground: root.foreground
                                value: root.transferFromWs
                                options: root.workspaceOptions
                                onChanged: function(v) { root.transferFromWs = v }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Text { text: "To"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(48) }
                            Dropdown {
                                visible: root.transferMode === "copy"
                                Layout.fillWidth: true
                                label: ""
                                showLabel: false
                                foreground: root.foreground
                                value: root.transferToProfileId
                                options: root.transferToProfileOptions
                                onChanged: function(v) { root.transferToProfileId = v; root.copyTargetId = v }
                            }
                            Text {
                                visible: root.transferMode === "move"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                                text: root.activeProfile.name
                                color: root.foreground
                                font.family: root.fontFamily
                            }
                            Dropdown {
                                Layout.preferredWidth: Style.space(110)
                                label: ""
                                showLabel: false
                                foreground: root.foreground
                                value: root.transferToWs
                                options: root.workspaceOptions
                                onChanged: function(v) { root.transferToWs = v }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Item { Layout.fillWidth: true }
                            Button { text: "Cancel"; onClicked: root.closeTransfer() }
                            Button {
                                text: root.transferMode === "move" ? "Move" : "Copy"
                                onClicked: root.confirmTransfer()
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: newProfileScrim
                visible: root.newProfileOpen
                z: 210
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)
                MouseArea { anchors.fill: parent; onClicked: root.closeNewProfile() }

                Rectangle {
                    width: Math.min(parent.width - Style.space(28), Style.space(420))
                    implicitHeight: newProfileCol.implicitHeight + Style.space(28)
                    height: implicitHeight
                    anchors.centerIn: parent
                    radius: Style.cornerRadius
                    color: Color.background
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                    MouseArea { anchors.fill: parent; onClicked: function(e) { e.accepted = true } }

                    ColumnLayout {
                        id: newProfileCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Style.space(16)
                        spacing: Style.space(10)

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: "New profile"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                            }
                            HintMark { tooltipText: "Name this layout first. One profile owns a given display set + network. Binding Wi-Fi / LAN lets the same dock look different at home vs work." }
                        }
                        TextField {
                            id: newProfileNameField
                            Layout.fillWidth: true
                            foreground: root.foreground
                            placeholderText: "Profile name"
                            text: root.newProfileName
                            onTextChanged: root.newProfileName = text
                            onAccepted: root.confirmNewProfile()
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(4)
                            WrapToggle {
                                Layout.fillWidth: true
                                label: "Bind current network"
                                description: Model.liveNetworkSummary(root.liveNetwork)
                                checked: root.newProfileBindNetwork
                                foreground: root.foreground
                                onClicked: root.newProfileBindNetwork = !root.newProfileBindNetwork
                            }
                            HintMark { tooltipText: "SSID when on Wi-Fi, otherwise the LAN subnet — not Tailscale or public IP." }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Item { Layout.fillWidth: true }
                            Button { text: "Cancel"; onClicked: root.closeNewProfile() }
                            Button { text: "Create"; onClicked: root.confirmNewProfile() }
                        }
                    }
                }
            }

            Rectangle {
                id: editNetworkScrim
                visible: root.editNetworkOpen
                z: 211
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)
                MouseArea { anchors.fill: parent; onClicked: root.closeEditNetwork() }

                Rectangle {
                    width: Math.min(parent.width - Style.space(28), Style.space(440))
                    implicitHeight: editNetworkCol.implicitHeight + Style.space(28)
                    height: implicitHeight
                    anchors.centerIn: parent
                    radius: Style.cornerRadius
                    color: Color.background
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                    MouseArea { anchors.fill: parent; onClicked: function(e) { e.accepted = true } }

                    ColumnLayout {
                        id: editNetworkCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Style.space(16)
                        spacing: Style.space(8)

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: "Edit network"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                            }
                            HintMark { tooltipText: "Use this when you are not on the network that should load this profile. SSID is enough for Wi-Fi; subnet (192.168.2.0/24) covers ethernet. Leave all empty for any-network fallback. Now: " + Model.liveNetworkSummary(root.liveNetwork) }
                        }
                        Text { text: "Wi-Fi SSID"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                        TextField {
                            id: editNetworkSsidField
                            Layout.fillWidth: true
                            foreground: root.foreground
                            placeholderText: "HomeWiFi"
                            text: root.editNetworkSsids
                            onTextChanged: root.editNetworkSsids = text
                            onAccepted: root.confirmEditNetwork()
                        }
                        Text { text: "LAN subnet"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                        TextField {
                            id: editNetworkSubnetField
                            Layout.fillWidth: true
                            foreground: root.foreground
                            placeholderText: "192.168.1.0/24"
                            text: root.editNetworkSubnets
                            onTextChanged: root.editNetworkSubnets = text
                            onAccepted: root.confirmEditNetwork()
                        }
                        Text { text: "Connection name (optional)"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                        TextField {
                            id: editNetworkConnField
                            Layout.fillWidth: true
                            foreground: root.foreground
                            placeholderText: "NetworkManager name"
                            text: root.editNetworkConnections
                            onTextChanged: root.editNetworkConnections = text
                            onAccepted: root.confirmEditNetwork()
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Button {
                                text: "Use current"
                                onClicked: {
                                    var live = root.liveNetwork || {}
                                    if (live.ssid) root.editNetworkSsids = String(live.ssid)
                                    if (live.subnet) root.editNetworkSubnets = String(live.subnet)
                                    if (live.connection) root.editNetworkConnections = String(live.connection)
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Button { text: "Cancel"; onClicked: root.closeEditNetwork() }
                            Button { text: "Save"; onClicked: root.confirmEditNetwork() }
                        }
                    }
                }
            }

            Rectangle {
                id: overflowScrim
                visible: root.overflowOpen
                z: 212
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)
                MouseArea { anchors.fill: parent; onClicked: root.closeOverflow() }

                Rectangle {
                    width: Math.min(parent.width - Style.space(28), Style.space(480))
                    implicitHeight: overflowCol.implicitHeight + Style.space(28)
                    height: implicitHeight
                    anchors.centerIn: parent
                    radius: Style.cornerRadius
                    color: Color.background
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                    MouseArea { anchors.fill: parent; onClicked: function(e) { e.accepted = true } }

                    ColumnLayout {
                        id: overflowCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Style.space(16)
                        spacing: Style.space(10)

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: "Overflow chain"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                            }
                            HintMark { tooltipText: "Profile-wide overflow chain. Checked workspaces take the next extra window in this order. Max windows / workspace is for this chain only. Fill unused selects workspaces with no pinned apps." }
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 5
                            columnSpacing: Style.space(6)
                            rowSpacing: Style.space(6)
                            Repeater {
                                model: 20
                                delegate: Button {
                                    required property int index
                                    readonly property int ws: index + 1
                                    readonly property bool assigned: {
                                        var used = Model.assignedWorkspaceSet(root.activeProfile)
                                        return used[ws] === true
                                    }
                                    text: assigned ? (ws + "·") : String(ws)
                                    selected: root.overflowDraftHas(ws)
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Style.space(32)
                                    tooltipText: assigned ? ("WS " + ws + " has pinned apps") : ("WS " + ws + " — no pinned apps")
                                    onClicked: root.toggleOverflowDraft(ws)
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: root.overflowDraft && root.overflowDraft.length
                                ? ("Order: " + root.overflowDraft.join(" → "))
                                : "No workspaces selected."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Text {
                                text: "Max / workspace"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                            }
                            Button {
                                text: "−"
                                enabled: root.overflowDraftMax > 1
                                Layout.preferredHeight: Style.space(28)
                                Layout.preferredWidth: Style.space(28)
                                onClicked: root.overflowDraftMax = Model.clampVisibleCount(root.overflowDraftMax - 1)
                            }
                            Text {
                                text: String(root.overflowDraftMax)
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }
                            Button {
                                text: "+"
                                enabled: root.overflowDraftMax < 20
                                Layout.preferredHeight: Style.space(28)
                                Layout.preferredWidth: Style.space(28)
                                onClicked: root.overflowDraftMax = Model.clampVisibleCount(root.overflowDraftMax + 1)
                            }
                            Item { Layout.fillWidth: true }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Button { text: "Fill unused"; tooltipText: "Select workspaces with no pinned apps as overflow destinations (scrolling, extras bounce after the max)."; onClicked: root.overflowDraftSetStage() }
                            Button { text: "None"; onClicked: root.overflowDraftNone() }
                            Item { Layout.fillWidth: true }
                            Button { text: "Cancel"; onClicked: root.closeOverflow() }
                            Button { text: "Save"; onClicked: root.confirmOverflow() }
                        }
                    }
                }
            }

            Rectangle {
                visible: root.organizerOpen
                z: 220
                anchors.fill: parent
                color: Color.background
                Organizer {
                    anchors.fill: parent
                    bar: root.bar
                    assignedApps: root.addedApps
                    appList: root.appList
                    hyprLayout: root.currentWsPref.layout
                    columnWidth: 1 / Math.max(1, root.currentWsPref.visibleCount)
                    onLayoutChanged: function(tiles) { root.applyPreviewLayout(tiles) }
                    onLayoutCleared: root.resetPreviewLayout()
                    onPlaceChanged: function(index, place) { root.setAssignmentPlace(index, place) }
                    onSplitRequested: function(index, dir) { root.applyOrganizerSplit(index, dir) }
                    onGearRequested: function(index) { root.openChrome(index) }
                    onCloseRequested: root.organizerOpen = false
                    onWindowRemoved: function(id) { root.removeAssignment(id) }
                }
            }

            Rectangle {
                visible: root.chromeOpen
                z: 230
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)
                MouseArea { anchors.fill: parent; onClicked: root.chromeOpen = false }
                Rectangle {
                    width: Math.min(parent.width - Style.space(28), Style.space(420))
                    implicitHeight: chromeCol.implicitHeight + Style.space(28)
                    height: implicitHeight
                    anchors.centerIn: parent
                    radius: Style.cornerRadius
                    color: Color.background
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                    MouseArea { anchors.fill: parent; onClicked: function(e) { e.accepted = true } }
                    ColumnLayout {
                        id: chromeCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Style.space(16)
                        spacing: Style.space(8)
                        Text {
                            text: "Window look"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.title
                            font.bold: true
                        }
                        Text { text: "Focused opacity " + root.chromeOpA; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                        RowLayout {
                            Layout.fillWidth: true
                            Button { text: "−"; onClicked: root.chromeOpA = Model.clampOpacity(root.chromeOpA - 0.1) }
                            Button { text: "+"; onClicked: root.chromeOpA = Model.clampOpacity(root.chromeOpA + 0.1) }
                            Item { Layout.fillWidth: true }
                        }
                        Text { text: "Unfocused opacity " + root.chromeOpI; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                        RowLayout {
                            Layout.fillWidth: true
                            Button { text: "−"; onClicked: root.chromeOpI = Model.clampOpacity(root.chromeOpI - 0.1) }
                            Button { text: "+"; onClicked: root.chromeOpI = Model.clampOpacity(root.chromeOpI + 0.1) }
                            Item { Layout.fillWidth: true }
                        }
                        WrapToggle {
                            Layout.fillWidth: true
                            label: "Focused border"
                            checked: root.chromeBorderA
                            foreground: root.foreground
                            onClicked: root.chromeBorderA = !root.chromeBorderA
                        }
                        WrapToggle {
                            Layout.fillWidth: true
                            label: "Unfocused border"
                            checked: root.chromeBorderI
                            foreground: root.foreground
                            onClicked: root.chromeBorderI = !root.chromeBorderI
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Border px"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                            Button { text: "−"; enabled: root.chromeBorderSize > -1; onClicked: root.chromeBorderSize = root.chromeBorderSize < 0 ? 0 : Math.max(-1, root.chromeBorderSize - 1) }
                            Text { text: root.chromeBorderSize < 0 ? "default" : String(root.chromeBorderSize); color: root.foreground; font.family: root.fontFamily }
                            Button { text: "+"; enabled: root.chromeBorderSize < 12; onClicked: root.chromeBorderSize = Math.min(12, (root.chromeBorderSize < 0 ? 1 : root.chromeBorderSize + 1)) }
                            Item { Layout.fillWidth: true }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            Button { text: "Cancel"; onClicked: root.chromeOpen = false }
                            Button { text: "Save"; onClicked: root.saveChrome() }
                        }
                    }
                }
            }
        }
    }

    component AppRow: CursorSurface {
        property var app: null
        property int rowIndex: 0
        readonly property bool rowSelected: root.cursorActive && root.selectedRow === rowIndex
        hasCursor: rowSelected
        foreground: root.foreground
        implicitHeight: Style.space(36)

        onRowSelectedChanged: if (rowSelected) root.ensureCursorVisible(this)

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)

            Item {
                Layout.preferredWidth: Style.space(22)
                Layout.alignment: Qt.AlignVCenter
                Image {
                    id: rowIcon
                    anchors.centerIn: parent
                    visible: source !== ""
                    width: 16
                    height: 16
                    source: app ? root.iconSourceFor(app) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    onStatusChanged: if (status === Image.Error) source = ""
                }
                Text {
                    anchors.centerIn: parent
                    visible: rowIcon.source === ""
                    text: "󰐱"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    textFormat: Text.PlainText
                    text: {
                        if (!app) return ""
                        var n = root.countInWorkspace(app.exec)
                        return n > 0 ? (app.name + "  ×" + n) : app.name
                    }
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Text {
                    textFormat: Text.PlainText
                    text: {
                        if (!app) return ""
                        var n = root.countInWorkspace(app.exec)
                        var kind = app.exec.indexOf("omarchy-launch-webapp") !== -1 ? "web app" : app.exec.split(" ")[0].split("/").pop()
                        return n > 1 ? (n + " on this workspace") : kind
                    }
                    color: root.dim
                    font.family: "monospace"
                    font.pixelSize: Style.font.caption - 2
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            Button {
                visible: app ? root.countInWorkspace(app.exec) > 0 : false
                Layout.preferredWidth: Style.space(36)
                Layout.minimumWidth: Style.space(36)
                Layout.maximumWidth: Style.space(40)
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignVCenter
                text: app && root.isAppLocked(app.exec) ? "🔒" : "🔓"
                tooltipText: "Lock this window’s size on this workspace"
                onClicked: if (app) root.toggleAppLock(app.exec)
            }
            Button {
                visible: app ? root.countInWorkspace(app.exec) > 0 : false
                Layout.preferredWidth: Style.space(36)
                Layout.minimumWidth: Style.space(36)
                Layout.maximumWidth: Style.space(40)
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignVCenter
                text: "+"
                tooltipText: "Add another window of this app on this workspace"
                onClicked: if (app) root.addInstance(app.exec, app.name)
            }
            ToggleSwitch {
                Layout.alignment: Qt.AlignVCenter
                checked: app ? root.isInList(root.addedApps, app.exec) : false
                cursorRing: true
                cursorPad: Style.space(3)
                foreground: root.foreground
                accent: Color.accent
                hasCursor: rowSelected && root.selectedButton === 0
                onHovered: function(on) { if (on) root.setCursor(rowIndex, 0) }
                onToggled: if (app) root.toggleInWorkspace(app.exec, app.name)
            }
        }
    }

    Component.onCompleted: loadConfig()
}
