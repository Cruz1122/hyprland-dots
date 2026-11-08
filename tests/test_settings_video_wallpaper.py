"""The wallpaper card previews a video wallpaper by its thumbnail.

switchwall.sh plays videos with mpvpaper and stores a still frame in
background.thumbnailPath. The card used to load the video itself as an image:
the preview stayed empty and Qt warned "Cannot open". Renders the pages that
show the card in the sandboxed harness (--strict fails on any app warning).
"""
from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DEFAULT_CONFIG = ROOT / "config/illogical-impulse/config.json"


class VideoWallpaperPreviewTest(unittest.TestCase):
    def test_pages_with_the_wallpaper_card_render_a_video_wallpaper_cleanly(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            config = json.loads(DEFAULT_CONFIG.read_text(encoding="utf-8"))
            # run.sh expands @CONFIG@ and copies the repository wallpaper.png
            # to @CONFIG@/hypr/wallpaper.png; the video itself need not exist.
            config["background"]["wallpaperPath"] = "@CONFIG@/hypr/wallpaper.mp4"
            config["background"]["thumbnailPath"] = "@CONFIG@/hypr/wallpaper.png"
            seeded = Path(temp) / "config.json"
            seeded.write_text(json.dumps(config, indent=2), encoding="utf-8")
            out = Path(temp) / "out"
            result = subprocess.run(
                ["bash", str(RUN), "--strict", "--renderer", "software", "--pages", "quick,background",
                 "--sizes", "1100x760", "--config", str(seeded), "--out", str(out), "--timeout", "120"],
                capture_output=True, text=True, timeout=180,
            )
            if result.returncode == 77:
                self.skipTest(result.stderr.strip() or "harness prerequisites missing")
            log = (out / "harness.log").read_text(encoding="utf-8", errors="replace")
        self.assertNotIn("Cannot open", log)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr + log[-2000:])


if __name__ == "__main__":
    unittest.main()
