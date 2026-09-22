#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import signal
import stat
import subprocess
import sys
import time
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATEIO = ROOT / "scripts" / "stateio"
SAFE = SourceFileLoader("hyprsafe", str(ROOT / "scripts" / "hyprsafe")).load_module()


def run(env, args, stdin=b"", timeout=8):
    proc = subprocess.run(
        ["python3", str(STATEIO), *args],
        input=stdin,
        capture_output=True,
        timeout=timeout,
        env=env,
    )
    return proc


def test_helper_env_disables_bytecode():
    sio = SourceFileLoader("stateio", str(STATEIO)).load_module()
    env = sio.helper_env()
    assert env["PYTHONDONTWRITEBYTECODE"] == "1"


def test_write_read_roundtrip(tmp: Path):
    env = os.environ.copy()
    env["WORKSCAPE_STATE_DIR"] = str(tmp)
    payload = json.dumps({"version": 2, "settings": {}, "profiles": []}).encode()
    r = run(env, ["write-config"], stdin=payload)
    assert r.returncode == 0, r.stderr
    r = run(env, ["ensure-config"])
    assert r.returncode == 0
    obj = json.loads(r.stdout.decode())
    assert obj["version"] == 2
    st = os.stat(tmp / "config.json")
    assert stat.S_ISREG(st.st_mode)
    assert st.st_mode & 0o077 == 0


def test_symlink_config_rejected(tmp: Path):
    env = os.environ.copy()
    env["WORKSCAPE_STATE_DIR"] = str(tmp)
    run(env, ["ensure-config"])
    target = tmp / "other"
    target.write_text("secret\n")
    cfg = tmp / "config.json"
    cfg.unlink()
    cfg.symlink_to(target)
    r = run(env, ["write-config"], stdin=b'{"ok":true}')
    assert r.returncode != 0
    assert target.read_text() == "secret\n"


def test_fifo_config_rejected(tmp: Path):
    env = os.environ.copy()
    env["WORKSCAPE_STATE_DIR"] = str(tmp)
    tmp.mkdir(parents=True, exist_ok=True)
    os.mkfifo(tmp / "config.json")
    r = run(env, ["write-config"], stdin=b'{"ok":true}', timeout=3)
    assert r.returncode != 0


def test_parent_symlink_rejected(tmp: Path):
    real = tmp / "real"
    real.mkdir()
    link = tmp / "link"
    link.symlink_to(real)
    env = os.environ.copy()
    env["WORKSCAPE_STATE_DIR"] = str(link)
    r = run(env, ["write-config"], stdin=b'{"ok":true}')
    assert r.returncode != 0


def test_oversized_config(tmp: Path):
    env = os.environ.copy()
    env["WORKSCAPE_STATE_DIR"] = str(tmp)
    blob = b"{" + (b"x" * (SAFE.MAX_CONFIG_BYTES + 8))
    r = run(env, ["write-config"], stdin=blob)
    assert r.returncode != 0
    assert b"too large" in r.stderr


def test_short_write_leaves_dest(tmp: Path):
    env = os.environ.copy()
    env["WORKSCAPE_STATE_DIR"] = str(tmp)
    first = b'{"keep":true}'
    assert run(env, ["write-config"], stdin=first).returncode == 0
    first = (tmp / "config.json").read_bytes()
    orig = SAFE.write_at

    def boom(dirfd, name, data, mode=0o600, max_bytes=None):
        if name == "config.json":
            raise OSError("short write")
        return orig(dirfd, name, data, mode=mode, max_bytes=max_bytes)

    SAFE.write_at = boom
    try:
        dirfd = SAFE.open_dir_fd(tmp, create=True, private=True)
        try:
            SAFE.write_at(dirfd, "config.json", b'{"keep":false}', mode=0o600, max_bytes=SAFE.MAX_CONFIG_BYTES)
            raise AssertionError("should fail")
        except OSError:
            pass
        finally:
            os.close(dirfd)
    finally:
        SAFE.write_at = orig
    assert (tmp / "config.json").read_bytes() == first


def test_write_keeps_previous_as_bak(tmp: Path):
    env = os.environ.copy()
    env["WORKSCAPE_STATE_DIR"] = str(tmp)
    first = json.dumps({"version": 2, "profiles": [{"id": "one", "name": "One"}]})
    second = json.dumps({"version": 2, "profiles": [{"id": "two", "name": "Two"}]})
    assert run(env, ["write-config"], stdin=first.encode()).returncode == 0
    first_saved = (tmp / "config.json").read_bytes()
    assert run(env, ["write-config"], stdin=second.encode()).returncode == 0
    assert (tmp / "config.json.bak").read_bytes() == first_saved
    assert b'"Two"' in (tmp / "config.json").read_bytes()


def test_atomic_hyprland_backup(tmp: Path):
    hypr = tmp / "hypr"
    hypr.mkdir()
    lua = hypr / "hyprland.lua"
    lua.write_text("require('old')\n")
    SAFE.write_atomic(lua, "require('new')\n", mode=0o644, backup=True)
    assert lua.read_text() == "require('new')\n"
    assert (hypr / "hyprland.lua.workscape.bak").read_text() == "require('old')\n"


