from __future__ import annotations

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
APPLYCOLOR = REPO_ROOT / "config/quickshell/ii/scripts/colors/applycolor.sh"
SWITCHWALL = REPO_ROOT / "config/quickshell/ii/scripts/colors/switchwall.sh"
TERMINAL_TEMPLATES = APPLYCOLOR.parent / "terminal"


class TerminalColorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.config_home = self.root / "config"
        self.state_home = self.root / "state"
        self.cache_home = self.root / "cache"
        (self.config_home / "quickshell/ii").mkdir(parents=True)
        self.generated_directory = self.state_home / "quickshell/user/generated"
        self.generated_directory.mkdir(parents=True)
        self.palette_path = self.generated_directory / "material_colors.scss"
        self.theme_path = self.generated_directory / "terminal/kitty-theme.conf"

    def environment(self) -> dict[str, str]:
        environment = os.environ.copy()
        environment.update(
            {
                "XDG_CONFIG_HOME": str(self.config_home),
                "XDG_STATE_HOME": str(self.state_home),
                "XDG_CACHE_HOME": str(self.cache_home),
            }
        )
        return environment

    def complete_palette(self) -> str:
        placeholders: set[str] = set()
        for template_name in ["kitty-theme.conf", "sequences.txt"]:
            template = (TERMINAL_TEMPLATES / template_name).read_text(encoding="utf-8")
            placeholders.update(re.findall(r"#\$([A-Za-z0-9_]+) #", template))
        return "".join(f"${name}: #123456;\n" for name in sorted(placeholders))

    def run_apply_kitty(self) -> subprocess.CompletedProcess[str]:
        command = 'source "$1"; pidof() { return 1; }; apply_kitty'
        return subprocess.run(
            ["bash", "-c", command, "bash", str(APPLYCOLOR)],
            check=False,
            capture_output=True,
            env=self.environment(),
            text=True,
        )

    def test_complete_palette_renders_valid_kitty_theme(self) -> None:
        self.palette_path.write_text(self.complete_palette(), encoding="utf-8")

        result = self.run_apply_kitty()

        self.assertEqual(result.returncode, 0, result.stderr)
        rendered_theme = self.theme_path.read_text(encoding="utf-8")
        self.assertNotRegex(rendered_theme, r"#\$[A-Za-z0-9_]+ #")
        self.assertIn("background            #123456", rendered_theme)

    def test_incomplete_palette_preserves_existing_theme(self) -> None:
        self.palette_path.write_text("$term0: #123456;\n", encoding="utf-8")
        self.theme_path.parent.mkdir(parents=True)
        self.theme_path.write_text("existing valid theme\n", encoding="utf-8")

        result = self.run_apply_kitty()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.theme_path.read_text(encoding="utf-8"), "existing valid theme\n")
        self.assertIn("Palette is incomplete", result.stderr)

    def test_empty_palette_preserves_existing_theme(self) -> None:
        self.palette_path.touch()
        self.theme_path.parent.mkdir(parents=True)
        self.theme_path.write_text("existing valid theme\n", encoding="utf-8")

        result = subprocess.run(
            ["bash", str(APPLYCOLOR)],
            check=False,
            capture_output=True,
            env=self.environment(),
            text=True,
        )

        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.theme_path.read_text(encoding="utf-8"), "existing valid theme\n")
        self.assertIn("palette is missing or empty", result.stderr)

    def test_switchwall_uses_cached_color_and_atomic_palette_install(self) -> None:
        script = SWITCHWALL.read_text(encoding="utf-8")
        self.assertIn('cached_color_file="$STATE_DIR/user/generated/color.txt"', script)
        self.assertIn('material_colors_tmp=$(mktemp', script)
        self.assertIn('mv -- "$material_colors_tmp" "$material_colors_file"', script)
        self.assertIn("keeping the last valid terminal palette", script)


if __name__ == "__main__":
    unittest.main()
