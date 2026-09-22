#!/usr/bin/env python3
"""Dummy matrix profile: every layout/extras option, never the user config."""
from __future__ import annotations

import json
import os
import time
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "test/fixtures/dummy-profile.json"
USER_CONFIG = Path.home() / ".local/state/omarchy/workscape/config.json"

geom = SourceFileLoader("dummy_geom", str(ROOT / "scripts/geom")).load_module()
watch = SourceFileLoader("dummy_watch", str(ROOT / "scripts/watch")).load_module()


def load_dummy() -> dict:
    return json.loads(FIXTURE.read_text())


def test_fixture_is_not_user_config():
    dummy = load_dummy()
    assert dummy["settings"]["activeProfileId"] == "dummy-matrix"
    assert dummy["settings"]["applyOnBoot"] is False
    assert dummy["_test"]["liveWorkspaceOffset"] == 10
    assert dummy["_test"]["appIdPrefix"] == "workscape-dummy"
    if USER_CONFIG.exists():
        user = json.loads(USER_CONFIG.read_text())
        assert user.get("settings", {}).get("activeProfileId") != "dummy-matrix"
        ids = {p.get("id") for p in (user.get("profiles") or [])}
        assert "dummy-matrix" not in ids


def test_config_path_honors_env(tmp_path=None):
    orig = os.environ.get("WORKSCAPE_CONFIG")
    os.environ["WORKSCAPE_CONFIG"] = str(FIXTURE)
    try:
        assert geom.config_path() == str(FIXTURE)
        assert watch.config_path() == FIXTURE
    finally:
        if orig is None:
            os.environ.pop("WORKSCAPE_CONFIG", None)
        else:
            os.environ["WORKSCAPE_CONFIG"] = orig


def test_dummy_lock_plans():
    profile = load_dummy()["profiles"][0]
    s1 = geom.lock_plan_for_workspace(profile, "1")
    assert s1["layout"] == "scrolling" and s1["extras"] == "around"
    s2 = geom.lock_plan_for_workspace(profile, "2")
    assert s2["layout"] == "dwindle"
    assert s2["extras"] == "block"
    assert len(s2["locked"]) == 2
    assert abs(float(s2["locked"][0]["geom"]["w"]) - 0.6456) < 0.0001
    assert abs(float(s2["locked"][1]["geom"]["w"]) - 0.3544) < 0.0001
    s3 = geom.lock_plan_for_workspace(profile, "3")
    assert s3["layout"] == "scrolling" and s3["setWidth"] is False
    s5 = geom.lock_plan_for_workspace(profile, "5")
    assert s5["layout"] == "scrolling" and s5["visibleCount"] == 3 and s5["extras"] == "around"
    s6 = geom.lock_plan_for_workspace(profile, "6")
    assert s6["layout"] == "scrolling" and s6["extras"] == "block" and s6["visibleCount"] == 4
    s8 = geom.lock_plan_for_workspace(profile, "8")
    assert s8["layout"] == "dwindle"


def test_dummy_watch_maps_via_env():
    orig = os.environ.get("WORKSCAPE_CONFIG")
    os.environ["WORKSCAPE_CONFIG"] = str(FIXTURE)
    try:
        blocked = watch.load_block_map()
        assert blocked.get("6") == 1
        assert blocked.get("2") == 2
        ov = watch.overflow_order(watch.load_active_profile())
        assert ov == ["9"]
        managed = geom.managed_workspaces(watch.load_active_profile())
        assert {"1", "2", "3", "4", "5", "6", "7", "8", "9"} <= managed
        assert "20" not in managed
    finally:
        if orig is None:
            os.environ.pop("WORKSCAPE_CONFIG", None)
        else:
            os.environ["WORKSCAPE_CONFIG"] = orig


