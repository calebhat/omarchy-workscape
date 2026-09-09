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
    # Old bug: measure against eDP-1 (logical 1440) → herdr clamps to full width.
    assert left["geom"]["w"] != 1


GROUPED_CLIENTS = [
    # WS 3: a two-member group on the left, a plain window on the right.
    # Group members report the box below the 28px groupbar, and Hyprland lists
    # the whole membership on each member in tab order.
    {
        "class": "org.telegram.desktop",
        "title": "Telegram",
        "address": "0xAAA",
        "grouped": ["0xAAA", "0xBBB"],
        "focusHistoryID": 4,
        "at": [8, 62],
        "size": [940, 1006],
        "monitor": 1,
        "floating": False,
        "workspace": {"id": 3, "name": "3"},
        "pid": 0,
    },
    {
        "class": "org.signal.Signal",
        "title": "Signal",
        "address": "0xBBB",
        "grouped": ["0xAAA", "0xBBB"],
        "focusHistoryID": 1,
        "at": [8, 62],
        "size": [940, 1006],
        "monitor": 1,
        "floating": False,
        "workspace": {"id": 3, "name": "3"},
        "pid": 0,
    },
    {
        "class": "Spotify",
        "title": "Spotify Premium",
        "address": "0xCCC",
        "grouped": [],
        "focusHistoryID": 7,
        "at": [956, 34],
        "size": [940, 1034],
        "monitor": 1,
        "floating": False,
        "workspace": {"id": 3, "name": "3"},
        "pid": 0,
    },
]


def setup_grouped():
    state = (cap.hypr_j, cap.GEOM.gaps_out, cap.groupbar_px)

    def fake_hypr(cmd: str):
        if cmd == "clients":
            return GROUPED_CLIENTS
        if cmd == "monitors":
            return MONITORS
        raise AssertionError(cmd)

    cap.hypr_j = fake_hypr
    cap.GEOM.gaps_out = lambda: (8, 8, 8, 8)
    cap.groupbar_px = lambda: 28
    return state


def restore_grouped(state):
    cap.hypr_j, cap.GEOM.gaps_out, cap.groupbar_px = state


def test_group_tokens_and_active_member():
    by_addr, members = cap.group_tokens(GROUPED_CLIENTS)
    assert by_addr == {"0xAAA": "g1", "0xBBB": "g1"}
    assert members == {"g1": ["0xAAA", "0xBBB"]}
    # Lowest focusHistoryID is the tab on top.
    assert cap.active_group_member(GROUPED_CLIENTS, ["0xAAA", "0xBBB"]) == "0xBBB"
    # A one-member group is not persisted.
    lone = [dict(GROUPED_CLIENTS[0], grouped=["0xAAA"])]
    assert cap.group_tokens(lone) == ({}, {})


def test_capture_group_is_one_tile():
    state = setup_grouped()
    try:
        rows = cap.capture_workspace("3")
    finally:
        restore_grouped(state)
    assert len(rows) == 3
    by_name = {r["title"]: r for r in rows}
    tg, sg, sp = by_name["Telegram"], by_name["Signal"], by_name["Spotify Premium"]

    # Both members carry the same token and the same tile geom.
    assert tg["group"] == sg["group"] == "g1"
    assert "group" not in sp
    assert tg["geom"] == sg["geom"], "group members must share one tile"

    # The group is one of two tiles, so the split is two columns that fill the
    # workspace. The 28px groupbar must not shrink the stored tile.
    assert tg["geom"]["y"] == 0.0 and tg["geom"]["h"] == 1.0
    assert sp["geom"]["y"] == 0.0 and sp["geom"]["h"] == 1.0
    assert abs(tg["geom"]["w"] + sp["geom"]["w"] - 1.0) < 0.001
    assert tg["geom"]["x"] == 0.0

    # The captured tab order is preserved and the visible tab is marked.
    assert [r["title"] for r in rows[:2]] == ["Telegram", "Signal"]
    assert sg.get("groupActive") is True
    assert tg.get("groupActive") is not True


def test_capture_group_geom_is_stable_across_recapture():
    """The groupbar offset must not compound the way a re-read suffix would."""
    state = setup_grouped()
    try:
        first = cap.capture_workspace("3")
        second = cap.capture_workspace("3")
    finally:
        restore_grouped(state)
    assert {r["title"]: r["geom"] for r in first} == {r["title"]: r["geom"] for r in second}


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
    test_group_tokens_and_active_member()
    test_capture_group_is_one_tile()
    test_capture_group_geom_is_stable_across_recapture()
    test_tessellate_columns()
    print("capture.test.py ok")
