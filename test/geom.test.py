#!/usr/bin/env python3
import time
from importlib.machinery import SourceFileLoader

geom = SourceFileLoader("geom", str(__import__("pathlib").Path(__file__).resolve().parent.parent / "scripts/geom")).load_module()


def test_layout_metrics_scale():
    mon = {
        "width": 2880,
        "height": 1920,
        "scale": 2,
        "reserved": [0, 26, 0, 0],
        "x": 0,
        "y": 0,
    }
    orig = geom.gaps_out
    geom.gaps_out = lambda: (8, 8, 8, 8)
    try:
        m = geom.layout_metrics(mon)
    finally:
        geom.gaps_out = orig
    assert m["lw"] == 1440
    assert m["lh"] == 960
    assert m["x"] == 8
    assert m["y"] == 34
    assert m["w"] == 1424
    assert m["h"] == 918


def test_geom_pixels():
    metrics = {"x": 8, "y": 34, "w": 1424, "h": 918, "scale": 2}
    left = geom.geom_pixels({"x": 0, "y": 0, "w": 0.5, "h": 1}, metrics)
    right = geom.geom_pixels({"x": 0.5, "y": 0, "w": 0.5, "h": 1}, metrics)
    assert left["x"] == 8
    assert right["x"] == 8 + 712
    assert left["w"] + right["w"] == 1424


def test_box_to_geom():
    metrics = {"x": 8, "y": 34, "w": 1000, "h": 900, "scale": 1}
    g = geom.box_to_geom({"x": 8, "y": 34, "w": 628, "h": 900}, metrics)
    assert g["x"] == 0
    assert g["y"] == 0
    assert abs(g["w"] - 0.628) < 0.001
    assert g["h"] == 1
    thin = geom.box_to_geom({"x": 808, "y": 34, "w": 50, "h": 900}, metrics)
    assert abs(thin["w"] - 0.05) < 0.001


def test_monitor_for_client_uses_id():
    mons = [
        {"id": 0, "name": "eDP-1", "width": 2880, "height": 1920, "scale": 2, "x": 0, "y": 0},
        {"id": 2, "name": "DVI-I-2", "width": 1920, "height": 1080, "scale": 1, "x": 3360, "y": 0},
    ]
    hit = geom.monitor_for_client({"monitor": 2}, mons)
    assert hit["name"] == "DVI-I-2"
    by_name = geom.monitor_for_client({"monitor": "eDP-1"}, mons)
    assert by_name["name"] == "eDP-1"
    assert geom.monitor_for_client({"monitor": 99}, mons) is None


def test_lock_plan_and_assignment():
    prefs = {"2": {"lockSizes": False, "extras": "around", "visibleCount": 2}}
    locked = {"workspace": 2, "exec": "herdr", "lockPlace": True}
    unlocked = {"workspace": 2, "exec": "panel", "lockPlace": False}
    assert geom.assignment_is_locked(locked, prefs) is True
    assert geom.assignment_is_locked(unlocked, prefs) is False
    assert geom.assignment_is_locked(unlocked, {"2": {"lockSizes": True}}) is True
    profile = {
        "workspacePrefs": prefs,
        "assignments": [locked, unlocked, {"workspace": 3, "exec": "x", "lockPlace": True}],
    }
    plan = geom.lock_plan_for_workspace(profile, "2")
    assert len(plan["locked"]) == 1
    assert plan["locked"][0]["exec"] == "herdr"
    assert plan["extras"] == "around"
    stage_profile = {
        "workspacePrefs": {"1": {"layout": "scrolling", "visibleCount": 2, "extras": "around"}},
        "assignments": [{"workspace": 1, "exec": "brave", "lockPlace": False, "geom": {"x": 0, "y": 0, "w": 1, "h": 1}}],
    }
    sp = geom.lock_plan_for_workspace(stage_profile, "1")
    assert sp["layout"] == "scrolling"
    assert sp["stage"] is False
    assert len(sp["locked"]) == 1
    assert sp["locked"][0]["geom"]["w"] == 1.0


def test_close_enough_and_fallback():
    assert geom.close_enough({"w": 600, "h": 900}, {"w": 608, "h": 900})
    assert not geom.close_enough({"w": 400, "h": 900}, {"w": 600, "h": 900})
    g = geom.fallback_geom(0, 2)
    assert g["x"] == 0 and g["w"] == 0.5
    g2 = geom.fallback_geom(1, 2)
    assert g2["x"] == 0.5


def test_managed_workspaces():
    profile = {
        "assignments": [{"workspace": 1, "enabled": True}, {"workspace": 2, "enabled": True}],
        "workspacePrefs": {"3": {"layout": "scrolling"}, "5": {"layout": "dwindle"}},
    }
    got = geom.managed_workspaces(profile)
    assert "1" in got and "2" in got and "3" in got
    assert "5" in got


def test_column_width_frac():
    assert geom.extra_column_frac(2) == 0.5
    assert geom.extra_column_frac(3) == 0.3333
    assert geom.extra_column_frac(4) == 0.25
    assert geom.extra_column_frac(10) == 0.1
    assert geom.extra_column_frac(20) == 0.05
    assert geom.peeked_column_frac(2) == 0.48
    assert geom.peeked_column_frac(3) == 0.32
    assert geom.peeked_column_frac(4) == 0.24
    assert geom.peeked_column_frac(10) == 0.1
    assert geom.stage_fill_frac() == 0.98
    assert geom.clamp_visible_count(21) == 20
    assert geom.clamp_visible_count(0) == 1
    locked = {"lock": True, "geom": {"x": 0, "y": 0, "w": 0.6279, "h": 1}}
    extra = {"lock": False, "geom": {}}
    assert geom.column_width_frac(locked, 0.5) == 0.6279
    assert geom.column_width_frac(extra, 0.5) == 0.5
    assert "column_width = 0.5" in geom.scrolling_layout_opts(2)
    assert "column_width = 0.3333" in geom.scrolling_layout_opts(3)
    assert "column_width = 0.25" in geom.scrolling_layout_opts(4)
    assert "follow_focus" not in geom.scrolling_layout_opts(2, lock=True)
    assert "fullscreen_on_one_column" not in geom.scrolling_layout_opts(2, stage=True)


def test_apply_scrolling_globals_sets_hypr_config():
    calls = []
    orig = geom.hypr_eval
    geom.hypr_eval = lambda lua: calls.append(lua)
    try:
        geom.apply_scrolling_globals()
        assert calls == []
    finally:
        geom.hypr_eval = orig


def test_push_column_after_locked():
    calls = []
    clients = [
        {"address": "0xa0", "floating": False, "at": [10, 36], "size": [600, 900]},
        {"address": "0x3", "floating": False, "at": [200, 36], "size": [300, 900]},
        {"address": "0xa1", "floating": False, "at": [620, 36], "size": [400, 900]},
    ]
    orig = (
        geom.hypr_eval, geom.cache_clear, geom.focus_window, geom.layout_msg,
        geom.clients_on_workspace, geom.activate_workspace_for_layout,
        geom.managed_workspaces, time.sleep,
    )
    geom.hypr_eval = lambda lua: calls.append(lua)
    geom.cache_clear = lambda: None
    geom.clients_on_workspace = lambda ws: clients
    geom.activate_workspace_for_layout = lambda ws: True
    geom.managed_workspaces = lambda profile=None: {"2"}
    geom.focus_window = lambda addr: calls.append(("focus", addr))
    time.sleep = lambda _s: None

    def layout_msg(msg):
        calls.append(msg)
        if msg in ("swapcol r", "movewindowto r"):
            for c in clients:
                if c["address"] == "0x3":
                    c["at"] = [1100, 36]

    geom.layout_msg = layout_msg
    try:
        geom.push_column_after_locked("0x3", "2", {"0xa0", "0xa1"})
        assert "movewindowto r" in calls or "swapcol r" in calls, calls
        xs = {c["address"]: c["at"][0] for c in clients}
        assert xs["0x3"] > xs["0xa1"], xs
    finally:
        (
            geom.hypr_eval, geom.cache_clear, geom.focus_window, geom.layout_msg,
            geom.clients_on_workspace, geom.activate_workspace_for_layout,
            geom.managed_workspaces, time.sleep,
        ) = orig


