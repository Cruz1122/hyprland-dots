"""The Windows page's preview follows the page's values, in the sandboxed harness.

Runs tests/harness/drivers/window-preview.qml with the fake hyprctl: the
driver writes gaps, border, rounding and rounding power through the store and
checks the preview's geometry, the highlight of the focused row and Game
Mode's paused rows (see the driver). This test checks the driver's reports
and the pixels of the magnifier it saves at 1:1: the corner of the main
window sits at (anchorX, anchorY), so the border, the gap to the neighbor and
the gap to the bar fall on known pixels. The pure geometry is unit-tested in
tests/qml_settings/tst_SettingsWindowPreview.qml.
"""
from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - depends on the machine
    Image = None

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DRIVER = ROOT / "tests/harness/drivers/window-preview.qml"
MARKER = "[harness:report] "


def rgb(hex_color: str) -> tuple[int, int, int]:
    value = hex_color.lstrip("#")
    value = value[-6:]  # "#aarrggbb" or "#rrggbb"
    return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)


class WindowPreviewTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp = tempfile.TemporaryDirectory()
        out = cls.temp.name
        cls.result = subprocess.run(
            ["bash", str(RUN), "--driver", str(DRIVER), "--renderer", "software", "--hyprland-stub",
             "--strict", "--allow-config-writes", "--out", out, "--timeout", "120"],
            capture_output=True, text=True, timeout=180,
        )
        log_path = Path(out) / "harness.log"
        cls.log = log_path.read_text(encoding="utf-8", errors="replace") if log_path.is_file() else ""
        cls.events = [json.loads(line[line.index(MARKER) + len(MARKER):])
                      for line in cls.log.splitlines() if MARKER in line]
        cls.images = {}
        if Image is not None:
            for event in cls.events:
                if event.get("type") == "image" and Path(event["file"]).is_file():
                    with Image.open(event["file"]) as image:
                        cls.images[event["name"]] = image.convert("RGB")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def setUp(self) -> None:
        if self.result.returncode == 77:
            self.skipTest(self.result.stderr.strip() or "harness prerequisites missing")

    def context(self) -> str:
        return self.result.stdout + self.log[-3000:]

    def test_driver_checks_pass(self) -> None:
        self.assertFalse([e for e in self.events if e.get("type") == "fatal"], self.context())
        checks = [e for e in self.events if e.get("type") == "check"]
        names = {check["name"] for check in checks}
        for expected in ("two previews on the page", "the preview follows the written values",
                         "desktop: neighbors are 2 × gaps_in apart", "magnifier: real-size border, rounding and gaps",
                         "focusing the border row highlights the border", "a hovered row wins over the focused one",
                         "moving to another previewed row follows it", "leaving the rows falls back to the focused one",
                         "Game Mode banner shown",
                         "hyprland.general.allow_tearing: paused by Game Mode",
                         "hyprland.general.gaps_in: shows the stored value", "values back to their defaults"):
            self.assertIn(expected, names, self.context())
        for check in checks:
            with self.subTest(check=check["name"]):
                self.assertTrue(check["ok"], check)
        self.assertEqual([e.get("failures") for e in self.events if e.get("type") == "done"], [0], self.context())
        # --strict: no QML warning.
        self.assertEqual(self.result.returncode, 0, self.context())

    def assertColor(self, image, x: int, y: int, expected: tuple[int, int, int], what: str) -> None:
        actual = image.getpixel((x, y))
        self.assertTrue(all(abs(a - e) <= 12 for a, e in zip(actual, expected)),
                        f"{what}: pixel ({x}, {y}) is {actual}, expected about {expected}")

    @unittest.skipIf(Image is None, "Pillow is not installed: cannot read the saved magnifier")
    def test_magnifier_pixels_follow_the_values(self) -> None:
        lens = [e for e in self.events if e.get("type") == "lens"]
        self.assertEqual(len(lens), 1, self.context())
        lens = lens[0]
        after = self.images.get("magnifier-after")
        before = self.images.get("magnifier-before")
        self.assertIsNotNone(after, self.context())
        self.assertIsNotNone(before, self.context())
        x0, y0 = lens["anchorX"], lens["anchorY"]
        active, inactive, wallpaper = rgb(lens["activeBorder"]), rgb(lens["inactiveBorder"]), rgb(lens["wallpaper"])
        self.assertNotEqual(active, wallpaper)
        self.assertNotEqual(inactive, wallpaper)
        y = y0 + 64  # below the rounded corner and the gap's measure line
        # The main window's 3 px border ends at the corner's x.
        for x in range(x0 - lens["border"], x0):
            self.assertColor(after, x, y, active, "main window border")
        # 2 × gaps_in of wallpaper, then the neighbor's border.
        for x in range(x0 + 1, x0 + 2 * lens["gapsIn"] - 1):
            self.assertColor(after, x, y, wallpaper, "gap between windows")
        self.assertColor(after, x0 + 2 * lens["gapsIn"] + 1, y, inactive, "neighbor border")
        # gaps_out of wallpaper between the bar and the window's top edge.
        for dy in range(2, lens["gapsOut"] - 1):
            self.assertColor(after, 20, y0 - dy, wallpaper, "gap below the bar")
        # The written values moved the drawing.
        self.assertNotEqual(before.getpixel((x0 + 2 * lens["gapsIn"] + 1, y)), after.getpixel((x0 + 2 * lens["gapsIn"] + 1, y)))


if __name__ == "__main__":
    unittest.main()
