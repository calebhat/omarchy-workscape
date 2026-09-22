pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import "Model.js" as Model

Item {
    id: root

    property QtObject bar: null
    property string moduleName: "io.github.calebhat.workscape"
    property var settings: ({})
    property var shell: null
    property var manifest: null

    readonly property string home: Quickshell.env("HOME")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
    readonly property string pluginId: "io.github.calebhat.workscape"
    readonly property string pluginDir: {
        var u = String(Qt.resolvedUrl("./manifest.json"))
        if (u.indexOf("file://") === 0) u = u.slice(7)
        try { u = decodeURIComponent(u) } catch (e) {}
        var i = u.lastIndexOf("/")
        return i > 0 ? u.slice(0, i) : u
    }
    readonly property string script: root.pluginDir + "/workscape.sh"
    readonly property string stateio: root.pluginDir + "/scripts/stateio"
    readonly property string configFile: stateHome + "/omarchy/workscape/config.json"

    function helperRun(args, timeoutSec, maxOut) {
        var cmd = ["python3", "-B", root.stateio, "run", "--timeout", String(timeoutSec), "--max-out", String(maxOut), "--"]
        return cmd.concat(args)
    }

    property bool autoEnabled: true
    property bool applyOnBoot: false
    property bool applyOnMonitorChange: false
    property bool applyOnShellRestart: false
    property int launchDelayMs: 1500
    property bool launchedThisSession: false
    property bool launchScheduled: false
    property bool shellStartScheduled: false
    property string lastStatus: ""

    function log(msg) {
        console.log("[workscape] " + msg)
    }

    Process {
        id: gestureBootProc
        command: root.helperRun(["bash", root.script, "--apply-gestures"], 8, 8192)
        stdout: StdioCollector { waitForEnd: true }
        stderr: SplitParser { onRead: function(d){ if (d.length > 4096) return; console.warn("[workscape] gestures] " + d) } }
        onExited: function(code) {
            root.log("apply-gestures exited " + code)
            if (!hotkeyBootProc.running)
                hotkeyBootProc.running = true
        }
    }

    Process {
        id: hotkeyBootProc
        command: root.helperRun(["bash", root.script, "--apply-hotkeys"], 8, 8192)
        stdout: StdioCollector { waitForEnd: true }
        stderr: SplitParser { onRead: function(d){ if (d.length > 4096) return; console.warn("[workscape] hotkeys] " + d) } }
        onExited: function(code) {
            root.log("apply-hotkeys exited " + code)
        }
    }

    Process {
        id: ensureProc
        command: root.helperRun(["bash", root.script, "--ensure-config"], 8, Model.maxConfigBytes())
        stdout: StdioCollector { id: ensureOut; waitForEnd: true }
        onExited: function(code) {
            if (code !== 0) {
                root.log("ensure-config failed: " + code)
                return
            }
            var txt = ensureOut.text || ""
            try {
                var cfg = Model.parseCappedJson(txt)
                if (!cfg) {
                    root.log("parse ensure-config: oversized or invalid")
                    return
                }
                if (cfg.settings) {
                    root.autoEnabled = cfg.settings.enabled !== false
                    root.applyOnBoot = cfg.settings.applyOnBoot === true
                    root.applyOnMonitorChange = cfg.settings.applyOnMonitorChange === true
                    root.applyOnShellRestart = cfg.settings.applyOnShellRestart === true
                    root.launchDelayMs = Number(cfg.settings.launchDelayMs || 1500)
                }
            } catch (e) { root.log("parse ensure-config: " + e) }
            if (!gestureBootProc.running)
                gestureBootProc.running = true
            if (!root.launchScheduled) {
                root.launchScheduled = true
                if (root.autoEnabled && root.applyOnBoot) {
                    launchTimer.interval = root.launchDelayMs
                    launchTimer.restart()
                } else {
                    root.log("boot apply skipped (applyOnBoot=" + root.applyOnBoot + ")")
                }
            }
            if (!root.shellStartScheduled) {
                root.shellStartScheduled = true
                if (root.autoEnabled && root.applyOnShellRestart)
                    shellStartTimer.restart()
            }
        }
    }

    Process {
        id: launchProc
        stdout: SplitParser { onRead: function(d){ if (d.length > 4096) return; console.log("[workscape] launch] " + d) } }
        stderr: SplitParser { onRead: function(d){ if (d.length > 4096) return; console.warn("[workscape] launch err] " + d) } }
        onExited: function(code) {
            root.lastStatus = code === 0 ? "launched" : "failed:" + code
            root.launchedThisSession = true
            root.log("apply exited " + code)
        }
    }

    Process {
        id: statusProc
        stdout: StdioCollector { id: statusOut; waitForEnd: true }
        onExited: function(code) {
            if (code === 0) root.lastStatus = statusOut.text
        }
    }

    Process {
        id: extrasWatch
        command: ["python3", "-B", root.pluginDir + "/scripts/watch"]
        running: false
        stdout: SplitParser {
            onRead: function(d) {
                if (d.length > 4096) return
                root.log("extras " + d)
                if (d.indexOf('"monitorChange"') >= 0)
                    monitorDebounce.restart()
            }
        }
        stderr: SplitParser { onRead: function(d){ if (d.length > 4096) return; console.warn("[workscape] extras] " + d) } }
    }

    // A dock brings displays up over seconds and Hyprland re-emits events
    // while modes settle. Coalesce every monitorChange line into one deferred
    // trigger so the match never sees a half-connected dock.
    Timer {
        id: monitorDebounce
        interval: 2500
        repeat: false
        onTriggered: {
            if (!syncMatchProc.running)
                syncMatchProc.running = true
            root.applyOnDisplayChange()
        }
    }

    Timer {
        id: scanTimer
        interval: 30000
        repeat: true
        running: root.applyOnMonitorChange && root.autoEnabled
        onTriggered: root.applyOnDisplayChange()
    }

    Process {
        id: syncMatchProc
        command: root.helperRun(["bash", root.script, "--sync-active-profile"], 8, 4096)
        stdout: SplitParser { onRead: function(d){ if (d.length > 4096) return; root.log("sync " + d) } }
        stderr: SplitParser { onRead: function(d){ if (d.length > 4096) return; console.warn("[workscape] sync] " + d) } }
    }

    Timer {
        interval: 1500
        running: true
        repeat: false
        onTriggered: extrasWatch.running = true
    }

    Process {
        id: manualLaunchProc
        stdout: SplitParser { onRead: function(d){ console.log("[workscape] manual] " + d) } }
        stderr: SplitParser { onRead: function(d){ console.warn("[workscape] manual err] " + d) } }
    }

    Timer {
        id: launchTimer
        interval: 800
        repeat: false
        onTriggered: {
            if (!root.autoEnabled || !root.applyOnBoot) {
                root.log("autostart disabled, skipping")
                return
            }
            if (root.launchedThisSession) {
                root.log("already launched this session, skipping (use force)")
                return
            }
            root.log("auto-applying matching profile...")
            launchProc.command = root.helperRun(["bash", root.script, "--launch-all"], 180, 65536)
            launchProc.running = true
        }
    }

    function launchAll(force) {
        if (launchProc.running) return
        if (force) {
            launchProc.command = root.helperRun(["bash", root.script, "--force-launch-all"], 180, 65536)
        } else {
            launchProc.command = root.helperRun(["bash", root.script, "--launch-all"], 180, 65536)
        }
        launchProc.running = true
    }

    function applyMatching() {
        if (launchProc.running) return
        launchProc.command = root.helperRun(["bash", root.script, "--apply-matching"], 180, 65536)
        launchProc.running = true
    }

    // One forced scan per service start: settles the display set, then
    // re-applies the matching profile even when the guard would call it
    // unchanged — a shell restart can disturb state the fingerprint cannot
    // see (workspace pins, runtime rules). Window-safe by design.
    Timer {
        id: shellStartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (!root.autoEnabled || !root.applyOnShellRestart || launchProc.running) return
            launchProc.command = root.helperRun(["bash", root.script, "--apply-on-monitor-change", "--force"], 240, 65536)
            launchProc.running = true
        }
    }

    function applyOnDisplayChange() {
        if (!root.applyOnMonitorChange || !root.autoEnabled) return
        if (launchProc.running) return
        launchProc.command = root.helperRun(["bash", root.script, "--apply-on-monitor-change"], 240, 65536)
        launchProc.running = true
    }

    function applyProfile(profileId) {
        if (launchProc.running) return
        launchProc.command = root.helperRun(["bash", root.script, "--apply-profile", String(profileId || "")], 180, 65536)
        launchProc.running = true
    }

    function applyFresh(profileId) {
        if (launchProc.running) {
            root.log("apply already in progress")
            return
        }
        launchProc.command = root.helperRun(["bash", root.script, "--fresh-apply-profile", String(profileId || "")], 180, 65536)
        launchProc.running = true
    }

    function applyWorkspaceHere(ws) {
        if (launchProc.running) {
            root.log("apply already in progress")
            return
        }
        launchProc.command = root.helperRun(["bash", root.script, "--apply-workspace-here", String(ws || "")], 180, 65536)
        launchProc.running = true
    }

    function applyHotkeys() {
        if (hotkeyBootProc.running) return
        hotkeyBootProc.running = true
    }

    function launchOnWorkspace(workspace, execCmd) {
        var silent = "true"
        manualLaunchProc.command = root.helperRun(["bash", root.script, "--launch", String(workspace), execCmd, silent], 15, 4096)
        manualLaunchProc.running = true
    }

    function refreshConfig() {
        ensureProc.running = true
    }

    function status(): string {
        if (!statusProc.running) statusProc.command = root.helperRun(["bash", root.script, "--status"], 5, 8192)
        if (!statusProc.running) statusProc.running = true
        try {
            var cached = root.lastStatus
            if (cached && cached.indexOf("{") === 0) return cached
        } catch (e) {}
        return JSON.stringify({ plugin: pluginId, enabled: autoEnabled, applyOnBoot: applyOnBoot, launched: launchedThisSession, lastStatus: lastStatus })
    }

    IpcHandler {
        target: root.pluginId
        function launchAll(): void { root.launchAll(false) }
        function forceLaunchAll(): void { root.launchAll(true) }
        function applyMatching(): void { root.applyMatching() }
        function applyOnDisplayChange(): void { root.applyOnDisplayChange() }
        function applyProfile(profileId: string): void { root.applyProfile(profileId) }
        function applyFresh(profileId: string): void { root.applyFresh(profileId) }
        function applyWorkspaceHere(ws: string): void { root.applyWorkspaceHere(ws) }
        function applyHotkeys(): void { root.applyHotkeys() }
        function refreshConfig(): void { root.refreshConfig() }
        function status(): string { return root.status() }
    }

    Component.onCompleted: {
        root.log("service started, ensuring config " + root.configFile)
        ensureProc.running = true
    }
}