def test_dummy_append_extra_uses_locked_geoms():
    dummy = load_dummy()
    calls = []
    clients = [
        {"address": "0xa1", "class": "workscape-dummy-left", "title": "dummy-left", "workspace": {"id": 2}, "at": [10, 36], "size": [1229, 1034], "floating": False},
        {"address": "0xa2", "class": "workscape-dummy-right", "title": "dummy-right", "workspace": {"id": 2}, "at": [1240, 36], "size": [675, 1034], "floating": False},
        {"address": "0xee", "class": "workscape-dummy-extra", "title": "dummy-extra", "workspace": {"id": 2}, "at": [800, 36], "size": [627, 1034], "floating": False},
    ]
    monitors = [{"name": "DUMMY-1", "id": 0, "width": 1920, "height": 1080, "scale": 1, "x": 0, "y": 0, "reserved": [0, 0, 0, 0]}]
    workspaces = [{"id": 2, "name": "2", "monitor": "DUMMY-1", "tiledLayout": "dwindle"}]

    def fake_j(cmd, cached=False):
        if cmd == "clients":
            return clients
        if cmd == "monitors":
            return monitors
        if cmd == "workspaces":
            return workspaces
        if cmd == "activewindow":
            return {"address": "0xee", "workspace": {"id": 2}}
        if cmd == "activeworkspace":
            return {"id": 2}
        if cmd.startswith("getoption"):
            return {"css": "8"}
        return {}

    orig = (
        geom.hypr_j, geom.hypr_eval, geom.force_scrolling, geom.force_tiled,
        geom.clear_size_lock, geom.focus_window, geom.actual_box, geom.gaps_out,
        geom.swap_windows, time.sleep,
    )
    geom.hypr_j = fake_j
    geom.hypr_eval = lambda lua: calls.append(lua)
    geom.force_scrolling = lambda *a, **k: calls.append(("force_scrolling",))
    geom.force_tiled = lambda addr: None
    geom.clear_size_lock = lambda addr: None
    geom.focus_window = lambda addr: calls.append(("focus", addr))
    geom.actual_box = lambda addr: {"x": 0, "y": 0, "w": 1229 if addr == "0xa1" else 675, "h": 1034}
    geom.gaps_out = lambda: (8, 8, 8, 8)
    time.sleep = lambda _s: None

    def swap(a, b):
        calls.append(("swap", a, b))
        ca = next(c for c in clients if c["address"] == a)
        cb = next(c for c in clients if c["address"] == b)
        ca["at"], cb["at"] = cb["at"], ca["at"]

    geom.swap_windows = swap
    try:
        result = geom.append_extra_after_locked("2", "0xee", dummy)
    finally:
        (
            geom.hypr_j, geom.hypr_eval, geom.force_scrolling, geom.force_tiled,
            geom.clear_size_lock, geom.focus_window, geom.actual_box, geom.gaps_out,
            geom.swap_windows, time.sleep,
        ) = orig
    assert result.get("ok") is True
    assert result.get("skipped") is True
    joined = "\n".join(str(c) for c in calls)
    assert "Workscape.plans" not in joined
    assert "swap" not in joined


def test_dummy_stage_append_is_skipped():
    dummy = load_dummy()
    result = geom.append_extra_after_locked("1", "0xE", dummy)
    assert result.get("skipped") is True


def test_dummy_exec_silent_and_launch_script():
    lua = geom.exec_silent_lua("foot --app-id=workscape-dummy-left -T dummy-left", "12")
    assert "no_initial_focus = true" in lua
    assert "dsp.focus" not in lua
    text = (ROOT / "workscape.sh").read_text()
    assert "no_initial_focus = true" in text
    assert 'workspace = "%s silent"' in text


def test_dummy_append_extra_does_not_min_size():
    dummy = load_dummy()
    calls = []
    clients = [
        {"address": "0xa1", "class": "workscape-dummy-left", "title": "dummy-left", "workspace": {"id": 2}, "at": [10, 36], "size": [1229, 1034], "floating": False},
        {"address": "0xa2", "class": "workscape-dummy-right", "title": "dummy-right", "workspace": {"id": 2}, "at": [1240, 36], "size": [675, 1034], "floating": False},
        {"address": "0xee", "class": "workscape-dummy-extra", "title": "dummy-extra", "workspace": {"id": 2}, "at": [1915, 36], "size": [627, 1034], "floating": False},
    ]
    monitors = [{"name": "DUMMY-1", "id": 0, "width": 1920, "height": 1080, "scale": 1, "x": 0, "y": 0, "reserved": [0, 0, 0, 0]}]
    workspaces = [{"id": 2, "name": "2", "monitor": "DUMMY-1", "tiledLayout": "scrolling"}]

    def fake_j(cmd, cached=False):
        if cmd == "clients":
            return clients
        if cmd == "monitors":
            return monitors
        if cmd == "workspaces":
            return workspaces
        if cmd == "activewindow":
            return {"address": "0xee", "workspace": {"id": 2}}
        if cmd == "activeworkspace":
            return {"id": 2}
        if cmd.startswith("getoption"):
            return {"css": "8"}
        return {}

    orig = (geom.hypr_j, geom.hypr_eval, geom.force_scrolling, geom.force_tiled,
            geom.focus_window, geom.actual_box, geom.gaps_out, geom.swap_windows, time.sleep)
    geom.hypr_j = fake_j
    geom.hypr_eval = lambda lua: calls.append(lua)
    geom.force_scrolling = lambda *a, **k: calls.append(("force_scrolling",))
    geom.force_tiled = lambda addr: None
    geom.focus_window = lambda addr: calls.append(("focus", addr))
    geom.actual_box = lambda addr: {"x": 0, "y": 0, "w": 1229 if addr == "0xa1" else 675, "h": 1034}
    geom.gaps_out = lambda: (8, 8, 8, 8)
    geom.swap_windows = lambda a, b: calls.append(("swap", a, b))
    time.sleep = lambda _s: None
    try:
        result = geom.append_extra_after_locked("2", "0xee", dummy)
    finally:
        (geom.hypr_j, geom.hypr_eval, geom.force_scrolling, geom.force_tiled,
         geom.focus_window, geom.actual_box, geom.gaps_out, geom.swap_windows, time.sleep) = orig
    assert result.get("ok") is True
    joined = "\n".join(str(c) for c in calls)
    assert "value=\"1229" not in joined and "value=\"675" not in joined
    assert not any("min_size" in str(c) and 'value="0 0"' not in str(c) for c in calls)
    assert "force_scrolling" not in joined


