#!/usr/bin/env python3
from importlib.machinery import SourceFileLoader
from pathlib import Path

SAFE = SourceFileLoader(
    "hyprsafe",
    str(Path(__file__).resolve().parent.parent / "scripts" / "hyprsafe"),
).load_module()


def test_safe_ws():
    assert SAFE.safe_ws("8") == "8"
    assert SAFE.safe_ws("20") == "20"
    assert SAFE.safe_ws("21") == "21"
    assert SAFE.safe_ws("200") == "200"
    assert SAFE.safe_ws("0") is None
    assert SAFE.safe_ws("201") is None
    assert SAFE.safe_ws("1;hl.dispatch") is None


def test_safe_addr():
    assert SAFE.safe_addr("0xabc") == "0xabc"
    assert SAFE.safe_addr("address:0xABC") == "0xABC"
    assert SAFE.safe_addr("0x;os.execute") is None
    assert SAFE.safe_addr("") is None


def test_lua_str_escapes_quotes():
    assert SAFE.lua_str('foot -e "hi"') == r'foot -e \"hi\"'
    assert '\\' in SAFE.lua_str(r'a\b')
    assert "\n" not in SAFE.lua_str("a\nb")


def test_safe_connector():
    assert SAFE.safe_connector("eDP-1") == "eDP-1"
    assert SAFE.safe_connector("HEADLESS-1") is None
    assert SAFE.safe_connector("eDP-1;rm") is None


if __name__ == "__main__":
    test_safe_ws()
    test_safe_addr()
    test_lua_str_escapes_quotes()
    test_safe_connector()
    print("hyprsafe.test.py ok")
