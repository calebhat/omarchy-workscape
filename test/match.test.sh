#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MATCH="$ROOT/scripts/match"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/config.json" <<'JSON'
{
  "monitors": [
    { "id": "laptop", "label": "Laptop", "serial": "", "description": "BOE NE135A1M-NY1", "name": "eDP-1" },
    { "id": "desk-left", "label": "Desk left", "serial": "", "description": "HP Inc. HP E24 G5 SN-LEFT", "name": "DVI-I-1" },
    { "id": "desk-right", "label": "Desk right", "serial": "", "description": "HP Inc. HP E24 G5 SN-RIGHT", "name": "DVI-I-2" }
  ],
  "profiles": [
    {
      "id": "desk-dock",
      "name": "Desk dock",
      "matchMode": "exact",
      "monitors": ["laptop", "desk-left", "desk-right"],
      "workspaceMonitors": { "1": "desk-left", "2": "desk-right", "9": "laptop" }
    },
    {
      "id": "laptop",
      "name": "Laptop",
      "matchMode": "exact",
      "monitors": ["laptop"],
      "workspaceMonitors": {}
    }
  ]
}
JSON

cat >"$TMP/live-laptop.json" <<'JSON'
[{ "name": "eDP-1", "description": "BOE NE135A1M-NY1", "serial": "", "disabled": false }]
JSON

# Connector names flipped vs the saved name field — must still match descriptions.
cat >"$TMP/live-desk.json" <<'JSON'
[
  { "name": "eDP-1", "description": "BOE NE135A1M-NY1", "serial": "", "disabled": false },
  { "name": "DVI-I-1", "description": "HP Inc. HP E24 G5 SN-RIGHT", "serial": "", "disabled": false },
  { "name": "DVI-I-2", "description": "HP Inc. HP E24 G5 SN-LEFT", "serial": "", "disabled": false }
]
JSON

laptop_id=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-laptop.json" --print-id)
desk_id=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-desk.json" --print-id)
[[ $laptop_id == "laptop" ]]
[[ $desk_id == "desk-dock" ]]
desk_bind=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-desk.json" --profile-id desk-dock --bindings)
echo "$desk_bind" | jq -e '.["1"] and .["2"] and .["9"]' >/dev/null
laptop_bind=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-laptop.json" --profile-id laptop --bindings)
echo "$laptop_bind" | jq -e 'type=="object"' >/dev/null
echo "dock bindings ok"

set +e
mismatch_json=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-laptop.json" --profile-id desk-dock --require-match)
mismatch_rc=$?
set -e
[[ $mismatch_rc -eq 3 ]]
echo "$mismatch_json" | jq -e '.matches==false and .reason=="missing"' >/dev/null
echo "$mismatch_json" | jq -r '.detail' | grep -q "aren't connected"
python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-laptop.json" --profile-id laptop --require-match >/dev/null
set +e
docked_laptop=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-desk.json" --profile-id laptop --require-match)
docked_rc=$?
set -e
[[ $docked_rc -eq 3 ]]
echo "$docked_laptop" | jq -e '.matches==false and .reason=="extra"' >/dev/null
echo "mismatch apply refused ok"

bindings=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-desk.json" --profile-id desk-dock --bindings)
left=$(printf '%s' "$bindings" | jq -r '.["1"]')
right=$(printf '%s' "$bindings" | jq -r '.["2"]')
lap=$(printf '%s' "$bindings" | jq -r '.["9"]')
[[ $left == "DVI-I-2" ]]
[[ $right == "DVI-I-1" ]]
[[ $lap == "eDP-1" ]]

cat >"$TMP/live-desk-lid.json" <<'JSON'
[
  { "name": "eDP-1", "description": "BOE NE135A1M-NY1", "serial": "", "disabled": true },
  { "name": "DVI-I-1", "description": "HP Inc. HP E24 G5 SN-RIGHT", "serial": "", "disabled": false },
  { "name": "DVI-I-2", "description": "HP Inc. HP E24 G5 SN-LEFT", "serial": "", "disabled": false }
]
JSON
lid_id=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-desk-lid.json" --print-id)
[[ $lid_id == "desk-dock" ]]