def test_append_extra_restores_prior_focus():
    focuses = []
    clients = [
        {"address": "0xa0", "class": "herdr", "title": "herdr", "workspace": {"id": 2}, "at": [10, 36], "size": [900, 900], "floating": False},
        {"address": "0xa1", "class": "quickshell", "title": "Control", "workspace": {"id": 2}, "at": [920, 36], "size": [500, 900], "floating": False},
        {"address": "0xee", "class": "foot", "title": "foot", "workspace": {"id": 2}, "at": [400, 36], "size": [300, 900], "floating": False},
        {"address": "0xuser", "class": "foot", "title": "user", "workspace": {"id": 8}, "at": [10, 36], "size": [800, 800], "floating": False},
    ]
    orig = (
        geom.hypr_j, geom.hypr_eval, geom.layout_msg, geom.activate_workspace_for_layout,
        geom.managed_workspaces, geom.focus_window, geom.force_scrolling, geom.force_tiled,
        geom.clear_size_lock, geom.actual_box, geom.gaps_out, time.sleep,
    )

    def fake_j(cmd, cached=False):
        if cmd == "clients":
            return clients
        if cmd == "activewindow":
            return {"address": "0xuser", "workspace": {"id": 8}}
        if cmd == "activeworkspace":
            return {"id": 8}
        if cmd == "monitors":
            return [{"name": "eDP-1", "id": 0, "width": 1920, "height": 1080, "scale": 1, "x": 0, "y": 0, "reserved": [0, 0, 0, 0]}]
        if cmd == "workspaces":
            return [{"id": 2, "name": "2", "monitor": "eDP-1", "tiledLayout": "scrolling"}]
        if cmd.startswith("getoption"):
            return {"css": "8"}
        return {}

    geom.hypr_j = fake_j
    geom.hypr_eval = lambda lua: None
    geom.activate_workspace_for_layout = lambda ws: True
    geom.managed_workspaces = lambda profile=None: {"2"}
    geom.focus_window = lambda addr: focuses.append(addr)
    geom.force_scrolling = lambda *a, **k: None
    geom.force_tiled = lambda addr: None
    geom.clear_size_lock = lambda addr: None
    geom.actual_box = lambda addr: {"x": 10, "y": 36, "w": 900, "h": 900}
    geom.gaps_out = lambda: (8, 8, 8, 8)
    time.sleep = lambda _s: None

    def layout_msg(msg):
        if msg in ("swapcol r", "movewindowto r"):
            for c in clients:
                if c["address"] == "0xee":
                    c["at"] = [1500, 36]

    geom.layout_msg = layout_msg
    try:
        cfg = {
            "settings": {"activeProfileId": "p"},
            "profiles": [{
                "id": "p",
                "assignments": [
                    {"workspace": 2, "name": "Herdr", "exec": "herdr", "lockPlace": True, "geom": {"x": 0, "y": 0, "w": 0.65, "h": 1}},
                    {"workspace": 2, "name": "Control", "exec": "quickshell", "lockPlace": True, "geom": {"x": 0.65, "y": 0, "w": 0.35, "h": 1}},
                ],
                "workspacePrefs": {"2": {"layout": "scrolling", "visibleCount": 3, "extras": "around"}},
            }],
        }
        geom.append_extra_after_locked("2", "0xee", cfg)
        assert "0xa0" not in focuses and "0xee" not in focuses, focuses
    finally:
        (
            geom.hypr_j, geom.hypr_eval, geom.layout_msg, geom.activate_workspace_for_layout,
            geom.managed_workspaces, geom.focus_window, geom.force_scrolling, geom.force_tiled,
            geom.clear_size_lock, geom.actual_box, geom.gaps_out, time.sleep,
        ) = orig


def test_push_column_from_left_uses_few_swaps():
    swaps = []
    clients = [
        {"address": "0xee", "floating": False, "at": [10, 36], "size": [300, 900]},
        {"address": "0xa0", "floating": False, "at": [320, 36], "size": [600, 900]},
        {"address": "0xa1", "floating": False, "at": [930, 36], "size": [400, 900]},
    ]
    orig = (
        geom.clients_on_workspace, geom.hypr_eval, geom.focus_window, geom.layout_msg,
        geom.activate_workspace_for_layout, geom.managed_workspaces, time.sleep,
    )
    geom.clients_on_workspace = lambda ws: clients
    geom.hypr_eval = lambda lua: None
    geom.focus_window = lambda addr: swaps.append(("focus", addr))
    time.sleep = lambda _s: None
    geom.activate_workspace_for_layout = lambda ws: True
    geom.managed_workspaces = lambda profile=None: {"2"}

    def layout_msg(msg):
        swaps.append(msg)
        if msg in ("swapcol r", "movewindowto r"):
            for c in clients:
                if c["address"] == "0xee":
                    c["at"] = [1100, 36]

    geom.layout_msg = layout_msg
    try:
        geom.push_column_after_locked("0xee", "2", {"0xa0", "0xa1"})
        assert "movewindowto r" in swaps or "swapcol r" in swaps, swaps
        xs = {c["address"]: c["at"][0] for c in clients}
        assert xs["0xee"] > xs["0xa0"] and xs["0xee"] > xs["0xa1"], xs
    finally:
        (
            geom.clients_on_workspace, geom.hypr_eval, geom.focus_window, geom.layout_msg,
            geom.activate_workspace_for_layout, geom.managed_workspaces, time.sleep,
        ) = orig


def test_push_column_skips_when_extra_already_after_locked():
    swaps = []
    clients = [
        {"address": "0xa0", "floating": False, "at": [10, 36], "size": [600, 900]},
        {"address": "0xa1", "floating": False, "at": [620, 36], "size": [400, 900]},
        {"address": "0xee", "floating": False, "at": [1100, 36], "size": [300, 900]},
    ]
    orig = (
        geom.clients_on_workspace, geom.hypr_eval, geom.focus_window, geom.layout_msg,
        geom.activate_workspace_for_layout, geom.managed_workspaces, time.sleep,
    )
    geom.clients_on_workspace = lambda ws: clients
    geom.hypr_eval = lambda lua: None
    geom.focus_window = lambda addr: swaps.append(("focus", addr))
    geom.layout_msg = lambda msg: swaps.append(msg)
    geom.activate_workspace_for_layout = lambda ws: True
    geom.managed_workspaces = lambda profile=None: {"2"}
    time.sleep = lambda _s: None
    try:
        geom.push_column_after_locked("0xee", "2", {"0xa0", "0xa1"})
        assert "movewindowto r" not in swaps and "swapcol r" not in swaps, swaps
    finally:
        (
            geom.clients_on_workspace, geom.hypr_eval, geom.focus_window, geom.layout_msg,
            geom.activate_workspace_for_layout, geom.managed_workspaces, time.sleep,
        ) = orig


def test_clamp_pans_shifted_split_back():
    calls = []
    clients = [
        {"address": "0x1", "floating": False, "at": [3687, 36], "size": [1206, 1034]},
        {"address": "0x2", "floating": False, "at": [4905, 36], "size": [682, 1034]},
    ]
    orig = (geom.cache_clear, geom.clients_on_workspace, geom.sort_clients_axis, geom.focus_window, geom.layout_msg, geom.ensure_layout_workspace)
    geom.cache_clear = lambda: None
    geom.clients_on_workspace = lambda ws: clients
    geom.sort_clients_axis = lambda cs, axis: cs
    geom.focus_window = lambda addr: calls.append(f"focus {addr}")
    geom.layout_msg = lambda msg: calls.append(msg)
    geom.ensure_layout_workspace = lambda ws, attempts=6: True
    try:
        geom.clamp_scrolling_to_monitor("2", {"x": 3368.0, "w": 1904.0, "lw": 1920.0}, [])
        moves = [c for c in calls if str(c).startswith("move ")]
        assert moves, calls
        assert "move -319" in moves or any(str(c).startswith("move -") for c in moves), calls
    finally:
        geom.cache_clear, geom.clients_on_workspace, geom.sort_clients_axis, geom.focus_window, geom.layout_msg, geom.ensure_layout_workspace = orig


def test_clamp_grows_last_instead_of_panning_gutter():
    calls = []
    clients = [
        {"address": "0x1", "floating": False, "at": [3382, 36], "size": [1206, 1034]},
        {"address": "0x2", "floating": False, "at": [4600, 36], "size": [658, 1034]},
    ]
    orig = (geom.cache_clear, geom.clients_on_workspace, geom.sort_clients_axis, geom.focus_window, geom.layout_msg, geom.ensure_layout_workspace)
    geom.cache_clear = lambda: None
    geom.clients_on_workspace = lambda ws: clients
    geom.sort_clients_axis = lambda cs, axis: cs
    geom.focus_window = lambda addr: calls.append(f"focus {addr}")
    geom.layout_msg = lambda msg: calls.append(msg)
    geom.ensure_layout_workspace = lambda ws, attempts=6: True
    try:
        geom.clamp_scrolling_to_monitor("2", {"x": 3368.0, "w": 1904.0, "lw": 1920.0}, [])
        moves = [c for c in calls if str(c).startswith("move ")]
        assert "move -14" in moves, calls
        assert "fit expand" not in calls, calls
    finally:
        geom.cache_clear, geom.clients_on_workspace, geom.sort_clients_axis, geom.focus_window, geom.layout_msg, geom.ensure_layout_workspace = orig


def test_pack_peek_camera_left_middle_right():
    calls = []
    clients = [
        {"address": "0xa", "floating": False, "at": [1440, 36], "size": [960, 1034], "monitor": 2, "workspace": {"id": 1}},
        {"address": "0xb", "floating": False, "at": [2400, 36], "size": [960, 1034], "monitor": 2, "workspace": {"id": 1}},
        {"address": "0xc", "floating": False, "at": [3360, 36], "size": [960, 1034], "monitor": 2, "workspace": {"id": 1}},
    ]
    orig = (geom.hypr_j, geom.layout_msg, geom.cache_clear, geom.clients_on_workspace, geom.sort_clients_axis)
    geom.cache_clear = lambda: None
    geom.layout_msg = lambda msg: calls.append(msg)
    geom.clients_on_workspace = lambda ws: clients
    geom.sort_clients_axis = lambda cs, axis: cs
    geom.hypr_j = lambda cmd, cached=False: (
        {"id": 1} if cmd == "activeworkspace" else (
            [{"id": 2, "name": "DVI-I-2", "x": 1440, "y": 0, "width": 1920, "height": 1080, "scale": 1}]
            if cmd == "monitors" else []
        )
    )
    try:
        geom.pack_peek_camera("1", "0xa")
        assert calls == [], calls
        calls.clear()
        geom.pack_peek_camera("1", "0xb")
        peek_px = max(16, int(round(geom.PEEK_FRAC * 1920)))
        slack = 2400 - (1440 + peek_px)
        assert f"move {-slack}" in calls, calls
        calls.clear()
        geom.pack_peek_camera("1", "0xc")
        assert "move -960" in calls, calls
    finally:
        geom.hypr_j, geom.layout_msg, geom.cache_clear, geom.clients_on_workspace, geom.sort_clients_axis = orig


