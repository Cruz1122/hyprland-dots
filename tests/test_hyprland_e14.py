"""Options added in wave 2 (E14) round-trip through HyprlandBackend and pass Hyprland.

Runs tests/harness/drivers/hyprland-e14.qml with the fake hyprctl: each option
is written through the store, read back, counted as modified and reset. The
generated custom/shell-settings.lua must hold one `hl.config` line per option,
and that file must pass `Hyprland --verify-config` (offline, private HOME and
XDG directories, no HYPRLAND_INSTANCE_SIGNATURE: the live session is never
contacted). The registry side (names, types, ranges against the 0.57
fixture) is in tests/test_hyprland_registry.py.

The Advanced page's "Hyprland configuration errors" row runs
tests/harness/drivers/config-errors.qml with each HYPRCTL_CONFIGERRORS
fixture, with the stub's default `[""]` and without the stub (Hyprland not
running); its parser is unit-tested in tst_SettingsAdvancedLogic.qml.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DRIVER = ROOT / "tests/harness/drivers/hyprland-e14.qml"
ERRORS_DRIVER = ROOT / "tests/harness/drivers/config-errors.qml"
FIXTURES = ROOT / "tests/fixtures"
REGISTRY = ROOT / "config/quickshell/ii/modules/settings/registry"
HYPRLAND = shutil.which("Hyprland")
MARKER = "[harness:report] "

# Line hyprconfigurator.py writes for the value the driver sets.
EXPECTED_LINES = [
    "hl.config({input={scroll_factor=1.5}})",
    "hl.config({cursor={hide_on_key_press=true}})",
    "hl.config({input={focus_on_close=2}})",
    "hl.config({input={touchpad={tap_and_drag=false}}})",
    "hl.config({input={touchpad={drag_lock=2}}})",
    "hl.config({binds={workspace_back_and_forth=1}})",
    "hl.config({misc={middle_click_paste=false}})",
    "hl.config({misc={initial_workspace_tracking=2}})",
    "hl.config({ecosystem={no_update_news=true}})",
    "hl.config({ecosystem={no_donation_nag=true}})",
]
E14_KEYS = {
    "input": ["hyprland.input.scroll_factor", "hyprland.cursor.hide_on_key_press", "hyprland.input.focus_on_close",
              "hyprland.input.touchpad.tap_and_drag", "hyprland.input.touchpad.drag_lock"],
    "windows": ["hyprland.binds.workspace_back_and_forth", "hyprland.misc.middle_click_paste",
                "hyprland.misc.initial_workspace_tracking"],
    "advanced": ["hyprland.ecosystem.no_update_news", "hyprland.ecosystem.no_donation_nag"],
}


def verify_config(lua: str) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as temp:
        home = Path(temp) / "home"
        hypr = home / ".config/hypr"
        (hypr / "custom").mkdir(parents=True)
        runtime = Path(temp) / "runtime"
        runtime.mkdir(mode=0o700)
        (hypr / "custom/shell-settings.lua").write_text(lua, encoding="utf-8")
        # Loaded the way config/hypr/hyprland.lua loads it.
        (hypr / "hyprland.lua").write_text('require("custom.shell-settings")\n', encoding="utf-8")
        env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(home),
               "XDG_CONFIG_HOME": str(home / ".config"), "XDG_RUNTIME_DIR": str(runtime),
               "XDG_CACHE_HOME": str(home / ".cache"), "XDG_STATE_HOME": str(home / ".local/state")}
        return subprocess.run([HYPRLAND, "--verify-config", "-c", str(hypr / "hyprland.lua")],
                              env=env, capture_output=True, text=True, timeout=60)


class E14RegistryTest(unittest.TestCase):
    def test_each_option_is_on_its_page(self) -> None:
        for page, keys in E14_KEYS.items():
            entries = {e["key"]: e for e in json.loads((REGISTRY / f"{page}.json").read_text(encoding="utf-8"))["entries"]}
            for key in keys:
                with self.subTest(key=key):
                    self.assertIn(key, entries)
                    self.assertEqual(entries[key]["backend"], "hyprland")

    def test_touchpad_rows_need_a_touchpad(self) -> None:
        entries = {e["key"]: e for e in json.loads((REGISTRY / "input.json").read_text(encoding="utf-8"))["entries"]}
        for key in ("hyprland.input.touchpad.tap_and_drag", "hyprland.input.touchpad.drag_lock"):
            self.assertEqual(entries[key]["section"], "touchpad")
            self.assertEqual(entries[key]["visibleWhen"], {"capability": "touchpad"})
        self.assertEqual(entries["hyprland.input.touchpad.drag_lock"]["enabledWhen"],
                         {"key": "hyprland.input.touchpad.tap_and_drag", "equals": True})
        self.assertEqual(entries["hyprland.input.scroll_factor"]["section"], "mouse")
        self.assertEqual((entries["hyprland.input.scroll_factor"]["min"], entries["hyprland.input.scroll_factor"]["max"],
                          entries["hyprland.input.scroll_factor"]["unit"]), (0.1, 3, "×"))

    def test_vrr_needs_a_capable_display(self) -> None:
        entries = {e["key"]: e for e in json.loads((REGISTRY / "windows.json").read_text(encoding="utf-8"))["entries"]}
        self.assertEqual(entries["hyprland.misc.vrr"]["enabledWhen"], {"capability": "vrr"})
        self.assertNotIn("visibleWhen", entries["hyprland.misc.vrr"], "the row stays visible, disabled with the reason")


class E14RoundTripTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        with tempfile.TemporaryDirectory() as out:
            cls.result = subprocess.run(
                ["bash", str(RUN), "--driver", str(DRIVER), "--renderer", "software", "--hyprland-stub",
                 "--strict", "--allow-config-writes", "--out", out, "--timeout", "120"],
                capture_output=True, text=True, timeout=180,
            )
            log_path = Path(out) / "harness.log"
            cls.log = log_path.read_text(encoding="utf-8", errors="replace") if log_path.is_file() else ""
            calls = Path(out) / "hyprctl.log"
            cls.calls = calls.read_text(encoding="utf-8") if calls.is_file() else ""
        cls.events = [json.loads(line[line.index(MARKER) + len(MARKER):])
                      for line in cls.log.splitlines() if MARKER in line]

    def setUp(self) -> None:
        if self.result.returncode == 77:
            self.skipTest(self.result.stderr.strip() or "harness prerequisites missing")

    def context(self) -> str:
        return self.result.stdout + self.log[-3000:]

    def test_driver_checks_pass(self) -> None:
        self.assertFalse([e for e in self.events if e.get("type") == "fatal"], self.context())
        checks = [e for e in self.events if e.get("type") == "check"]
        # 10 options × (registered, differs, write, read, modified, reset, not modified, gone) + 5 others.
        self.assertEqual(len(checks), 85, self.context())
        for check in checks:
            with self.subTest(check=check["name"]):
                self.assertTrue(check["ok"], check)
        self.assertEqual([e.get("failures") for e in self.events if e.get("type") == "done"], [0], self.context())
        # --strict: no QML warning.
        self.assertEqual(self.result.returncode, 0, self.context())

    def test_generated_file_has_one_line_per_option(self) -> None:
        files = [e["text"] for e in self.events if e.get("type") == "file"]
        self.assertEqual(len(files), 1, self.context())
        lines = [line for line in files[0].splitlines() if line.startswith("hl.config(")]
        self.assertEqual(sorted(lines), sorted(EXPECTED_LINES), files[0])
        after = [e["text"] for e in self.events if e.get("type") == "fileAfterReset"]
        self.assertEqual(len(after), 1, self.context())
        self.assertEqual([line for line in after[0].splitlines() if line.startswith("hl.config(")], [], after[0])

    def test_nothing_is_evaluated_live(self) -> None:
        # Not risky: values reach Hyprland through the file and a reload only.
        self.assertNotIn("eval ", self.calls)
        self.assertNotIn("keyword", self.calls)

    @unittest.skipIf(HYPRLAND is None, "Hyprland is not installed: cannot run --verify-config")
    def test_generated_file_passes_verify_config(self) -> None:
        files = [e["text"] for e in self.events if e.get("type") == "file"]
        self.assertTrue(files, self.context())
        result = verify_config(files[0])
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, f"{files[0]}\n{output[-3000:]}")
        self.assertIn("config ok", output)

    @unittest.skipIf(HYPRLAND is None, "Hyprland is not installed: cannot run --verify-config")
    def test_verify_config_catches_a_wrong_name(self) -> None:
        # Negative control: the getoption name with "-" is not a Lua key.
        result = verify_config("hl.config({input={touchpad={tap-and-drag=false}}})\n")
        self.assertNotEqual(result.returncode, 0)
        result = verify_config("hl.config({input={touchpad={tap_and_dragx=false}}})\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("unknown config key 'input.touchpad.tap_and_dragx'", result.stdout + result.stderr)


def run_config_errors(*, stub: bool, fixture: str | None = None) -> tuple[subprocess.CompletedProcess, list, str, str]:
    with tempfile.TemporaryDirectory() as out:
        argv = ["bash", str(RUN), "--driver", str(ERRORS_DRIVER), "--renderer", "software", "--strict",
                "--out", out, "--timeout", "90"]
        if stub:
            argv.append("--hyprland-stub")
        if fixture:
            argv += ["--env", f"HYPRCTL_CONFIGERRORS={FIXTURES / f'hyprctl-configerrors-{fixture}.json'}"]
        result = subprocess.run(argv, capture_output=True, text=True, timeout=150)
        log_path = Path(out) / "harness.log"
        log = log_path.read_text(encoding="utf-8", errors="replace") if log_path.is_file() else ""
        calls_path = Path(out) / "hyprctl.log"
        calls = calls_path.read_text(encoding="utf-8") if calls_path.is_file() else ""
    events = [json.loads(line[line.index(MARKER) + len(MARKER):]) for line in log.splitlines() if MARKER in line]
    return result, events, calls, log[-3000:]


class ConfigErrorsRowTest(unittest.TestCase):
    def run_row(self, **kwargs) -> tuple[list, str]:
        result, events, calls, log = run_config_errors(**kwargs)
        self.calls = calls
        if result.returncode == 77:
            self.skipTest(result.stderr.strip() or "harness prerequisites missing")
        context = result.stdout + calls + log
        self.assertFalse([e for e in events if e.get("type") == "fatal"], context)
        # --strict: no QML warning, no overlap.
        self.assertEqual(result.returncode, 0, context)
        return [e for e in events if e.get("type") == "state"], context

    def assert_checked_twice(self, states: list, context: str) -> None:
        # Once when the page opens, once more on "Check again", argv only.
        self.assertEqual([s["step"] for s in states], ["open", "again"], context)
        self.assertEqual(self.calls.splitlines().count("-j configerrors"), 2, context)
        self.assertEqual(states[0]["status"], states[1]["status"], context)

    def test_no_errors(self) -> None:
        for fixture in ("none", None):
            with self.subTest(fixture=fixture or "stub default [\"\"]"):
                states, context = self.run_row(stub=True, fixture=fixture)
                self.assert_checked_twice(states, context)
                self.assertEqual(states[0]["status"], "none", context)
                self.assertEqual(states[0]["errors"], [], context)
                self.assertIn(states[0]["summary"], ("No errors", "Sin errores"), context)
                self.assertFalse(states[0]["textShown"], context)
                self.assertTrue(states[0]["buttonShown"], context)

    def test_two_errors_are_listed(self) -> None:
        states, context = self.run_row(stub=True, fixture="two")
        self.assert_checked_twice(states, context)
        state = states[0]
        self.assertEqual(state["status"], "errors", context)
        self.assertEqual(len(state["errors"]), 2, context)
        self.assertIn(state["summary"], ("2 errors", "2 errores"), context)
        self.assertTrue(state["textShown"] and state["selectable"] and state["wraps"] and state["textInside"], state)
        self.assertIn("unknown config key 'general.gaps_inn'", state["text"])
        self.assertIn("custom/rules.lua at line 3", state["text"])

    def test_malformed_answer(self) -> None:
        states, context = self.run_row(stub=True, fixture="malformed")
        self.assert_checked_twice(states, context)
        self.assertEqual(states[0]["status"], "failed", context)
        self.assertFalse(states[0]["textShown"], context)

    def test_hyprland_not_running(self) -> None:
        states, context = self.run_row(stub=False)
        self.assertEqual([s["step"] for s in states], ["open"], context)
        self.assertEqual(states[0]["status"], "unavailable", context)
        self.assertIn(states[0]["summary"], ("Hyprland is not running", "Hyprland no se está ejecutando"), context)
        self.assertFalse(states[0]["buttonShown"], context)


if __name__ == "__main__":
    unittest.main()