def test_live_offset_does_not_collide_with_desk_dock():
    dummy = load_dummy()
    offset = int(dummy["_test"]["liveWorkspaceOffset"])
    live = {int(a["workspace"]) + offset for a in dummy["profiles"][0]["assignments"]}
    assert live == {11, 12, 13, 14, 15, 16, 17, 18}
    assert 1 not in live and 2 not in live and 5 not in live


def test_schema_keeps_monitor_scales_and_modes():
    schema = SourceFileLoader("dummy_schema", str(ROOT / "scripts/schema")).load_module()
    cfg = schema.sanitize_config({
        "version": 2,
        "settings": {},
        "monitors": [{"id": "laptop", "label": "Laptop", "description": "BOE NE135A1M-NY1", "name": "eDP-1"}],
        "profiles": [{
            "id": "p", "name": "P", "monitors": ["laptop"],
            "monitorScales": {"laptop": 1.5, "ghost": 2, "bad": "junk"},
            "monitorModes": {
                "laptop": {"width": 2880, "height": 1800, "refreshRate": 120},
                "ghost": {"width": 1920, "height": 1080, "refreshRate": 60},
                "bad": {"width": "x", "height": 2, "refreshRate": 5},
            },
        }],
    })
    prof = cfg["profiles"][0]
    assert prof["monitorScales"] == {"laptop": 1.5}, prof["monitorScales"]
    assert prof["monitorModes"] == {"laptop": {"width": 2880, "height": 1800, "refreshRate": 120}}, prof["monitorModes"]


def test_schema_settings_and_docks():
    schema = SourceFileLoader("dummy_schema2", str(ROOT / "scripts/schema")).load_module()
    cfg = schema.sanitize_config({
        "version": 2,
        "settings": {"applyOnMonitorChange": True},
        "profiles": [{
            "id": "p", "name": "P",
            "docks": ["usb:413c:b06f:DG7X753", "usb:413c:b06f:DG7X753", "  "],
            "dockLabels": {"usb:413c:b06f:DG7X753": "Dell Dock", "usb:nope:0:0": "Unbound"},
        }],
    })
    assert cfg["settings"]["applyOnMonitorChange"] is True
    assert cfg["settings"].get("applyOnShellRestart") is False
    default = schema.sanitize_config({"version": 2, "settings": {}, "profiles": [{"id": "q", "name": "Q"}]})
    assert default["settings"]["applyOnMonitorChange"] is False
    assert default["settings"]["applyOnShellRestart"] is False
    prof = cfg["profiles"][0]
    assert prof["docks"] == ["usb:413c:b06f:DG7X753"], prof["docks"]
    assert prof["dockLabels"] == {"usb:413c:b06f:DG7X753": "Dell Dock"}, prof["dockLabels"]


if __name__ == "__main__":
    test_fixture_is_not_user_config()
    test_config_path_honors_env()
    test_dummy_lock_plans()
    test_dummy_watch_maps_via_env()
    test_dummy_append_extra_uses_locked_geoms()
    test_dummy_stage_append_is_skipped()
    test_dummy_exec_silent_and_launch_script()
    test_dummy_append_extra_does_not_min_size()
    test_live_offset_does_not_collide_with_desk_dock()
    test_schema_keeps_monitor_scales_and_modes()
    test_schema_settings_and_docks()
    print("dummy.test.py ok")
