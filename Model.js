.pragma library

// Shared helpers for WorkScape panel + service.
// Config lives outside the plugin dir so saves do not reload the plugin.

function defaultConfig() {
    return {
        version: 2,
        settings: {
            enabled: true,
            applyOnBoot: false,
            launchDelayMs: 800,
            staggerMs: 80,
            silent: true,
            onlyOnBoot: true,
            lastFormWorkspace: 1,
            lastMainView: "profiles",
            activeProfileId: "default",
            gestureSource: "global",
            persistHyprGestures: false,
            gestures: defaultGestures()
        },
        monitors: [],
        extraApps: [],
        profiles: [defaultProfile()]
    }
}

function defaultProfile() {
    return {
        id: "default",
        name: "Default",
        matchMode: "exact",
        monitors: [],
        workspaceMonitors: {},
        disabledMonitors: [],
        monitorLayout: {},
        workspacePrefs: {},
        assignments: [],
        gestures: defaultGestures(),
        workspaceNames: {},
        defaultWorkspace: 0,
        persistentWorkspaces: false,
        network: emptyNetwork(),
        overflow: emptyOverflow(),
        claimedAt: 0
    }
}

function maxWorkspace() { return 20 }

function maxConfigBytes() { return 524288 }

function parseCappedJson(txt, maxBytes) {
    var s = String(txt || "")
    var cap = maxBytes != null ? maxBytes : maxConfigBytes()
    if (!s || s.length > cap) return null
    try {
        return JSON.parse(s)
    } catch (e) {
        return null
    }
}

function evalPayload(lua) {
    var s = String(lua || "")
    if (/^\s*do\b/.test(s)) return s
    return "do\n" + s + "\nend"
}

function allowedMainView(v) {
    var s = String(v || "")
    if (s === "profiles" || s === "workspaces" || s === "displays" || s === "gestures") return s
    return "profiles"
}

function emptyOverflow() {
    return { enabled: false, workspaces: [], maxWindows: 1 }
}

function normalizeOverflow(raw) {
    var src = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {}
    var seen = {}
    var list = []
    var arr = Array.isArray(src.workspaces) ? src.workspaces : []
    var maxWs = maxWorkspace()
    for (var i = 0; i < arr.length && list.length < maxWs; i++) {
        var n = parseInt(arr[i], 10)
        if (!(n >= 1 && n <= maxWs) || seen[n]) continue
        seen[n] = true
        list.push(n)
    }
    return {
        enabled: src.enabled === true,
        workspaces: list,
        maxWindows: clampVisibleCount(src.maxWindows != null ? src.maxWindows : 1)
    }
}

function assignedWorkspaceSet(profile) {
    var used = {}
    var list = (profile && profile.assignments) || []
    for (var i = 0; i < list.length; i++) {
        var ws = parseInt(list[i].workspace, 10)
        if (ws >= 1 && ws <= maxWorkspace()) used[ws] = true
    }
    return used
}

function unsetWorkspaces(profile) {
    var used = assignedWorkspaceSet(profile)
    var out = []
    var maxWs = maxWorkspace()
    for (var i = 1; i <= maxWs; i++) if (!used[i]) out.push(i)
    return out
}

function overflowSummary(profile) {
    var ov = normalizeOverflow(profile && profile.overflow)
    if (!ov.enabled) return "Off — extras only follow each workspace’s own send-extra toggle."
    if (!ov.workspaces.length) return "On — no workspaces in the chain yet. Use Choose… then Set Stage."
    return "On · " + ov.maxWindows + "/ws · " + ov.workspaces.join(" → ")
}

function emptyNetwork() {
    return { ssids: [], subnets: [], connections: [] }
}

function uniqueStrings(list, maxLen, maxCount) {
    var out = []
    var seen = {}
    if (!Array.isArray(list)) return out
    for (var i = 0; i < list.length && out.length < maxCount; i++) {
        var s = String(list[i] || "").trim().slice(0, maxLen)
        var k = s.toLowerCase()
        if (!s || seen[k]) continue
        seen[k] = true
        out.push(s)
    }
    return out
}

function normalizeNetwork(raw) {
    var src = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {}
    return {
        ssids: uniqueStrings(src.ssids, 64, 8),
        subnets: uniqueStrings(src.subnets, 64, 8),
        connections: uniqueStrings(src.connections, 64, 8)
    }
}

function networkConfigured(raw) {
    var n = normalizeNetwork(raw)
    return n.ssids.length + n.subnets.length + n.connections.length > 0
}

function captureNetwork(live) {
    var liveObj = live && typeof live === "object" ? live : {}
    return normalizeNetwork({
        ssids: liveObj.ssid ? [liveObj.ssid] : [],
        subnets: liveObj.subnet ? [liveObj.subnet] : [],
        connections: liveObj.connection ? [liveObj.connection] : []
    })
}

function anyNetworkHit(savedArr, liveVal) {
    if (!liveVal) return false
    var want = String(liveVal).toLowerCase()
    for (var i = 0; i < savedArr.length; i++) {
        if (String(savedArr[i]).toLowerCase() === want) return true
    }
    return false
}

function networkMatches(saved, live) {
    var n = normalizeNetwork(saved)
    if (!networkConfigured(n)) return { constrained: false, matches: true }
    if (!live || typeof live !== "object") return { constrained: true, matches: false }
    var hit = anyNetworkHit(n.ssids, live.ssid) || anyNetworkHit(n.subnets, live.subnet) || anyNetworkHit(n.connections, live.connection)
    return { constrained: true, matches: hit }
}

function networksOverlap(a, b) {
    var na = normalizeNetwork(a)
    var nb = normalizeNetwork(b)
    var ca = networkConfigured(na)
    var cb = networkConfigured(nb)
    if (!ca && !cb) return true
    if (ca !== cb) return false
    function share(left, right) {
        var other = {}
        for (var i = 0; i < right.length; i++) other[String(right[i]).toLowerCase()] = true
        for (var j = 0; j < left.length; j++) if (other[String(left[j]).toLowerCase()]) return true
        return false
    }
    return share(na.ssids, nb.ssids) || share(na.subnets, nb.subnets) || share(na.connections, nb.connections)
}

function monitorKey(profile) {
    var mons = []
    var raw = (profile && profile.monitors) ? profile.monitors : []
    for (var i = 0; i < raw.length; i++) {
        var id = String(raw[i] || "")
        if (id) mons.push(id)
    }
    mons.sort()
    return mons.join(",")
}

function subtractNetwork(fromNet, claimed) {
    var n = normalizeNetwork(fromNet)
    var c = normalizeNetwork(claimed)
    function drop(arr, other) {
        var skip = {}
        for (var i = 0; i < other.length; i++) skip[String(other[i]).toLowerCase()] = true
        var out = []
        for (var j = 0; j < arr.length; j++) if (!skip[String(arr[j]).toLowerCase()]) out.push(arr[j])
        return out
    }
    return normalizeNetwork({
        ssids: drop(n.ssids, c.ssids),
        subnets: drop(n.subnets, c.subnets),
        connections: drop(n.connections, c.connections)
    })
}

function environmentOwner(cfg, key, network, exceptId) {
    var list = (cfg && cfg.profiles) || []
    for (var i = 0; i < list.length; i++) {
        if (exceptId && list[i].id === exceptId) continue
        if (monitorKey(list[i]) !== key) continue
        if (networksOverlap(list[i].network, network)) return list[i]
    }
    return null
}

function claimEnvironment(cfg, profileId, network) {
    var out = clone(cfg)
    var net = normalizeNetwork(network)
    var stolen = []
    var prof = profileById(out, profileId)
    if (!prof) return { config: out, stolen: stolen }
    var key = monitorKey(prof)
    for (var i = 0; i < out.profiles.length; i++) {
        var p = out.profiles[i]
        if (p.id === profileId) {
            p.network = net
            p.claimedAt = Date.now()
            continue
        }
        if (monitorKey(p) !== key) continue
        if (!networksOverlap(p.network, net)) continue
        if (!networkConfigured(net) || !networkConfigured(p.network)) continue
        var next = subtractNetwork(p.network, net)
        if (JSON.stringify(next) !== JSON.stringify(normalizeNetwork(p.network))) {
            stolen.push({ id: p.id, name: p.name })
            p.network = next
        }
    }
    return { config: out, stolen: stolen }
}

function suggestedProfileName(liveMonitors) {
    var n = (liveMonitors || []).length
    return n <= 1 ? "Laptop" : ("Desk " + n + " monitors")
}

function liveNetworkSummary(live) {
    if (!live || typeof live !== "object") return "No LAN / Wi-Fi yet"
    if (live.kind === "wifi" && live.ssid)
        return "Wi-Fi " + live.ssid + (live.subnet ? " · " + live.subnet : "")
    if (live.subnet)
        return (live.kind === "ethernet" ? "Ethernet " : "") + live.subnet
    if (live.iface) return String(live.iface)
    return "No LAN / Wi-Fi yet"
}

function networkSummary(raw) {
    var n = normalizeNetwork(raw)
    if (!networkConfigured(n)) return "Any network (fallback for this layout)"
    var parts = []
    if (n.ssids.length) parts.push("Wi-Fi " + n.ssids.join(", "))
    if (n.subnets.length) parts.push(n.subnets.join(", "))
    if (n.connections.length) {
        var same = n.ssids.join(",").toLowerCase() === n.connections.join(",").toLowerCase()
        if (!same) parts.push(n.connections.join(", "))
    }
    return parts.join(" · ")
}

function splitNetworkField(s) {
    var out = []
    var raw = String(s || "").replace(/\n/g, ",")
    var parts = raw.split(",")
    for (var i = 0; i < parts.length; i++) {
        var t = String(parts[i] || "").trim()
        if (t) out.push(t)
    }
    return out
}

function parseNetworkText(ssidsText, subnetsText, connectionsText) {
    return normalizeNetwork({
        ssids: splitNetworkField(ssidsText),
        subnets: splitNetworkField(subnetsText),
        connections: splitNetworkField(connectionsText)
    })
}

function networkFieldText(raw) {
    var n = normalizeNetwork(raw)
    return {
        ssids: n.ssids.join(", "),
        subnets: n.subnets.join(", "),
        connections: n.connections.join(", ")
    }
}

function boundNetworkLine(profile, liveNet) {
    var net = profile && profile.network
    var bound = networkSummary(net)
    if (!networkConfigured(net)) return bound
    var hit = networkMatches(net, liveNet)
    if (hit.matches) return bound + " · connected now"
    var live = liveNetworkSummary(liveNet)
    if (live && live.indexOf("No LAN") !== 0) return bound + " · now " + live
    return bound
}

function matchReasonLabel(reason) {
    if (reason === "network") return "wrong network"
    if (reason === "missing") return "missing displays"
    if (reason === "extra") return "extra displays"
    if (reason === "exact" || reason === "all-present") return "matches now"
    return String(reason || "")
}

function applyRefuseText(cfg, profile, match) {
    if (!match || match.matches) return ""
    if (match.detail) return String(match.detail)
    var name = String((profile && (profile.name || profile.id)) || "This profile")
    if (match.reason === "missing") {
        var ids = match.missing || []
        var labels = []
        for (var i = 0; i < ids.length; i++) {
            var mon = monitorById(cfg, ids[i])
            labels.push((mon && mon.label) ? mon.label : String(ids[i]))
        }
        return name + " needs " + (labels.length ? labels.join(", ") : "its saved displays") + " — those displays aren't connected"
    }
    if (match.reason === "extra") {
        var extra = match.extra || []
        if (extra.length) return name + " is an exact layout and extra displays are connected (" + extra.join(", ") + ")"
        return name + " is an exact layout and extra displays are connected"
    }
    if (match.reason === "network") return name + " is bound to a different network than this machine"
    return name + " does not match the current displays"
}

function profileById(cfg, id) {
    var list = (cfg && cfg.profiles) || []
    var want = String(id || "")
    if (!want) return null
    for (var i = 0; i < list.length; i++) if (String(list[i].id) === want) return list[i]
    return null
}

