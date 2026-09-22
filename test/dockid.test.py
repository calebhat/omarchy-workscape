#!/usr/bin/env python3
"""dockid: sysfs USB parsing, picker list, and best-capture choice."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
dockid = SourceFileLoader("dummy_dockid", str(ROOT / "scripts/dockid")).load_module()


def make_tree(*devices):
    tmp = tempfile.mkdtemp(prefix="workscape-dockid-")
    root = Path(tmp)
    for name, vendor, product, label, serial in devices:
        dev = root / name
        dev.mkdir(parents=True)
        (dev / "idVendor").write_text(vendor)
        (dev / "idProduct").write_text(product)
        if label:
            (dev / "product").write_text(label)
        if serial:
            (dev / "serial").write_text(serial)
    return root


def test_iter_devices_skips_interfaces_and_roots():
    root = make_tree(
        ("usb3", "1d6b", "0002", "xHCI Host Controller", "0000:00:14.0"),
        ("3-3", "413c", "b06f", "Dell Dock WD19DC", "DG7X753"),
        ("3-3:1.0", "413c", "b06f", "", ""),
        ("1-2", "06cb", "0701", "SVP7500", "01.00.00.00"),
    )
    ids = {d["id"] for d in dockid.iter_devices(root)}
    assert ids == {"usb:413c:b06f:DG7X753", "usb:06cb:0701:01.00.00.00"}, ids
    assert dockid.connected_ids(root) == ids


def test_list_prefers_docks_and_serials():
    root = make_tree(
        ("1-2", "06cb", "0701", "SVP7500", "01.00.00.00"),
        ("3-3", "413c", "b06f", "Dell Dock WD19DC", "DG7X753"),
        ("4-1", "1d6b", "0002", "xHCI Host Controller", ""),
        ("5-1", "05ac", "12a0", "", ""),
    )
    listed = dockid.list_devices(root)
    labels = [d["label"] for d in listed]
    assert labels[0] == "Dell Dock WD19DC", labels
    assert labels[-1] == "xHCI Host Controller", labels
    assert any(d["id"].startswith("usb:05ac:12a0:") for d in listed), listed


def test_best_candidate_order():
    dock = make_tree(
        ("1-2", "06cb", "0701", "SVP7500", "01.00.00.00"),
        ("3-3", "413c", "b06f", "Dell Dock WD19DC", "DG7X753"),
    )
    hit = dockid.best_candidate(dock)
    assert hit and hit["id"] == "usb:413c:b06f:DG7X753", hit
    hub_only = make_tree(("2-2", "2109", "0817", "USB2.0 Hub", "123456"))
    hit = dockid.best_candidate(hub_only)
    assert hit and "hub" in hit["label"].lower(), hit
    only_serial = make_tree(("1-2", "06cb", "0701", "SVP7500", "01.00.00.00"))
    hit = dockid.best_candidate(only_serial)
    assert hit and hit["id"] == "usb:06cb:0701:01.00.00.00", hit
    empty = make_tree(("4-1", "1d6b", "0002", "xHCI Host Controller", ""))
    assert dockid.best_candidate(empty) is None


def test_cli_has_and_list():
    root = make_tree(("3-3", "413c", "b06f", "Dell Dock WD19DC", "DG7X753"))
    script = str(ROOT / "scripts/dockid")
    out = subprocess.run(
        [sys.executable, script, "--has", "usb:413c:b06f:DG7X753", "--sys-root", str(root)],
        capture_output=True, text=True,
    )
    assert out.returncode == 0, out
    out = subprocess.run(
        [sys.executable, script, "--has", "usb:413c:b06f:NOPE", "--sys-root", str(root)],
        capture_output=True, text=True,
    )
    assert out.returncode == 1, out
    out = subprocess.run(
        [sys.executable, script, "--capture", "--sys-root", str(root)],
        capture_output=True, text=True,
    )
    hit = json.loads(out.stdout)
    assert hit["label"] == "Dell Dock WD19DC", hit


if __name__ == "__main__":
    test_iter_devices_skips_interfaces_and_roots()
    test_list_prefers_docks_and_serials()
    test_best_candidate_order()
    test_cli_has_and_list()
    print("dockid.test.py ok")
