#!/usr/bin/env python3
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
cap = SourceFileLoader("workscape_capture", str(ROOT / "scripts" / "capture")).load_module()

MONITORS = [
    {
        "id": 0,
        "name": "eDP-1",
        "x": 0,
        "y": 0,
        "width": 2880,
        "height": 1920,
        "scale": 2,
        "reserved": [0, 26, 0, 0],
    },
    {
        "id": 1,
        "name": "DVI-I-1",
        "x": 1440,
        "y": 0,
        "width": 1920,
        "height": 1080,
        "scale": 1,
        "reserved": [0, 26, 0, 0],
    },
    {
        "id": 2,
        "name": "DVI-I-2",
        "x": 3360,
        "y": 0,
        "width": 1920,
        "height": 1080,
        "scale": 1,
        "reserved": [0, 26, 0, 0],
    },
]

CLIENTS = [
    {
        "class": "org.quickshell",
        "title": "Shophawk Control",
        "at": [4826, 36],
        "size": [444, 1034],
        "monitor": 2,
        "floating": False,
        "workspace": {"id": 2, "name": "2"},
        "pid": 0,
    },
    {
        "class": "org.omarchy.herdr-shophawk",
        "title": "omarchy: master",
        "at": [3370, 36],
        "size": [1444, 1034],
        "monitor": 2,
        "floating": False,
        "workspace": {"id": 2, "name": "2"},
        "pid": 0,
    },
]


def setup_hypr():
    orig_hypr = cap.hypr_j
    orig_gaps = cap.GEOM.gaps_out

    def fake_hypr(cmd: str):
        if cmd == "clients":
            return CLIENTS
        if cmd == "monitors":
            return MONITORS
        raise AssertionError(cmd)

    cap.hypr_j = fake_hypr
    cap.GEOM.gaps_out = lambda: (8, 8, 8, 8)
    return orig_hypr, orig_gaps


def restore_hypr(orig_hypr, orig_gaps):
    cap.hypr_j = orig_hypr
    cap.GEOM.gaps_out = orig_gaps


def test_capture_ws2_keeps_uneven_split():
    orig_hypr, orig_gaps = setup_hypr()
    try:
        rows = cap.capture_workspace("2")
    finally:
        restore_hypr(orig_hypr, orig_gaps)
    assert len(rows) == 2
    left = rows[0]
    right = rows[1]
    assert left["class"] == "org.omarchy.herdr-shophawk"
    assert right["class"] == "org.quickshell"
    assert left["geom"]["x"] == 0
    assert abs(left["geom"]["w"] + right["geom"]["w"] - 1) < 0.001
    assert left["geom"]["w"] > 0.7
    assert right["geom"]["w"] < 0.3
    assert left["lockPlace"] is True
    assert right["lockPlace"] is True
    assert "herdr-shophawk" in left["exec"]
    assert "shophawk-panel" in right["exec"]
    assert left["exec"] != "foot"
    assert right["exec"] != "qs"
    # Old bug: measure against eDP-1 (logical 1440) → herdr clamps to full width.
    assert left["geom"]["w"] != 1


def test_exec_for_herdr_not_parent_foot():
    home = str(Path.home() / ".local/bin/herdr-shophawk")
    got = cap.exec_for_client(
        {"class": "org.omarchy.herdr", "title": "omarchyhome: desk-a", "pid": 0},
        "",
        "",
    )
    assert "herdr" in got
    assert got != "foot"
    panel = cap.exec_for_client(
        {"class": "org.quickshell", "title": "Shophawk Control", "pid": 0},
        "",
        "",
    )
    assert "shophawk-panel" in panel
    assert panel != "qs"
    _ = home


def test_url_from_client_strips_browser_profile_dir():
    # Chromium/Brave append the profile directory to an app window's class.
    # Only "Default" used to be stripped, so any other profile leaked into the
    # path and grew by one segment every time the launched window was recaptured.
    cases = [
        ("chrome-web.whatsapp.com__-Profile_1", "https://web.whatsapp.com"),
        ("chrome-web.whatsapp.com__-Default", "https://web.whatsapp.com"),
        ("brave-meet.google.com__-Profile_3", "https://meet.google.com"),
        ("chrome-app.slack.com__client-Default", "https://app.slack.com/client"),
        ("brave-www.youtube.com__watch-Profile_2", "https://www.youtube.com/watch"),
    ]
    for cls, want in cases:
        got = cap.url_from_client({"class": cls, "title": "", "pid": 0})
        assert got == want, f"{cls}: {got!r} != {want!r}"
    # A plain browser window is not a web app and must not yield a URL.
    assert cap.url_from_client({"class": "brave-browser", "title": "", "pid": 0}) == ""


def test_tessellate_columns():
    items = [
        {"place": "tile", "geom": {"x": 0.001, "y": 0.002, "w": 0.758, "h": 0.99}},
        {"place": "tile", "geom": {"x": 0.766, "y": 0.002, "w": 0.233, "h": 0.99}},
    ]
    cap.tessellate_tile_geoms(items)
    assert items[0]["geom"]["x"] == 0
    assert items[0]["geom"]["h"] == 1
    assert abs(items[0]["geom"]["w"] + items[1]["geom"]["w"] - 1) < 0.001
    assert items[0]["geom"]["w"] > 0.74


if __name__ == "__main__":
    test_capture_ws2_keeps_uneven_split()
    test_exec_for_herdr_not_parent_foot()
    test_url_from_client_strips_browser_profile_dir()
    test_tessellate_columns()
    print("capture.test.py ok")
