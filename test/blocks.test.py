#!/usr/bin/env python3
"""Per-monitor workspace ids. Does not talk to Hyprland."""
import os
from importlib.machinery import SourceFileLoader
from pathlib import Path

BLOCKS = SourceFileLoader(
    "workscape_blocks",
    str(Path(__file__).resolve().parent.parent / "scripts" / "blocks"),
).load_module()


def test_block_zero_keeps_the_slot(tmp_path):
    state = tmp_path / "monitor-workspaces"
    state.write_text("0\teDP-1\tBOE PANEL\n1\t\tHP Inc. HP E24 LEFT\n2\t\tHP Inc. HP E24 RIGHT\n")
    os.environ["XDG_STATE_HOME"] = str(tmp_path.parent)
    # state_path is XDG_STATE_HOME/omarchy/monitor-workspaces
    omarchy = tmp_path / "omarchy"
    omarchy.mkdir()
    (omarchy / "monitor-workspaces").write_text(state.read_text())
    os.environ["XDG_STATE_HOME"] = str(tmp_path)
    try:
        assert BLOCKS.id_for_connector("2", "eDP-1") == "2"
        assert BLOCKS.id_for_connector("1", "eDP-1") == "1"
        rows = BLOCKS.load_rows()
        assert BLOCKS.block_for_identity("HP Inc. HP E24 LEFT", "", rows) == 1
        assert BLOCKS.block_for_identity("HP Inc. HP E24 RIGHT", "", rows) == 2
        cfg = {
            "monitors": [
                {"id": "laptop", "description": "BOE PANEL", "name": "eDP-1"},
                {"id": "desk-left", "description": "HP Inc. HP E24 LEFT", "name": ""},
                {"id": "desk-right", "description": "HP Inc. HP E24 RIGHT", "name": ""},
            ]
        }
        profile = {
            "workspaceMonitors": {"1": "desk-left", "2": "desk-right", "9": "laptop"},
            "assignments": [{"workspace": "1", "name": "Browser"}, {"workspace": "9", "name": "Mail"}],
            "workspacePrefs": {"1": {"layout": "dwindle"}, "9": {"layout": "scrolling"}},
        }
        assert BLOCKS.id_for_profile_slot(cfg, profile, "1") == "11"
        assert BLOCKS.id_for_profile_slot(cfg, profile, "2") == "22"
        assert BLOCKS.id_for_profile_slot(cfg, profile, "9") == "9"
        assert BLOCKS.id_for_profile_slot(cfg, profile, "11") == "11"
        copied = BLOCKS.translate_profile(cfg, profile)
        assert copied["assignments"][0]["workspace"] == "11"
        assert copied["assignments"][1]["workspace"] == "9"
        assert copied["workspacePrefs"]["11"]["layout"] == "dwindle"
        assert profile["assignments"][0]["workspace"] == "1"
    finally:
        os.environ.pop("XDG_STATE_HOME", None)


def test_missing_state_keeps_literal_ids(tmp_path, monkeypatch=None):
    os.environ["XDG_STATE_HOME"] = str(tmp_path)
    try:
        assert BLOCKS.id_for_connector("4", "DVI-I-9") == "4"
        assert BLOCKS.id_for_profile_slot(
            {"monitors": [{"id": "laptop", "description": "gone", "name": "eDP-1"}]},
            {"workspaceMonitors": {"1": "laptop"}},
            "1",
        ) == "1"
    finally:
        os.environ.pop("XDG_STATE_HOME", None)


def test_internal_connector_without_a_row_is_block_zero():
    assert BLOCKS.global_id(3, 0) == 3
    assert BLOCKS.global_id(1, 1) == 11
    assert BLOCKS.global_id(4, 2) == 24


if __name__ == "__main__":
    import tempfile
    with tempfile.TemporaryDirectory() as raw:
        test_block_zero_keeps_the_slot(Path(raw))
    with tempfile.TemporaryDirectory() as raw:
        test_missing_state_keeps_literal_ids(Path(raw))
    test_internal_connector_without_a_row_is_block_zero()
    print("blocks ok")