def test_clamp_single_column_fills():
    calls = []
    clients = [
        {"address": "0x1", "floating": False, "at": [1469, 36], "size": [1900, 1034]},
    ]
    orig = (geom.cache_clear, geom.clients_on_workspace, geom.sort_clients_axis, geom.focus_window, geom.layout_msg, geom.ensure_layout_workspace)
    geom.cache_clear = lambda: None
    geom.clients_on_workspace = lambda ws: clients
    geom.sort_clients_axis = lambda cs, axis: cs
    geom.focus_window = lambda addr: calls.append(f"focus {addr}")
    geom.layout_msg = lambda msg: calls.append(msg)
    geom.ensure_layout_workspace = lambda ws, attempts=6: True
    try:
        geom.clamp_scrolling_to_monitor("1", {"x": 1448.0, "w": 1904.0, "lw": 1920.0}, [])
        assert f"colresize {geom.stage_fill_frac()}" in calls, calls
    finally:
        geom.cache_clear, geom.clients_on_workspace, geom.sort_clients_axis, geom.focus_window, geom.layout_msg, geom.ensure_layout_workspace = orig


def test_clamp_pans_16px_fresh_offset():
    calls = []
    clients = [
        {"address": "0x1", "floating": False, "at": [24, 36], "size": [896, 914]},
        {"address": "0x2", "floating": False, "at": [932, 36], "size": [512, 914]},
    ]
    orig = (geom.cache_clear, geom.clients_on_workspace, geom.sort_clients_axis, geom.focus_window, geom.layout_msg, geom.ensure_layout_workspace)
    geom.cache_clear = lambda: None
    geom.clients_on_workspace = lambda ws: clients
    geom.sort_clients_axis = lambda cs, axis: cs
    geom.focus_window = lambda addr: calls.append(f"focus {addr}")
    geom.layout_msg = lambda msg: calls.append(msg)
    geom.ensure_layout_workspace = lambda ws, attempts=6: True
    try:
        geom.clamp_scrolling_to_monitor("2", {"x": 8.0, "w": 1424.0, "lw": 1440.0}, [])
        assert any(str(c).startswith("move -") for c in calls), calls
        assert "move -16" in calls, calls
    finally:
        geom.cache_clear, geom.clients_on_workspace, geom.sort_clients_axis, geom.focus_window, geom.layout_msg, geom.ensure_layout_workspace = orig


def test_clamp_skips_when_already_filled():
    calls = []
    clients = [
        {"address": "0x1", "floating": False, "at": [3370, 36], "size": [1900, 1034]},
    ]
    orig = (geom.cache_clear, geom.clients_on_workspace, geom.sort_clients_axis, geom.focus_window, geom.layout_msg, geom.ensure_layout_workspace)
    geom.cache_clear = lambda: None
    geom.clients_on_workspace = lambda ws: clients
    geom.sort_clients_axis = lambda cs, axis: cs
    geom.focus_window = lambda addr: calls.append(f"focus {addr}")
    geom.layout_msg = lambda msg: calls.append(msg)
    geom.ensure_layout_workspace = lambda ws, attempts=6: True
    try:
        geom.clamp_scrolling_to_monitor("4", {"x": 3368.0, "w": 1904.0, "lw": 1920.0}, [])
        assert calls == []
    finally:
        geom.cache_clear, geom.clients_on_workspace, geom.sort_clients_axis, geom.focus_window, geom.layout_msg, geom.ensure_layout_workspace = orig


def test_fit_column_fracs_keeps_columns_on_screen():
    orig_out, orig_in, orig_b = geom.gaps_out, geom.gaps_in, geom.border_size
    geom.gaps_out = lambda: (8, 8, 8, 8)
    geom.gaps_in = lambda: (4, 4, 4, 4)
    geom.border_size = lambda: 2
    try:
        metrics = {"lw": 1440.0, "w": 1424.0}
        raw = [0.6764, 0.3236]
        out = geom.fit_column_fracs(raw, metrics, 2)
        assert out[0] > out[1]
        assert abs(out[0] / out[1] - raw[0] / raw[1]) < 0.02
        px = sum(f * metrics["lw"] for f in out)
        between = 4 + 4
        assert px + between <= metrics["w"] + 2
        assert px >= metrics["w"] * 0.95
    finally:
        geom.gaps_out, geom.gaps_in, geom.border_size = orig_out, orig_in, orig_b


def test_force_scrolling_not_persistent_by_default():
    calls = []
    orig = geom.hypr_eval
    geom.hypr_eval = lambda lua: calls.append(lua)
    try:
        geom.force_scrolling("3", visible_count=2, lock=False, stage=True)
        assert calls, "expected workspace_rule"
        lua = "\n".join(calls)
        assert "persistent = false" in lua
        assert "layout = \"scrolling\"" in lua
        assert "column_width = 0.5" in lua
        assert "follow_focus" not in lua
        calls.clear()
        geom.force_scrolling("2", visible_count=2, lock=True, persist=True)
        assert "persistent = true" in "\n".join(calls)
    finally:
        geom.hypr_eval = orig


def test_restamp_does_not_set_global_column_width():
    calls = []
    orig = geom.hypr_eval
    orig_repair = geom.repair_unmanaged_workspaces
    geom.hypr_eval = lambda lua: calls.append(lua)
    geom.repair_unmanaged_workspaces = lambda **k: None
    try:
        geom.restamp_scrolling_default("2", 3, lock=True, n_cols=3)
        joined = "\n".join(calls)
        assert "scrolling_width" in joined
        for c in calls:
            if "hl.config" in c:
                assert "column_width" not in c
        geom.sync_column_width_for_workspace("3", visible_count=4)
        for c in calls:
            if "hl.config" in c:
                assert "column_width" not in c
    finally:
        geom.hypr_eval = orig
        geom.repair_unmanaged_workspaces = orig_repair


def test_restamp_set_width_disables_fullscreen_on_one_column():
    calls = []
    orig = (geom.hypr_eval, geom.workspace_is_scrolling, geom.repair_unmanaged_workspaces)
    geom.hypr_eval = lambda lua: calls.append(lua)
    geom.workspace_is_scrolling = lambda ws: True
    geom.repair_unmanaged_workspaces = lambda **k: None
    try:
        geom.restamp_scrolling_default("3", 4, set_width=True, n_cols=1)
        joined = "\n".join(calls)
        assert "fullscreen_on_one_column = false" in joined, calls
        assert "scrolling_width = 0.25" in joined
    finally:
        geom.hypr_eval, geom.workspace_is_scrolling, geom.repair_unmanaged_workspaces = orig


def test_restore_resizes_locked_pane():
    calls = []
    clients = [
        {
            "address": "0x1",
            "class": "herdr",
            "title": "herdr",
            "initialClass": "herdr",
            "workspace": {"id": 2, "name": "2"},
            "at": [8, 34],
            "size": [400, 900],
        },
        {
            "address": "0x2",
            "class": "foot",
            "title": "foot",
            "initialClass": "foot",
            "workspace": {"id": 2, "name": "2"},
            "at": [8, 34],
            "size": [-3, 900],
        },
    ]
    monitors = [{"name": "DVI-I-1", "width": 1920, "height": 1080, "scale": 1, "x": 0, "y": 0, "reserved": [0, 0, 0, 0], "focused": True}]
    workspaces = [{"id": 2, "name": "2", "monitor": "DVI-I-1"}]

    def fake_j(cmd, cached=False):
        if cmd == "clients":
            return clients
        if cmd == "monitors":
            return monitors
        if cmd == "workspaces":
            return workspaces
        if cmd == "activewindow":
            return {"address": "0x2", "workspace": {"id": 2}}
        if cmd == "activeworkspace":
            return {"id": 2}
        if cmd.startswith("getoption"):
            return {"css": "8"}
        return {}

    orig_j, orig_eval, orig_sleep = geom.hypr_j, geom.hypr_eval, time.sleep
    geom.hypr_j = fake_j
    geom.hypr_eval = lambda lua: calls.append(lua)
    time.sleep = lambda _s: None
    try:
        cfg = {
            "settings": {"activeProfileId": "p"},
            "profiles": [{
                "id": "p",
                "assignments": [{
                    "workspace": 2,
                    "name": "Herdr",
                    "exec": "herdr",
                    "lockPlace": True,
                    "geom": {"x": 0, "y": 0, "w": 0.6, "h": 1},
                }],
                "workspacePrefs": {"2": {"layout": "dwindle", "lockSizes": False, "extras": "around", "visibleCount": 2}},
            }],
        }
        result = geom.restore_locks_for_workspace("2", cfg, prefer_addr="0x2")
    finally:
        geom.hypr_j, geom.hypr_eval, time.sleep = orig_j, orig_eval, orig_sleep
    assert result["ok"] is True
    assert result.get("skipped") is not True
    joined = "\n".join(calls)
    assert "layout = \"scrolling\"" in joined
    assert "fullscreen_on_one_column = false" in joined
    assert "hl.dsp.focus" in joined
    assert "colresize 0.6" in joined
    assert "colresize 0.48" in joined
    assert "window.resize" not in joined
    assert "fit all" not in joined
    inhibit_at = next(i for i, c in enumerate(calls) if "inhibit_scroll true" in c)
    first_locked_focus = next(i for i, c in enumerate(calls) if 'window = "address:0x1"' in c)
    first_extra_focus = next(i for i, c in enumerate(calls) if 'window = "address:0x2"' in c)
    assert first_extra_focus < inhibit_at < first_locked_focus, (first_extra_focus, inhibit_at, first_locked_focus)


