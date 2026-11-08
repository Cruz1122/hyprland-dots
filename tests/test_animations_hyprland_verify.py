"""Files written by animationsgen.py pass `Hyprland --verify-config` (offline).

Each case renders custom/shell-animations.lua with the generator into a
temporary HOME whose hyprland.lua defines the dotfiles curves (parsed from
config/hypr/hyprland/general.lua) and loads the file with the exact block of
config/hypr/hyprland.lua. Hyprland runs with private HOME/XDG directories and
without HYPRLAND_INSTANCE_SIGNATURE, so the live session is never contacted.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "config/quickshell/ii/scripts/settings/animationsgen.py"
LOGIC_JS = ROOT / "config/quickshell/ii/modules/settings/backends/AnimationLogic.js"
GENERAL = ROOT / "config/hypr/hyprland/general.lua"
ENTRY = ROOT / "config/hypr/hyprland.lua"
LIB = ROOT / "config/hypr/hyprland/lib/init.lua"
BASE = json.loads((ROOT / "tests/fixtures/hyprbase-sample.json").read_text(encoding="utf-8"))
HYPRLAND = shutil.which("Hyprland")
SENTINEL = "ranAfterTheAnimationsFile"

sys.path.insert(0, str(ROOT / "tests"))
from test_animationsgen import gen, preset_cards, presets  # noqa: E402


def dotfiles_curves() -> str:
    text = GENERAL.read_text(encoding="utf-8")
    curves = re.findall(r'^hl\.curve\("\w+", \{.*?\n\}\)', text, re.M | re.S)
    if len(curves) != len(BASE["curves"]):
        raise AssertionError(f"expected {len(BASE['curves'])} hl.curve blocks in general.lua, found {len(curves)}")
    return "\n".join(curves)


def loader_block() -> str:
    """The `if is_file_exists(...shell-animations.lua) ... end` block of hyprland.lua, verbatim."""
    match = re.search(r'^if is_file_exists\(HOME \.\. "/\.config/hypr/custom/shell-animations\.lua"\) then\n.*?^end$',
                      ENTRY.read_text(encoding="utf-8"), re.M | re.S)
    if not match:
        raise AssertionError("config/hypr/hyprland.lua does not load custom/shell-animations.lua")
    return match.group(0)


class LoaderBlockTest(unittest.TestCase):
    def test_the_loader_uses_pcall(self) -> None:
        # `Hyprland --verify-config` alone cannot show that the pcall matters:
        # Hyprland 0.57 continues after a failing require (it records the
        # error and runs the rest of hyprland.lua), so the broken-file test
        # below passes with or without it. The pcall is the documented guard
        # for Game Mode's overrides that follow, so it is pinned in the text.
        self.assertIn('pcall(require, "custom.shell-animations")', loader_block())


@unittest.skipIf(HYPRLAND is None, "Hyprland is not installed: cannot run --verify-config")
class HyprlandVerifyConfigTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name) / "home"
        self.hypr = self.home / ".config/hypr"
        (self.hypr / "custom").mkdir(parents=True)
        (self.hypr / "hyprland/lib").mkdir(parents=True)
        shutil.copy(LIB, self.hypr / "hyprland/lib/init.lua")
        self.runtime = Path(self.temp.name) / "runtime"
        self.runtime.mkdir(mode=0o700)
        self.target = self.hypr / "custom/shell-animations.lua"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_entry(self, after: str = "") -> None:
        (self.hypr / "hyprland.lua").write_text(
            'require("hyprland.lib")\n' + dotfiles_curves() + "\n" + loader_block() + "\n" + after + "\n",
            encoding="utf-8")

    def generate(self, changes: dict) -> None:
        self.target.unlink(missing_ok=True)
        result = subprocess.run([sys.executable, str(SCRIPT), "--file", str(self.target), "--apply-json", "-"],
                                input=json.dumps({"base": BASE, **changes}), capture_output=True, text=True,
                                timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def verify(self) -> subprocess.CompletedProcess:
        env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(self.home),
               "XDG_CONFIG_HOME": str(self.home / ".config"), "XDG_RUNTIME_DIR": str(self.runtime),
               "XDG_CACHE_HOME": str(self.home / ".cache"), "XDG_STATE_HOME": str(self.home / ".local/state")}
        return subprocess.run([HYPRLAND, "--verify-config", "-c", str(self.hypr / "hyprland.lua")],
                              env=env, capture_output=True, text=True, timeout=60)

    def assert_config_ok(self, what: str) -> None:
        result = self.verify()
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, f"{what}:\n{self.target.read_text(encoding='utf-8')}\n{output[-3000:]}")
        self.assertIn("config ok", output)

    def test_verify_config_catches_a_bad_line(self) -> None:
        # Negative control: the setup really reports binding errors.
        self.write_entry()
        self.target.write_text(gen.MARKER + '\nhl.animation({ leaf = "windowsIn", enabled = true, speed = 3, '
                                            'bezier = "noSuchCurve" })\n', encoding="utf-8")
        result = self.verify()
        self.assertEqual(result.returncode, 1)
        self.assertIn('no such bezier "noSuchCurve"', result.stdout + result.stderr)

    def test_every_preset_passes(self) -> None:
        self.write_entry()
        for name in presets():
            with self.subTest(preset=name):
                self.generate({"cards": preset_cards(name)})
                self.assert_config_ok(name)

    def test_all_disabled_cards_pass(self) -> None:
        self.write_entry()
        cards = {card: {**value, "enabled": False} for card, value in preset_cards("bouncy").items()}
        self.generate({"cards": cards})
        self.assertNotIn("enabled = true", self.target.read_text(encoding="utf-8"))
        self.assert_config_ok("all disabled")

    def test_user_curve_and_both_springs_pass(self) -> None:
        self.write_entry()
        curve = {"type": "bezier", "points": [0.2, -0.5, 0.1, 1.8], "label": 'Mine "quoted" ]] --[['}
        spring = {"type": "spring", "mass": 1.5, "stiffness": 300, "damping": 22.5, "label": "Spring"}
        cards = preset_cards("smooth")
        cards["windowsIn"]["curve"] = "ii_mine"
        cards["windowsOut"]["curve"] = "ii_spring_soft"
        cards["layersIn"]["curve"] = "ii_spring_bouncy"
        cards["border"]["curve"] = "ii_spring_mine"
        self.generate({"curves": {"ii_mine": curve, "ii_spring_mine": spring}, "cards": cards})
        text = self.target.read_text(encoding="utf-8")
        for name in ("ii_mine", "ii_spring_mine", "ii_spring_soft", "ii_spring_bouncy"):
            self.assertIn(f'hl.curve("{name}"', text)
        self.assert_config_ok("user curves and springs")

    def test_every_allowlisted_style_passes(self) -> None:
        self.write_entry()
        variants = {
            "windows": ["", "popin", "popin 0%", "popin 100%", "slide", "slide top", "slide bottom", "slide left",
                        "slide right", "gnomed"],
            "workspaces": ["", "slide", "slidevert", "fade", "slidefade", "slidefade 0%", "slidefade 40%",
                           "slidefadevert", "slidefadevert 100%"],
            "layers": ["", "fade", "slide", "slide top", "slide left", "popin", "popin 50%", "popin 100%"],
            "none": [""],
        }
        rounds = max(len(v) for v in variants.values())
        for index in range(rounds):
            cards = preset_cards("agile")
            for card, (_, _, family) in gen.CARDS.items():
                cards[card]["style"] = variants[family][index % len(variants[family])]
            with self.subTest(round=index):
                self.generate({"cards": cards})
                self.assert_config_ok(f"styles round {index}")

    def test_broken_file_does_not_stop_the_statements_after_it(self) -> None:
        # The sentinel fails on purpose with a message that proves it ran.
        self.write_entry(f'hl.animation({{ leaf = "monitorAdded", enabled = true, speed = 1, bezier = "{SENTINEL}" }})')
        self.target.write_text(gen.MARKER + '\nlocal broken = nil\nbroken()\nhl.animation({ leaf = "border"\n',
                               encoding="utf-8")
        result = self.verify()
        output = result.stdout + result.stderr
        self.assertIn(f'no such bezier "{SENTINEL}"', output)
        self.assertIn("shell-animations", output, "Hyprland reports the broken file")
        self.target.write_text(gen.MARKER + '\nlocal broken = nil\nbroken()\n', encoding="utf-8")
        result = self.verify()
        output = result.stdout + result.stderr
        self.assertIn(f'no such bezier "{SENTINEL}"', output, "a runtime error does not stop hyprland.lua either")


if __name__ == "__main__":
    unittest.main()
