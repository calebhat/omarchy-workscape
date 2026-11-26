#!/usr/bin/env python3
"""Omarchy 4.5 workspace mode files. Does not touch the real state dir."""
import os
import stat
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODES = SourceFileLoader("modes", str(ROOT / "scripts" / "modes")).load_module()


def _use(state: Path):
    os.environ["XDG_STATE_HOME"] = str(state)
    os.environ["WORKSCAPE_SYNC_MODES"] = "1"
    calls = []

    def record(cmd, timeout=3.0):
        calls.append(cmd)
        return 0

    MODES.SAFE.bounded_run = record
    return calls


def test_sync_writes_and_clears(tmp_path: Path):
    state = tmp_path / "state"
    layouts = state / "omarchy" / "workspace-layouts"
    layouts.mkdir(parents=True)
    (layouts / "default.lua").write_text('o.workspace_mode({ default = "dwindle" })\n')
    calls = _use(state)

    MODES.sync_workspace_mode("22", "scrolling")
    text = (layouts / "22.lua").read_text()
    assert text == 'o.workspace_mode({ workspace = "22", mode = "scrolling" })\n'
    assert any("scrolling" in c[-1] for c in calls)
    assert calls[-1] == ["omarchy-shell", "omarchy.dock", "refresh"]

    before = len(calls)
    MODES.sync_workspace_mode("22", "dwindle")
    assert not (layouts / "22.lua").exists()
    assert any("dwindle" in c[-1] for c in calls[before:])
    assert calls[-1] == ["omarchy-shell", "omarchy.dock", "refresh"]

    after_dwindle = len(calls)
    MODES.sync_workspace_mode("22", "master")
    assert len(calls) == after_dwindle
    assert not (layouts / "22.lua").exists()


def test_sync_off_does_not_write(tmp_path: Path):
    state = tmp_path / "state"
    os.environ["XDG_STATE_HOME"] = str(state)
    os.environ.pop("WORKSCAPE_SYNC_MODES", None)
    MODES.sync_workspace_mode("2", "scrolling")
    assert not (state / "omarchy" / "workspace-layouts").exists()


def test_refuses_symlink_dir(tmp_path: Path):
    state = tmp_path / "state"
    real = tmp_path / "elsewhere"
    real.mkdir(parents=True)
    link_parent = state / "omarchy"
    link_parent.mkdir(parents=True)
    (link_parent / "workspace-layouts").symlink_to(real, target_is_directory=True)
    _use(state)
    MODES.sync_workspace_mode("4", "scrolling")
    assert list(real.iterdir()) == []
    assert stat.S_ISLNK((link_parent / "workspace-layouts").lstat().st_mode)


if __name__ == "__main__":
    import tempfile
    os.environ.pop("WORKSCAPE_SYNC_MODES", None)
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        test_sync_writes_and_clears(root / "a")
        test_sync_off_does_not_write(root / "b")
        test_refuses_symlink_dir(root / "c")
    print("modes ok")
