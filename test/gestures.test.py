#!/usr/bin/env python3
import os
from importlib.machinery import SourceFileLoader
from pathlib import Path

g = SourceFileLoader("gestures", str(Path(__file__).resolve().parent.parent / "scripts/gestures")).load_module()


def test_skip_empty_uses_m():
    lua = g.render_lua({"skipEmpty": True, "workspaceSwipe": True, "fingers": 3})
    assert "workspace_swipe_use_r = false" in lua
    assert "workspace_swipe_invert = true" in lua
    assert 'action = "workspace"' in lua


def test_include_empty_uses_r():
    lua = g.render_lua({"skipEmpty": False, "keyboard": True})
    assert "workspace_swipe_use_r = true" in lua
    assert 'workspace = "r-1"' in lua
    assert 'workspace = "r+1"' in lua


def test_occupied_keyboard():
    lua = g.render_lua({"skipEmpty": True, "keyboard": True})
    assert 'workspace = "e-1"' in lua
    assert "SUPER + comma" in lua


def test_four_fingers_sets_four():
    lua = g.render_lua({"fingers": 4, "workspaceSwipe": True})
    assert 'fingers = 4, direction = "horizontal", action = "workspace"' in lua
    assert "WORKSCAPE_SWIPE_FINGERS = 4" in lua
    assert 'action = "unset"' not in lua


def test_scratchpad_and_touch():
    lua = g.render_lua({"scratchpadSwipe": True, "scratchpadFingers": 4, "touch": True})
    assert "workspace_swipe_touch = true" in lua
    assert 'workspace_name = "scratchpad"' in lua


def test_ensure_hyprland_require(tmp_path):
    os.environ["WORKSCAPE_STATE_DIR"] = str(tmp_path / "state")
    (tmp_path / "state").mkdir()
    lua = tmp_path / "hyprland.lua"
    lua.write_text("-- Learn how to configure Hyprland\nrequire(\"default.hypr.omarchy\")\n")
    try:
        assert g.ensure_hyprland_require(tmp_path) is True
        text = lua.read_text()
        assert 'pcall(require, "hypr.workscape-gestures")' in text
        assert g.ensure_hyprland_require(tmp_path) is False
    finally:
        os.environ.pop("WORKSCAPE_STATE_DIR", None)


def test_write_registers_workspace_swipe(tmp_path, monkeypatch=None):
    hypr = tmp_path / "hypr"
    hypr.mkdir()
    state = tmp_path / "state"
    state.mkdir(exist_ok=True)
    os.environ["WORKSCAPE_STATE_DIR"] = str(state)
    (hypr / "hyprland.lua").write_text("-- user hyprland\n")
    cfg = {
        "settings": {
            "persistHyprGestures": False,
            "gestures": {"workspaceSwipe": True, "fingers": 3},
        }
    }
    orig_eval = g.hypr_eval
    g.hypr_eval = lambda lua: None
    try:
        out = g.write_and_apply(cfg, hypr_dir=str(hypr / "workscape-gestures.lua"))
        assert out["ok"] is True
        assert not (hypr / "workscape-gestures.lua").exists()
        assert 'pcall(require, "hypr.workscape-gestures")' not in (hypr / "hyprland.lua").read_text()
        cfg["settings"]["persistHyprGestures"] = True
        out = g.write_and_apply(cfg, hypr_dir=str(hypr / "workscape-gestures.lua"))
        written = (hypr / "workscape-gestures.lua").read_text()
        assert 'action = "workspace"' in written
        assert 'fingers = 3' in written
        assert 'pcall(require, "hypr.workscape-gestures")' in (hypr / "hyprland.lua").read_text()
        (hypr / "hyprland.lua").write_text(
            (hypr / "hyprland.lua").read_text() + "-- later user edit\n"
        )
        restored = g.restore_hypr_persist(str(hypr))
        assert restored["ok"] is True
        assert restored["hyprland"] == "stripped"
        assert restored["backup"] == "kept"
        text = (hypr / "hyprland.lua").read_text()
        assert 'pcall(require, "hypr.workscape-gestures")' not in text
        assert "-- later user edit" in text
        assert (hypr / "hyprland.lua.workscape.bak").exists()
        assert not (hypr / "workscape-gestures.lua").exists()
        cfg["settings"]["persistHyprGestures"] = True
        g.write_and_apply(cfg, hypr_dir=str(hypr / "workscape-gestures.lua"))
        edited = (hypr / "workscape-gestures.lua").read_text() + "\n-- user tweak\n"
        (hypr / "workscape-gestures.lua").write_text(edited)
        conflict = g.restore_hypr_persist(str(hypr))
        assert conflict["ok"] is False
        assert conflict["files"].get("workscape-gestures.lua") == "conflict"
        assert (hypr / "workscape-gestures.lua").exists()
    finally:
        g.hypr_eval = orig_eval
        os.environ.pop("WORKSCAPE_STATE_DIR", None)