def test_locked_colresize_frac_uses_pixel_width():
    metrics = {"lw": 1920.0, "w": 1904.0}
    it = {"geom": {"w": 0.6456}, "px": {"w": 1229, "h": 1038}, "lock": True}
    assert geom.locked_colresize_frac(it, metrics, 0.3333) == 0.6401
    it2 = {"geom": {"w": 0.3544}, "px": {"w": 675, "h": 1038}, "lock": True}
    assert geom.locked_colresize_frac(it2, metrics, 0.3333) == 0.3516
    extra_like = {"geom": {}, "px": {}, "lock": False}
    assert geom.locked_colresize_frac(extra_like, metrics, 0.3333) == 0.3333


def test_append_extra_preserves_locked_column_sizes():
    """2-lock extras publish a lua:workscape plan; no swapcol/colresize/focus."""
    calls = []
    clients = [
        {"address": "0x1", "class": "herdr", "title": "herdr", "workspace": {"id": 2}, "at": [3370, 36], "size": [1229, 1034], "floating": False},
        {"address": "0x3", "class": "foot", "title": "foot", "workspace": {"id": 2}, "at": [4000, 36], "size": [627, 1034], "floating": False},
        {"address": "0x2", "class": "quickshell", "title": "Control", "workspace": {"id": 2}, "at": [4611, 36], "size": [659, 1034], "floating": False},
    ]
    monitors = [{"name": "DVI-I-2", "id": 2, "width": 1920, "height": 1080, "scale": 1, "x": 3360, "y": 0, "reserved": [0, 0, 0, 0]}]
    workspaces = [{"id": 2, "name": "2", "monitor": "DVI-I-2", "tiledLayout": "scrolling"}]

    def fake_j(cmd, cached=False):
        if cmd == "clients":
            return clients
        if cmd == "monitors":
            return monitors
        if cmd == "workspaces":
            return workspaces
        if cmd == "activewindow":
            return {"address": "0x3", "workspace": {"id": 2}}
        if cmd == "activeworkspace":
            return {"id": 2}
        if cmd.startswith("getoption"):
            return {"css": "8"}
        return {}

    orig = (
        geom.hypr_j, geom.hypr_eval, geom.force_scrolling, geom.force_tiled,
        geom.clear_size_lock, geom.focus_window, geom.actual_box, geom.gaps_out,
        geom.layout_msg, geom.activate_workspace_for_layout, geom.managed_workspaces, time.sleep,
    )
    geom.hypr_j = fake_j
    geom.hypr_eval = lambda lua: calls.append(lua)
    geom.force_scrolling = lambda *a, **k: None
    geom.force_tiled = lambda addr: None
    geom.clear_size_lock = lambda addr: None
    geom.focus_window = lambda addr: calls.append(("focus", addr))
    geom.actual_box = lambda addr: next(({"x": c["at"][0], "y": 36, "w": c["size"][0], "h": 1034} for c in clients if c["address"] == addr), None)
    geom.gaps_out = lambda: (8, 8, 8, 8)
    time.sleep = lambda _s: None

    def layout_msg(msg):
        calls.append(msg)
        if msg in ("swapcol r", "movewindowto r"):
            for c in clients:
                if c["address"] == "0x3":
                    c["at"] = [5300, 36]

    geom.layout_msg = layout_msg
    geom.activate_workspace_for_layout = lambda ws: True
    geom.managed_workspaces = lambda profile=None: {"2"}
    try:
        cfg = {
            "settings": {"activeProfileId": "p"},
            "profiles": [{
                "id": "p",
                "assignments": [
                    {"workspace": 2, "name": "Herdr", "exec": "herdr", "lockPlace": True, "geom": {"x": 0, "y": 0, "w": 0.6456, "h": 1}},
                    {"workspace": 2, "name": "Control", "exec": "quickshell", "lockPlace": True, "geom": {"x": 0.6456, "y": 0, "w": 0.3544, "h": 1}},
                ],
                "workspacePrefs": {"2": {"layout": "scrolling", "visibleCount": 3, "extras": "around"}},
            }],
        }
        result = geom.append_extra_after_locked("2", "0x3", cfg)
    finally:
        (
            geom.hypr_j, geom.hypr_eval, geom.force_scrolling, geom.force_tiled,
            geom.clear_size_lock, geom.focus_window, geom.actual_box, geom.gaps_out,
            geom.layout_msg, geom.activate_workspace_for_layout, geom.managed_workspaces, time.sleep,
        ) = orig
    assert result.get("ok") is True
    joined = "\n".join(str(c) for c in calls)
    assert "Workscape.plans" in joined, calls
    assert "lua:workscape" in joined, calls
    assert "swapcol r" not in joined
    assert "movewindowto r" not in joined
    assert "colresize" not in joined
    foc = [c[1] for c in calls if isinstance(c, tuple) and c[0] == "focus"]
    assert foc == [], foc
    assert "Workscape.fresh" not in joined
    assert "offsets[" not in joined


def test_append_extra_skips_when_already_tape():
    calls = []
    orig = (geom.hypr_j, geom.hypr_eval, geom.repair_unmanaged_workspaces)
    geom.hypr_eval = lambda lua: calls.append(lua)
    geom.repair_unmanaged_workspaces = lambda **k: calls.append("repair")
    geom.hypr_j = lambda cmd, cached=False: (
        [{"id": 2, "tiledLayout": "lua:workscape", "monitor": "eDP-1"}] if cmd == "workspaces" else (
            [{"name": "eDP-1", "width": 1920, "height": 1080, "scale": 1, "x": 0, "y": 0, "reserved": [0, 0, 0, 0]}]
            if cmd == "monitors"
            else [
                {"address": "0x1", "class": "herdr", "workspace": {"id": 2}, "at": [10, 36], "size": [900, 900], "floating": False},
                {"address": "0x2", "class": "quickshell", "workspace": {"id": 2}, "at": [910, 36], "size": [500, 900], "floating": False},
                {"address": "0xee", "class": "foot", "workspace": {"id": 2}, "at": [1410, 36], "size": [400, 900], "floating": False},
            ]
            if cmd == "clients"
            else {}
        )
    )
    try:
        cfg = {
            "settings": {"activeProfileId": "p"},
            "profiles": [{
                "id": "p",
                "assignments": [
                    {"workspace": 2, "name": "Herdr", "exec": "herdr", "lockPlace": True, "geom": {"x": 0, "y": 0, "w": 0.65, "h": 1}},
                    {"workspace": 2, "name": "Control", "exec": "quickshell", "lockPlace": True, "geom": {"x": 0.65, "y": 0, "w": 0.35, "h": 1}},
                ],
                "workspacePrefs": {"2": {"layout": "scrolling", "visibleCount": 3, "extras": "around"}},
            }],
        }
        result = geom.append_extra_after_locked("2", "0xee", cfg)
        assert result.get("skipped") is True
        assert result.get("reason") == "already_tape"
        assert calls == []
    finally:
        geom.hypr_j, geom.hypr_eval, geom.repair_unmanaged_workspaces = orig


def test_two_locked_around_stays_scrolling():
    """2-lock extras=around uses lua:workscape instead of swapcol packing."""
    calls = []
    clients = [
        {"address": "0x1", "class": "herdr", "title": "herdr", "workspace": {"id": 2}, "at": [10, 36], "size": [900, 900], "floating": False},
        {"address": "0x2", "class": "quickshell", "title": "Control", "workspace": {"id": 2}, "at": [910, 36], "size": [500, 900], "floating": False},
    ]
    monitors = [{"name": "eDP-1", "id": 0, "width": 1920, "height": 1080, "scale": 1, "x": 0, "y": 0, "reserved": [0, 0, 0, 0]}]
    workspaces = [{"id": 2, "name": "2", "monitor": "eDP-1"}]

    def fake_j(cmd, cached=False):
        if cmd == "clients":
            return clients
        if cmd == "monitors":
            return monitors
        if cmd == "workspaces":
            return workspaces
        if cmd == "activewindow":
            return {"address": "0x1", "workspace": {"id": 2}}
        if cmd == "activeworkspace":
            return {"id": 2}
        if cmd.startswith("getoption"):
            return {"css": "8"}
        return {}

    orig_j, orig_eval, orig_sleep = geom.hypr_j, geom.hypr_eval, time.sleep
    geom.hypr_j = fake_j
    geom.hypr_eval = lambda lua: calls.append(lua)
    time.sleep = lambda _s: None
    try:
        cfg = {
            "settings": {"activeProfileId": "p"},
            "profiles": [{
                "id": "p",
                "assignments": [
                    {"workspace": 2, "name": "Herdr", "exec": "herdr", "lockPlace": True, "geom": {"x": 0, "y": 0, "w": 0.65, "h": 1}},
                    {"workspace": 2, "name": "Control", "exec": "quickshell", "lockPlace": True, "geom": {"x": 0.65, "y": 0, "w": 0.35, "h": 1}},
                ],
                "workspacePrefs": {"2": {"layout": "scrolling", "lockSizes": False, "extras": "around", "visibleCount": 3}},
            }],
        }
        result = geom.restore_locks_for_workspace("2", cfg)
    finally:
        geom.hypr_j, geom.hypr_eval, time.sleep = orig_j, orig_eval, orig_sleep
    assert result.get("mode") == "lua:workscape", result
    joined = "\n".join(calls)
    assert "layout = \"lua:workscape\"" in joined
    assert "layout = \"dwindle\"" not in joined
    assert "Workscape.plans" in joined


