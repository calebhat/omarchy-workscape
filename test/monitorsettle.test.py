#!/usr/bin/env python3
"""monitorsettle: fingerprint determinism and the wait-stable loop."""
from __future__ import annotations

from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ms = SourceFileLoader("dummy_monitorsettle", str(ROOT / "scripts/monitorsettle")).load_module()


def mon(name, w, h, hz, scale, disabled=False):
    return {
        "name": name,
        "width": w,
        "height": h,
        "refreshRate": hz,
        "scale": scale,
        "disabled": disabled,
    }


def test_fingerprint_ignores_order_and_headless():
    a = [mon("eDP-1", 2880, 1800, 120, 1.25), mon("DP-1", 3440, 1440, 160, 1)]
    b = list(reversed(a)) + [{"name": "HEADLESS-1", "width": 1280, "height": 720, "refreshRate": 60, "scale": 1}]
    assert ms.fingerprint(a) == ms.fingerprint(b)
    assert ms.fingerprint([]) == ms.fingerprint([{"name": "HEADLESS-1"}])


def test_fingerprint_sensitivity():
    base = [mon("eDP-1", 2880, 1800, 120, 1.25)]
    assert ms.fingerprint(base) != ms.fingerprint([mon("eDP-1", 2880, 1800, 120, 1.5)])
    assert ms.fingerprint(base) != ms.fingerprint([mon("eDP-1", 2880, 1800, 60, 1.25)])
    assert ms.fingerprint(base) != ms.fingerprint([mon("DP-1", 2880, 1800, 120, 1.25)])
    assert ms.fingerprint(base) != ms.fingerprint([mon("eDP-1", 1920, 1200, 120, 1.25)])
    assert ms.fingerprint(base) != ms.fingerprint([mon("eDP-1", 2880, 1800, 120, 1.25, disabled=True)])
    # tiny refresh jitter is the same display, not a change
    assert ms.fingerprint(base) == ms.fingerprint([mon("eDP-1", 2880, 1800, 120.001, 1.25)])


def test_wait_stable():
    seq = [
        [mon("eDP-1", 2880, 1800, 120, 1.25)],
        [mon("eDP-1", 2880, 1800, 120, 1.25), mon("DP-1", 3440, 1440, 160, 1)],
        [mon("eDP-1", 2880, 1800, 120, 1.25), mon("DP-1", 3440, 1440, 160, 1)],
    ]
    state = {"i": 0}
    orig = ms.live_monitors

    def fake():
        idx = min(state["i"], len(seq) - 1)
        state["i"] += 1
        return seq[idx]

    ms.live_monitors = fake
    try:
        out = ms.wait_stable(timeout=2, interval=0.01)
        assert out["stable"] is True, out
        assert out["fingerprint"] == ms.fingerprint(seq[-1]), out
    finally:
        ms.live_monitors = orig


def test_wait_timeout():
    state = {"i": 0}
    orig = ms.live_monitors

    def flip():
        state["i"] += 1
        scale = 1.25 if state["i"] % 2 else 1.0
        return [mon("eDP-1", 2880, 1800, 120, scale)]

    ms.live_monitors = flip
    try:
        out = ms.wait_stable(timeout=0.2, interval=0.02)
        assert out["stable"] is False, out
    finally:
        ms.live_monitors = orig


if __name__ == "__main__":
    test_fingerprint_ignores_order_and_headless()
    test_fingerprint_sensitivity()
    test_wait_stable()
    test_wait_timeout()
    print("monitorsettle.test.py ok")
