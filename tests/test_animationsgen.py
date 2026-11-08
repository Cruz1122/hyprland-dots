"""Tests of config/quickshell/ii/scripts/settings/animationsgen.py (offline; never ~/.config).

The generator is the only Lua serializer of the settings app: every case of
tests/fixtures/animation-cases.json is checked here and, with the same
expectations, in tests/qml_settings/tst_AnimationLogic.qml (parity).
`--eval` runs against the harness hyprctl stub, never a real Hyprland.
"""
from __future__ import annotations

import importlib.util
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "config/quickshell/ii/scripts/settings/animationsgen.py"
LOGIC_JS = ROOT / "config/quickshell/ii/modules/settings/backends/AnimationLogic.js"
CASES = json.loads((ROOT / "tests/fixtures/animation-cases.json").read_text(encoding="utf-8"))
BASE = json.loads((ROOT / "tests/fixtures/hyprbase-sample.json").read_text(encoding="utf-8"))
STUB = ROOT / "tests/harness/stubs/hyprctl"
QMLTESTRUNNER = Path("/usr/lib/qt6/bin/qmltestrunner")
QML_TEST = ROOT / "tests/qml_settings/tst_AnimationLogic.qml"

spec = importlib.util.spec_from_file_location("animationsgen", SCRIPT)
gen = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(gen)


def presets() -> dict[str, dict]:
    text = LOGIC_JS.read_text(encoding="utf-8")
    block = text.split("// presets-json-begin\n", 1)[1].split("// presets-json-end", 1)[0]
    return json.loads(block.split("=", 1)[1].strip().rstrip(";"))


def base_card(card: str) -> dict:
    return gen.resolve(gen.check_base(BASE), gen.CARDS[card][0])


def preset_cards(name: str) -> dict[str, dict]:
    table = presets()[name]
    return {card: {**base_card(card), **table.get(card, {})} for card in gen.CARDS}


def known() -> dict[str, dict]:
    user = {name: {"type": desc["type"]} for name, desc in CASES["userCurves"].items()}
    return gen.known_curves(gen.check_base(BASE), user, {})


class ParityCasesTest(unittest.TestCase):
    """The same expectations tst_AnimationLogic.qml checks against AnimationLogic.js."""

    def test_card_values(self) -> None:
        for case in CASES["cards"]:
            with self.subTest(case=case):
                try:
                    if case["card"] not in gen.CARDS:
                        raise gen.Invalid("unknown card")
                    gen.check_card_value(case["card"], case["value"], known())
                    valid = True
                except gen.Invalid:
                    valid = False
                self.assertEqual(valid, case["valid"])

    def test_curve_descriptors(self) -> None:
        for case in CASES["curves"]:
            with self.subTest(case=case):
                try:
                    gen.check_curve(case["name"], case["desc"])
                    valid = True
                except gen.Invalid:
                    valid = False
                self.assertEqual(valid, case["valid"])

    def test_styles(self) -> None:
        for case in CASES["styles"]:
            with self.subTest(case=case):
                parsed = gen.parse_style(gen.CARDS[case["card"]][2], case["style"])
                self.assertEqual(parsed is not None, case["known"])
                if parsed is not None:
                    self.assertEqual((parsed["kind"], parsed["percent"], parsed["direction"]),
                                     (case["kind"], case["percent"], case["direction"]))

    def test_companions(self) -> None:
        for case in CASES["companions"]:
            with self.subTest(case=case):
                value = gen.companion_value(case["card"], case["primary"], gen.check_base(BASE), known())
                self.assertEqual(value, case["expect"])

    def test_logic_strings_are_translated(self) -> None:
        # Labels, descriptions and errors of AnimationLogic.js are English
        # source strings shown through Translation.tr.
        code = "\n".join(line for line in LOGIC_JS.read_text(encoding="utf-8").splitlines()
                         if not line.strip().startswith("//"))
        texts = set(re.findall(r'"([A-Z][^"]*)"', code))
        translations = json.loads((ROOT / "config/quickshell/ii/translations/es_MX.json").read_text(encoding="utf-8"))
        self.assertGreater(len(texts), 40)
        self.assertEqual(sorted(t for t in texts if t not in translations), [])

    def test_numbers_never_use_an_exponent(self) -> None:
        self.assertEqual(gen.format_number(1e-05), "0.00001")
        self.assertEqual(gen.format_number(3.0), "3")
        self.assertEqual(gen.format_number(0.1 + 0.2), "0.30000000000000004")
        self.assertEqual(gen.format_number(1e16 + 0.0), "10000000000000000")
        for bad in (float("nan"), float("inf"), True):
            with self.assertRaises(gen.Invalid):
                gen.format_number(bad)