cat >"$TMP/net-config.json" <<'JSON'
{
  "monitors": [
    { "id": "laptop", "label": "Laptop", "serial": "", "description": "BOE NE135A1M-NY1", "name": "eDP-1" }
  ],
  "profiles": [
    { "id": "home", "name": "Home", "matchMode": "exact", "monitors": ["laptop"], "network": { "ssids": ["HomeNet"], "subnets": ["192.168.1.0/24"], "connections": [] }, "claimedAt": 1 },
    { "id": "office", "name": "Office", "matchMode": "exact", "monitors": ["laptop"], "network": { "ssids": ["Office"], "subnets": ["192.168.2.0/24"], "connections": [] }, "claimedAt": 2 },
    { "id": "any", "name": "Any", "matchMode": "exact", "monitors": ["laptop"], "network": { "ssids": [], "subnets": [], "connections": [] }, "claimedAt": 0 }
  ]
}
JSON
cat >"$TMP/net-home.json" <<'JSON'
{ "ssid": "HomeNet", "subnet": "192.168.1.0/24", "connection": "HomeNet" }
JSON
cat >"$TMP/net-cafe.json" <<'JSON'
{ "ssid": "Cafe", "subnet": "10.1.1.0/24", "connection": "" }
JSON
home_id=$(python3 "$MATCH" --config "$TMP/net-config.json" --live-json "$TMP/live-laptop.json" --network-json "$TMP/net-home.json" --print-id)
cafe_id=$(python3 "$MATCH" --config "$TMP/net-config.json" --live-json "$TMP/live-laptop.json" --network-json "$TMP/net-cafe.json" --print-id)
[[ $home_id == "home" ]]
[[ $cafe_id == "any" ]]
needs=$(python3 "$MATCH" --config "$TMP/net-config.json" --live-json "$TMP/live-laptop.json" --needs-identity)
# net-config has unconstrained "any" for laptop, so no wait required
[[ $needs == "no" ]]
cat >"$TMP/net-only.json" <<'JSON'
{
  "monitors": [
    { "id": "laptop", "label": "Laptop", "serial": "", "description": "BOE NE135A1M-NY1", "name": "eDP-1" }
  ],
  "profiles": [
    { "id": "home", "name": "Home", "matchMode": "exact", "monitors": ["laptop"], "network": { "ssids": ["HomeNet"], "subnets": [], "connections": [] } }
  ]
}
JSON
needs_only=$(python3 "$MATCH" --config "$TMP/net-only.json" --live-json "$TMP/live-laptop.json" --needs-identity)
[[ $needs_only == "yes" ]]
lid_bind=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-desk-lid.json" --profile-id desk-dock --bindings)
[[ $(printf '%s' "$lid_bind" | jq -r '.["9"]') == "null" ]]

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
assert m.disable_plan(["eDP-1"], ["eDP-1"]) == []
assert m.disable_plan(["eDP-1", "DVI-I-1"], ["eDP-1"]) == ["eDP-1"]
assert m.disable_plan(["eDP-1", "DVI-I-1"], ["eDP-1", "DVI-I-1"]) == ["eDP-1"]
assert m.safe_connector("eDP-1") == "eDP-1"
assert m.safe_connector("eDP-1; rm -rf /") is None
s = m.SAFE
assert s.safe_ws("3") == "3"
assert s.safe_ws("20") == "20"
assert s.safe_ws("21") is None
assert s.safe_ws('1"}); os.execute("id")') is None
assert s.safe_addr("0xabc") == "0xabc"
assert s.safe_addr("5602fd5c9090") == "0x5602fd5c9090"
assert s.safe_addr('0x1"}); os.execute("id")') is None
assert abs(s.clamp_scale("2") - 2.0) < 1e-9
assert s.clamp_scale("1}); x") == 1.0
print("disable_plan ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
calls = []
m.safe_connector = lambda n: n or ""
m.workspace_bindings = lambda cfg, profile, live: {"2": "DVI-I-1"}
m.SAFE.bounded_run = lambda cmd, timeout=3.0: calls.append(cmd) or 0
profile = {
    "workspacePrefs": {"2": {"layout": "dwindle", "visibleCount": 2, "lockSizes": False, "extras": "block"}},
    "assignments": [{"workspace": 2, "exec": "herdr", "lockPlace": True}],
    "workspaceMonitors": {"2": "desk-right"},
}
m.apply_ws_prefs({"monitors": []}, profile, [])
lua = " ".join(str(c) for c in calls)
assert "layout = \"dwindle\"" in lua, lua
assert "lua:workscape" not in lua, lua
print("dwindle extras=block keeps dwindle ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
profile = {
    "assignments": [{"workspace": 1, "exec": "brave"}, {"workspace": 2, "exec": "herdr"}],
    "workspacePrefs": {"1": {"layout": "stage"}, "5": {"layout": "stage"}, "8": {"layout": "scrolling"}},
    "overflow": {"enabled": False, "workspaces": [5, 6, 7], "maxWindows": 2},
}
assert m.assigned_workspaces(profile) == {"1", "2"}
assert m.overflow_active_workspaces(profile) == set()
profile["overflow"]["enabled"] = True
assert m.overflow_active_workspaces(profile) == {"5", "6", "7"}
calls = []
m.SAFE.bounded_run = lambda cmd, timeout=3.0: calls.append(cmd) or 0
m.SAFE.lua_str = lambda s: s
out = m.reset_empty_workspaces({"profiles": [profile]}, profile)
assert "5" in out["overflowKept"]
assert "8" in out["cleared"]
assert "1" not in out["cleared"]
assert "5" not in (profile.get("workspacePrefs") or {}) or profile["workspacePrefs"]["5"]["layout"] == "scrolling"
assert "8" not in profile.get("workspacePrefs", {})
print("reset empty keeps overflow, clears leftovers ok")
PY

python3 - <<'PY'
import json, subprocess, tempfile, os
from pathlib import Path
cfg = {
  "profiles": [{
    "id": "p",
    "assignments": [{"workspace": 2, "exec": "herdr"}],
    "workspacePrefs": {"2": {"layout": "scrolling"}, "5": {"layout": "stage"}, "8": {"layout": "scrolling"}},
    "workspaceMonitors": {"2": "laptop", "9": "laptop"}
  }]
}
# jq used by close_preset_workspaces
raw = json.dumps(cfg)
import subprocess as sp
out = sp.check_output(["jq", "-r", '--arg', "id", "p", '[.profiles[]? | select(.id==$id) | .assignments[]? | .workspace | tostring] | unique | .[]'], input=raw, text=True)
got = set(out.split())
assert got == {"2"}, got
print("fresh close only assigned workspaces ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
calls = []
m.safe_connector = lambda n: n or ""
m.workspace_bindings = lambda cfg, profile, live: {"1": "DVI-I-2"}
m.SAFE.bounded_run = lambda cmd, timeout=3.0: calls.append(cmd) or 0
profile = {
    "workspacePrefs": {"1": {"layout": "master", "visibleCount": 2, "lockSizes": False, "extras": "around"}},
    "assignments": [{"workspace": 1, "exec": "brave", "lockPlace": False}],
    "workspaceMonitors": {"1": "desk-left"},
}
m.apply_ws_prefs({"monitors": []}, profile, [])
lua = " ".join(str(c) for c in calls)
assert "layout = \"master\"" in lua, lua
assert "orientation = \"left\"" in lua, lua
assert "column_width" not in lua, lua
print("master layout rule ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
calls = []
m.safe_connector = lambda n: n or ""
m.workspace_bindings = lambda cfg, profile, live: {"5": "DVI-I-2"}
m.SAFE.bounded_run = lambda cmd, timeout=3.0: calls.append(cmd) or 0
profile = {
    "workspacePrefs": {"5": {"layout": "scrolling", "visibleCount": 3, "lockSizes": False, "extras": "around"}},
    "assignments": [{"workspace": 5, "exec": "foot", "lockPlace": False}],
    "workspaceMonitors": {"5": "desk-left"},
}
out = m.apply_ws_prefs({"monitors": []}, profile, [])
lua = " ".join(str(c) for c in calls)
assert out["workspaces"][0]["layout"] == "scrolling", out
assert "layout = \"scrolling\"" in lua, lua
assert "column_width = 0.3333" in lua, lua
assert "follow_focus = false" not in lua, lua
assert "orientation" not in lua, lua
print("scrolling layout rule ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
calls = []
m.safe_connector = lambda n: n or ""
m.workspace_bindings = lambda cfg, profile, live: {}
m.SAFE.bounded_run = lambda cmd, timeout=3.0: calls.append(cmd) or 0
profile = {
    "workspacePrefs": {"3": {"layout": "scrolling", "visibleCount": 2, "lockSizes": False, "extras": "around"}},
    "assignments": [{"workspace": 3, "exec": "grok-bot", "lockPlace": True}],
}
m.apply_ws_prefs({"monitors": []}, profile, [])
lua = " ".join(str(c) for c in calls)
assert "layout = \"scrolling\"" in lua, lua
assert "lua:workscape" not in lua, lua
print("single assignment scrolling ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
calls = []
m.safe_connector = lambda n: n or ""
m.workspace_bindings = lambda cfg, profile, live: {}
m.SAFE.bounded_run = lambda cmd, timeout=3.0: calls.append(cmd) or 0
profile = {
    "workspacePrefs": {"2": {"layout": "scrolling", "visibleCount": 2, "lockSizes": False, "extras": "around"}},
    "assignments": [
        {"workspace": 2, "exec": "herdr", "lockPlace": True},
        {"workspace": 2, "exec": "shophawk-panel", "lockPlace": True},
    ],
}
m.apply_ws_prefs({"monitors": []}, profile, [])
lua = " ".join(str(c) for c in calls)
assert "layout = \"dwindle\"" in lua, lua
assert "lua:workscape" not in lua, lua
print("multi locked split uses dwindle + block ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
calls = []
m.safe_connector = lambda n: n or ""
m.workspace_bindings = lambda cfg, profile, live: {}
m.SAFE.bounded_run = lambda cmd, timeout=3.0: calls.append(cmd) or 0
profile = {
    "workspacePrefs": {"1": {"layout": "scrolling", "visibleCount": 4, "lockSizes": False, "extras": "around"}},
    "assignments": [{"workspace": 1, "exec": "foot", "lockPlace": False}],
}
m.apply_ws_prefs({"monitors": []}, profile, [])
lua = " ".join(str(c) for c in calls)
assert "layout = \"scrolling\"" in lua, lua
assert "column_width = 0.25" in lua, lua
assert "scrolling_width = 0.25" in lua, lua
print("scrolling spawn rule ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
placed = [
    ({"name": "eDP-1"}, 893, 781),
    ({"name": "DVI-I-1"}, 2333, 722),
    ({"name": "DVI-I-2"}, 4253, 722),
]
got = m.origin_shift_layout(placed)
assert got[0][1:] == (0, 59), got
assert got[1][1:] == (1440, 0), got
assert got[2][1:] == (3360, 0), got
print("origin shift layout ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
a = {"name": "eDP-1", "width": 2880, "height": 1920, "scale": 2}
b = {"name": "DVI-I-1", "width": 1920, "height": 1080, "scale": 1}
c = {"name": "DVI-I-2", "width": 1920, "height": 1080, "scale": 1}
# Saved desk layout after origin-shift: laptop above, desks below — no overlap.
ok = m.pack_monitor_positions([(a, 1089, 0), (b, 0, 960), (c, 1920, 960)])
assert ok[0][1:] == (1089, 0) and ok[1][1:] == (0, 960) and ok[2][1:] == (1920, 960), ok
# Two screens stacked on 0,0 must pack left-to-right.
packed = m.pack_monitor_positions([(a, 0, 0), (b, 0, 0)])
assert packed[0][1] == 0 and packed[1][1] == 1440, packed
lua = []
m._hypr_eval = lambda s, timeout=8: lua.append(s)
m.place_monitors_batch([(a, 1089, 0), (b, 0, 960)])
assert len(lua) == 1 and lua[0].count("hl.monitor") == 2, lua
print("monitor pack and batch place ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import json, sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
placed_calls = []
saved = []
m.place_monitors_batch = lambda placed, scales=None: placed_calls.append((list(placed), dict(scales or {})))
m.save_config = lambda cfg, path: saved.append(path)
m.time.sleep = lambda s: None
live = [
    {"name": "eDP-1", "description": "BOE NE135A1M-NY1", "x": 1089, "y": 0,
     "width": 2880, "height": 1920, "scale": 2, "refreshRate": 120},
    {"name": "DVI-I-2", "description": "HP Inc. HP E24 G5 SN-LEFT", "x": 0, "y": 960,
     "width": 1920, "height": 1080, "scale": 1, "refreshRate": 60},
    {"name": "DVI-I-1", "description": "HP Inc. HP E24 G5 SN-RIGHT", "x": 1920, "y": 960,
     "width": 1920, "height": 1080, "scale": 1, "refreshRate": 60},
]
m.SAFE.hypr_json = lambda args, timeout=3.0: live
cfg = {
    "monitors": [
        {"id": "laptop", "description": "BOE NE135A1M-NY1", "name": "eDP-1"},
        {"id": "desk-left", "description": "HP Inc. HP E24 G5 SN-LEFT"},
        {"id": "desk-right", "description": "HP Inc. HP E24 G5 SN-RIGHT"},
    ],
    "profiles": [{
        "id": "desk-dock",
        "monitors": ["laptop", "desk-left", "desk-right"],
        "monitorLayout": {
            "laptop": {"x": 1089, "y": 0},
            "desk-left": {"x": 0, "y": 960},
            "desk-right": {"x": 1920, "y": 960},
        },
    }],
}
profile = cfg["profiles"][0]
out = m.apply_outputs(cfg, profile, live, config_path="/tmp/workscape-skip.json")
assert placed_calls == [], placed_calls
assert saved == [], saved
assert "pos:" not in str(out.get("changed")), out
live[0] = dict(live[0], x=0, y=0)
m.SAFE.hypr_json = lambda args, timeout=3.0: live
out = m.apply_outputs(cfg, profile, live, config_path="/tmp/workscape-skip.json")
assert len(placed_calls) == 1, placed_calls
assert any(item[0].get("name") == "eDP-1" and item[1:] == (1089, 0) for item in placed_calls[0][0]), placed_calls[0][0]
print("skip already-placed monitors ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
placed_calls = []
real_batch = m.place_monitors_batch
m.place_monitors_batch = lambda placed, want=None: placed_calls.append((list(placed), dict(want or {})))
m.save_config = lambda cfg, path: None
m.time.sleep = lambda s: None
live = [
    {"name": "DVI-I-2", "description": "HP Inc. HP E24 G5 SN-LEFT", "x": 0, "y": 0,
     "width": 1920, "height": 1080, "scale": 1, "refreshRate": 60},
    {"name": "eDP-1", "description": "BOE NE135A1M-NY1", "x": 1920, "y": 0,
     "width": 2880, "height": 1800, "scale": 2, "refreshRate": 120},
]
m.SAFE.hypr_json = lambda args, timeout=3.0: live
cfg = {
    "monitors": [
        {"id": "laptop", "description": "BOE NE135A1M-NY1", "name": "eDP-1"},
        {"id": "desk-left", "description": "HP Inc. HP E24 G5 SN-LEFT"},
    ],
    "profiles": [{
        "id": "desk-dock",
        "monitors": ["laptop", "desk-left"],
        "monitorLayout": {"laptop": {"x": 1920, "y": 0}, "desk-left": {"x": 0, "y": 0}},
        "monitorScales": {"laptop": 1.5, "desk-left": 1},
        "monitorModes": {"desk-left": {"width": 1920, "height": 1080, "refreshRate": 100}},
    }],
}
profile = cfg["profiles"][0]
# Positions already right, but the laptop panel should run 1.5 (not live 2)
# and the desk should run 100 Hz (not live 60).
out = m.apply_outputs(cfg, profile, live, config_path="/tmp/workscape-scale.json")
assert len(placed_calls) == 1, placed_calls
placed, want = placed_calls[0]
assert want == {"eDP-1": {"scale": 1.5}, "DVI-I-2": {"scale": 1.0, "width": 1920, "height": 1080, "refreshRate": 100.0}}, want
assert any(ch.startswith("scale:eDP-1@1.5") for ch in out["changed"]), out
assert any(ch.startswith("mode:DVI-I-2@1920x1080@100") for ch in out["changed"]), out
assert not any(ch.startswith("pos:") for ch in out["changed"]), out
# The real batch builder puts the overrides into the hl.monitor lua.
lua = []
m._hypr_eval = lambda s, timeout=8: lua.append(s)
real_batch(placed, want)
joined = "\n".join(lua)
assert 'mode = "2880x1800@120"' in joined and "scale = 1.5" in joined, joined
assert 'mode = "1920x1080@100"' in joined, joined
# Second pass with everything desired now live: nothing to do.
live[1] = dict(live[1], scale=1.5)
live[0] = dict(live[0], refreshRate=100)
placed_calls.clear(); lua.clear()
out = m.apply_outputs(cfg, profile, live, config_path="/tmp/workscape-scale.json")
assert placed_calls == [], placed_calls
assert out["changed"] == [], out
# No arranged canvas: overrides still re-asserted at the current spot.
del profile["monitorLayout"]
profile["monitors"] = ["laptop"]
live[1] = dict(live[1], scale=2)
placed_calls.clear(); lua.clear()
out = m.apply_outputs(cfg, profile, live, config_path="/tmp/workscape-scale.json")
assert len(placed_calls) == 1, placed_calls
placed, want = placed_calls[0]
assert want == {"eDP-1": {"scale": 1.5}}, want
assert placed[0][1:] == (1920, 0), placed
print("per-monitor scale and mode apply ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
lua = []
m._hypr_eval = lambda s, timeout=8: lua.append(s)
m._keyword_monitor = lambda spec: lua.append("kw " + spec)
a = {"name": "eDP-1", "width": 2880, "height": 1800, "scale": 2, "refreshRate": 120, "disabled": True}
m.enable_monitor(a, {"scale": 1.5})
assert lua and lua[-1] == "kw eDP-1,2880x1800@120,auto,1.5", lua
m.enable_monitor(a, {"width": 1920, "height": 1200, "refreshRate": 60, "scale": 1.25})
assert lua[-1] == "kw eDP-1,1920x1200@60,auto,1.25", lua
m.enable_monitor(a)
assert lua[-1] == "kw eDP-1,2880x1800@120,auto,2.0", lua
assert m.mode_scale_differs(a, {"refreshRate": 120.3}) is False
assert m.mode_scale_differs(a, {"refreshRate": 100}) is True
assert m.mode_scale_differs(a, {"width": 1920}) is True
assert m.mode_scale_differs(a, {"scale": 1.99}) is True
assert m.mode_scale_differs(a, {"scale": 2.0}) is False
print("enable and diff with overrides ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import os, sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
calls = []
m.safe_connector = lambda n: n or ""
m.workspace_bindings = lambda cfg, profile, live: {"2": "DVI-I-2"}
m.SAFE.bounded_run = lambda cmd, timeout=3.0: calls.append(cmd) or 0
profile = {
    "workspacePrefs": {"2": {"layout": "scrolling", "visibleCount": 2, "lockSizes": True, "extras": "around"}},
    "assignments": [
        {"workspace": 2, "exec": "herdr", "lockPlace": True},
        {"workspace": 2, "exec": "panel", "lockPlace": True},
    ],
}
os.environ["WORKSCAPE_OCCUPIED_WS"] = "2"
os.environ.pop("WORKSCAPE_MIGRATE_OCCUPIED", None)
m.apply_ws_prefs({"monitors": []}, profile, [])
lua = " ".join(str(c) for c in calls)
assert "layout = \"dwindle\"" in lua, lua
assert "lua:workscape" not in lua, lua
os.environ.pop("WORKSCAPE_OCCUPIED_WS", None)
print("occupied prefs still restamp layout ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
cfg = {
    "monitors": [
        {"id": "laptop", "label": "Laptop", "description": "BOE NE135A1M-NY1", "name": "eDP-1"},
    ],
    "profiles": [
        {"id": "desk-home", "name": "Desk home", "monitors": ["laptop"], "docks": ["usb:413c:b06f:DG7X753"]},
        {"id": "desk-roam", "name": "Desk roam", "monitors": ["laptop"]},
    ],
}
live = [{"name": "eDP-1", "description": "BOE NE135A1M-NY1"}]
m.DOCK.connected_ids = lambda root=None: {"usb:413c:b06f:DG7X753"}
best = m.best_profile(cfg, live, {})
assert best["id"] == "desk-home", best
info = m.profile_match(cfg, cfg["profiles"][0], live, {})
assert info["matches"] is True and info["dockConstrained"] is True and info["dockMatches"] is True, info
# Dock unplugged: the bound profile refuses, the fallback takes over.
m.DOCK.connected_ids = lambda root=None: set()
info = m.profile_match(cfg, cfg["profiles"][0], live, {})
assert info["matches"] is False and info["reason"] == "dock", info
assert "dock that isn't connected" in m.mismatch_detail(cfg, cfg["profiles"][0], info)
best = m.best_profile(cfg, live, {})
assert best["id"] == "desk-roam", best
status = m.live_status(cfg, live, {})
assert status["docks"] == [], status
assert status["profiles"][0]["reason"] == "dock", status["profiles"][0]
print("dock-bound profile matching ok")
PY

conn=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-laptop.json" --connector-for laptop)
[[ $conn == "eDP-1" ]] || { echo "connector-for laptop: $conn"; exit 1; }
ghost_rc=0
python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-laptop.json" --connector-for ghost >/dev/null 2>&1 || ghost_rc=$?
[[ $ghost_rc -eq 3 ]] || { echo "connector-for ghost should miss: $ghost_rc"; exit 1; }
echo "connector-for ok"
echo "match.test.sh ok"
