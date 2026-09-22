#!/usr/bin/env python3
"""monitorslua: the marked block in monitors.lua is rewritten, never more."""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = str(ROOT / "scripts/monitorslua")

USER = """-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
local omarchy_monitor_scale = 1.25
hl.env("GDK_SCALE", tostring(1))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
-- user note at the bottom
"""

R1 = 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.5 })'
R2 = 'hl.monitor({ output = "DP-4", mode = "3840x2160@60", position = "394x1728", scale = 1.5 })'


def run(*args, path):
    return subprocess.run([sys.executable, SCRIPT, *args, "--file", str(path)], capture_output=True, text=True)


def test_lifecycle():
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "monitors.lua"
        f.write_text(USER)
        out = run("--write", f"{R1};{R2}", path=f)
        assert out.returncode == 0, out
        text = f.read_text()
        assert "local omarchy_monitor_scale = 1.25" in text, text
        assert "-- user note at the bottom" in text, text
        assert text.count(R1) == 1 and text.count(R2) == 1, text
        # Rewrite replaces, not appends.
        run("--write", R1, path=f)
        text = f.read_text()
        assert text.count(R1) == 1 and R2 not in text, text
        # Print reflects current rules.
        out = run("--print", path=f)
        assert out.stdout.strip() == R1, out
        # Empty write removes the whole block, user content intact.
        run("--write", "", path=f)
        text = f.read_text()
        assert "workscape" not in text and R1 not in text, text
        assert "-- user note at the bottom" in text, text
        assert run("--print", path=f).stdout.strip() == ""


def test_rejects_unsafe_rules():
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "monitors.lua"
        f.write_text(USER)
        bad = 'hl.monitor({ output = "x", mode = "preferred", position = "auto", scale = 1 }) or os.exit(1) '
        out = run("--write", bad, path=f)
        assert out.returncode == 1, out
        assert "workscape" not in f.read_text()
        good = 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2 })'
        out = run("--write", f"{good};garbage", path=f)
        assert out.returncode == 1, out


if __name__ == "__main__":
    test_lifecycle()
    test_rejects_unsafe_rules()
    print("monitorslua.test.py ok")
