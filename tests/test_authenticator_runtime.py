"""Opt-in live desktop checks; never run on the user's desktop by default."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
import unittest
from dataclasses import dataclass


@dataclass(frozen=True)
class OverlayLayer:
    monitor: str
    address: str
    x: int
    y: int
    width: int
    height: int


@unittest.skipUnless(
    os.environ.get("HYPRLAND_DOTS_AUTHENTICATOR_RUNTIME") == "1",
    "Live desktop checks require explicit HYPRLAND_DOTS_AUTHENTICATOR_RUNTIME=1",
)
class AuthenticatorRuntimeTest(unittest.TestCase):
    @staticmethod
    def command(*args: str) -> str:
        return subprocess.run(
            args, check=True, capture_output=True, text=True, timeout=5
        ).stdout

    @classmethod
    def toggle_shortcut(cls) -> None:
        # This repository uses Hyprland's Lua dispatcher syntax.
        cls.command("hyprctl", "dispatch", 'hl.dsp.global("quickshell:authenticatorToggle")')

    @classmethod
    def layers(cls) -> list[OverlayLayer]:
        monitors = json.loads(cls.command("hyprctl", "layers", "-j"))
        return [
            OverlayLayer(name, layer["address"], layer["x"], layer["y"], layer["w"], layer["h"])
            for name, monitor in monitors.items()
            for layer in monitor["levels"]["3"]
            if layer["namespace"] == "quickshell:authenticator"
        ]

    @classmethod
    def setUpClass(cls) -> None:
        for executable in ("qs", "hyprctl", "wtype"):
            if shutil.which(executable) is None:
                raise unittest.SkipTest(f"Missing runtime tool: {executable}")
        if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
            raise unittest.SkipTest("Requires a running Hyprland session")
        if cls.layers():
            raise unittest.SkipTest("Close the existing authenticator before live tests")

    def wait_for_layer(self, present: bool) -> list[OverlayLayer]:
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            layers = self.layers()
            if bool(layers) == present:
                return layers
            time.sleep(0.02)
        self.fail(f"Authenticator layer did not become present={present}")

    def close_and_wait(self) -> None:
        self.command("qs", "-c", "ii", "ipc", "call", "authenticator", "close")
        self.wait_for_layer(False)

    def setUp(self) -> None:
        self.assertEqual(self.layers(), [])
        self.addCleanup(self.close_and_wait)

    def open_and_settle(self, *, shortcut: bool = False) -> OverlayLayer:
        if shortcut:
            self.toggle_shortcut()
        else:
            self.command("qs", "-c", "ii", "ipc", "call", "authenticator", "toggle")
        layers = self.wait_for_layer(True)
        self.assertEqual(len(layers), 1)
        time.sleep(0.5)
        return layers[0]

    def test_fullscreen_focused_monitor_and_escape_close(self) -> None:
        monitor = next(
            item for item in json.loads(self.command("hyprctl", "monitors", "-j"))
            if item["focused"]
        )
        layer = self.open_and_settle()
        self.assertEqual(layer.monitor, monitor["name"])
        self.assertEqual((layer.x, layer.y), (monitor["x"], monitor["y"]))
        scale = monitor["scale"]
        size = (monitor["width"], monitor["height"])
        if monitor["transform"] % 2:
            size = size[::-1]
        self.assertEqual((layer.width, layer.height), tuple(round(value / scale) for value in size))
        self.command("wtype", "-k", "Escape")
        self.wait_for_layer(False)

    def test_footer_close_control_can_be_keyboard_activated(self) -> None:
        self.open_and_settle()
        self.command("wtype", "-k", "Tab", "-k", "space")
        self.wait_for_layer(False)

    def test_global_shortcut_reverses_exit_without_replacing_window(self) -> None:
        original = self.open_and_settle(shortcut=True)
        self.command("qs", "-c", "ii", "ipc", "call", "authenticator", "close")
        closing = self.layers()
        self.assertEqual(closing, [original], "Window must survive its exit animation")
        self.toggle_shortcut()
        time.sleep(0.5)
        self.assertEqual(self.layers(), [original])
        self.toggle_shortcut()
        self.wait_for_layer(False)


if __name__ == "__main__":
    unittest.main()