function applyHint(cfg, profile, liveList, liveNet, liveStatus) {
    var match = profileMatch(cfg, profile || {}, liveList, liveNet)
    if (liveStatus && Array.isArray(liveStatus.profiles) && profile && profile.id) {
        for (var i = 0; i < liveStatus.profiles.length; i++) {
            if (String(liveStatus.profiles[i].id) === String(profile.id)) {
                match.matches = !!liveStatus.profiles[i].matches
                match.reason = liveStatus.profiles[i].reason || match.reason
                match.missing = liveStatus.profiles[i].missing || match.missing
                match.extra = liveStatus.profiles[i].extra || match.extra
                match.detail = liveStatus.profiles[i].detail || match.detail
                match.networkConstrained = liveStatus.profiles[i].networkConstrained
                match.networkMatches = liveStatus.profiles[i].networkMatches
                break
            }
        }
    }
    var will = null
    var willId = ""
    if (liveStatus && liveStatus.matchedProfileId) {
        willId = String(liveStatus.matchedProfileId)
        will = profileById(cfg, willId)
    }
    if (!willId) {
        will = bestProfile(cfg, liveList, liveNet)
        willId = will && will.id ? String(will.id) : ""
    }
    var willName = will ? String(will.name || willId) : String((liveStatus && liveStatus.matchedProfileName) || willId || "")
    var viewingId = profile && profile.id ? String(profile.id) : ""
    var applies = !!(match.matches && willId && willId === viewingId)
    var canApply = !!match.matches
    var refuseText = canApply ? "" : applyRefuseText(cfg, profile, match)
    var text
    if (applies) {
        text = networkConfigured(profile && profile.network)
            ? "matches now · this applies"
            : "matches now · fallback for this layout"
    } else if (match.matches && willId && willId !== viewingId) {
        text = "displays match · " + willName + " still wins"
    } else if (match.matches && !willId) {
        text = "displays match · nothing applies"
    } else {
        var why = matchReasonLabel(match.reason) || "no match"
        if (willId) text = why + " · fallback " + willName + " will apply"
        else text = why + " · no matching profile"
    }
    return {
        text: text,
        matches: applies,
        canApply: canApply,
        refuseText: refuseText,
        reason: match.reason || "",
        willId: willId,
        willName: willName,
        appliedId: String(((cfg && cfg.settings) || {}).activeProfileId || ""),
        appliedName: ""
    }
}

function defaultGestures() {
    return {
        workspaceSwipe: true,
        fingers: 3,
        skipEmpty: true,
        invert: true,
        createNew: false,
        forever: false,
        touch: false,
        keyboard: false,
        scratchpadSwipe: false,
        scratchpadFingers: 4
    }
}

function normalizeGestures(raw) {
    var src = raw && typeof raw === "object" ? raw : {}
    var out = defaultGestures()
    out.workspaceSwipe = src.workspaceSwipe !== false
    out.fingers = parseInt(src.fingers, 10) === 4 ? 4 : 3
    out.skipEmpty = src.skipEmpty !== false
    out.invert = src.invert !== false
    out.createNew = src.createNew === true
    out.forever = src.forever === true
    out.touch = src.touch === true
    out.keyboard = src.keyboard === true
    out.scratchpadSwipe = src.scratchpadSwipe === true
    out.scratchpadFingers = parseInt(src.scratchpadFingers, 10) === 3 ? 3 : 4
    return out
}