def test_apply_config_skips_occupied(monkeypatch=None):
    orig_env = geom.os.environ.get("WORKSCAPE_OCCUPIED_WS")
    calls = []
    geom.os.environ["WORKSCAPE_OCCUPIED_WS"] = "2 8"
    orig_hypr_j = geom.hypr_j
    orig_apply_items = geom.apply_items
    geom.hypr_j = lambda cmd, cached=False: [
        {
            "address": "0xabc",
            "class": "herdr",
            "title": "herdr",
            "initialClass": "herdr",
            "workspace": {"id": 2, "name": "2"},
            "at": [8, 34],
            "size": [700, 900],
        }
    ] if cmd == "clients" else []
    geom.apply_items = lambda *a, **k: calls.append(a) or []
    try:
        cfg = {
            "settings": {"activeProfileId": "p"},
            "profiles": [{
                "id": "p",
                "assignments": [{
                    "workspace": 2,
                    "name": "Herdr",
                    "exec": "herdr",
                    "lockPlace": True,
                    "geom": {"x": 0, "y": 0, "w": 0.6, "h": 1},
                }],
                "workspacePrefs": {"2": {"layout": "scrolling"}},
            }],
        }
        import tempfile, json, os
        fd, path = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(cfg, fh)
        try:
            result = geom.apply_config(path, "p")
        finally:
            os.unlink(path)
        assert result.get("ok") is True
        assert calls == []
    finally:
        geom.hypr_j = orig_hypr_j
        geom.apply_items = orig_apply_items
        if orig_env is None:
            geom.os.environ.pop("WORKSCAPE_OCCUPIED_WS", None)
        else:
            geom.os.environ["WORKSCAPE_OCCUPIED_WS"] = orig_env


def test_apply_config_migrates_occupied_on_profile_change():
    orig_env = geom.os.environ.get("WORKSCAPE_OCCUPIED_WS")
    orig_mig = geom.os.environ.get("WORKSCAPE_MIGRATE_OCCUPIED")
    calls = []
    geom.os.environ["WORKSCAPE_OCCUPIED_WS"] = "2"
    geom.os.environ["WORKSCAPE_MIGRATE_OCCUPIED"] = "1"
    orig_hypr_j = geom.hypr_j
    orig_restore = geom.restore_locks_for_workspace
    orig_match = geom.match_client
    orig_focus = geom.active_window_addr
    orig_focus_w = geom.focus_window
    client = {
        "address": "0xabc",
        "class": "herdr",
        "title": "herdr",
        "initialClass": "herdr",
        "workspace": {"id": 2, "name": "2"},
        "at": [8, 34],
        "size": [700, 900],
    }
    geom.hypr_j = lambda cmd, cached=False: [client] if cmd == "clients" else []
    geom.match_client = lambda a, on_ws, used: client
    geom.active_window_addr = lambda: ""
    geom.focus_window = lambda addr: None
    geom.restore_locks_for_workspace = lambda *a, **k: calls.append(a) or {"ok": True, "workspace": "2"}
    try:
        cfg = {
            "settings": {"activeProfileId": "p"},
            "profiles": [{
                "id": "p",
                "assignments": [{
                    "workspace": 2,
                    "name": "Herdr",
                    "exec": "herdr",
                    "lockPlace": True,
                    "geom": {"x": 0, "y": 0, "w": 0.6, "h": 1},
                }],
                "workspacePrefs": {"2": {"layout": "scrolling"}},
            }],
        }
        import tempfile, json, os
        fd, path = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(cfg, fh)
        try:
            result = geom.apply_config(path, "p")
        finally:
            os.unlink(path)
        assert result.get("ok") is True
        assert calls, "migrate should restamp occupied assigned workspaces"
    finally:
        geom.hypr_j = orig_hypr_j
        geom.restore_locks_for_workspace = orig_restore
        geom.match_client = orig_match
        geom.active_window_addr = orig_focus
        geom.focus_window = orig_focus_w
        if orig_env is None:
            geom.os.environ.pop("WORKSCAPE_OCCUPIED_WS", None)
        else:
            geom.os.environ["WORKSCAPE_OCCUPIED_WS"] = orig_env
        if orig_mig is None:
            geom.os.environ.pop("WORKSCAPE_MIGRATE_OCCUPIED", None)
        else:
            geom.os.environ["WORKSCAPE_MIGRATE_OCCUPIED"] = orig_mig


def test_restamp_layout_sizes_locked_settles_tape():
    orig_settle = geom._settle_workspace_once
    orig_clients = geom.clients_on_workspace
    settled = []
    geom.clients_on_workspace = lambda ws: [
        {"address": "0xa", "floating": False},
        {"address": "0xb", "floating": False},
    ]
    geom._settle_workspace_once = lambda ws, plan, prefer_addr="": settled.append((ws, len(plan.get("locked") or []))) or {
        "ok": True, "workspace": ws, "mode": "lua:workscape", "closeEnough": True
    }
    profile = {
        "assignments": [
            {"workspace": 2, "exec": "herdr", "lockPlace": True, "geom": {"x": 0, "y": 0, "w": 0.65, "h": 1}},
            {"workspace": 2, "exec": "panel", "lockPlace": True, "geom": {"x": 0.65, "y": 0, "w": 0.35, "h": 1}},
        ],
        "workspacePrefs": {"2": {"layout": "scrolling", "visibleCount": 2, "lockSizes": False, "extras": "around"}},
    }
    try:
        out = geom.restamp_layout_sizes("2", profile)
        assert out.get("mode") == "lua:workscape", out
        assert settled == [("2", 2)], settled
        assert out.get("reason") != "locked"
    finally:
        geom._settle_workspace_once = orig_settle
        geom.clients_on_workspace = orig_clients


def test_restamp_layout_sizes_stage_fills_lone():
    msgs = []
    orig = (
        geom.clients_on_workspace,
        geom.force_scrolling,
        geom.apply_spawn_width_rule,
        geom.ensure_layout_workspace,
        geom.layout_msg,
        geom.size_new_scrolling_column,
        geom.hypr_j,
    )
    geom.clients_on_workspace = lambda ws: [{"address": "0xbrave", "floating": False, "workspace": {"id": 1}}]
    geom.force_scrolling = lambda *a, **k: msgs.append(("scroll", k))
    geom.apply_spawn_width_rule = lambda ws, frac: msgs.append(("spawn", frac))
    geom.ensure_layout_workspace = lambda ws, attempts=6: msgs.append(("activate", ws)) or True
    geom.layout_msg = lambda msg: msgs.append(("msg", msg))
    geom.size_new_scrolling_column = lambda *a, **k: msgs.append("setwidth")
    profile = {
        "assignments": [{"workspace": 1, "exec": "brave", "lockPlace": False}],
        "workspacePrefs": {"1": {"layout": "stage", "visibleCount": 2, "lockSizes": False, "extras": "around"}},
    }
    try:
        out = geom.restamp_layout_sizes("1", profile)
        assert out.get("mode") == "stage" and out.get("filled") is True, out
        assert any(m == ("msg", "colresize 0.98") for m in msgs), msgs
        assert any(m[0] == "spawn" and m[1] == 0.48 for m in msgs), msgs
    finally:
        (
            geom.clients_on_workspace,
            geom.force_scrolling,
            geom.apply_spawn_width_rule,
            geom.ensure_layout_workspace,
            geom.layout_msg,
            geom.size_new_scrolling_column,
            geom.hypr_j,
        ) = orig


def test_apply_config_occupied_stage_still_fills():
    orig_env = geom.os.environ.get("WORKSCAPE_OCCUPIED_WS")
    orig_mig = geom.os.environ.get("WORKSCAPE_MIGRATE_OCCUPIED")
    orig_hypr = geom.hypr_j
    orig_restamp = geom.restamp_layout_sizes
    orig_focus = geom.active_window_addr
    orig_fw = geom.focus_window
    orig_restore = geom.restore_locks_for_workspace
    calls = []
    geom.os.environ["WORKSCAPE_OCCUPIED_WS"] = "1"
    geom.os.environ.pop("WORKSCAPE_MIGRATE_OCCUPIED", None)
    geom.hypr_j = lambda cmd, cached=False: (
        [{"address": "0xbrave", "class": "brave-browser", "workspace": {"id": 1}}] if cmd == "clients" else []
    )
    geom.restamp_layout_sizes = lambda ws, profile=None: calls.append(ws) or {"ok": True, "mode": "stage", "workspace": ws, "filled": True}
    geom.active_window_addr = lambda: ""
    geom.focus_window = lambda addr: None
    geom.restore_locks_for_workspace = lambda *a, **k: {"ok": True, "skipped": True, "reason": "occupied"}
    try:
        cfg = {
            "settings": {"activeProfileId": "p"},
            "profiles": [{
                "id": "p",
                "assignments": [{"workspace": 1, "name": "Brave", "exec": "brave", "lockPlace": False}],
                "workspacePrefs": {"1": {"layout": "stage", "visibleCount": 2}},
            }],
        }
        import tempfile, json, os
        fd, path = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(cfg, fh)
        try:
            result = geom.apply_config(path, "p")
        finally:
            os.unlink(path)
        assert result.get("ok") is True
        assert "1" in calls, calls
    finally:
        geom.hypr_j = orig_hypr
        geom.restamp_layout_sizes = orig_restamp
        geom.active_window_addr = orig_focus
        geom.focus_window = orig_fw
        geom.restore_locks_for_workspace = orig_restore
        if orig_env is None:
            geom.os.environ.pop("WORKSCAPE_OCCUPIED_WS", None)
        else:
            geom.os.environ["WORKSCAPE_OCCUPIED_WS"] = orig_env
        if orig_mig is None:
            geom.os.environ.pop("WORKSCAPE_MIGRATE_OCCUPIED", None)
        else:
            geom.os.environ["WORKSCAPE_MIGRATE_OCCUPIED"] = orig_mig