def test_unlink_does_not_follow(tmp: Path):
    victim = tmp / "victim"
    victim.write_text("stay")
    stamp = tmp / "last-swipe-fingers"
    stamp.symlink_to(victim)
    SAFE.unlink_nofollow(stamp)
    assert not stamp.exists()
    assert victim.read_text() == "stay"


def test_migrate_copies_only_config(tmp: Path):
    env = os.environ.copy()
    state = tmp / "state"
    xdg = tmp / "xdg"
    xdg.mkdir()
    legacy = xdg / "omarchy" / "workbook"
    legacy.mkdir(parents=True)
    (legacy / "config.json").write_text('{"version":2,"profiles":[]}\n')
    (legacy / "secret.txt").write_text("nope")
    env["XDG_STATE_HOME"] = str(xdg)
    env["WORKSCAPE_STATE_DIR"] = str(state)
    r = run(env, ["ensure-config"])
    assert r.returncode == 0
    assert json.loads(r.stdout.decode())["version"] == 2
    assert not (state / "secret.txt").exists()


def test_hung_helper_and_descendants(tmp: Path):
    env = os.environ.copy()
    marker = tmp / "child.pid"
    script = tmp / "hang.sh"
    script.write_text(
        "#!/bin/bash\n"
        f"sleep 30 &\n"
        f"echo $! > {marker}\n"
        "wait\n"
    )
    script.chmod(0o700)
    t0 = time.monotonic()
    r = run(env, ["run", "--timeout", "1", "--", "bash", str(script)], timeout=6)
    assert time.monotonic() - t0 < 5
    assert r.returncode == 124
    time.sleep(0.2)
    if marker.exists():
        pid = int(marker.read_text().strip() or "0")
        if pid:
            try:
                os.kill(pid, 0)
                os.kill(pid, signal.SIGKILL)
                raise AssertionError("descendant still alive")
            except ProcessLookupError:
                pass


def test_schema_caps_profiles(tmp: Path):
    env = os.environ.copy()
    env["WORKSCAPE_STATE_DIR"] = str(tmp)
    profiles = [{"id": f"p{i}", "name": f"P{i}", "assignments": [{"exec": "foot" + ("x" * 600), "workspace": 1}]} for i in range(20)]
    r = run(env, ["write-config"], stdin=json.dumps({"version": 2, "profiles": profiles}).encode())
    assert r.returncode == 0, r.stderr
    obj = json.loads(run(env, ["ensure-config"]).stdout.decode())
    assert len(obj["profiles"]) == 12
    assert len(obj["profiles"][0]["assignments"][0]["exec"]) <= 500
    assert obj["settings"]["persistHyprGestures"] is False


def test_run_kills_on_overflow(tmp: Path):
    env = os.environ.copy()
    r = run(
        env,
        ["run", "--timeout", "3", "--max-out", "4096", "--", "python3", "-c", "print('x'*200000)"],
        timeout=6,
    )
    assert r.returncode != 0
    assert len(r.stdout) <= 8192


def test_isolate_log_hard_cap(tmp: Path):
    env = os.environ.copy()
    env["WORKSCAPE_STATE_DIR"] = str(tmp)
    r = run(
        env,
        ["isolate-apply", "--timeout", "5", "--", "python3", "-c", "print('x'*2000000)"],
        timeout=8,
    )
    assert r.returncode != 0
    log = tmp / "apply.log"
    assert log.exists()
    assert log.stat().st_size <= SAFE.MAX_APPLY_LOG
    assert len(r.stdout) <= SAFE.MAX_APPLY_LOG


def test_isolate_lock(tmp: Path):
    env = os.environ.copy()
    env["WORKSCAPE_STATE_DIR"] = str(tmp)
    first = subprocess.Popen(
        ["python3", str(STATEIO), "isolate-apply", "--timeout", "5", "--", "sleep", "2"],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(0.25)
    second = run(env, ["isolate-apply", "--timeout", "1", "--", "true"], timeout=4)
    first.wait(timeout=5)
    assert second.returncode == 0
    assert b"apply already in progress" in second.stdout


if __name__ == "__main__":
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        base = Path(d)
        for name in list("abcdefghijklmno"):
            (base / name).mkdir()
        test_helper_env_disables_bytecode()
        test_write_read_roundtrip(base / "a")
        test_symlink_config_rejected(base / "b")
        test_fifo_config_rejected(base / "c")
        test_parent_symlink_rejected(base / "d")
        test_oversized_config(base / "e")
        test_short_write_leaves_dest(base / "f")
        test_write_keeps_previous_as_bak(base / "o")
        test_atomic_hyprland_backup(base / "g")
        test_unlink_does_not_follow(base / "h")
        test_migrate_copies_only_config(base / "i")
        test_hung_helper_and_descendants(base / "j")
        test_schema_caps_profiles(base / "k")
        test_run_kills_on_overflow(base / "l")
        test_isolate_log_hard_cap(base / "n")
        test_isolate_lock(base / "m")
    print("stateio.test.py ok")