@unittest.skipUnless(QMLTESTRUNNER.is_file(), f"Qt 6 qmltestrunner not found at {QMLTESTRUNNER}")
class ParityQmlTest(unittest.TestCase):
    """tests/test_settings_qml.py runs tst_AnimationLogic.qml without file reads,
    so its fixture-driven parity test skips there; it runs here."""

    def test_animation_logic_reads_the_shared_cases(self) -> None:
        result = subprocess.run(
            [str(QMLTESTRUNNER), "-input", str(QML_TEST)],
            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QML_XHR_ALLOW_FILE_READ": "1"},
            capture_output=True, text=True, timeout=120,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn(", 0 failed, 0 skipped", output)
        self.assertRegex(output, r"PASS\s+:\s+\S*::AnimationLogic::test_parity_cases\(\)")


class GeneratorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.dir = Path(self.temp.name)
        self.file = self.dir / "hypr/custom/shell-animations.lua"
        self.log = self.dir / "hyprctl.log"
        bin_dir = self.dir / "bin"
        bin_dir.mkdir()
        shutil.copy(STUB, bin_dir / "hyprctl")
        (bin_dir / "hyprctl").chmod(0o755)
        self.env = {**os.environ, "PATH": f"{bin_dir}:{os.environ.get('PATH', '/usr/bin:/bin')}",
                    "HYPRCTL_LOG": str(self.log), "HYPRCTL_FIXTURES": str(ROOT / "tests/fixtures")}
        self.env.pop("HYPRCTL_FAIL_MATCH", None)
        self.env.pop("XDG_CONFIG_HOME", None)

    def tearDown(self) -> None:
        for path in self.dir.rglob("*"):
            if path.is_dir():
                path.chmod(0o755)
        self.temp.cleanup()

    def run_gen(self, *args: str, stdin: object | None = None, env: dict | None = None,
                with_file: bool = True) -> tuple[int, dict, str]:
        argv = [sys.executable, str(SCRIPT)] + (["--file", str(self.file)] if with_file else []) + list(args)
        text = None if stdin is None else (stdin if isinstance(stdin, str) else json.dumps(stdin))
        result = subprocess.run(argv, input=text, capture_output=True, text=True, timeout=30, env=env or self.env)
        try:
            data = json.loads(result.stdout) if result.stdout.strip() else {}
        except json.JSONDecodeError:
            self.fail(f"not one JSON object: {result.stdout!r}")
        return result.returncode, data, result.stderr

    def apply(self, changes: dict, *flags: str, base: bool = True) -> tuple[int, dict]:
        payload = dict(changes)
        if base:
            payload.setdefault("base", BASE)
        code, data, _ = self.run_gen("--apply-json", "-", *flags, stdin=payload)
        return code, data

    def listed(self) -> dict:
        code, data, err = self.run_gen("--list", "--json")
        self.assertEqual(code, 0, err)
        return data

    def calls(self) -> list[str]:
        return self.log.read_text(encoding="utf-8").splitlines() if self.log.exists() else []

    def value(self, **fields) -> dict:
        return {"enabled": True, "speed": 3, "curve": "emphasizedDecel", "style": "popin 80%", **fields}

    # ------------------------------------------------------------- list

    def test_list_without_a_file_is_empty(self) -> None:
        data = self.listed()
        self.assertEqual(data, {"ok": True, "exists": False, "cards": {}, "leaves": {}, "curves": {},
                                "appCurves": [], "errors": []})

    def test_foreign_file_is_never_read_as_ours_nor_overwritten(self) -> None:
        self.file.parent.mkdir(parents=True)
        self.file.write_text('hl.animation({ leaf = "border", enabled = false })\n', encoding="utf-8")
        before = self.file.read_bytes()
        code, data, _ = self.run_gen("--list", "--json")
        self.assertEqual((code, data["ok"], data["foreign"]), (3, False, True))
        code, data = self.apply({"removeAllAnimations": True})
        self.assertEqual(code, 3)
        self.assertFalse(data["written"])
        self.assertEqual(self.file.read_bytes(), before)

    def test_symlinked_target_counts_as_foreign(self) -> None:
        real = self.dir / "elsewhere.lua"
        real.write_text(gen.MARKER + "\n", encoding="utf-8")
        self.file.parent.mkdir(parents=True)
        self.file.symlink_to(real)
        code, _ = self.apply({"cards": {"border": self.value(style="")}})
        self.assertEqual(code, 3)
        self.assertEqual(real.read_text(encoding="utf-8"), gen.MARKER + "\n")

    def test_default_file_honours_xdg_config_home(self) -> None:
        env = {**self.env, "XDG_CONFIG_HOME": str(self.dir / "xdg")}
        code, data, _ = self.run_gen("--apply-json", "-", stdin={"base": BASE, "cards": {"border": self.value(style="")}},
                                     env=env, with_file=False)
        self.assertEqual(code, 0, data)
        self.assertTrue((self.dir / "xdg/hypr/custom/shell-animations.lua").is_file())

    def test_usage_errors(self) -> None:
        for args in ([], ["--list"], ["--list", "--json", "--eval"], ["--bogus"]):
            with self.subTest(args=args):
                code, _, _ = self.run_gen(*args)
                self.assertEqual(code, 2)
        code, data, _ = self.run_gen("--apply-json", "-", stdin="{not json")
        self.assertEqual((code, data["ok"]), (2, False))
        for bad in ([], {"cards": {"nope": None}}, {"cards": []}, {"removeAllAnimations": "yes"}, {"extra": 1},
                    {"base": "x"}, {"base": {"curves": {"ok": {"type": "nope"}}}}):
            with self.subTest(changes=bad):
                code, data, _ = self.run_gen("--apply-json", "-", stdin=bad)
                self.assertEqual(code, 2, data)
        self.assertFalse(self.file.exists())

    # ------------------------------------------------------------ apply

    def test_marker_header_and_generated_comment(self) -> None:
        code, data = self.apply({"cards": {"windowsIn": self.value(speed=2)}})
        self.assertEqual(code, 0, data)
        self.assertEqual((data["ok"], data["changed"], data["written"]), (True, True, True))
        lines = self.file.read_text(encoding="utf-8").splitlines()
        self.assertEqual(lines[0], gen.MARKER)
        self.assertIn("Generated file", lines[1])
        self.assertEqual(data["cards"], {"windowsIn": self.value(speed=2)})

    def test_unchanged_content_is_not_rewritten(self) -> None:
        changes = {"cards": {"windowsIn": self.value(speed=2)}}
        self.assertEqual(self.apply(changes)[0], 0)
        os.utime(self.file, (1, 1))
        inode = self.file.stat().st_ino
        code, data = self.apply(changes, "--eval")
        self.assertEqual(code, 0)
        self.assertEqual((data["changed"], data["written"], data["evalOk"]), (False, False, None))
        self.assertEqual((self.file.stat().st_mtime, self.file.stat().st_ino), (1, inode))
        self.assertEqual(self.calls(), [], "an unchanged write makes no hyprctl call")

    def test_write_is_atomic_and_a_failed_write_keeps_the_old_file(self) -> None:
        self.assertEqual(self.apply({"cards": {"border": self.value(style="")}})[0], 0)
        before = self.file.read_bytes()
        self.assertEqual(sorted(p.name for p in self.file.parent.iterdir()), ["shell-animations.lua"])
        self.file.parent.chmod(stat.S_IRUSR | stat.S_IXUSR)
        code, data = self.apply({"cards": {"border": self.value(style="", speed=4)}})
        self.assertEqual(code, 5, data)
        self.assertFalse(data["written"])
        self.assertEqual(self.file.read_bytes(), before)
        self.file.parent.chmod(0o755)
        self.assertEqual(sorted(p.name for p in self.file.parent.iterdir()), ["shell-animations.lua"])

    def test_companions_follow_the_primary(self) -> None:
        code, _ = self.apply({"cards": {"layersIn": self.value(speed=1.8, curve="emphasizedDecel", style="popin 93%"),
                                        "windowsOut": self.value(speed=1.4, style="popin 90%", curve="emphasizedDecel")}})
        self.assertEqual(code, 0)
        leaves = self.listed()["leaves"]
        self.assertEqual(leaves["fadeLayersIn"], {"enabled": True, "speed": 0.33, "curve": "menu_decel", "style": ""})
        self.assertEqual(leaves["fadeOut"], {"enabled": True, "speed": 1.4, "curve": "emphasizedDecel", "style": ""})
        self.assertNotIn("fadeIn", leaves)

    def test_disabled_card_keeps_its_tuple_and_enabling_restores_it(self) -> None:
        tuple_on = self.value(speed=2.5, curve="menu_decel", style="slide left")
        self.assertEqual(self.apply({"cards": {"windowsIn": tuple_on}})[0], 0)
        original = self.file.read_bytes()
        self.assertEqual(self.apply({"cards": {"windowsIn": {**tuple_on, "enabled": False}}})[0], 0)
        text = self.file.read_text(encoding="utf-8")
        self.assertIn('hl.animation({ leaf = "windowsIn", enabled = false, speed = 2.5, bezier = "menu_decel", '
                      'style = "slide left" })', text)
        self.assertIn('leaf = "fadeIn", enabled = false, speed = 2.5', text)
        listed = self.listed()["cards"]["windowsIn"]
        self.assertEqual(listed, {**tuple_on, "enabled": False})
        self.assertEqual(self.apply({"cards": {"windowsIn": {**listed, "enabled": True}}})[0], 0)
        self.assertEqual(self.file.read_bytes(), original)

    def test_card_reset_removes_both_lines(self) -> None:
        self.assertEqual(self.apply({"cards": {"windowsIn": self.value(), "border": self.value(style="")}})[0], 0)
        self.assertEqual(self.apply({"cards": {"windowsIn": None}}, base=False)[0], 0)
        self.assertEqual(set(self.listed()["leaves"]), {"border"})

    def test_every_preset_round_trips(self) -> None:
        for name in presets():
            with self.subTest(preset=name):
                cards = preset_cards(name)
                code, data = self.apply({"cards": cards})
                self.assertEqual(code, 0, data)
                self.assertEqual(self.listed()["cards"], cards)
                self.assert_curves_before_animations()

    def test_default_preset_removes_animations_and_keeps_curves(self) -> None:
        curve = {"type": "bezier", "points": [0.2, 0, 0, 1], "label": "Mine"}
        cards = {**preset_cards("agile"), "border": self.value(style="", curve="ii_mine")}
        self.assertEqual(self.apply({"curves": {"ii_mine": curve}, "cards": cards})[0], 0)
        code, data = self.apply({"removeAllAnimations": True}, base=False)
        self.assertEqual(code, 0, data)
        listed = self.listed()
        self.assertEqual((listed["cards"], listed["leaves"]), ({}, {}))
        self.assertEqual(listed["curves"]["ii_mine"]["label"], "Mine")
        self.assertNotIn("hl.animation", self.file.read_text(encoding="utf-8"))

    def test_curve_in_use_cannot_be_deleted(self) -> None:
        curve = {"type": "spring", "mass": 1, "stiffness": 100, "damping": 10, "label": "Mine"}
        self.assertEqual(self.apply({"curves": {"ii_mine": curve},
                                     "cards": {"border": self.value(style="", curve="ii_mine"),
                                               "zoomFactor": self.value(style="", curve="ii_mine")}})[0], 0)
        before = self.file.read_bytes()
        code, data = self.apply({"curves": {"ii_mine": None}})
        self.assertEqual(code, 2)
        self.assertEqual(data["errors"], ["curve ii_mine is used by: border, zoomFactor"])
        self.assertEqual(self.file.read_bytes(), before)
        self.assertIn('spring = "ii_mine"', before.decode())
        code, _ = self.apply({"curves": {"ii_mine": None}, "cards": {"border": None, "zoomFactor": None}})
        self.assertEqual(code, 0)
        self.assertEqual(self.listed()["curves"], {})
        for name in ("ii_spring_soft", "default", "emphasizedDecel"):
            with self.subTest(curve=name):
                self.assertEqual(self.apply({"curves": {name: None}})[0], 2)

    def test_app_springs_are_written_only_while_used_and_user_curves_always(self) -> None:
        curve = {"type": "bezier", "points": [0.3, 0.1, 0.2, 1], "label": "Ünïcode \"label\""}
        self.assertEqual(self.apply({"curves": {"ii_mine": curve},
                                     "cards": {"windowsIn": self.value(curve="ii_spring_bouncy")}})[0], 0)
        text = self.file.read_text(encoding="utf-8")
        self.assertIn('hl.curve("ii_spring_bouncy", { type = "spring", mass = 1, stiffness = 260, damping = 18 })', text)
        self.assertIn('spring = "ii_spring_bouncy"', text)
        # Springs ignore speed: the companion keeps its base speed.
        self.assertIn('hl.animation({ leaf = "fadeIn", enabled = true, speed = 3, bezier = "emphasizedDecel" })', text)
        self.assertIn('-- ii:curve {"label": "\\u00dcn\\u00efcode \\"label\\"", "name": "ii_mine"}', text)
        self.assert_curves_before_animations()
        self.assertEqual(self.listed()["appCurves"], ["ii_spring_bouncy"])
        self.assertEqual(self.apply({"cards": {"windowsIn": self.value()}})[0], 0)
        text = self.file.read_text(encoding="utf-8")
        self.assertNotIn("ii_spring_bouncy", text)
        self.assertIn('hl.curve("ii_mine"', text)
        self.assertEqual(self.listed()["curves"]["ii_mine"]["label"], 'Ünïcode "label"')

    def test_card_writes_need_the_base(self) -> None:
        code, data = self.apply({"cards": {"border": self.value(style="")}}, base=False)
        self.assertEqual(code, 2)
        self.assertIn("base", data["errors"][0])

    def test_a_dotfiles_curve_that_is_not_an_identifier_is_ignored(self) -> None:
        # One odd name must not reject the whole base (every card write would
        # fail with exit 2): that curve is left out and reported.
        base = json.loads(json.dumps(BASE))
        base["curves"]["my curve"] = {"type": "bezier", "points": [0, 0, 1, 1]}
        code, data = self.apply({"base": base, "cards": {"border": self.value(style="")}})
        self.assertEqual(code, 0, data)
        self.assertEqual(data["errors"], ["base.curves.my curve is not a Lua identifier; it is ignored"])
        self.assertEqual(data["cards"]["border"], self.value(style=""))
        code, data = self.apply({"base": base, "cards": {"border": self.value(style="", curve="my curve")}})
        self.assertEqual(code, 2, data)
        checked = gen.check_base(base)
        self.assertNotIn("my curve", checked["curves"])
        self.assertIn("emphasizedDecel", checked["curves"])

    def test_a_base_animation_using_an_ignored_curve_is_ignored(self) -> None:
        # The realistic case: the dotfiles define the odd curve to use it.
        # That animation is left out (its parent or Hyprland's compiled tuple
        # applies) and an unrelated card write still succeeds.
        base = json.loads(json.dumps(BASE))
        base["curves"]["my-curve"] = {"type": "bezier", "points": [0, 0, 1, 1]}
        base["animations"]["windowsMove"] = {"enabled": True, "speed": 3, "bezier": "my-curve"}
        code, data = self.apply({"base": base, "cards": {"border": self.value(style="")}})
        self.assertEqual(code, 0, data)
        self.assertEqual(data["errors"], [
            "base.curves.my-curve is not a Lua identifier; it is ignored",
            "base.animations.windowsMove uses the ignored curve my-curve; it is ignored",
        ])
        self.assertEqual(data["cards"]["border"], self.value(style=""))
        checked = gen.check_base(base)
        self.assertNotIn("windowsMove", checked["animations"])
        self.assertEqual(gen.resolve(checked, "windowsMove"), gen.resolve(checked, "windows"))
        # A malformed animation still rejects the base.
        base["animations"]["windowsMove"] = {"enabled": True, "speed": 3, "bezier": 7}
        self.assertEqual(self.apply({"base": base, "cards": {"border": self.value(style="")}})[0], 2)

    def test_a_base_animation_without_a_speed_inherits(self) -> None:
        # hyprbase.py drops a non-finite speed (`speed = 1/0`) and leaves the
        # leaf without one. Hyprland rejects that call, so the leaf inherits
        # from its parent; one such line must not refuse the whole base.
        base = json.loads(json.dumps(BASE))
        base["animations"]["windowsMove"] = {"enabled": True, "bezier": "default"}
        code, data = self.apply({"base": base, "cards": {"border": self.value(style="")}})
        self.assertEqual(code, 0, data)
        self.assertEqual(data["errors"], ["base.animations.windowsMove has no speed; it is ignored"])
        self.assertEqual(data["cards"]["border"], self.value(style=""))
        checked = gen.check_base(base)
        self.assertNotIn("windowsMove", checked["animations"])
        self.assertEqual(gen.resolve(checked, "windowsMove"), gen.resolve(checked, "windows"))
        # A speed that is present but out of range still rejects the base.
        base["animations"]["windowsMove"] = {"enabled": True, "speed": 0, "bezier": "default"}
        self.assertEqual(self.apply({"base": base, "cards": {"border": self.value(style="")}})[0], 2)

    def test_carried_over_lines_are_validated_again(self) -> None:
        # The file regex accepts styles the allowlist does not (a side on
        # workspaces), so lines carried over from the file are checked again.
        self.assertEqual(self.apply({"cards": {"border": self.value(style="")}})[0], 0)
        with self.file.open("a", encoding="utf-8") as handle:
            handle.write('hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "menu_decel", '
                         'style = "slide top" })\n')
        before = self.file.read_bytes()
        code, data = self.apply({"cards": {"border": self.value(style="", speed=4)}})
        self.assertEqual(code, 2, data)
        self.assertIn("leaf workspaces", data["errors"][0])
        self.assertEqual(self.file.read_bytes(), before)

    def test_unknown_lines_are_reported_and_dropped(self) -> None:
        self.assertEqual(self.apply({"cards": {"border": self.value(style="")}})[0], 0)
        with self.file.open("a", encoding="utf-8") as handle:
            handle.write('os.execute("true")\n')
        self.assertEqual(len(self.listed()["errors"]), 1)
        self.assertEqual(self.apply({"cards": {"border": self.value(style="", speed=4)}})[0], 0)
        self.assertNotIn("os.execute", self.file.read_text(encoding="utf-8"))

    def test_invalid_and_injection_cases_change_nothing(self) -> None:
        self.assertEqual(self.apply({"cards": {"border": self.value(style="")}})[0], 0)
        before = self.file.read_bytes()
        for case in CASES["cards"]:
            # null is not a value: in a change set it removes the card.
            if case["valid"] or case["card"] not in gen.CARDS or case["value"] is None:
                continue
            with self.subTest(case=case):
                code, data = self.apply({"cards": {case["card"]: case["value"]},
                                         "curves": {"ii_user": CASES["userCurves"]["ii_user"]}}, "--eval")
                self.assertEqual(code, 2, data)
        for case in CASES["curves"]:
            if case["valid"] or case["desc"] is None:
                continue
            with self.subTest(case=case):
                code, data = self.apply({"curves": {case["name"]: case["desc"]}}, "--eval")
                self.assertEqual(code, 2, data)
        self.assertEqual(self.file.read_bytes(), before)
        self.assertEqual(self.calls(), [], "nothing invalid reaches hyprctl")

    def test_valid_cases_produce_only_allowlisted_lua(self) -> None:
        line = re.compile(r'(hl\.(curve|animation)\(.*\)|-- .*|)')
        for case in CASES["curves"]:
            if not case["valid"]:
                continue
            with self.subTest(case=case):
                code, data = self.apply({"curves": {case["name"]: case["desc"]},
                                         "cards": {"border": self.value(style="", curve=case["name"])}})
                self.assertEqual(code, 0, data)
                text = self.file.read_text(encoding="utf-8")
                self.assertTrue(text.isascii())
                for row in text.splitlines():
                    self.assertRegex(row, line)
                self.assertEqual(self.listed()["curves"][case["name"]]["label"], case["desc"]["label"])
                self.assertEqual(self.apply({"curves": {case["name"]: None}, "cards": {"border": None}})[0], 0)

    # ------------------------------------------------------------- eval

    def test_eval_failure_reloads_and_writes_nothing(self) -> None:
        self.assertEqual(self.apply({"cards": {"border": self.value(style="")}})[0], 0)
        before = self.file.read_bytes()
        env = {**self.env, "HYPRCTL_FAIL_MATCH": 'leaf = "zoomFactor"'}
        payload = {"base": BASE, "cards": {"windowsIn": self.value(speed=2), "zoomFactor": self.value(style="")}}
        code, data, _ = self.run_gen("--apply-json", "-", "--eval", stdin=payload, env=env)
        self.assertEqual(code, 4, data)
        self.assertEqual((data["ok"], data["evalOk"], data["reloaded"], data["written"]), (False, False, True, False))
        self.assertIn("stub failure", data["errors"][0])
        calls = self.calls()
        self.assertEqual(len(calls), 2, calls)
        self.assertTrue(calls[0].startswith("eval "))
        self.assertEqual(calls[1], "reload config-only")
        self.assertEqual(self.file.read_bytes(), before)

    def test_eval_error_text_with_exit_0_counts_as_a_failure(self) -> None:
        # Hyprland reports binding errors as "error: ..." with exit 0.
        bin_dir = self.dir / "bin"
        (bin_dir / "hyprctl").write_text(
            "#!/bin/sh\n"
            f'printf "%s\\n" "$*" >> "{self.log}"\n'
            'if [ "$1" = eval ]; then echo "error: no such bezier"; else echo ok; fi\n', encoding="utf-8")
        before_exists = self.file.exists()
        code, data = self.apply({"cards": {"border": self.value(style="")}}, "--eval")
        self.assertEqual(code, 4, data)
        self.assertEqual((data["ok"], data["evalOk"], data["reloaded"], data["written"]), (False, False, True, False))
        self.assertEqual(data["errors"], ["error: no such bezier"])
        calls = self.calls()
        self.assertEqual(len(calls), 2, calls)
        self.assertTrue(calls[0].startswith("eval "), calls)
        self.assertEqual(calls[1], "reload config-only")
        self.assertEqual(self.file.exists(), before_exists)

    def test_eval_success_applies_changed_statements_once_curves_first(self) -> None:
        curve = {"type": "bezier", "points": [0.3, 0.1, 0.2, 1], "label": "Mine"}
        code, data = self.apply({"curves": {"ii_mine": curve},
                                 "cards": {"windowsIn": self.value(curve="ii_mine"), "border": self.value(style="")}},
                                "--eval")
        self.assertEqual(code, 0, data)
        self.assertEqual((data["evalOk"], data["written"], data["reloaded"]), (True, True, False))
        calls = self.calls()
        self.assertEqual(len(calls), 1, calls)
        statements = calls[0][len("eval "):].split("; ")
        self.assertTrue(statements[0].startswith('hl.curve("ii_mine"'), statements)
        self.assertEqual(len(statements), 4, statements)
        self.assertTrue(all(s.startswith("hl.animation(") for s in statements[1:]))
        self.assertTrue(self.file.exists())
        # A second change evaluates only what changed.
        code, data = self.apply({"cards": {"border": self.value(style="", speed=6)}}, "--eval")
        self.assertEqual(code, 0, data)
        self.assertEqual(self.calls()[1], 'eval hl.animation({ leaf = "border", enabled = true, speed = 6, '
                                          'bezier = "emphasizedDecel" })')
        # Removals cannot be evaluated: the reload after the write applies them.
        code, data = self.apply({"cards": {"border": None}}, "--eval")
        self.assertEqual((code, data["changed"], data["evalOk"]), (0, True, None))
        self.assertEqual(len(self.calls()), 2)

    def assert_curves_before_animations(self) -> None:
        rows = self.file.read_text(encoding="utf-8").splitlines()
        kinds = [row.split("(")[0] for row in rows if row.startswith("hl.")]
        self.assertEqual(kinds, sorted(kinds, key=lambda k: k != "hl.curve"), rows)


if __name__ == "__main__":
    unittest.main()