def test_match_saved_class_when_exec_is_generic_foot():
    herdr = {
        "address": "0x1",
        "class": "org.omarchy.herdr",
        "title": "session",
        "initialClass": "org.omarchy.herdr",
    }
    panel = {
        "address": "0x2",
        "class": "org.quickshell",
        "title": "Shophawk Control",
        "initialClass": "org.quickshell",
    }
    used: set[str] = set()
    a = geom.match_client(
        {"name": "omarchyhome: desk-a", "exec": "foot", "class": "org.omarchy.herdr", "title": "omarchyhome: desk-a"},
        [herdr, panel],
        used,
    )
    assert a and a["address"] == "0x1", a
    used.add("0x1")
    b = geom.match_client(
        {"name": "Shophawk Control", "exec": "qs", "class": "org.quickshell"},
        [herdr, panel],
        used,
    )
    assert b and b["address"] == "0x2", b


def test_occupied_skip_allows_two_lock_split():
    profile = {
        "assignments": [
            {"workspace": 2, "exec": "herdr", "lockPlace": True, "geom": {"x": 0, "y": 0, "w": 0.72, "h": 1}},
            {"workspace": 2, "exec": "qs", "lockPlace": True, "geom": {"x": 0.72, "y": 0, "w": 0.28, "h": 1}},
        ],
        "workspacePrefs": {"2": {"layout": "dwindle", "extras": "block"}},
    }
    orig_env = geom.os.environ.get("WORKSCAPE_OCCUPIED_WS")
    orig_mig = geom.os.environ.get("WORKSCAPE_MIGRATE_OCCUPIED")
    geom.os.environ["WORKSCAPE_OCCUPIED_WS"] = "2"
    geom.os.environ.pop("WORKSCAPE_MIGRATE_OCCUPIED", None)
    try:
        assert geom.occupied_skip("2", profile) is False
        assert geom.occupied_skip("3", {"assignments": [], "workspacePrefs": {}}) is False
        geom.os.environ["WORKSCAPE_OCCUPIED_WS"] = "3"
        assert geom.occupied_skip("3", {"assignments": [], "workspacePrefs": {}}) is True
    finally:
        if orig_env is None:
            geom.os.environ.pop("WORKSCAPE_OCCUPIED_WS", None)
        else:
            geom.os.environ["WORKSCAPE_OCCUPIED_WS"] = orig_env
        if orig_mig is None:
            geom.os.environ.pop("WORKSCAPE_MIGRATE_OCCUPIED", None)
        else:
            geom.os.environ["WORKSCAPE_MIGRATE_OCCUPIED"] = orig_mig


def test_restore_locks_occupied_skips_unless_migrate():
    orig_env = geom.os.environ.get("WORKSCAPE_OCCUPIED_WS")
    orig_mig = geom.os.environ.get("WORKSCAPE_MIGRATE_OCCUPIED")
    cfg = {"settings": {"activeProfileId": "p"}, "profiles": [{"id": "p", "assignments": [], "workspacePrefs": {}}]}
    geom.os.environ["WORKSCAPE_OCCUPIED_WS"] = "3"
    geom.os.environ.pop("WORKSCAPE_MIGRATE_OCCUPIED", None)
    try:
        skipped = geom.restore_locks_for_workspace("3", cfg, "p")
        assert skipped.get("reason") == "occupied", skipped
        geom.os.environ["WORKSCAPE_MIGRATE_OCCUPIED"] = "1"
        moved = geom.restore_locks_for_workspace("3", cfg, "p")
        assert moved.get("reason") != "occupied", moved
        assert moved.get("workspace") == "3"
    finally:
        if orig_env is None:
            geom.os.environ.pop("WORKSCAPE_OCCUPIED_WS", None)
        else:
            geom.os.environ["WORKSCAPE_OCCUPIED_WS"] = orig_env
        if orig_mig is None:
            geom.os.environ.pop("WORKSCAPE_MIGRATE_OCCUPIED", None)
        else:
            geom.os.environ["WORKSCAPE_MIGRATE_OCCUPIED"] = orig_mig


def test_apply_items_scrolling_vs_stacked_rows():
    metrics = {"x": 8, "y": 34, "w": 1424, "h": 918, "scale": 2}
    items = [
        {"addr": "0x1", "geom": {"x": 0, "y": 0, "w": 1, "h": 0.5}, "px": {"x": 8, "y": 34, "w": 1424, "h": 459}},
        {"addr": "0x2", "geom": {"x": 0, "y": 0.5, "w": 1, "h": 0.5}, "px": {"x": 8, "y": 493, "w": 1424, "h": 459}},
    ]
    boxes = {
        "0x1": {"x": 8, "y": 34, "w": 1424, "h": 900},
        "0x2": {"x": 8, "y": 34, "w": 1424, "h": 18},
    }
    axes = []
    orig_force = geom.force_tiled
    orig_box = geom.actual_box
    orig_resize = geom.resize_relative
    orig_swap = geom.swap_windows
    orig_scroll = geom.workspace_is_scrolling
    orig_place = geom.place_scrolling_columns
    geom.force_tiled = lambda addr: None
    geom.actual_box = lambda addr: dict(boxes[addr])
    geom.resize_relative = lambda addr, dx, dy: axes.append(("resize", addr, dx, dy))
    geom.swap_windows = lambda a, b: axes.append(("swap", a, b))
    geom.workspace_is_scrolling = lambda ws, workspaces=None: False
    geom.place_scrolling_columns = lambda *a, **k: axes.append(("scroll", a, k)) or items
    try:
        geom.apply_items(items, metrics, ws="7")
        assert any(c[0] == "resize" and c[3] != 0 for c in axes), axes
        assert not any(c[0] == "scroll" for c in axes)
        axes.clear()
        geom.workspace_is_scrolling = lambda ws, workspaces=None: True
        geom.apply_items(
            [
                {"addr": "0x1", "geom": {"x": 0, "y": 0, "w": 0.5, "h": 1}, "px": {"x": 8, "y": 34, "w": 712, "h": 918}},
                {"addr": "0x2", "geom": {"x": 0.5, "y": 0, "w": 0.5, "h": 1}, "px": {"x": 720, "y": 34, "w": 712, "h": 918}},
            ],
            metrics,
            ws="6",
        )
        assert any(c[0] == "scroll" for c in axes), axes
    finally:
        geom.force_tiled = orig_force
        geom.actual_box = orig_box
        geom.resize_relative = orig_resize
        geom.swap_windows = orig_swap
        geom.workspace_is_scrolling = orig_scroll
        geom.place_scrolling_columns = orig_place


def test_geom_pixels_master_stack():
    metrics = {"x": 8, "y": 34, "w": 1000, "h": 900, "scale": 1}
    left = geom.geom_pixels({"x": 0, "y": 0, "w": 0.55, "h": 1}, metrics)
    top = geom.geom_pixels({"x": 0.55, "y": 0, "w": 0.45, "h": 0.5}, metrics)
    bot = geom.geom_pixels({"x": 0.55, "y": 0.5, "w": 0.45, "h": 0.5}, metrics)
    assert left["x"] == 8
    assert top["x"] == 8 + 550
    assert bot["y"] == 34 + 450
    assert top["h"] + bot["h"] == 900
    assert left["w"] + top["w"] == 1000


def test_match_app_id_when_title_is_shell_prompt():
    left = {
        "address": "0xL",
        "class": "workscape-dummy-left",
        "title": "user@host:~/project",
        "initialClass": "workscape-dummy-left",
        "initialTitle": "dummy-left",
    }
    right = {
        "address": "0xR",
        "class": "workscape-dummy-right",
        "title": "user@host:~/project",
        "initialClass": "workscape-dummy-right",
        "initialTitle": "dummy-right",
    }
    a_left = {"name": "dummy-left", "exec": "foot --app-id=workscape-dummy-left -T dummy-left"}
    a_right = {"name": "dummy-right", "exec": "foot --app-id=workscape-dummy-right -T dummy-right"}
    used: set[str] = set()
    hit = geom.match_client(a_left, [left, right], used)
    assert hit and hit["address"] == "0xL", hit
    used.add("0xL")
    hit = geom.match_client(a_right, [left, right], used)
    assert hit and hit["address"] == "0xR", hit
    assert geom.exec_app_id(a_left["exec"]) == "workscape-dummy-left"


def test_match_herdr_not_shophawk():
    herdr = {"address": "0x1", "class": "org.omarchy.herdr", "title": "omarchy: master", "initialClass": "org.omarchy.herdr"}
    panel = {"address": "0x2", "class": "org.quickshell", "title": "Shophawk Control", "initialClass": "org.quickshell"}
    used = set()
    a = geom.match_client({"name": "ShopHawk Herdr", "exec": "/home/user/.local/bin/herdr-shophawk"}, [herdr, panel], used)
    assert a and a["address"] == "0x1"
    used.add("0x1")
    b = geom.match_client({"name": "Shophawk Control", "exec": "/home/user/.local/bin/shophawk-panel"}, [herdr, panel], used)
    assert b and b["address"] == "0x2"


