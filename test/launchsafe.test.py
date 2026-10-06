#!/usr/bin/env python3
import os
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAUNCH = SourceFileLoader(
    "workscape_launchsafe_test",
    str(ROOT / "scripts" / "launchsafe"),
).load_module()
cap = SourceFileLoader(
    "workscape_capture_launchsafe",
    str(ROOT / "scripts" / "capture"),
).load_module()


def test_shell_quotes_argv_and_rejects_syntax():
    assert LAUNCH.prepare_shell("brave --new-window") == "brave --new-window"
    assert LAUNCH.prepare_shell("flatpak run org.signal.Signal") == "flatpak run org.signal.Signal"
    web = "omarchy-launch-webapp 'https://outlook.office.com/mail/?a=1&b=2'"
    quoted = LAUNCH.prepare_shell(web)
    assert "omarchy-launch-webapp" in quoted
    assert "&" in quoted
    assert ";" not in quoted.split()[0]
    cwd = "foot --working-directory='/home/caleb/My Projects'"
    assert "My Projects" in LAUNCH.prepare_shell(cwd)
    for bad in (
        "bash -c id",
        "brave;id",
        "brave && id",
        "$(id)",
        "flatpak run --command=sh org.foo.Bar",
        "snap run --shell firefox",
        "omarchy-launch-webapp https://ok.example/;id",
        "/tmp/pwn",
    ):
        try:
            LAUNCH.prepare_shell(bad)
        except LAUNCH.UnsafeLaunch:
            continue
        raise AssertionError(bad)


def test_capture_ignores_argv_and_app_id():
    pid = os.getpid()
    orig = cap.proc_cmd
    cap.proc_cmd = lambda _pid: "bash -c 'touch /tmp/workscape-pwn'"
    try:
        got = cap.exec_for_client(
            {"class": "$(id)", "title": "x;id", "pid": pid},
            "",
            "",
        )
    finally:
        cap.proc_cmd = orig
    assert got == ""


def test_sandboxed_restore_is_flatpak_run():
    orig = (cap.LAUNCH.is_sandboxed, cap.LAUNCH.flatpak_id, cap.LAUNCH.snap_id)
    cap.LAUNCH.is_sandboxed = lambda _pid: True
    cap.LAUNCH.snap_id = lambda _pid: None
    try:
        cap.LAUNCH.flatpak_id = lambda _pid: "org.signal.Signal"
        got = cap.exec_for_client(
            {"class": "'; rm -rf /", "title": "Signal", "pid": 9},
            "https://evil.example/$(id)",
            "",
        )
        assert got == "flatpak run org.signal.Signal"
        cap.LAUNCH.flatpak_id = lambda _pid: "org.foo;id"
        assert cap.exec_for_client({"class": "org.foo.Bar", "title": "", "pid": 9}, "", "") == ""
    finally:
        cap.LAUNCH.is_sandboxed, cap.LAUNCH.flatpak_id, cap.LAUNCH.snap_id = orig


def test_foot_app_id_is_not_the_command():
    got = cap.exec_for_client({"class": "foot;id", "title": "x", "pid": 0}, "", "")
    assert got == "foot"
    assert ";" not in got


if __name__ == "__main__":
    test_shell_quotes_argv_and_rejects_syntax()
    test_capture_ignores_argv_and_app_id()
    test_sandboxed_restore_is_flatpak_run()
    test_foot_app_id_is_not_the_command()
    print("launchsafe.test.py ok")