def test_keyboard_binds_reach_hyprland_without_persist(tmp_path):
    """The generated file only reaches Hyprland when the user opts into
    persisting it, so the workspace keybinds have to be registered live the way
    the swipe gesture already is. Otherwise turning the toggle on writes a file
    nobody reads and SUPER+,/. keep whatever they were bound to."""
    tmp_path.mkdir(parents=True, exist_ok=True)
    hypr = tmp_path / "hypr"
    hypr.mkdir()
    state = tmp_path / "state"
    state.mkdir(exist_ok=True)
    os.environ["WORKSCAPE_STATE_DIR"] = str(state)
    os.environ["XDG_STATE_HOME"] = str(state)
    (hypr / "hyprland.lua").write_text("-- user hyprland\n")
    cfg = {
        "settings": {
            "persistHyprGestures": False,
            "gestures": {"workspaceSwipe": False, "keyboard": True, "skipEmpty": True},
        }
    }
    seen = []
    orig_eval = g.hypr_eval
    g.hypr_eval = lambda lua: seen.append(lua)
    try:
        g.write_and_apply(cfg, hypr_dir=str(hypr / "workscape-gestures.lua"))
        assert not (hypr / "workscape-gestures.lua").exists()
        joined = "\n".join(seen)
        assert 'o.bind("SUPER + comma"' in joined, "previous-workspace bind never reached Hyprland"
        assert 'o.bind("SUPER + period"' in joined, "next-workspace bind never reached Hyprland"
        assert 'workspace = "e-1"' in joined and 'workspace = "e+1"' in joined
        assert 'hl.unbind("SUPER + comma")' in joined, "the old binding is not released"
        # Turning it back off must release the keys rather than leave them bound.
        seen.clear()
        cfg["settings"]["gestures"]["keyboard"] = False
        g.write_and_apply(cfg, hypr_dir=str(hypr / "workscape-gestures.lua"))
        joined = "\n".join(seen)
        assert 'o.bind("SUPER + comma"' not in joined, "binds re-registered while disabled"
        assert 'hl.unbind("SUPER + comma")' in joined, "keys stay bound after disabling"
        # Never take SUPER+, from someone who has this switched off: it is
        # Omarchy's dismiss-notification bind.
        seen.clear()
        state2 = tmp_path / "state2"
        state2.mkdir(exist_ok=True)
        os.environ["XDG_STATE_HOME"] = str(state2)
        g.write_and_apply(cfg, hypr_dir=str(hypr / "workscape-gestures.lua"))
        assert 'hl.unbind("SUPER + comma")' not in "\n".join(seen), \
            "released a key the user never handed over"
    finally:
        g.hypr_eval = orig_eval
        os.environ.pop("WORKSCAPE_STATE_DIR", None)
        os.environ.pop("XDG_STATE_HOME", None)


def test_restore_leaves_user_owned_files(tmp_path):
    os.environ["WORKSCAPE_STATE_DIR"] = str(tmp_path / "state")
    (tmp_path / "state").mkdir(parents=True, exist_ok=True)
    hypr = tmp_path / "hypr"
    hypr.mkdir(parents=True)
    (hypr / "hyprland.lua").write_text(
        'require("default.hypr.omarchy")\n'
        'pcall(require, "hypr.workscape-gestures")\n'
    )
    (hypr / "workscape-gestures.lua").write_text("-- my custom swipe\nhl.config({})\n")
    (hypr / "workscape-binds.lua").write_text("-- not ours\n")
    out = g.restore_hypr_persist(str(hypr))
    assert out["ok"] is True
    assert out["hyprland"] == "skipped"
    text = (hypr / "hyprland.lua").read_text()
    assert 'pcall(require, "hypr.workscape-gestures")' in text
    assert (hypr / "workscape-gestures.lua").read_text().startswith("-- my custom swipe")
    assert (hypr / "workscape-binds.lua").exists()
    os.environ.pop("WORKSCAPE_STATE_DIR", None)


def test_resolve_profile_vs_global():
    cfg = {
        "settings": {"gestureSource": "global", "gestures": {"skipEmpty": False}, "activeProfileId": "p"},
        "profiles": [{"id": "p", "gestures": {"skipEmpty": True}}],
    }
    assert g.resolve_gestures(cfg)["skipEmpty"] is False
    cfg["settings"]["gestureSource"] = "profile"
    assert g.resolve_gestures(cfg)["skipEmpty"] is True
    del cfg["settings"]["gestureSource"]
    assert g.resolve_gestures(cfg)["skipEmpty"] is False


if __name__ == "__main__":
    test_skip_empty_uses_m()
    test_four_fingers_sets_four()
    test_include_empty_uses_r()
    test_occupied_keyboard()
    test_scratchpad_and_touch()
    test_resolve_profile_vs_global()
    import tempfile
    from pathlib import Path as P
    with tempfile.TemporaryDirectory() as d:
        test_ensure_hyprland_require(P(d))
        test_write_registers_workspace_swipe(P(d))
        test_keyboard_binds_reach_hyprland_without_persist(P(d) / "kb")
        test_restore_leaves_user_owned_files(P(d) / "keep")
    print("gestures.test.py ok")