def test_set_width_plan_ignores_lockplace():
    profile = {
        "assignments": [{"workspace": 3, "name": "Grok Bot", "exec": "grok-bot", "lockPlace": True, "geom": {"x": 0, "y": 0, "w": 1, "h": 1}}],
        "workspacePrefs": {"3": {"layout": "set-width", "visibleCount": 4, "extras": "around"}},
    }
    plan = geom.lock_plan_for_workspace(profile, "3")
    assert plan["setWidth"] is True
    assert plan["locked"] == []
    assert plan["visibleCount"] == 4


def test_restore_set_width_applies_scrolling_without_locks():
    calls = []
    orig_j, orig_eval = geom.hypr_j, geom.hypr_eval
    geom.hypr_eval = lambda lua: calls.append(lua)
    geom.hypr_j = lambda cmd, cached=False: [] if cmd == "clients" else (
        [{"id": 15, "name": "15", "monitor": "eDP-1"}] if cmd == "workspaces" else (
            [{"name": "eDP-1", "width": 1920, "height": 1080, "scale": 1, "x": 0, "y": 0, "reserved": [0, 0, 0, 0]}]
            if cmd == "monitors" else {"id": 15}
        )
    )
    try:
        cfg = {
            "settings": {"activeProfileId": "p"},
            "profiles": [{
                "id": "p",
                "assignments": [{"workspace": 15, "exec": "foot", "lockPlace": False}],
                "workspacePrefs": {"15": {"layout": "set-width", "visibleCount": 3, "extras": "around"}},
            }],
        }
        result = geom.restore_locks_for_workspace("15", cfg)
        assert result.get("mode") == "set-width", result
        joined = "\n".join(calls)
        assert "layout = \"scrolling\"" in joined
        assert "scrolling_width = 0.3333" in joined
    finally:
        geom.hypr_j, geom.hypr_eval = orig_j, orig_eval


def test_restore_set_width_resizes_locked_assignment_to_frac():
    calls = []
    orig = (
        geom.hypr_j, geom.hypr_eval, geom.activate_workspace_for_layout,
        geom.managed_workspaces, geom.focus_window, geom.layout_msg, geom.layout_msg_on,
        geom.force_scrolling, geom.apply_spawn_width_rule, geom.size_new_scrolling_column, time.sleep,
    )
    clients = [{"address": "0xg", "class": "grok-bot", "workspace": {"id": 3}, "at": [10, 36], "size": [1420, 914], "floating": False}]
    geom.hypr_j = lambda cmd, cached=False: (
        clients if cmd == "clients" else (
            [{"id": 3, "name": "3", "monitor": "eDP-1", "tiledLayout": "scrolling"}] if cmd == "workspaces" else (
                [{"name": "eDP-1", "width": 2880, "height": 1920, "scale": 2, "x": 0, "y": 0, "reserved": [0, 26, 0, 0]}]
                if cmd == "monitors" else {"id": 3}
            )
        )
    )
    geom.hypr_eval = lambda lua: calls.append(lua)
    geom.activate_workspace_for_layout = lambda ws: True
    geom.managed_workspaces = lambda profile=None: {"3"}
    geom.focus_window = lambda addr: calls.append(("focus", addr))
    geom.layout_msg = lambda msg: calls.append(msg)
    geom.layout_msg_on = lambda ws, msg: calls.append(msg)
    geom.force_scrolling = lambda *a, **k: calls.append(("force_scrolling", k))
    orig_size = geom.size_new_scrolling_column

    def size(ws, addr, vis, set_width=False, **k):
        calls.append(("size", ws, addr, vis, set_width))

    geom.size_new_scrolling_column = size
    time.sleep = lambda _s: None
    try:
        cfg = {
            "settings": {"activeProfileId": "p"},
            "profiles": [{
                "id": "p",
                "assignments": [{"workspace": 3, "name": "Grok Bot", "exec": "grok-bot", "lockPlace": True, "geom": {"x": 0, "y": 0, "w": 1, "h": 1}}],
                "workspacePrefs": {"3": {"layout": "set-width", "visibleCount": 4, "extras": "around"}},
            }],
        }
        result = geom.restore_locks_for_workspace("3", cfg)
        assert result.get("mode") == "set-width", result
        assert ("size", "3", "0xg", 4, True) in calls
        assert not any(isinstance(c, tuple) and c[0] == "force_scrolling" and c[1].get("fill_one") is True for c in calls if isinstance(c, tuple) and c[0] == "force_scrolling")
    finally:
        (
            geom.hypr_j, geom.hypr_eval, geom.activate_workspace_for_layout,
            geom.managed_workspaces, geom.focus_window, geom.layout_msg, geom.layout_msg_on,
            geom.force_scrolling, geom.apply_spawn_width_rule, geom.size_new_scrolling_column, time.sleep,
        ) = orig
        geom.size_new_scrolling_column = orig_size


def test_size_new_scrolling_column_set_width_resizes_every_column():
    calls = []
    clients = [
        {"address": "0xaa", "class": "workscape-dummy-setwidth", "floating": False, "workspace": {"id": 15}, "at": [10, 36], "size": [1420, 900]},
        {"address": "0xbb", "class": "workscape-dummy-extra", "floating": False, "workspace": {"id": 15}, "at": [726, 36], "size": [704, 900]},
    ]
    orig = (
        geom.hypr_j,
        geom.layout_msg,
        geom.layout_msg_on,
        geom.activate_workspace_for_layout,
        geom.ensure_layout_workspace,
        geom.managed_workspaces,
        geom.focus_window,
        geom.restamp_scrolling_default,
        geom.load_config,
        time.sleep,
    )
    geom.hypr_j = lambda cmd, cached=False: (
        clients if cmd == "clients" else (
            [{"id": 15, "name": "15", "monitor": "eDP-1", "tiledLayout": "scrolling"}] if cmd == "workspaces" else (
                [{"name": "eDP-1", "id": 0, "width": 1920, "height": 1080, "scale": 1, "x": 0, "y": 0}] if cmd == "monitors" else {"id": 15}
            )
        )
    )
    geom.layout_msg = lambda msg: calls.append(msg)
    geom.layout_msg_on = lambda ws, msg: calls.append(msg)
    geom.activate_workspace_for_layout = lambda ws: True
    geom.ensure_layout_workspace = lambda ws: True
    geom.managed_workspaces = lambda profile=None: {"15"}
    geom.focus_window = lambda addr: calls.append(("focus", addr))
    geom.restamp_scrolling_default = lambda *a, **k: None
    geom.load_config = lambda path: {"settings": {"activeProfileId": "p"}, "profiles": [{"id": "p", "assignments": [], "workspacePrefs": {"15": {"layout": "set-width", "visibleCount": 3}}}]}
    time.sleep = lambda _s: None
    try:
        geom.size_new_scrolling_column("15", "0xbb", 3, set_width=True)
    finally:
        (
            geom.hypr_j,
            geom.layout_msg,
            geom.layout_msg_on,
            geom.activate_workspace_for_layout,
            geom.ensure_layout_workspace,
            geom.managed_workspaces,
            geom.focus_window,
            geom.restamp_scrolling_default,
            geom.load_config,
            time.sleep,
        ) = orig
    assert "colresize all 0.3333" in calls, calls
    assert not any(isinstance(c, tuple) and c and c[0] == "focus" for c in calls), calls


def test_size_new_scrolling_column_set_width_skips_inactive():
    calls = []
    orig = (
        geom.hypr_j,
        geom.layout_msg,
        geom.layout_msg_on,
        geom.ensure_layout_workspace,
        geom.activate_workspace_for_layout,
        geom.managed_workspaces,
        geom.focus_window,
        geom.restamp_scrolling_default,
        geom.load_config,
        time.sleep,
    )
    geom.hypr_j = lambda cmd, cached=False: (
        [{"address": "0xbb", "floating": False, "workspace": {"id": 3}}] if cmd == "clients" else (
            [{"id": 3, "tiledLayout": "scrolling"}] if cmd == "workspaces" else {"id": 6}
        )
    )
    geom.layout_msg = lambda msg: calls.append(msg)
    geom.layout_msg_on = lambda ws, msg: calls.append(("on", ws, msg))
    geom.ensure_layout_workspace = lambda ws: calls.append(("activate", ws)) or True
    geom.activate_workspace_for_layout = lambda ws: calls.append(("activate", ws)) or True
    geom.managed_workspaces = lambda profile=None: {"3"}
    geom.focus_window = lambda addr: calls.append(("focus", addr))
    geom.restamp_scrolling_default = lambda *a, **k: None
    geom.load_config = lambda path: {"settings": {"activeProfileId": "p"}, "profiles": [{"id": "p", "assignments": [], "workspacePrefs": {"3": {"layout": "set-width", "visibleCount": 2}}}]}
    time.sleep = lambda _s: None
    try:
        geom.size_new_scrolling_column("3", "0xbb", 2, set_width=True)
    finally:
        (
            geom.hypr_j,
            geom.layout_msg,
            geom.layout_msg_on,
            geom.ensure_layout_workspace,
            geom.activate_workspace_for_layout,
            geom.managed_workspaces,
            geom.focus_window,
            geom.restamp_scrolling_default,
            geom.load_config,
            time.sleep,
        ) = orig
    assert calls == [], calls


def test_set_size_lock_is_noop():
    calls = []
    orig = geom.hypr_eval
    geom.hypr_eval = lambda lua: calls.append(lua)
    try:
        geom.set_size_lock("0xabc", 1229, 1034)
        assert calls == []
    finally:
        geom.hypr_eval = orig


def test_clear_size_lock_is_noop():
    calls = []
    orig = geom.hypr_eval
    geom.hypr_eval = lambda lua: calls.append(lua)
    try:
        geom.clear_size_lock("0xabc")
        assert calls == []
    finally:
        geom.hypr_eval = orig