function normalizeWorkspaceNames(raw) {
    var out = {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
    var keys = Object.keys(raw)
    for (var i = 0; i < keys.length; i++) {
        var ws = parseInt(keys[i], 10)
        if (!(ws >= 1 && ws <= 10)) continue
        var name = String(raw[keys[i]] || "").trim().slice(0, 24)
        if (name) out[String(ws)] = name
    }
    return out
}

function layoutDescription(layout, hasLock) {
    if (hasLock && (layout === "dwindle" || !layout))
        return "Locked split: assigned apps keep their sizes on dwindle. Extra windows open on the next unused workspace — extras cannot stay here."
    if (layout === "master")
        return "Hyprland master: one large pane with the rest stacked beside it on the same screen. No scrolling."
    if (layout === "scrolling")
        return "Hyprland scrolling: the first window fills the workspace. New windows are 1/Visible columns; Super+Left/Right pans on this workspace."
    return "Hyprland dwindle: each new window splits the current one. Turn off “Keep extra windows” to bounce extras to the next workspace."
}

function clampVisibleCount(n) {
    var v = parseInt(n, 10)
    if (isNaN(v)) return 2
    if (v < 1) return 1
    if (v > 20) return 20
    return v
}

function visibleCountHelp(visibleCount, hasLock, layout) {
    var n = clampVisibleCount(visibleCount)
    return "New scrolling columns are 1/" + n + " of the monitor (1–20). The first window still fills until a second opens."
}

function normalizeWorkspacePref(p) {
    if (!p || typeof p !== "object") {
        return { layout: "dwindle", visibleCount: 2, lockSizes: false, extras: "around" }
    }
    var layout = p.layout
    if (layout === "stage" || layout === "set-width") layout = "scrolling"
    if (layout !== "scrolling" && layout !== "master") layout = "dwindle"
    var vis = clampVisibleCount(p.visibleCount)
    var extras = p.extras === "block" ? "block" : "around"
    return {
        layout: layout,
        visibleCount: vis,
        lockSizes: p.lockSizes === true,
        extras: extras
    }
}

function normalizeWorkspacePrefs(raw) {
    var out = {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
    var keys = Object.keys(raw)
    for (var i = 0; i < keys.length; i++) {
        var ws = parseInt(keys[i], 10)
        if (!(ws >= 1 && ws <= 10)) continue
        out[String(ws)] = normalizeWorkspacePref(raw[keys[i]])
    }
    return out
}

function migrateWorkspacePrefs(prefs, assignments) {
    var list = assignments || []
    var normalized = prefs || {}
    var stub = { assignments: list, workspacePrefs: normalized }
    var keys = {}
    var existing = Object.keys(normalized)
    for (var e = 0; e < existing.length; e++) keys[existing[e]] = true
    for (var n = 1; n <= 10; n++) {
        if (workspaceForcesBlock(stub, n)) keys[String(n)] = true
    }
    var out = {}
    var names = Object.keys(keys)
    for (var p = 0; p < names.length; p++) {
        var ws = names[p]
        var pref = normalizeWorkspacePref(normalized[ws])
        if (workspaceForcesBlock(stub, ws)) {
            pref.layout = "dwindle"
            pref.extras = "block"
        }
        out[ws] = pref
    }
    return out
}

function workspacePref(profile, ws) {
    var map = (profile && profile.workspacePrefs) || {}
    return normalizeWorkspacePref(map[String(ws)])
}

function assignedAppCount(profile, ws) {
    var n = 0
    var list = (profile && profile.assignments) || []
    var want = Number(ws)
    for (var i = 0; i < list.length; i++) {
        if (list[i].enabled === false) continue
        if (Number(list[i].workspace) === want) n++
    }
    return n
}

function lockPlaceCount(profile, ws) {
    var n = 0
    var list = (profile && profile.assignments) || []
    var want = Number(ws)
    for (var i = 0; i < list.length; i++) {
        if (list[i].enabled === false) continue
        if (Number(list[i].workspace) !== want) continue
        if (list[i].lockPlace === true) n++
    }
    return n
}

function workspaceForcesBlock(profile, ws) {
    if (lockPlaceCount(profile, ws) >= 2) return true
    var pref = workspacePref(profile, ws)
    return pref.lockSizes === true && assignedAppCount(profile, ws) >= 2
}

function effectiveWorkspacePref(profile, ws) {
    var pref = workspacePref(profile, ws)
    if (workspaceForcesBlock(profile, ws)) {
        pref.layout = "dwindle"
        pref.extras = "block"
    }
    return pref
}

function workspaceControlFlags(profile, ws) {
    var pref = effectiveWorkspacePref(profile, ws)
    var forced = workspaceForcesBlock(profile, ws)
    var scrolling = !forced && pref.layout === "scrolling"
    return {
        layout: pref.layout,
        extras: pref.extras,
        visibleCount: pref.visibleCount,
        lockSizes: pref.lockSizes === true,
        forcedBlock: forced,
        showLayoutPicker: !forced,
        showVisibleCount: scrolling,
        showExtrasToggle: !forced,
        showScrollingLayout: !forced,
        showMasterLayout: !forced
    }
}

function canEditWorkspacePref(profile, ws, field) {
    var flags = workspaceControlFlags(profile, ws)
    if (field === "layout") return flags.showLayoutPicker
    if (field === "visibleCount") return flags.showVisibleCount
    if (field === "extras") return flags.showExtrasToggle
    return true
}

function profileUsesBounce(profile) {
    for (var ws = 1; ws <= 10; ws++) {
        if (workspaceForcesBlock(profile, ws)) return true
        if (workspacePref(profile, ws).extras === "block") return true
    }
    return false
}

function profileControlFlags(profile) {
    var ov = normalizeOverflow(profile && profile.overflow)
    var bounce = profileUsesBounce(profile)
    return {
        usesBounce: bounce,
        showOverflowCard: bounce || ov.enabled === true,
        showOverflowChainControls: ov.enabled === true
    }
}

function normalizeMonitorLayout(raw) {
    var out = {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
    var keys = Object.keys(raw)
    for (var i = 0; i < keys.length; i++) {
        var id = String(keys[i] || "").slice(0, 40)
        var p = raw[keys[i]]
        if (!id || !p || typeof p !== "object") continue
        var x = parseInt(p.x, 10)
        var y = parseInt(p.y, 10)
        if (isNaN(x)) x = 0
        if (isNaN(y)) y = 0
        out[id] = {
            x: Math.max(-20000, Math.min(20000, x)),
            y: Math.max(-20000, Math.min(20000, y))
        }
    }
    return out
}

function rectsOverlap(a, b) {
    if (!a || !b) return false
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
}

function spanOverlap(a0, a1, b0, b1) {
    return Math.min(a1, b1) - Math.max(a0, b0)
}

function edgesTouch(a, b, eps) {
    if (eps == null) eps = 1.5
    var yOv = spanOverlap(a.y, a.y + a.h, b.y, b.y + b.h)
    var xOv = spanOverlap(a.x, a.x + a.w, b.x, b.x + b.w)
    var flushR = Math.abs((a.x + a.w) - b.x) <= eps
    var flushL = Math.abs((b.x + b.w) - a.x) <= eps
    var flushB = Math.abs((a.y + a.h) - b.y) <= eps
    var flushT = Math.abs((b.y + b.h) - a.y) <= eps
    return ((flushR || flushL) && yOv > eps) || ((flushT || flushB) && xOv > eps)
}

function uniqueNums(vals) {
    var seen = {}, out = []
    for (var i = 0; i < vals.length; i++) {
        var n = Math.round(Number(vals[i]))
        if (seen[n]) continue
        seen[n] = true
        out.push(n)
    }
    return out
}

function compoundEdgeSlots(dragged, others) {
    var w = dragged.w, h = dragged.h
    var slots = []
    var list = others || []

    function groups(keyFn) {
        var map = {}
        for (var i = 0; i < list.length; i++) {
            var k = String(Math.round(keyFn(list[i])))
            if (!map[k]) map[k] = []
            map[k].push(list[i])
        }
        return map
    }

    function vertical(lineX, members, placeLeft) {
        if (!members || !members.length) return
        var y0 = members[0].y, y1 = members[0].y + members[0].h
        var i
        for (i = 1; i < members.length; i++) {
            y0 = Math.min(y0, members[i].y)
            y1 = Math.max(y1, members[i].y + members[i].h)
        }
        var x = placeLeft ? lineX - w : lineX
        var yMin = y0 - h + 24
        var yMax = y1 - 24
        if (yMax < yMin) {
            yMin = y0
            yMax = y1 - h
        }
        var yDrop = Math.max(yMin, Math.min(yMax, dragged.y))
        if (Math.abs(h - (y1 - y0)) <= 48) yDrop = y0
        else if (Math.abs(yDrop - y0) <= 48) yDrop = y0
        else if (Math.abs(yDrop - (y1 - h)) <= 48) yDrop = y1 - h
        slots.push({ x: x, y: yDrop })
        slots.push({ x: x, y: y0 })
        slots.push({ x: x, y: y1 - h })
    }

    function horizontal(lineY, members, placeAbove) {
        if (!members || !members.length) return
        var x0 = members[0].x, x1 = members[0].x + members[0].w
        var i
        for (i = 1; i < members.length; i++) {
            x0 = Math.min(x0, members[i].x)
            x1 = Math.max(x1, members[i].x + members[i].w)
        }
        var y = placeAbove ? lineY - h : lineY
        var xMin = x0 - w + 24
        var xMax = x1 - 24
        if (xMax < xMin) {
            xMin = x0
            xMax = x1 - w
        }
        var xDrop = Math.max(xMin, Math.min(xMax, dragged.x))
        if (Math.abs(w - (x1 - x0)) <= 48) xDrop = x0
        else if (Math.abs(xDrop - x0) <= 48) xDrop = x0
        else if (Math.abs(xDrop - (x1 - w)) <= 48) xDrop = x1 - w
        slots.push({ x: xDrop, y: y })
        slots.push({ x: x0, y: y })
        slots.push({ x: x1 - w, y: y })
    }

    var g, k
    g = groups(function(o) { return o.x })
    for (k in g) if (Object.prototype.hasOwnProperty.call(g, k)) vertical(Number(k), g[k], true)
    g = groups(function(o) { return o.x + o.w })
    for (k in g) if (Object.prototype.hasOwnProperty.call(g, k)) vertical(Number(k), g[k], false)
    g = groups(function(o) { return o.y })
    for (k in g) if (Object.prototype.hasOwnProperty.call(g, k)) horizontal(Number(k), g[k], true)
    g = groups(function(o) { return o.y + o.h })
    for (k in g) if (Object.prototype.hasOwnProperty.call(g, k)) horizontal(Number(k), g[k], false)
    return slots
}

function flushSlots(dragged, o) {
    var w = dragged.w, h = dragged.h
    return [
        { x: o.x + o.w, y: o.y },
        { x: o.x + o.w, y: o.y + o.h - h },
        { x: o.x + o.w, y: o.y + (o.h - h) / 2 },
        { x: o.x - w, y: o.y },
        { x: o.x - w, y: o.y + o.h - h },
        { x: o.x - w, y: o.y + (o.h - h) / 2 },
        { x: o.x, y: o.y + o.h },
        { x: o.x + o.w - w, y: o.y + o.h },
        { x: o.x + (o.w - w) / 2, y: o.y + o.h },
        { x: o.x, y: o.y - h },
        { x: o.x + o.w - w, y: o.y - h },
        { x: o.x + (o.w - w) / 2, y: o.y - h }
    ]
}

function anyRectsOverlap(items) {
    for (var i = 0; i < items.length; i++) {
        for (var j = i + 1; j < items.length; j++) {
            if (rectsOverlap(items[i], items[j])) return true
        }
    }
    return false
}

function arrangeMonitorsAfterDrop(dragged, others) {
    var w = dragged.w, h = dragged.h
    var dropCx = dragged.x + w / 2
    var dropCy = dragged.y + h / 2
    var list = others || []
    var best = null
    var bestScore = Infinity

    function consider(positions, draggedPos) {
        if (!draggedPos) return
        var items = []
        var ids = Object.keys(positions)
        var i
        for (i = 0; i < ids.length; i++) {
            var p = positions[ids[i]]
            var src = ids[i] === dragged.id ? dragged : null
            if (!src) {
                for (var k = 0; k < list.length; k++) if (list[k].id === ids[i]) { src = list[k]; break }
            }
            if (!src) continue
            items.push({ id: ids[i], x: p.x, y: p.y, w: src.w, h: src.h })
        }
        if (anyRectsOverlap(items)) return
        var placed = positions[dragged.id]
        if (!placed) return
        var r = { x: placed.x, y: placed.y, w: w, h: h }
        var nTouch = 0
        for (i = 0; i < items.length; i++) {
            if (items[i].id === dragged.id) continue
            if (edgesTouch(r, items[i])) nTouch++
        }
        if (list.length && nTouch === 0) return
        var d = (placed.x + w / 2 - dropCx) * (placed.x + w / 2 - dropCx) + (placed.y + h / 2 - dropCy) * (placed.y + h / 2 - dropCy)
        // Prefer bordering more parallel monitors when the drop spans them.
        var score = d - nTouch * 400 * 400
        if (score < bestScore) {
            bestScore = score
            best = JSON.parse(JSON.stringify(positions))
        }
    }

    function basePositions(dragX, dragY) {
        var pos = {}
        pos[dragged.id] = { x: dragX, y: dragY }
        for (var i = 0; i < list.length; i++) pos[list[i].id] = { x: list[i].x, y: list[i].y }
        return pos
    }

    if (!list.length) {
        var only = {}
        only[dragged.id] = { x: dragged.x, y: dragged.y }
        return only
    }

    var xs = [], ys = [], i, j, o
    for (i = 0; i < list.length; i++) {
        o = list[i]
        xs.push(o.x, o.x + o.w, o.x - w, o.x + o.w - w, o.x + (o.w - w) / 2)
        ys.push(o.y, o.y + o.h, o.y - h, o.y + o.h - h, o.y + (o.h - h) / 2)
        var slots = flushSlots(dragged, o)
        for (j = 0; j < slots.length; j++) consider(basePositions(slots[j].x, slots[j].y), slots[j])
    }
    xs = uniqueNums(xs)
    ys = uniqueNums(ys)
    for (i = 0; i < xs.length; i++) {
        for (j = 0; j < ys.length; j++) consider(basePositions(xs[i], ys[j]), { x: xs[i], y: ys[j] })
    }
    var compound = compoundEdgeSlots(dragged, list)
    for (i = 0; i < compound.length; i++) consider(basePositions(compound[i].x, compound[i].y), compound[i])

    // Insert between two horizontal neighbors (split them apart if needed).
    for (i = 0; i < list.length; i++) {
        for (j = 0; j < list.length; j++) {
            if (i === j) continue
            var a = list[i], b = list[j]
            var yOv = spanOverlap(a.y, a.y + a.h, b.y, b.y + b.h)
            if (yOv <= 8) continue
            if (a.x + a.w > b.x + 2) continue
            var pairY0 = Math.max(a.y, b.y)
            var pairY1 = Math.min(a.y + a.h, b.y + b.h)
            if (dropCy < pairY0 - 80 || dropCy > pairY1 + 80) continue
            var seam = a.x + a.w
            var gap = b.x - seam
            if (Math.abs(dropCx - (seam + gap / 2)) > Math.max(w, 240)) continue
            var yOpts = uniqueNums([a.y, b.y, a.y + a.h - h, b.y + b.h - h, (a.y + b.y) / 2])
            var yi
            for (yi = 0; yi < yOpts.length; yi++) {
                var shift = Math.max(0, w - gap)
                var pos = {}
                pos[dragged.id] = { x: seam, y: yOpts[yi] }
                var k
                for (k = 0; k < list.length; k++) {
                    var n = list[k]
                    var nx = n.x
                    if (n.x >= b.x - 1) nx = n.x + shift
                    pos[n.id] = { x: nx, y: n.y }
                }
                consider(pos, pos[dragged.id])
            }
        }
    }
    // Insert between stacked neighbors.
    for (i = 0; i < list.length; i++) {
        for (j = 0; j < list.length; j++) {
            if (i === j) continue
            var a2 = list[i], b2 = list[j]
            var xOv = spanOverlap(a2.x, a2.x + a2.w, b2.x, b2.x + b2.w)
            if (xOv <= 8) continue
            if (a2.y + a2.h > b2.y + 2) continue
            var pairX0 = Math.max(a2.x, b2.x)
            var pairX1 = Math.min(a2.x + a2.w, b2.x + b2.w)
            if (dropCx < pairX0 - 80 || dropCx > pairX1 + 80) continue
            var seamY = a2.y + a2.h
            var gapY = b2.y - seamY
            if (Math.abs(dropCy - (seamY + gapY / 2)) > Math.max(h, 240)) continue
            var xOpts = uniqueNums([a2.x, b2.x, a2.x + a2.w - w, b2.x + b2.w - w, (a2.x + b2.x) / 2])
            var xi
            for (xi = 0; xi < xOpts.length; xi++) {
                var shiftY = Math.max(0, h - gapY)
                var pos2 = {}
                pos2[dragged.id] = { x: xOpts[xi], y: seamY }
                var k2
                for (k2 = 0; k2 < list.length; k2++) {
                    var n2 = list[k2]
                    var ny = n2.y
                    if (n2.y >= b2.y - 1) ny = n2.y + shiftY
                    pos2[n2.id] = { x: n2.x, y: ny }
                }
                consider(pos2, pos2[dragged.id])
            }
        }
    }

    if (!best) {
        var maxR = list[0].x + list[0].w
        var top = list[0].y
        for (i = 1; i < list.length; i++) {
            maxR = Math.max(maxR, list[i].x + list[i].w)
            top = Math.min(top, list[i].y)
        }
        best = basePositions(maxR, top)
    }
    return best
}

function placeMonitorNoOverlap(dragged, others) {
    var all = arrangeMonitorsAfterDrop(dragged, others)
    var p = all && dragged && all[dragged.id]
    if (!p) return dragged
    return { x: p.x, y: p.y, w: dragged.w, h: dragged.h, id: dragged.id }
}

function snapLayoutRect(dragged, others, thresh) {
    return placeMonitorNoOverlap(dragged, others)
}

function liveLogicalSize(live) {
    var scale = Number(live && live.scale) || 1
    if (scale <= 0) scale = 1
    var w = Number(live && live.width) || 1920
    var h = Number(live && live.height) || 1080
    return { w: Math.max(200, Math.round(w / scale)), h: Math.max(200, Math.round(h / scale)) }
}

function monitorLayoutTiles(cfg, profile, liveList) {
    var tiles = []
    if (!profile) return tiles
    var off = {}
    var dis = profile.disabledMonitors || []
    for (var d = 0; d < dis.length; d++) off[String(dis[d])] = true
    var layout = profile.monitorLayout || {}
    var ids = profile.monitors || []
    var live = liveList || []
    for (var i = 0; i < ids.length; i++) {
        var id = ids[i]
        var saved = monitorById(cfg, id)
        var hit = findLive(saved, live)
        var size = hit ? liveLogicalSize(hit) : { w: 1920, h: 1080 }
        var pos = layout[id]
        var x = pos ? pos.x : (hit ? Number(hit.x) || 0 : i * (size.w + 32))
        var y = pos ? pos.y : (hit ? Number(hit.y) || 0 : 0)
        var mlabel = saved ? saved.label : id
        tiles.push({
            id: id,
            label: mlabel,
            x: x,
            y: y,
            w: size.w,
            h: size.h,
            off: !!off[id],
            connected: !!hit
        })
    }
    return tiles
}

function clone(o) { return JSON.parse(JSON.stringify(o)) }

function makeId(prefix) {
    return (prefix || "aw") + "-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 6)
}

function defaultOnlyOnBootForType(type) {
    return type === "app" ? false : true
}

function slugId(s) {
    var t = String(s || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
    return t.slice(0, 32) || makeId("mon")
}

function shortMonitorLabel(m) {
    var desc = String((m && m.description) || "").trim()
    if (desc) {
        desc = desc.replace(/^HP Inc\.\s+/i, "")
        return desc.slice(0, 48)
    }
    var make = String((m && m.make) || "").trim()
    var model = String((m && m.model) || "").trim()
    if (make && model) return (make + " " + model).slice(0, 48)
    return String((m && (m.label || m.name)) || "Monitor").slice(0, 48)
}

function normalizeMonitor(m) {
    if (!m || typeof m !== "object") return null
    var serial = String(m.serial || "").trim()
    var description = String(m.description || "").trim()
    var name = String(m.name || "").trim()
    if (!serial && !description && !name) return null
    var id = String(m.id || "").trim()
    if (!id) id = slugId(serial || description || name)
    return {
        id: id.slice(0, 40),
        label: String(m.label || shortMonitorLabel(m)).slice(0, 48),
        serial: serial.slice(0, 80),
        description: description.slice(0, 160),
        name: name.slice(0, 40)
    }
}

function round4(n) {
    return Math.round(Number(n) * 10000) / 10000
}

function normalizeGeom(g) {
    if (!g || typeof g !== "object") return null
    var x = Number(g.x), y = Number(g.y), w = Number(g.w), h = Number(g.h)
    if (isNaN(x) || isNaN(y) || isNaN(w) || isNaN(h)) return null
    w = Math.max(GEOM_MIN, Math.min(1, w))
    h = Math.max(GEOM_MIN, Math.min(1, h))
    x = Math.max(0, Math.min(1 - w, x))
    y = Math.max(0, Math.min(1 - h, y))
    var out = { x: round4(x), y: round4(y), w: round4(w), h: round4(h) }
    var z = parseInt(g.z, 10)
    if (!isNaN(z)) out.z = z
    return out
}

function autoLayoutRects(count, layout, columnWidth) {
    var gap = 0
    var rects = []
    if (!(count > 0)) return rects
    function push(x, y, w, h) { rects.push(normalizeGeom({ x: x, y: y, w: w, h: h })) }
    if (layout === "set-width") {
        var sw = columnWidth > 0.1 && columnWidth < 1 ? columnWidth : 0.25
        for (var i = 0; i < count; i++) push(i * (sw + gap), 0, sw, 1)
        return rects
    }
    if (layout === "scrolling") {
        if (count === 1) { push(0, 0, 1, 1); return rects }
        var cw = columnWidth > 0.1 && columnWidth < 1 ? columnWidth : 0.49
        for (var i = 0; i < count; i++) push(i * (cw + gap), 0, cw, 1)
        return rects
    }
    if (layout === "stage") {
        push(0, 0, 1, 1)
        var scw = columnWidth > 0.1 && columnWidth < 1 ? columnWidth : 0.5
        for (var s = 1; s < count; s++) push(1 + (s - 1) * scw, 0, scw, 1)
        return rects
    }
    if (layout === "master") {
        if (count === 1) { push(0, 0, 1, 1); return rects }
        var mw = 0.55
        push(0, 0, mw - gap / 2, 1)
        var stackN = count - 1
        var sh = (1 - gap * (stackN - 1)) / stackN
        for (var j = 0; j < stackN; j++) push(mw + gap / 2, j * (sh + gap), 1 - mw - gap / 2, sh)
        return rects
    }
    if (count === 1) { push(0, 0, 1, 1); return rects }
    if (count === 2) { push(0, 0, 0.5 - gap / 2, 1); push(0.5 + gap / 2, 0, 0.5 - gap / 2, 1); return rects }
    if (count === 3) {
        push(0, 0, 0.5 - gap / 2, 1)
        push(0.5 + gap / 2, 0, 0.5 - gap / 2, 0.5 - gap / 2)
        push(0.5 + gap / 2, 0.5 + gap / 2, 0.5 - gap / 2, 0.5 - gap / 2)
        return rects
    }
    if (count === 4) {
        push(0, 0, 0.5 - gap / 2, 0.5 - gap / 2)
        push(0.5 + gap / 2, 0, 0.5 - gap / 2, 0.5 - gap / 2)
        push(0, 0.5 + gap / 2, 0.5 - gap / 2, 0.5 - gap / 2)
        push(0.5 + gap / 2, 0.5 + gap / 2, 0.5 - gap / 2, 0.5 - gap / 2)
        return rects
    }
    var cols = count <= 6 ? 3 : 4
    var rows = Math.ceil(count / cols)
    var tw = (1 - gap * (cols - 1)) / cols
    var th = (1 - gap * (rows - 1)) / rows
    for (var k = 0; k < count; k++) {
        var col = k % cols
        var row = Math.floor(k / cols)
        push(col * (tw + gap), row * (th + gap), tw, th)
    }
    return rects
}

function assignmentHasGeom(a) {
    return !!(a && normalizeGeom(a.geom))
}

function workspaceUsesCustomLayout(apps) {
    var list = apps || []
    for (var i = 0; i < list.length; i++) if (assignmentHasGeom(list[i])) return true
    return false
}

var GEOM_EPS = 0.02
var GEOM_MIN = 0.04
var MAX_PANES = 20

// Named split shapes stamp assignment geoms only. They do not change
// dwindle/scrolling/master or extras/lock apply.
var SNAP_POINTS = [0.20, 0.25, 1 / 3, 0.375, 0.382, 0.40, 0.50, 0.60, 0.618, 0.625, 2 / 3, 0.75, 0.80]
var SNAP_TOLERANCE = 0.016

function snapPosition(position, enabled) {
    var pos = Number(position)
    if (!isFinite(pos)) return 0
    if (enabled === false) return pos
    var best = pos
    var bestDistance = SNAP_TOLERANCE
    for (var i = 0; i < SNAP_POINTS.length; i++) {
        var distance = Math.abs(pos - SNAP_POINTS[i])
        if (distance <= bestDistance) {
            bestDistance = distance
            best = SNAP_POINTS[i]
        }
    }
    return best
}

function shapePresets() {
    return [
        { id: "even", name: "Even", orientation: "columns", weights: [50, 50], overflow: "extend", underfill: "rescale" },
        { id: "focus", name: "Focus", orientation: "columns", weights: [25, 50, 25], overflow: "last", underfill: "hold" },
        { id: "main", name: "Main", orientation: "columns", weights: [60, 40], overflow: "last", underfill: "rescale" },
        { id: "main-right", name: "Main right", orientation: "columns", weights: [40, 60], overflow: "first", underfill: "rescale" },
        { id: "golden", name: "Golden", orientation: "columns", weights: [61.8, 38.2], overflow: "last", underfill: "rescale" },
        { id: "thirds", name: "Thirds", orientation: "columns", weights: [100 / 3, 100 / 3, 100 / 3], overflow: "extend", underfill: "rescale" },
        { id: "wide-centre", name: "Wide centre", orientation: "columns", weights: [20, 60, 20], overflow: "last", underfill: "hold" },
        { id: "stacked", name: "Stacked", orientation: "rows", weights: [50, 50], overflow: "extend", underfill: "rescale" },
        { id: "grid", name: "Grid", kind: "grid" }
    ]
}

function findShape(id) {
    var want = String(id || "")
    var list = shapePresets()
    for (var i = 0; i < list.length; i++) if (list[i].id === want) return list[i]
    return null
}

function describeShape(shape) {
    if (!shape) return ""
    if (shape.kind === "grid") return "grid"
    var weights = shape.weights || []
    var parts = []
    for (var i = 0; i < weights.length; i++) {
        var n = Number(weights[i])
        var rounded = Math.round(n)
        parts.push(Math.abs(n - rounded) < 0.5 ? String(rounded) : n.toFixed(1))
    }
    return parts.join(" / ") + (shape.orientation === "rows" ? " (rows)" : "")
}

function fillOrder(weights) {
    var index = []
    for (var i = 0; i < weights.length; i++) index.push(i)
    index.sort(function(a, b) {
        if (weights[b] !== weights[a]) return weights[b] - weights[a]
        return a - b
    })
    return index
}

function normalizeFracWeights(weights) {
    var raw = []
    var i
    if (weights && weights.length) {
        for (i = 0; i < weights.length && i < MAX_PANES; i++) {
            var n = Number(weights[i])
            raw.push(isFinite(n) && n > 0 ? n : 1)
        }
    }
    if (!raw.length) return [1]
    var total = 0
    for (i = 0; i < raw.length; i++) total += raw[i]
    if (total <= 0) {
        for (i = 0; i < raw.length; i++) raw[i] = 1 / raw.length
        return raw
    }
    var out = []
    for (i = 0; i < raw.length; i++) out.push(raw[i] / total)
    return out
}

function shapeRects(shape, count) {
    var n = parseInt(count, 10)
    if (!(n > 0)) return []
    var spec = shape && typeof shape === "object" ? shape : findShape(shape) || {}
    if (spec.kind === "grid") return autoLayoutRects(n, "dwindle", 0.49)

    var orientation = spec.orientation === "rows" ? "rows" : "columns"
    var overflow = spec.overflow === "first" || spec.overflow === "extend" ? spec.overflow : "last"
    var underfill = spec.underfill === "hold" ? "hold" : "rescale"
    var weights = (spec.weights || []).slice()
    if (!weights.length) {
        for (var e = 0; e < n; e++) weights.push(1)
    }
    if (n > weights.length && overflow === "extend") {
        var last = weights[weights.length - 1]
        while (weights.length < n) weights.push(last)
    }
    if (n < weights.length && underfill === "rescale") weights = weights.slice(0, n)

    var frac = normalizeFracWeights(weights)
    var slots = []
    var running = 0
    var i
    for (i = 0; i < frac.length; i++) {
        var size = frac[i]
        if (orientation === "columns") slots.push({ x: running, y: 0, w: size, h: 1 })
        else slots.push({ x: 0, y: running, w: 1, h: size })
        running += size
    }

    if (n <= slots.length) {
        if (underfill === "hold") {
            var order = fillOrder(frac)
            var outHold = []
            for (i = 0; i < n; i++) outHold.push(normalizeGeom(slots[order[i]]))
            return outHold
        }
        var out = []
        for (i = 0; i < n; i++) out.push(normalizeGeom(slots[i]))
        return out
    }

    var stackAt = overflow === "first" ? 0 : slots.length - 1
    var partsN = n - slots.length + 1
    var stacked = []
    for (i = 0; i < slots.length; i++) {
        var sg = slots[i]
        if (i !== stackAt) {
            stacked.push(normalizeGeom(sg))
            continue
        }
        var p
        for (p = 0; p < partsN; p++) {
            if (orientation === "columns") {
                stacked.push(normalizeGeom({ x: sg.x, y: sg.y + (sg.h / partsN) * p, w: sg.w, h: sg.h / partsN }))
            } else {
                stacked.push(normalizeGeom({ x: sg.x + (sg.w / partsN) * p, y: sg.y, w: sg.w / partsN, h: sg.h }))
            }
        }
    }
    return stacked
}

function applyShapeToApps(apps, shapeId) {
    var list = clone(apps) || []
    var shape = findShape(shapeId)
    if (!shape || !list.length) return list
    var tileIdx = []
    var i
    for (i = 0; i < list.length; i++) {
        if (assignmentPlace(list[i]) !== "float") tileIdx.push(i)
    }
    var rects = shapeRects(shape, tileIdx.length)
    for (i = 0; i < tileIdx.length; i++) {
        var g = rects[i]
        if (!g) continue
        if (list[tileIdx[i]] && list[tileIdx[i]].id) g.id = list[tileIdx[i]].id
        list[tileIdx[i]].geom = g
        if (tileIdx.length >= 2) list[tileIdx[i]].lockPlace = true
    }
    return list
}

// A Hyprland group occupies a single tile, so the preview must pack one pane
// per group rather than one per window. Returns the tile representatives in
// order plus, for each input index, the representative it belongs to.
function collapseGroupTiles(list) {
    var tiles = []
    var owner = []
    var seen = {}
    for (var i = 0; i < list.length; i++) {
        var token = list[i] && list[i].group ? String(list[i].group) : ""
        if (!token || assignmentPlace(list[i]) === "float") {
            owner.push(tiles.length)
            tiles.push(list[i])
            continue
        }
        if (seen[token] === undefined) {
            seen[token] = tiles.length
            tiles.push(list[i])
        }
        owner.push(seen[token])
    }
    return { tiles: tiles, owner: owner }
}

// Per-window view of the same collapse, for the preview: it draws one pane per
// tile, so every member after the first is hidden and the first carries a tab
// strip naming the whole group. Entries line up with `list` index for index;
// an ungrouped window gets null and is drawn the ordinary way.
function groupPreviewTiles(list) {
    var src = list || []
    var counts = {}
    for (var i = 0; i < src.length; i++) {
        var t = groupTokenOf(src[i])
        if (t) counts[t] = (counts[t] || 0) + 1
    }
    var out = []
    var reps = {}
    for (var j = 0; j < src.length; j++) {
        var token = groupTokenOf(src[j])
        // A lone member is not a group: it occupies its tile by itself and a
        // one-tab strip would be noise.
        if (!token || counts[token] < 2) { out.push(null); continue }
        if (reps[token] === undefined) {
            reps[token] = j
            var tabs = []
            var active = null
            for (var k = 0; k < src.length; k++) {
                if (groupTokenOf(src[k]) !== token) continue
                var isActive = src[k].groupActive === true
                if (isActive && !active) active = src[k]
                tabs.push({ id: String(src[k].id || ""), name: String(src[k].name || "App"), exec: String(src[k].exec || src[k].command || ""), active: isActive })
            }
            out.push({ rep: true, repIndex: j, tabs: tabs, active: active })
        } else {
            out.push({ rep: false, repIndex: reps[token], tabs: [], active: null })
        }
    }
    return out
}

// A floating window sits above the tiles, so it never joins a tile group.
function groupTokenOf(a) {
    if (!a || !a.group) return ""
    if (assignmentPlace(a) === "float") return ""
    return String(a.group)
}

function chipGeomsForWorkspace(profile, workspace) {
    var ws = parseInt(workspace, 10)
    var list = []
    var apps = (profile && profile.assignments) || []
    for (var i = 0; i < apps.length; i++) {
        if (apps[i].enabled === false) continue
        if (Number(apps[i].workspace) === ws) list.push(apps[i])
    }
    if (!list.length) return [{ x: 0, y: 0, w: 0.5, h: 1 }, { x: 0.5, y: 0, w: 0.5, h: 1 }]
    var pref = effectiveWorkspacePref(profile, ws)
    var collapsed = collapseGroupTiles(list)
    return packedGeomsForApps(collapsed.tiles, pref.layout, 1 / Math.max(1, pref.visibleCount))
}

function geomRight(g) { return Number(g.x) + Number(g.w) }
function geomBottom(g) { return Number(g.y) + Number(g.h) }

function rangeOverlap(a0, a1, b0, b1) {
    return Math.min(a1, b1) - Math.max(a0, b0) > GEOM_EPS
}

function geomsOverlap(a, b) {
    if (!a || !b) return false
    return rangeOverlap(a.x, geomRight(a), b.x, geomRight(b)) &&
           rangeOverlap(a.y, geomBottom(a), b.y, geomBottom(b))
}

function layoutHasOverlap(geoms) {
    var list = geoms || []
    for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
            if (geomsOverlap(list[i], list[j])) return true
        }
    }
    return false
}

function repairOverlappingLayouts(cfg, layout, columnWidth) {
    if (!cfg || !Array.isArray(cfg.profiles)) return { config: cfg, changed: false }
    var out = clone(cfg)
    var changed = false
    for (var p = 0; p < out.profiles.length; p++) {
        var assignments = out.profiles[p].assignments || []
        var byWs = {}
        for (var i = 0; i < assignments.length; i++) {
            var ws = String(assignments[i].workspace)
            if (!byWs[ws]) byWs[ws] = []
            byWs[ws].push(assignments[i])
        }
        for (var wsKey in byWs) {
            var group = byWs[wsKey]
            var packed = packedGeomsForApps(group, layout || "dwindle", columnWidth)
            for (var g = 0; g < group.length; g++) {
                if (!assignmentHasGeom(group[g])) continue
                var next = packed[g]
                var cur = normalizeGeom(group[g].geom)
                if (!next || !cur) continue
                if (cur.x !== next.x || cur.y !== next.y || cur.w !== next.w || cur.h !== next.h) {
                    group[g].geom = { x: next.x, y: next.y, w: next.w, h: next.h }
                    changed = true
                }
            }
        }
    }
    return { config: out, changed: changed }
}

function packedGeomsForApps(apps, layout, columnWidth) {
    var list = apps || []
    var n = list.length
    var packLayout = layout === "scrolling" ? "dwindle" : (layout || "dwindle")
    var tileList = []
    var tilePos = []
    // Which tile each entry draws in. Members of a group share a tile, so they
    // also share its geometry — their identical geoms are the group, not an
    // overlap, and packing them as separate panes would lay out one pane too
    // many and throw the saved layout away.
    var tileOf = []
    var groupSeen = {}
    var i
    for (i = 0; i < n; i++) {
        if (assignmentPlace(list[i]) === "float") { tileOf.push(-1); continue }
        var gtok = groupTokenOf(list[i])
        if (gtok && groupSeen[gtok] !== undefined) { tileOf.push(groupSeen[gtok]); continue }
        if (gtok) groupSeen[gtok] = tileList.length
        tileOf.push(tileList.length)
        tilePos.push(i)
        tileList.push(list[i])
    }
    var autos = autoLayoutRects(tileList.length, packLayout, columnWidth)
    if (tileList.length === 1) autos = [{ x: 0, y: 0, w: 1, h: 1 }]
    var tileGeoms = []
    var anyCustom = false
    var t
    for (t = 0; t < tileList.length; t++) {
        var g = normalizeGeom(tileList[t] && tileList[t].geom)
        if (g) {
            anyCustom = true
            tileGeoms.push(g)
        } else {
            tileGeoms.push(autos[t] || normalizeGeom({ x: 0, y: 0, w: 1, h: 1 }))
        }
    }
    // One tiled pane always fills the workspace — leftover 1/N column geoms from
    // scrolling Visible columns must not keep a single window at half width.
    if (tileList.length === 1) {
        anyCustom = false
        tileGeoms = [{ x: 0, y: 0, w: 1, h: 1 }]
    }
    var use = (!anyCustom || layoutHasOverlap(tileGeoms)) ? autos : tileGeoms
    var out = []
    for (i = 0; i < n; i++) {
        var item
        if (tileOf[i] < 0) {
            item = normalizeFloatGeom(list[i] && list[i].geom) || normalizeFloatGeom({ x: 0.12, y: 0.12, w: 0.4, h: 0.4 })
        } else {
            item = clone(use[tileOf[i]] || { x: 0, y: 0, w: 1, h: 1 })
        }
        if (list[i] && list[i].id) item.id = list[i].id
        out.push(item)
    }
    return out
}

function listSplits(geoms) {
    var list = geoms || []
    var v = {}
    var h = {}
    function bucket(map, pos, side, idx) {
        var p = round4(pos)
        var k = null
        for (var existing in map) {
            if (Math.abs(map[existing].pos - p) < GEOM_EPS) { k = existing; break }
        }
        if (!k) {
            k = String(p)
            map[k] = { pos: p, left: [], right: [], top: [], bottom: [] }
        }
        map[k][side].push(idx)
    }
    for (var i = 0; i < list.length; i++) {
        var g = list[i]
        if (!g) continue
        if (g.x > GEOM_EPS) bucket(v, g.x, "right", i)
        if (geomRight(g) < 1 - GEOM_EPS) bucket(v, geomRight(g), "left", i)
        if (g.y > GEOM_EPS) bucket(h, g.y, "bottom", i)
        if (geomBottom(g) < 1 - GEOM_EPS) bucket(h, geomBottom(g), "top", i)
    }
    var splits = []
    function spanY(ids) {
        var y0 = 0, y1 = 1, first = true
        for (var i = 0; i < ids.length; i++) {
            var g = list[ids[i]]
            if (!g) continue
            if (first) { y0 = g.y; y1 = geomBottom(g); first = false }
            else { y0 = Math.min(y0, g.y); y1 = Math.max(y1, geomBottom(g)) }
        }
        return { s0: y0, s1: y1 }
    }
    function spanX(ids) {
        var x0 = 0, x1 = 1, first = true
        for (var i = 0; i < ids.length; i++) {
            var g = list[ids[i]]
            if (!g) continue
            if (first) { x0 = g.x; x1 = geomRight(g); first = false }
            else { x0 = Math.min(x0, g.x); x1 = Math.max(x1, geomRight(g)) }
        }
        return { s0: x0, s1: x1 }
    }
    for (var vk in v) {
        var vb = v[vk]
        if (vb.left.length && vb.right.length) {
            var ys = spanY(vb.left.concat(vb.right))
            splits.push({ axis: "v", pos: vb.pos, aIds: vb.left, bIds: vb.right, s0: ys.s0, s1: ys.s1 })
        }
    }
    for (var hk in h) {
        var hb = h[hk]
        if (hb.top.length && hb.bottom.length) {
            var xs = spanX(hb.top.concat(hb.bottom))
            splits.push({ axis: "h", pos: hb.pos, aIds: hb.top, bIds: hb.bottom, s0: xs.s0, s1: xs.s1 })
        }
    }
    return splits
}

function nudgeSplit(geoms, split, delta, options) {
    if (!split || !geoms || !geoms.length) return geoms
    var next = clone(geoms)
    var minD = -1
    var maxD = 1
    var i, g
    var aIds = split.aIds || []
    var bIds = split.bIds || []
    if (split.axis === "v") {
        for (i = 0; i < aIds.length; i++) {
            g = next[aIds[i]]
            if (g) minD = Math.max(minD, -(g.w - GEOM_MIN))
        }
        for (i = 0; i < bIds.length; i++) {
            g = next[bIds[i]]
            if (g) maxD = Math.min(maxD, g.w - GEOM_MIN)
        }
    } else {
        for (i = 0; i < aIds.length; i++) {
            g = next[aIds[i]]
            if (g) minD = Math.max(minD, -(g.h - GEOM_MIN))
        }
        for (i = 0; i < bIds.length; i++) {
            g = next[bIds[i]]
            if (g) maxD = Math.min(maxD, g.h - GEOM_MIN)
        }
    }
    var raw = Number(delta) || 0
    var pos = Number(split.pos) || 0
    var target = pos + raw
    if (options && options.snap === true) target = snapPosition(target, true)
    delta = Math.max(minD, Math.min(maxD, target - pos))
    if (split.axis === "v") {
        for (i = 0; i < aIds.length; i++) {
            g = next[aIds[i]]
            if (g) g.w = round4(g.w + delta)
        }
        for (i = 0; i < bIds.length; i++) {
            g = next[bIds[i]]
            if (g) {
                g.x = round4(g.x + delta)
                g.w = round4(g.w - delta)
            }
        }
    } else {
        for (i = 0; i < aIds.length; i++) {
            g = next[aIds[i]]
            if (g) g.h = round4(g.h + delta)
        }
        for (i = 0; i < bIds.length; i++) {
            g = next[bIds[i]]
            if (g) {
                g.y = round4(g.y + delta)
                g.h = round4(g.h - delta)
            }
        }
    }
    return next
}

function evenSplit(geoms, split) {
    if (!split || !geoms || !geoms.length) return geoms
    var aIds = split.aIds || []
    var bIds = split.bIds || []
    if (!aIds.length || !bIds.length) return geoms
    var minP = 1
    var maxP = 0
    var i, g
    var startKey = split.axis === "v" ? "x" : "y"
    var sizeKey = split.axis === "v" ? "w" : "h"
    function consider(idx) {
        g = geoms[idx]
        if (!g) return
        minP = Math.min(minP, Number(g[startKey]))
        maxP = Math.max(maxP, Number(g[startKey]) + Number(g[sizeKey]))
    }
    for (i = 0; i < aIds.length; i++) consider(aIds[i])
    for (i = 0; i < bIds.length; i++) consider(bIds[i])
    var mid = (minP + maxP) / 2
    return nudgeSplit(geoms, split, mid - (Number(split.pos) || 0))
}

function overlapLen(a0, a1, b0, b1) {
    return Math.min(a1, b1) - Math.max(a0, b0)
}

function splitRect(g, dir) {
    var r = normalizeGeom(g)
    if (!r) return null
    dir = String(dir || "")
    if (dir === "left" || dir === "right") {
        var hw = r.w / 2
        if (hw < GEOM_MIN) return null
        var left = { x: r.x, y: r.y, w: hw, h: r.h }
        var right = { x: round4(r.x + hw), y: r.y, w: round4(r.w - hw), h: r.h }
        return dir === "left" ? { incoming: left, stay: right } : { incoming: right, stay: left }
    }
    var hh = r.h / 2
    if (hh < GEOM_MIN) return null
    var top = { x: r.x, y: r.y, w: r.w, h: hh }
    var bot = { x: r.x, y: round4(r.y + hh), w: r.w, h: round4(r.h - hh) }
    if (dir === "up" || dir === "top") return { incoming: top, stay: bot }
    return { incoming: bot, stay: top }
}

function fillHole(geoms, hole, skip) {
    var next = clone(geoms)
    if (!hole) return next
    var hx0 = Number(hole.x), hy0 = Number(hole.y)
    var hx1 = hx0 + Number(hole.w), hy1 = hy0 + Number(hole.h)
    var i, g, oy, ox
    for (i = 0; i < next.length; i++) {
        if (skip && skip[i]) continue
        g = next[i]
        if (!g) continue
        oy = overlapLen(g.y, geomBottom(g), hy0, hy1)
        ox = overlapLen(g.x, geomRight(g), hx0, hx1)
        if (Math.abs(geomRight(g) - hx0) < GEOM_EPS && oy > g.h * 0.45) {
            g.w = round4(g.w + hole.w)
            continue
        }
        if (Math.abs(g.x - hx1) < GEOM_EPS && oy > g.h * 0.45) {
            g.w = round4(g.w + hole.w)
            g.x = round4(g.x - hole.w)
            continue
        }
        if (Math.abs(geomBottom(g) - hy0) < GEOM_EPS && ox > g.w * 0.45) {
            g.h = round4(g.h + hole.h)
            continue
        }
        if (Math.abs(g.y - hy1) < GEOM_EPS && ox > g.w * 0.45) {
            g.h = round4(g.h + hole.h)
            g.y = round4(g.y - hole.h)
        }
    }
    return next
}

function geomArea(g) {
    if (!g) return 0
    return Number(g.w) * Number(g.h)
}

function removeAppAndFill(apps, id) {
    var list = clone(apps || [])
    var idx = -1
    var i
    for (i = 0; i < list.length; i++) {
        if (String(list[i].id) === String(id)) { idx = i; break }
    }
    if (idx < 0) return apps
    var gone = list[idx]
    var ws = gone.workspace
    var hole = assignmentPlace(gone) === "float" ? null : normalizeGeom(gone.geom)
    var goneToken = groupTokenOf(gone)
    list.splice(idx, 1)
    if (!hole) return list
    // Closing one tab of a group leaves the tile occupied by the remaining
    // members, so there is no hole and the layout must be left alone.
    if (goneToken) {
        for (i = 0; i < list.length; i++) {
            if (String(list[i].workspace) !== String(ws)) continue
            if (groupTokenOf(list[i]) === goneToken) return list
        }
    }
    // Indices are grouped per tile: a group's members share one entry, take one
    // geometry between them, and are written back together.
    var tileIdx = []
    var tileGeoms = []
    var missing = false
    var tileSeen = {}
    for (i = 0; i < list.length; i++) {
        if (String(list[i].workspace) !== String(ws)) continue
        if (assignmentPlace(list[i]) === "float") continue
        var g = normalizeGeom(list[i].geom)
        if (!g) missing = true
        var tok = groupTokenOf(list[i])
        if (tok && tileSeen[tok] !== undefined) { tileIdx[tileSeen[tok]].push(i); continue }
        if (tok) tileSeen[tok] = tileIdx.length
        tileIdx.push([i])
        tileGeoms.push(g || { x: 0, y: 0, w: 1, h: 1 })
    }
    function setTileGeom(t, geom) {
        for (var k = 0; k < tileIdx[t].length; k++) list[tileIdx[t][k]].geom = clone(geom)
    }
    if (!tileIdx.length) return list
    if (tileIdx.length === 1) {
        setTileGeom(0, { x: 0, y: 0, w: 1, h: 1 })
        return list
    }
    if (missing) return list
    var filled = fillHole(tileGeoms, hole, {})
    var before = geomArea(hole)
    var after = 0
    for (i = 0; i < tileGeoms.length; i++) before += geomArea(tileGeoms[i])
    for (i = 0; i < filled.length; i++) after += geomArea(filled[i])
    if (after + 0.04 < before || layoutHasOverlap(filled)) {
        var autos = autoLayoutRects(tileIdx.length, "dwindle", 0.49)
        for (i = 0; i < tileIdx.length; i++) {
            if (autos[i]) setTileGeom(i, autos[i])
        }
        return list
    }
    for (i = 0; i < tileIdx.length; i++) setTileGeom(i, filled[i])
    return list
}

function swapGeoms(geoms, i, j) {
    var next = clone(geoms)
    if (i === j || !next[i] || !next[j]) return geoms
    var t = next[i]
    next[i] = next[j]
    next[j] = t
    return next
}

function splitDrop(geoms, fromIdx, toIdx, dir) {
    if (fromIdx === toIdx) return geoms
    var next = clone(geoms)
    if (!next[fromIdx] || !next[toIdx]) return geoms
    var hole = clone(next[fromIdx])
    var cut = splitRect(next[toIdx], dir)
    if (!cut) return geoms
    next[toIdx] = normalizeGeom(cut.stay)
    next[fromIdx] = normalizeGeom(cut.incoming)
    return fillHole(next, hole, {})
}

function dropZone(nx, ny) {
    var m = 0.28
    if (nx < m) return "left"
    if (nx > 1 - m) return "right"
    if (ny < m) return "top"
    if (ny > 1 - m) return "bottom"
    return "center"
}

function normalizeFloatGeom(g) {
    if (!g || typeof g !== "object") return null
    var x = Number(g.x), y = Number(g.y), w = Number(g.w), h = Number(g.h)
    if (isNaN(x) || isNaN(y) || isNaN(w) || isNaN(h)) return null
    w = Math.max(GEOM_MIN, Math.min(1, w))
    h = Math.max(GEOM_MIN, Math.min(1, h))
    x = Math.max(0, Math.min(1 - w, x))
    y = Math.max(0, Math.min(1 - h, y))
    var out = { x: round4(x), y: round4(y), w: round4(w), h: round4(h) }
    var z = parseInt(g.z, 10)
    if (!isNaN(z)) out.z = z
    return out
}

function moveFloatGeom(g, dx, dy) {
    var r = normalizeFloatGeom(g)
    if (!r) return g
    r.x += Number(dx) || 0
    r.y += Number(dy) || 0
    return normalizeFloatGeom(r)
}

function resizeFloatGeom(g, edge, dx, dy) {
    var r = normalizeFloatGeom(g)
    if (!r) return g
    edge = String(edge || "")
    if (edge.indexOf("l") >= 0) { r.x += dx; r.w -= dx }
    if (edge.indexOf("r") >= 0) r.w += dx
    if (edge.indexOf("t") >= 0) { r.y += dy; r.h -= dy }
    if (edge.indexOf("b") >= 0) r.h += dy
    return normalizeFloatGeom(r)
}

function assignmentPlace(a) {
    return a && a.place === "float" ? "float" : "tile"
}

function emptyChrome() {
    return {
        opacityActive: 1,
        opacityInactive: 1,
        borderActive: true,
        borderInactive: true,
        borderColorActive: "",
        borderColorInactive: "",
        borderSize: -1
    }
}

function clampOpacity(n) {
    var v = Number(n)
    if (isNaN(v)) return 1
    if (v < 0.2) return 0.2
    if (v > 1) return 1
    return Math.round(v * 100) / 100
}

function normalizeChrome(raw) {
    var d = emptyChrome()
    if (!raw || typeof raw !== "object") return d
    d.opacityActive = clampOpacity(raw.opacityActive != null ? raw.opacityActive : 1)
    d.opacityInactive = clampOpacity(raw.opacityInactive != null ? raw.opacityInactive : 1)
    d.borderActive = raw.borderActive !== false
    d.borderInactive = raw.borderInactive !== false
    d.borderColorActive = String(raw.borderColorActive || "").replace(/[^#0-9a-fA-F]/g, "").slice(0, 9)
    d.borderColorInactive = String(raw.borderColorInactive || "").replace(/[^#0-9a-fA-F]/g, "").slice(0, 9)
    var bs = parseInt(raw.borderSize, 10)
    d.borderSize = (!isNaN(bs) && bs >= 0 && bs <= 12) ? bs : -1
    return d
}

function chromeIsDefault(c) {
    var d = emptyChrome()
    var n = normalizeChrome(c)
    return n.opacityActive === d.opacityActive && n.opacityInactive === d.opacityInactive
        && n.borderActive === d.borderActive && n.borderInactive === d.borderInactive
        && n.borderColorActive === "" && n.borderColorInactive === "" && n.borderSize === -1
}

function safeCwd(s) {
    var t = String(s || "").trim()
    if (t.indexOf("/") !== 0 || t.length > 400) return ""
    if (t.indexOf("..") >= 0) return ""
    if (/[^A-Za-z0-9._/+\- ]/.test(t)) return ""
    return t
}

function safeUrl(s) {
    var t = String(s || "").trim()
    if (t.length > 300) t = t.slice(0, 300)
    if (!/^https:\/\/[A-Za-z0-9][A-Za-z0-9._~:/?#@&=+%,\-]*$/.test(t)) return ""
    return t
}

function setAppsPlace(apps, index, place, layout, columnWidth) {
    var next = clone(apps || [])
    if (!next[index]) return apps
    var want = place === "float" ? "float" : "tile"
    var i
    if (want === "float") {
        var hole = normalizeGeom(next[index].geom) || { x: 0, y: 0, w: 1, h: 1 }
        next[index].place = "float"
        next[index].geomTiled = clone(hole)
        next[index].geom = normalizeFloatGeom(hole)
        var tileGeoms = []
        var tileIdx = []
        for (i = 0; i < next.length; i++) {
            if (i === index || assignmentPlace(next[i]) === "float") continue
            tileIdx.push(i)
            tileGeoms.push(normalizeGeom(next[i].geom) || { x: 0, y: 0, w: 1, h: 1 })
        }
        if (tileGeoms.length) {
            tileGeoms = fillHole(tileGeoms, hole, {})
            for (i = 0; i < tileIdx.length; i++) next[tileIdx[i]].geom = tileGeoms[i]
        }
        return next
    }
    next[index].place = "tile"
    var others = []
    var otherIdx = []
    for (i = 0; i < next.length; i++) {
        if (i === index || assignmentPlace(next[i]) === "float") continue
        otherIdx.push(i)
        others.push(normalizeGeom(next[i].geom) || { x: 0, y: 0, w: 1, h: 1 })
    }
    if (!others.length) {
        next[index].geom = { x: 0, y: 0, w: 1, h: 1 }
        return next
    }
    var fg = normalizeFloatGeom(next[index].geom) || { x: 0.5, y: 0.5, w: 0.4, h: 0.4 }
    var cx = fg.x + fg.w / 2
    var cy = fg.y + fg.h / 2
    var best = 0
    var bestD = 1e9
    var contained = -1
    for (i = 0; i < others.length; i++) {
        var o = others[i]
        if (cx >= o.x - GEOM_EPS && cx <= o.x + o.w + GEOM_EPS && cy >= o.y - GEOM_EPS && cy <= o.y + o.h + GEOM_EPS)
            contained = i
        var ocx = o.x + o.w / 2
        var ocy = o.y + o.h / 2
        var d = (ocx - cx) * (ocx - cx) + (ocy - cy) * (ocy - cy)
        if (d < bestD) { bestD = d; best = i }
    }
    if (contained >= 0) best = contained
    var tw = Math.max(0.001, others[best].w)
    var th = Math.max(0.001, others[best].h)
    var dir = dropZone((cx - others[best].x) / tw, (cy - others[best].y) / th)
    if (dir === "center") {
        var dx = (cx - others[best].x) / tw - 0.5
        var dy = (cy - others[best].y) / th - 0.5
        if (Math.abs(dx) >= Math.abs(dy)) dir = dx >= 0 ? "right" : "left"
        else dir = dy >= 0 ? "bottom" : "top"
    }
    delete next[index].geomTiled
    var cut = splitRect(others[best], dir)
    if (!cut) {
        var autos = autoLayoutRects(others.length + 1, layout === "scrolling" ? "dwindle" : (layout || "dwindle"), columnWidth)
        var t = 0
        for (i = 0; i < next.length; i++) {
            if (i !== index && assignmentPlace(next[i]) === "float") continue
            if (autos[t]) next[i].geom = autos[t]
            t++
        }
        return next
    }
    next[otherIdx[best]].geom = normalizeGeom(cut.stay)
    next[index].geom = normalizeGeom(cut.incoming)
    return next
}

function maxOrganizerPanes() { return MAX_PANES }

function normalizeAssignment(a) {
    var ws = parseInt(a.workspace, 10)
    if (!(ws >= 1 && ws <= 10) && String(a.workspace).indexOf("special:") !== 0) ws = 1
    var type = (a.type === "webapp" || a.type === "app" || a.type === "custom") ? a.type : "app"
    var onlyOnBoot = defaultOnlyOnBootForType(type)
    if (typeof a.onlyOnBoot === "boolean") {
        onlyOnBoot = a.onlyOnBoot
    } else if (a.onlyOnBoot === 1 || a.onlyOnBoot === "1" || a.onlyOnBoot === "true") {
        onlyOnBoot = true
    } else if (a.onlyOnBoot === 0 || a.onlyOnBoot === "0" || a.onlyOnBoot === "false") {
        onlyOnBoot = false
    }
    var out = {
        id: String(a.id || makeId()),
        workspace: ws,
        name: String(a.name || a.command || "App").slice(0, 80),
        command: canonicalExec(String(a.command || a.exec || "")).slice(0, 500),
        exec: canonicalExec(String(a.exec || a.command || "")).slice(0, 500),
        type: type,
        enabled: a.enabled !== false,
        onlyOnBoot: onlyOnBoot,
        lockPlace: a.lockPlace === true,
        place: assignmentPlace(a)
    }
    if (a.geomTiled) {
        var gt = normalizeGeom(a.geomTiled)
        if (gt) out.geomTiled = gt
    }
    var cwd = safeCwd(a.cwd)
    if (cwd) out.cwd = cwd
    var url = safeUrl(a.url)
    if (url) out.url = url
    var title = String(a.title || "").trim()
    if (title) out.title = title.slice(0, 120)
    var cls = String(a.class || a.windowClass || "").trim()
    if (cls) out.class = cls.slice(0, 80)
    // Hyprland window group this assignment belongs to. Members of one group
    // share a token and occupy a single tile; order inside the group is the
    // order of the assignments themselves. groupActive marks the tab that was
    // on top when the workspace was captured. Mirrors scripts/schema.
    var group = String(a.group || "").trim()
    if (group) {
        out.group = group.slice(0, 40)
        if (a.groupActive === true) out.groupActive = true
    }
    var geom = a.place === "float" ? normalizeFloatGeom(a.geom) : normalizeGeom(a.geom)
    if (geom) out.geom = geom
    var chrome = normalizeChrome(a.chrome)
    if (!chromeIsDefault(chrome)) out.chrome = chrome
    return out
}

function assignmentIsLocked(a, profile) {
    if (!a) return false
    if (a.lockPlace === true) return true
    var pref = workspacePref(profile, a.workspace)
    return pref.lockSizes === true
}

function workspaceHasLockedApp(profile, ws) {
    var pref = workspacePref(profile, ws)
    if (pref.lockSizes === true) return true
    var list = (profile && profile.assignments) || []
    for (var i = 0; i < list.length; i++) {
        if (Number(list[i].workspace) === Number(ws) && list[i].lockPlace === true) return true
    }
    return false
}

function ensureAssignmentGeoms(assignments, ws, pref) {
    var list = assignments || []
    var idxs = []
    var group = []
    for (var i = 0; i < list.length; i++) {
        if (Number(list[i].workspace) === Number(ws)) {
            idxs.push(i)
            group.push(list[i])
        }
    }
    if (!group.length) return list
    // Group members share their tile's geom, so pack tiles and then hand the
    // same box to every window in that tile.
    var collapsed = collapseGroupTiles(group)
    var packed = packedGeomsForApps(collapsed.tiles, (pref && pref.layout) || "dwindle", 1 / Math.max(1, (pref && pref.visibleCount) || 2))
    for (var g = 0; g < group.length; g++) {
        if (assignmentHasGeom(group[g])) continue
        var pg = packed[collapsed.owner[g]]
        if (!pg) continue
        list[idxs[g]].geom = { x: pg.x, y: pg.y, w: pg.w, h: pg.h }
    }
    return list
}

function normalizeExtraApp(a) {
    if (!a || typeof a !== "object") return null
    var exec = String(a.exec || a.command || "").trim()
    if (!exec) return null
    return {
        name: String(a.name || displayNameForExec(exec, "App")).slice(0, 80),
        exec: exec.slice(0, 500),
        command: String(a.command || exec).slice(0, 500),
        icon: String(a.icon || "").slice(0, 80),
        type: a.type === "webapp" || a.type === "custom" ? a.type : "custom"
    }
}

function normalizeWorkspaceMonitors(raw, knownIds) {
    var out = {}
    if (!raw || typeof raw !== "object") return out
    var keys = Object.keys(raw)
    for (var i = 0; i < keys.length; i++) {
        var ws = parseInt(keys[i], 10)
        if (!(ws >= 1 && ws <= 10)) continue
        var mid = String(raw[keys[i]] || "").trim()
        if (!mid) continue
        if (knownIds && knownIds.length && knownIds.indexOf(mid) < 0) continue
        out[String(ws)] = mid.slice(0, 40)
    }
    return out
}

function normalizeProfile(p, monitorIds) {
    if (!p || typeof p !== "object") return defaultProfile()
    var matchMode = p.matchMode === "all-present" ? "all-present" : "exact"
    var mons = []
    var seen = {}
    var rawMons = Array.isArray(p.monitors) ? p.monitors : []
    for (var i = 0; i < rawMons.length; i++) {
        var id = String(rawMons[i] || "").trim()
        if (!id || seen[id]) continue
        if (monitorIds && monitorIds.length && monitorIds.indexOf(id) < 0) continue
        seen[id] = true
        mons.push(id.slice(0, 40))
        if (mons.length >= 8) break
    }
    var assignments = []
    if (Array.isArray(p.assignments)) {
        assignments = p.assignments.slice(0, 50).map(function(raw) {
            return normalizeAssignment(clone(raw))
        })
    }
    return {
        id: String(p.id || makeId("pr")).slice(0, 40),
        name: String(p.name || "Profile").slice(0, 48),
        matchMode: matchMode,
        monitors: mons,
        workspaceMonitors: normalizeWorkspaceMonitors(p.workspaceMonitors, monitorIds),
        disabledMonitors: (function() {
            var off = []
            var raw = Array.isArray(p.disabledMonitors) ? p.disabledMonitors : []
            var oseen = {}
            for (var d = 0; d < raw.length; d++) {
                var did = String(raw[d] || "").trim()
                if (!did || oseen[did] || mons.indexOf(did) < 0) continue
                oseen[did] = true
                off.push(did)
            }
            if (mons.length < 2) return []
            if (off.length >= mons.length) off = off.slice(0, mons.length - 1)
            return off
        })(),
        monitorLayout: normalizeMonitorLayout(p.monitorLayout),
        workspacePrefs: migrateWorkspacePrefs(normalizeWorkspacePrefs(p.workspacePrefs), assignments),
        assignments: assignments,
        gestures: normalizeGestures(p.gestures),
        workspaceNames: normalizeWorkspaceNames(p.workspaceNames),
        defaultWorkspace: (function() {
            var n = parseInt(p.defaultWorkspace, 10)
            if (!(n >= 0 && n <= 10)) n = 0
            return n
        })(),
        persistentWorkspaces: p.persistentWorkspaces === true,
        overflow: normalizeOverflow(p.overflow),
        network: normalizeNetwork(p.network),
        claimedAt: (function() {
            var n = parseInt(p.claimedAt, 10)
            return n > 0 ? n : 0
        })()
    }
}

function migrateV1(cfg) {
    var out = defaultConfig()
    if (cfg.settings && typeof cfg.settings === "object") {
        out.settings.enabled = cfg.settings.enabled !== false
        out.settings.applyOnBoot = cfg.settings.applyOnBoot === true
        out.settings.launchDelayMs = Math.max(0, Math.min(10000, parseInt(cfg.settings.launchDelayMs) || 800))
        out.settings.staggerMs = Math.max(0, Math.min(2000, parseInt(cfg.settings.staggerMs) || 80))
        out.settings.silent = cfg.settings.silent !== false
        out.settings.onlyOnBoot = cfg.settings.onlyOnBoot !== false
        out.settings.lastFormWorkspace = Math.max(1, Math.min(10, parseInt(cfg.settings.lastFormWorkspace) || 1))
        out.settings.lastMainView = allowedMainView(cfg.settings.lastMainView)
    }
    var prof = defaultProfile()
    if (Array.isArray(cfg.assignments)) {
        prof.assignments = cfg.assignments.slice(0, 50).map(function(raw) {
            return normalizeAssignment(clone(raw))
        })
    }
    out.profiles = [prof]
    out.settings.activeProfileId = prof.id
    return out
}

function sanitizeConfig(cfg) {
    if (!cfg || typeof cfg !== "object") return defaultConfig()
    if (!Array.isArray(cfg.profiles) && Array.isArray(cfg.assignments)) return migrateV1(cfg)
    var out = clone(defaultConfig())
    if (cfg.settings && typeof cfg.settings === "object") {
        out.settings.enabled = cfg.settings.enabled !== false
        out.settings.applyOnBoot = cfg.settings.applyOnBoot === true
        out.settings.launchDelayMs = Math.max(0, Math.min(10000, parseInt(cfg.settings.launchDelayMs) || 800))
        out.settings.staggerMs = Math.max(0, Math.min(2000, parseInt(cfg.settings.staggerMs) || 80))
        out.settings.silent = cfg.settings.silent !== false
        out.settings.onlyOnBoot = cfg.settings.onlyOnBoot !== false
        out.settings.lastFormWorkspace = Math.max(1, Math.min(10, parseInt(cfg.settings.lastFormWorkspace) || 1))
        out.settings.lastMainView = allowedMainView(cfg.settings.lastMainView)
        out.settings.activeProfileId = String(cfg.settings.activeProfileId || "default").slice(0, 40)
        out.settings.gestureSource = cfg.settings.gestureSource === "profile" ? "profile" : "global"
        out.settings.persistHyprGestures = cfg.settings.persistHyprGestures === true
        out.settings.gestures = normalizeGestures(cfg.settings.gestures)
    }
    var monitors = []
    var ids = []
    var seen = {}
    if (Array.isArray(cfg.monitors)) {
        for (var i = 0; i < cfg.monitors.length && monitors.length < 16; i++) {
            var mon = normalizeMonitor(cfg.monitors[i])
            if (!mon || seen[mon.id]) continue
            seen[mon.id] = true
            monitors.push(mon)
            ids.push(mon.id)
        }
    }
    out.monitors = monitors
    var extras = []
    if (Array.isArray(cfg.extraApps)) {
        for (var e = 0; e < cfg.extraApps.length && extras.length < 20; e++) {
            var extra = normalizeExtraApp(cfg.extraApps[e])
            if (extra) extras.push(extra)
        }
    }
    out.extraApps = extras
    var profiles = []
    var pseen = {}
    if (Array.isArray(cfg.profiles)) {
        for (var p = 0; p < cfg.profiles.length && profiles.length < 12; p++) {
            var prof = normalizeProfile(clone(cfg.profiles[p]), ids)
            if (pseen[prof.id]) continue
            pseen[prof.id] = true
            profiles.push(prof)
        }
    }
    if (profiles.length === 0) profiles = [defaultProfile()]
    out.profiles = profiles
    var active = out.settings.activeProfileId
    if (!profileById(out, active)) out.settings.activeProfileId = profiles[0].id
    out.version = 2
    return out
}

function profileById(cfg, id) {
    var list = (cfg && cfg.profiles) || []
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
}

function monitorById(cfg, id) {
    var list = (cfg && cfg.monitors) || []
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
}

function liveIsReal(m) {
    if (!m) return false
    var name = String(m.name || "")
    if (name.indexOf("HEADLESS") >= 0) return false
    return true
}

function sameMonitor(saved, live) {
    if (!saved || !live) return false
    var ss = String(saved.serial || "").trim()
    var ls = String(live.serial || "").trim()
    if (ss && ls && ss === ls) return true
    var sd = String(saved.description || "").trim()
    var ld = String(live.description || "").trim()
    if (sd && ld && sd === ld) return true
    if (!ss && !sd) {
        var sn = String(saved.name || "").trim()
        var ln = String(live.name || "").trim()
        return !!(sn && sn === ln)
    }
    return false
}

function findLive(saved, liveList) {
    for (var i = 0; i < liveList.length; i++) {
        if (liveIsReal(liveList[i]) && sameMonitor(saved, liveList[i])) return liveList[i]
    }
    return null
}

function profileMatch(cfg, profile, liveList, liveNet) {
    var live = (liveList || []).filter(liveIsReal)
    var required = profile && profile.monitors ? profile.monitors : []
    var missing = []
    var matched = []
    var used = {}
    for (var i = 0; i < required.length; i++) {
        var saved = monitorById(cfg, required[i])
        if (!saved) { missing.push(required[i]); continue }
        var hit = findLive(saved, live)
        if (!hit) missing.push(required[i])
        else {
            matched.push(required[i])
            used[String(hit.name || hit.description)] = true
        }
    }
    var extra = []
    for (var j = 0; j < live.length; j++) {
        var key = String(live[j].name || live[j].description)
        var claimed = false
        for (var k = 0; k < required.length; k++) {
            var s = monitorById(cfg, required[k])
            if (s && sameMonitor(s, live[j])) { claimed = true; break }
        }
        if (!claimed) extra.push(shortMonitorLabel(live[j]))
    }
    var allPresent = missing.length === 0 && required.length > 0
    var exact = allPresent && extra.length === 0
    var mode = profile && profile.matchMode === "all-present" ? "all-present" : "exact"
    var matches = mode === "all-present" ? allPresent : exact
    if (required.length === 0) {
        matches = live.length <= 1
        exact = matches
        allPresent = matches
    }
    var reason = matches ? (exact ? "exact" : "all-present") : (missing.length ? "missing" : "extra")
    var net = networkMatches(profile && profile.network, liveNet)
    if (matches && net.constrained && !net.matches) {
        matches = false
        reason = "network"
    }
    return {
        matches: matches,
        exact: exact,
        allPresent: allPresent,
        missing: missing,
        extra: extra,
        matchedCount: matched.length,
        requiredCount: required.length,
        reason: reason,
        networkConstrained: net.constrained,
        networkMatches: net.matches
    }
}

function nextFollowedMatch(matchedId, lastFollowed) {
    var id = String(matchedId || "")
    if (!id) return ""
    if (id === String(lastFollowed || "")) return ""
    return id
}

function bestProfile(cfg, liveList, liveNet) {
    var list = (cfg && cfg.profiles) || []
    var scored = []
    for (var i = 0; i < list.length; i++) {
        var info = profileMatch(cfg, list[i], liveList, liveNet)
        if (!info.matches) continue
        scored.push({
            profile: list[i],
            info: info,
            netBoost: info.networkConstrained && info.networkMatches ? 2 : 1,
            exactBoost: info.exact ? 2 : 1,
            claimed: Number(list[i].claimedAt) || 0
        })
    }
    if (!scored.length) return null
    scored.sort(function(a, b) {
        if (b.netBoost !== a.netBoost) return b.netBoost - a.netBoost
        if (b.exactBoost !== a.exactBoost) return b.exactBoost - a.exactBoost
        if (b.info.requiredCount !== a.info.requiredCount) return b.info.requiredCount - a.info.requiredCount
        if (b.claimed !== a.claimed) return b.claimed - a.claimed
        return 0
    })
    return scored[0].profile
}

function monitorOptions(cfg, profile, liveList) {
    var opts = []
    var seen = {}
    function add(id, label) {
        if (!id || seen[id]) return
        seen[id] = true
        opts.push({ value: id, label: label })
    }
    var prefer = (profile && profile.monitors) || []
    var off = {}
    var dis = (profile && profile.disabledMonitors) || []
    for (var d = 0; d < dis.length; d++) off[String(dis[d])] = true
    for (var i = 0; i < prefer.length; i++) {
        if (off[prefer[i]]) continue
        var m = monitorById(cfg, prefer[i])
        if (m) add(m.id, m.label)
    }
    if (prefer.length === 0) {
        var live = liveList || []
        for (var k = 0; k < live.length; k++) {
            if (!liveIsReal(live[k])) continue
            var tmp = normalizeMonitor(live[k])
            if (tmp) add(tmp.id, tmp.label)
        }
    }
    if (opts.length > 1) opts.unshift({ value: "", label: "Any monitor" })
    return opts
}

function copyWorkspace(cfg, fromId, fromWs, toId, toWs) {
    if (!cfg) return cfg
    var srcWs = parseInt(fromWs, 10)
    var dstWs = parseInt(toWs == null || toWs === "" ? fromWs : toWs, 10)
    if (!(srcWs >= 1 && srcWs <= 10) || !(dstWs >= 1 && dstWs <= 10)) return cfg
    if (fromId === toId && srcWs === dstWs) return cfg
    var out = clone(cfg)
    var from = profileById(out, fromId)
    var to = profileById(out, toId)
    if (!from || !to) return cfg
    var kept = []
    var list = to.assignments || []
    for (var i = 0; i < list.length; i++) if (list[i].workspace !== dstWs) kept.push(list[i])
    var copies = []
    var src = from.assignments || []
    for (var j = 0; j < src.length; j++) {
        if (src[j].workspace !== srcWs) continue
        var item = clone(src[j])
        item.id = makeId()
        item.workspace = dstWs
        copies.push(normalizeAssignment(item))
    }
    to.assignments = kept.concat(copies)
    if (!to.workspacePrefs) to.workspacePrefs = {}
    if ((from.workspacePrefs || {})[String(srcWs)])
        to.workspacePrefs[String(dstWs)] = clone(normalizeWorkspacePref(from.workspacePrefs[String(srcWs)]))
    if (!to.workspaceMonitors) to.workspaceMonitors = {}
    var pin = (from.workspaceMonitors || {})[String(srcWs)]
    if (pin && (to.monitors || []).indexOf(pin) >= 0) to.workspaceMonitors[String(dstWs)] = pin
    else if ((to.monitors || []).length === 1) to.workspaceMonitors[String(dstWs)] = to.monitors[0]
    else delete to.workspaceMonitors[String(dstWs)]
    return out
}

function moveWorkspace(cfg, profileId, fromWs, toWs) {
    var srcWs = parseInt(fromWs, 10)
    var dstWs = parseInt(toWs, 10)
    if (!cfg || srcWs === dstWs) return cfg
    if (!(srcWs >= 1 && srcWs <= 10) || !(dstWs >= 1 && dstWs <= 10)) return cfg
    var out = clone(cfg)
    var prof = profileById(out, profileId)
    if (!prof) return cfg
    var next = []
    var list = prof.assignments || []
    for (var i = 0; i < list.length; i++) {
        var item = clone(list[i])
        if (item.workspace === srcWs) item.workspace = dstWs
        else if (item.workspace === dstWs) item.workspace = srcWs
        next.push(normalizeAssignment(item))
    }
    prof.assignments = next
    var prefs = prof.workspacePrefs || {}
    var prefFrom = prefs[String(srcWs)]
    var prefTo = prefs[String(dstWs)]
    if (prefFrom) prefs[String(dstWs)] = prefFrom
    else delete prefs[String(dstWs)]
    if (prefTo) prefs[String(srcWs)] = prefTo
    else delete prefs[String(srcWs)]
    prof.workspacePrefs = prefs
    var pins = prof.workspaceMonitors || {}
    var pFrom = pins[String(srcWs)]
    var pTo = pins[String(dstWs)]
    if (pFrom) pins[String(dstWs)] = pFrom
    else delete pins[String(dstWs)]
    if (pTo) pins[String(srcWs)] = pTo
    else delete pins[String(srcWs)]
    prof.workspaceMonitors = pins
    return out
}

function upsertLiveMonitor(cfg, live) {
    var mon = normalizeMonitor(live)
    if (!mon) return { config: cfg, id: "" }
    var out = clone(cfg)
    for (var i = 0; i < out.monitors.length; i++) {
        if (out.monitors[i].id === mon.id || sameMonitor(out.monitors[i], mon)) {
            var cur = clone(out.monitors[i])
            if (mon.name && !cur.name) cur.name = mon.name
            if (mon.description && !cur.description) cur.description = mon.description
            if (mon.serial && !cur.serial) cur.serial = mon.serial
            out.monitors[i] = cur
            return { config: out, id: cur.id }
        }
    }
    out.monitors = out.monitors.concat([mon])
    return { config: out, id: mon.id }
}

function extractWebappUrl(s) {
    var m = String(s || "").match(/https:\/\/[^\s\"']+/g)
    if (!m || !m.length) return ""
    var i
    for (i = 0; i < m.length; i++) if (m[i].indexOf("deeplink") < 0) return m[i]
    return m[m.length - 1]
}

function extractChromiumAppKey(s) {
    var t = String(s || "")
    var id = t.match(/--app-id=([A-Za-z0-9_-]+)/)
    if (id) return "id:" + id[1]
    var app = t.match(/--app=(\S+)/)
    if (app) return "app:" + app[1]
    return ""
}

function canonicalExec(s) {
    var t = String(s || "").trim()
    if (!t) return ""
    var url = extractWebappUrl(t)
    if (t.indexOf("omarchy-launch-webapp") >= 0 && url) return "omarchy-launch-webapp '" + url + "'"
    return t
}

function execBasename(s) {
    var t = canonicalExec(s)
    var first = t.split(/\s+/)[0] || ""
    return first.split("/").pop().toLowerCase()
}

function isGenericLauncher(base) {
    var b = String(base || "").toLowerCase()
    return b === "sh" || b === "bash" || b === "env" || b === "uwsm-app"
        || b === "omarchy-launch-webapp" || b === "omarchy-launch-tui"
        || b === "omarchy-launch-or-focus-tui"
}

function sameAppExec(a, b) {
    var ca = canonicalExec(a), cb = canonicalExec(b)
    if (ca && cb && ca === cb) return true
    var ua = extractWebappUrl(a), ub = extractWebappUrl(b)
    if (ua && ub) return ua === ub
    var ka = extractChromiumAppKey(a), kb = extractChromiumAppKey(b)
    if (ka || kb) return !!(ka && kb && ka === kb)
    if (ua || ub) return false
    var ba = execBasename(a), bb = execBasename(b)
    if (!ba || !bb) return false
    if (isGenericLauncher(ba) || isGenericLauncher(bb)) return false
    return ba === bb
}

function execForAssignment(a) {
    if (a.exec && String(a.exec).trim().length) return String(a.exec).trim()
    if (a.command && String(a.command).trim().length) {
        var cmd = String(a.command).trim()
        if (a.type === "webapp") {
            if (cmd.indexOf("http://") === 0 || cmd.indexOf("https://") === 0) {
                return "omarchy-launch-webapp '" + cmd.replace(/'/g, "'\\''") + "'"
            }
            return cmd
        }
        return cmd
    }
    return ""
}

function displayNameForExec(execStr, fallback) {
    var s = String(execStr || "").trim()
    if (!s) return fallback || "App"
    var m = s.match(/omarchy-launch-webapp\s+'([^']+)'/)
    if (m) {
        try {
            var u = new URL(m[1])
            return u.hostname.replace(/^www\./, "") + u.pathname.split("/").slice(0, 2).join("/")
        } catch (e) { return m[1].slice(0, 40) }
    }
    if (/herdr/.test(s) && /shophawk/.test(s)) return "ShopHawk Herdr"
    if (/(^|[\/\s])herdr(\s|$)/.test(s)) return "Herdr"
    var first = s.split(/\s+/)[0]
    var base = first.split("/").pop()
    return base || fallback || "App"
}