def test_force_tiled_uses_off_not_toggle():
    calls = []
    orig = (geom.hypr_eval, geom.client_by_addr, geom.cache_clear, geom.actual_box, geom.resize_relative)
    geom.hypr_eval = lambda lua: calls.append(lua)
    geom.cache_clear = lambda: None
    geom.client_by_addr = lambda addr: {"address": addr, "floating": False}
    geom.actual_box = lambda addr: {"x": 10, "y": 36, "w": 1420, "h": 914}
    geom.resize_relative = lambda addr, dx, dy: calls.append(("resize", dx, dy))
    try:
        geom.force_tiled("0xabc")
        joined = "\n".join(c for c in calls if isinstance(c, str))
        assert 'action = "off"' in joined
        assert 'action = "toggle"' not in joined
        assert 'action = "unset"' not in joined
        assert not any(c[0] == "resize" for c in calls if isinstance(c, tuple))
    finally:
        geom.hypr_eval, geom.client_by_addr, geom.cache_clear, geom.actual_box, geom.resize_relative = orig


def test_force_tiled_shrinks_stuck_float():
    calls = []
    orig = (geom.hypr_eval, geom.client_by_addr, geom.cache_clear, geom.actual_box, geom.resize_relative)
    geom.hypr_eval = lambda lua: calls.append(lua)
    geom.cache_clear = lambda: None
    geom.client_by_addr = lambda addr: {"address": addr, "floating": True}
    geom.actual_box = lambda addr: {"x": 10, "y": 36, "w": 1420, "h": 914}
    geom.resize_relative = lambda addr, dx, dy: calls.append(("resize", dx, dy))
    try:
        geom.force_tiled("0xabc")
        joined = "\n".join(c for c in calls if isinstance(c, str))
        assert 'action = "off"' in joined
        assert 'action = "toggle"' not in joined
        assert ("resize", -64, -64) in calls
        assert joined.count('action = "off"') >= 2
    finally:
        geom.hypr_eval, geom.client_by_addr, geom.cache_clear, geom.actual_box, geom.resize_relative = orig


def test_ensure_floating_uses_on_not_toggle():
    calls = []
    orig = (geom.hypr_eval, geom.client_by_addr, geom.cache_clear)
    geom.hypr_eval = lambda lua: calls.append(lua)
    geom.cache_clear = lambda: None
    geom.client_by_addr = lambda addr: {"address": addr, "floating": False}
    try:
        geom.ensure_floating("0xabc", True)
        joined = "\n".join(calls)
        assert 'action = "on"' in joined
        assert 'action = "toggle"' not in joined
    finally:
        geom.hypr_eval, geom.client_by_addr, geom.cache_clear = orig


def test_covers_work_area_and_fill_skips_float():
    metrics = {"x": 10, "y": 36, "w": 1420, "h": 914}
    assert geom.covers_work_area({"x": 10, "y": 36, "w": 1420, "h": 914}, metrics)
    assert not geom.covers_work_area({"x": 10, "y": 36, "w": 704, "h": 914}, metrics)
    resizes = []
    orig = (geom.force_tiled, geom.client_by_addr, geom.actual_box, geom.resize_relative, geom.cache_clear)
    geom.force_tiled = lambda addr: None
    geom.cache_clear = lambda: None
    geom.client_by_addr = lambda addr: {"address": addr, "floating": True}
    geom.actual_box = lambda addr: {"x": 10, "y": 36, "w": 700, "h": 500}
    geom.resize_relative = lambda addr, dx, dy: resizes.append((dx, dy))
    try:
        geom.fill_window_to_monitor("0xabc", metrics)
        assert resizes == []
    finally:
        geom.force_tiled, geom.client_by_addr, geom.actual_box, geom.resize_relative, geom.cache_clear = orig


def test_tile_covering_floats_skips_dialogs():
    tiled = []
    clients = [
        {"address": "0xbig", "floating": True, "workspace": {"id": 8}, "at": [10, 36], "size": [1420, 914]},
        {"address": "0xdlg", "floating": True, "workspace": {"id": 8}, "at": [200, 200], "size": [875, 600]},
        {"address": "0xtile", "floating": False, "workspace": {"id": 8}, "at": [10, 36], "size": [704, 914]},
    ]
    orig = (
        geom.hypr_j, geom.force_tiled, geom.cache_clear, geom.layout_metrics,
        geom.monitor_for_workspace, geom.clients_on_workspace, geom.actual_box,
    )
    geom.cache_clear = lambda: None
    geom.hypr_j = lambda cmd, cached=False: (
        [{"name": "eDP-1"}] if cmd == "monitors" else [{"id": 8}]
    )
    geom.monitor_for_workspace = lambda ws, mons, spaces: {"name": "eDP-1"}
    geom.layout_metrics = lambda mon: {"x": 10, "y": 36, "w": 1420, "h": 914}
    geom.clients_on_workspace = lambda ws: clients
    geom.actual_box = lambda addr: next(
        ({"x": c["at"][0], "y": c["at"][1], "w": c["size"][0], "h": c["size"][1]} for c in clients if c["address"] == addr),
        None,
    )
    geom.force_tiled = lambda addr: tiled.append(addr)
    try:
        got = geom.tile_covering_floats("8")
        assert got == ["0xbig"]
        assert tiled == ["0xbig"]
    finally:
        (
            geom.hypr_j, geom.force_tiled, geom.cache_clear, geom.layout_metrics,
            geom.monitor_for_workspace, geom.clients_on_workspace, geom.actual_box,
        ) = orig


def test_exec_silent_lua_does_not_focus():
    lua = geom.exec_silent_lua("foot --app-id=workscape-dummy-left -T dummy-left", "12", "eDP-1")
    assert "no_initial_focus = true" in lua
    assert 'workspace = "12 silent"' in lua
    assert 'monitor = "eDP-1 silent"' in lua
    assert "dsp.focus" not in lua
    assert "hl.dispatch(hl.dsp.exec_cmd(" in lua


def test_layout_msg_skips_unmanaged_workspace():
    calls = []
    orig_j, orig_eval, orig_m = geom.hypr_j, geom.hypr_eval, geom.managed_workspaces
    geom.managed_workspaces = lambda: {"1", "2", "12"}
    geom.hypr_eval = lambda lua: calls.append(lua)

    def fake_j(cmd, cached=False):
        if cmd == "activeworkspace":
            return {"id": 5}
        if cmd == "activewindow":
            return {"workspace": {"id": 5}}
        return {}

    geom.hypr_j = fake_j
    try:
        geom.layout_msg("colresize 0.5")
        assert calls == []
        geom.hypr_j = lambda cmd, cached=False: {"id": 12} if cmd == "activeworkspace" else {"workspace": {"id": 12}}
        geom.layout_msg("colresize 0.3333")
        assert any("colresize 0.3333" in c or "layout(" in c for c in calls), calls
    finally:
        geom.hypr_j, geom.hypr_eval, geom.managed_workspaces = orig_j, orig_eval, orig_m


def test_pin_workspace_silent_does_not_focus():
    calls = []
    orig = geom.hypr_eval
    geom.hypr_eval = lambda lua: calls.append(lua)
    try:
        geom.pin_workspace_silent("12", "DVI-I-2")
        joined = "\n".join(calls)
        assert "workspace.move" in joined
        assert "dsp.focus" not in joined
    finally:
        geom.hypr_eval = orig


def test_match_outlook_prefers_full_pane():
    extra = {
        "address": "0xnew",
        "class": "brave-outlook.office.com__mail_-Default",
        "title": "Message",
        "at": [740, 36],
        "size": [704, 914],
    }
    main = {
        "address": "0xmain",
        "class": "brave-outlook.office.com__mail_-Default",
        "title": "Mail - Outlook",
        "at": [10, 36],
        "size": [1420, 914],
    }
    a = {"name": "Outlook", "exec": "omarchy-launch-webapp 'https://outlook.office.com/mail/'"}
    hit = geom.match_client(a, [extra, main], set())
    assert hit and hit["address"] == "0xmain", hit


if __name__ == "__main__":
    test_layout_metrics_scale()
    test_geom_pixels()
    test_box_to_geom()
    test_monitor_for_client_uses_id()
    test_lock_plan_and_assignment()
    test_close_enough_and_fallback()
    test_column_width_frac()
    test_managed_workspaces()
    test_apply_scrolling_globals_sets_hypr_config()
    test_force_scrolling_not_persistent_by_default()
    test_apply_config_skips_occupied()
    test_apply_config_migrates_occupied_on_profile_change()
    test_restore_locks_occupied_skips_unless_migrate()
    test_occupied_skip_allows_two_lock_split()
    test_match_saved_class_when_exec_is_generic_foot()
    test_apply_items_scrolling_vs_stacked_rows()
    test_geom_pixels_master_stack()
    test_match_app_id_when_title_is_shell_prompt()
    test_match_herdr_not_shophawk()
    test_match_outlook_prefers_full_pane()
    test_set_size_lock_is_noop()
    test_clear_size_lock_is_noop()
    test_force_tiled_uses_off_not_toggle()
    test_force_tiled_shrinks_stuck_float()
    test_ensure_floating_uses_on_not_toggle()
    test_covers_work_area_and_fill_skips_float()
    test_tile_covering_floats_skips_dialogs()
    test_exec_silent_lua_does_not_focus()
    test_layout_msg_skips_unmanaged_workspace()
    test_pin_workspace_silent_does_not_focus()
    print("geom.test.py ok")
