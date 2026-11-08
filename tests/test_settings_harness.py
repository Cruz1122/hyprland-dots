"""Unit tests for the settings harness summarizer; no sandbox or GPU needed."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUMMARIZE = ROOT / "scripts/settings-harness/summarize.py"
RUN = ROOT / "scripts/settings-harness/run.sh"
KNOWN = ROOT / "tests/harness/known-env-warnings.txt"
HYPRCTL = ROOT / "tests/harness/stubs/hyprctl"
FIXTURES = ROOT / "tests/fixtures"


def report(payload: dict) -> str:
    return f" DEBUG qml: [harness:report] {json.dumps(payload)}"


class SummarizeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.dir = Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def summarize(self, lines: list[str], *, strict: bool = False, before: dict | None = None,
                  after: dict | None = None, exit_code: int = 0, allow_writes: bool = False,
                  hypr_before: dict | None = None, hypr_after: dict | None = None,
                  hyprctl_calls: list[str] | None = None) -> tuple[int, dict]:
        log = self.dir / "harness.log"
        log.write_text("\n".join(lines) + "\n", encoding="utf-8")
        args = [sys.executable, str(SUMMARIZE), "--log", str(log), "--known", str(KNOWN),
                "--out", str(self.dir / "report.json"), "--exit-code", str(exit_code)]
        if before is not None and after is not None:
            (self.dir / "before.json").write_text(json.dumps(before), encoding="utf-8")
            (self.dir / "after.json").write_text(json.dumps(after), encoding="utf-8")
            args += ["--config-before", str(self.dir / "before.json"), "--config-after", str(self.dir / "after.json")]
        if hypr_before is not None and hypr_after is not None:
            (self.dir / "hypr.before.json").write_text(json.dumps(hypr_before), encoding="utf-8")
            (self.dir / "hypr.after.json").write_text(json.dumps(hypr_after), encoding="utf-8")
            args += ["--hypr-before", str(self.dir / "hypr.before.json"),
                     "--hypr-after", str(self.dir / "hypr.after.json")]
        if hyprctl_calls is not None:
            (self.dir / "hyprctl.log").write_text("".join(f"{call}\n" for call in hyprctl_calls), encoding="utf-8")
            args += ["--hyprctl-log", str(self.dir / "hyprctl.log")]
        if strict:
            args.append("--strict")
        if allow_writes:
            args.append("--allow-config-writes")
        result = subprocess.run(args, capture_output=True, text=True, timeout=30)
        return result.returncode, json.loads((self.dir / "report.json").read_text(encoding="utf-8"))

    def page(self, name: str, **extra) -> dict:
        return {"type": "page", "size": "800x600", "index": 0, "name": name, "file": f"/x/{name}.png",
                "saved": True, "openPopups": 0, "rows": 3, "overlaps": [], "overflowX": [], **extra}

    def test_clean_run_passes_in_strict_mode(self) -> None:
        code, data = self.summarize([
            report({"type": "visit", "size": "800x600", "name": "quick"}),
            report(self.page("quick")),
            report({"type": "done"}),
        ], strict=True, before={"a": 1}, after={"a": 1})
        self.assertEqual(code, 0, data)
        self.assertTrue(data["ok"])
        self.assertFalse(data["config"]["rewritten"])

    def test_warnings_are_attributed_to_the_visited_page(self) -> None:
        code, data = self.summarize([
            "  WARN scene: startup problem",
            report({"type": "visit", "size": "800x600", "name": "bar"}),
            "  WARN scene: @modules/settings/Bar.qml[3:4]: Unable to assign [undefined] to bool",
            report(self.page("bar")),
            report({"type": "done"}),
        ])
        self.assertEqual(code, 0, "warnings only fail in strict mode")
        contexts = [warning["context"] for warning in data["appWarnings"]]
        self.assertEqual(contexts, ["startup", "800x600/bar"])

    def test_known_sandbox_noise_is_not_an_app_warning(self) -> None:
        _, data = self.summarize([
            "  WARN: The active compositor does not support hyprland_global_shortcuts_v1.",
            report({"type": "done"}),
        ])
        self.assertEqual(data["appWarnings"], [])
        self.assertEqual(data["envWarnings"], 1)

    def test_missing_hyprland_socket_is_sandbox_noise(self) -> None:
        # --hyprland-stub sets HYPRLAND_INSTANCE_SIGNATURE without an event socket.
        _, data = self.summarize([
            "  WARN: Unable to find hyprland socket. Cannot connect to hyprland.",
            report({"type": "done"}),
        ], strict=True)
        self.assertEqual(data["appWarnings"], [])
        self.assertEqual(data["envWarnings"], 1)

    def test_strict_mode_fails_on_layout_findings_popups_and_config_writes(self) -> None:
        code, data = self.summarize([
            report({"type": "visit", "size": "800x600", "name": "bar"}),
            report(self.page("bar", overlaps=["a x b"], overflowX=["c"], openPopups=2)),
            report({"type": "done"}),
        ], strict=True, before={"bar": {"x": 1}}, after={"bar": {"x": 2}})
        self.assertEqual(code, 1)
        joined = " ".join(data["strictProblems"])
        for fragment in ("overlapping", "overflow", "popup", "config.json written"):
            self.assertIn(fragment, joined)
        self.assertEqual(data["config"]["changed"], [{"key": "bar.x", "before": 1, "after": 2}])

    def test_allowed_config_writes_are_reported_not_failed(self) -> None:
        lines = [report({"type": "done"})]
        code, data = self.summarize(lines, strict=True, before={"bar": {"x": 1}}, after={"bar": {"x": 1}, "y": 2},
                                    allow_writes=True)
        self.assertEqual(code, 0, data)
        self.assertTrue(data["config"]["rewritten"])
        code, data = self.summarize(lines + ["  WARN qml: broken"], strict=True, before={"a": 1}, after={"a": 2},
                                    allow_writes=True)
        self.assertEqual(code, 1, "warnings still fail")

    def test_strict_mode_fails_on_hyprland_file_writes(self) -> None:
        lines = [report({"type": "done"})]
        before = {"hypr/custom/shell-settings.lua": "aa", "hypr/monitors.lua": "bb"}
        code, data = self.summarize(lines, strict=True, hypr_before=before, hypr_after=dict(before))
        self.assertEqual(code, 0, data)
        self.assertEqual(data["hyprConfig"], {"checked": True, "written": [], "removed": []})
        after = {"hypr/custom/shell-settings.lua": "cc", "hypr/custom/shell-animations.lua": "dd"}
        code, data = self.summarize(lines, strict=True, hypr_before=before, hypr_after=after)
        self.assertEqual(code, 1, data)
        self.assertEqual(data["strictProblems"], [
            "unexpected write to hypr/custom/shell-animations.lua",
            "unexpected write to hypr/custom/shell-settings.lua",
            "unexpected removal of hypr/monitors.lua",
        ])
        code, data = self.summarize(lines, hypr_before=before, hypr_after=after)
        self.assertEqual(code, 0, "Hyprland file writes only fail in strict mode")
        code, data = self.summarize(lines, strict=True, allow_writes=True, hypr_before=before, hypr_after=after)
        self.assertEqual(code, 0, data)
        self.assertEqual(data["hyprConfig"]["written"],
                         ["hypr/custom/shell-animations.lua", "hypr/custom/shell-settings.lua"])

    def test_hyprland_stub_runs_must_use_the_stub_and_render_hyprland_rows_available(self) -> None:
        ok_calls = ["-j monitors all", "-j descriptions", "-j devices"]
        good = [report(self.page("windows", unavailable={"ipc": 1})), report({"type": "done"})]
        code, data = self.summarize(good, strict=True, hyprctl_calls=ok_calls)
        self.assertEqual(code, 0, data)

        code, data = self.summarize(good, strict=True, hyprctl_calls=[])
        self.assertEqual(code, 1, data)
        self.assertEqual(data["strictProblems"], ["the Hyprland stub never answered '-j descriptions' (see hyprctl.log)"])

        down = [report(self.page("windows", unavailable={"hyprland": 4})), report({"type": "done"})]
        code, data = self.summarize(down, strict=True, hyprctl_calls=ok_calls)
        self.assertEqual(code, 1, data)
        self.assertEqual(data["strictProblems"], ["800x600/windows: 4 Hyprland row(s) unavailable with the Hyprland stub"])

        animations_down = [report(self.page("animations", unavailable={"animation": 2})), report({"type": "done"})]
        code, data = self.summarize(animations_down, strict=True, hyprctl_calls=ok_calls)
        self.assertEqual(code, 1, data)
        self.assertEqual(data["strictProblems"],
                         ["800x600/animations: 2 animation row(s) unavailable with the Hyprland stub"])

        code, data = self.summarize(down, strict=True)
        self.assertEqual(code, 0, "runs without the stub may render Hyprland rows unavailable")
        code, data = self.summarize(down, hyprctl_calls=[])
        self.assertEqual(code, 0, "only strict mode enforces the stub expectations")

    def test_missing_hyprland_manifests_are_not_checked(self) -> None:
        code, data = self.summarize([report({"type": "done"})], strict=True)
        self.assertEqual(code, 0, data)
        self.assertEqual(data["hyprConfig"], {"checked": False})

    def test_missing_completion_or_unsaved_screenshot_always_fails(self) -> None:
        code, data = self.summarize([report(self.page("bar", saved=False))])
        self.assertEqual(code, 1)
        self.assertIn("driver never reported completion", data["problems"])
        self.assertTrue(any("not saved" in problem for problem in data["problems"]))

    def test_timeout_exit_status_fails(self) -> None:
        code, data = self.summarize([report({"type": "done"})], exit_code=124)
        self.assertEqual(code, 1)
        self.assertIn("124", data["problems"][0])


class HyprctlStubTest(unittest.TestCase):
    """tests/harness/stubs/hyprctl, the fake hyprctl behind run.sh --hyprland-stub."""

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.dir = Path(self.temp.name)
        self.log = self.dir / "hyprctl.log"
        self.env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HYPRCTL_FIXTURES": str(FIXTURES),
                    "HYPRCTL_LOG": str(self.log)}

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_stub(self, *argv: str, **env: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([str(HYPRCTL), *argv], capture_output=True, text=True, timeout=30,
                              env={**self.env, **env})

    def json_of(self, *argv: str) -> object:
        result = self.run_stub(*argv)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_descriptions_match_the_options_fixture_at_their_defaults(self) -> None:
        options = {name: data for name, data in json.loads((FIXTURES / "hyprland-options.json").read_text()).items()
                   if not name.startswith("_")}
        listed = self.json_of("-j", "descriptions")
        self.assertIsInstance(listed, list)
        self.assertEqual(sorted(item["name"] for item in listed), sorted(options))
        for item in listed:
            # HyprlandLogic.parseDescriptions reads name, current and default.
            self.assertEqual(item["current"], item["default"], item["name"])
            self.assertEqual(item["default"], options[item["name"]]["default"], item["name"])

    def test_read_queries_come_from_the_fixtures(self) -> None:
        devices = self.json_of("-j", "devices")
        self.assertTrue(any("touchpad" in mouse["name"] for mouse in devices["mice"]), "touchpad rows enable")
        self.assertEqual(len(devices["keyboards"]), 1)
        monitors = json.loads((FIXTURES / "hyprctl-monitors-all.json").read_text())
        self.assertEqual(self.json_of("-j", "monitors", "all"), monitors)
        self.assertEqual(self.json_of("-j", "monitors"), [m for m in monitors if not m.get("disabled")])
        self.assertEqual(self.json_of("-j", "animations"),
                         json.loads((FIXTURES / "hyprctl-animations.json").read_text()))
        self.assertEqual(self.json_of("-j", "getoption", "general:gaps_workspaces"),
                         {"option": "general:gaps_workspaces", "int": 0, "set": False})

    def test_configerrors_default_to_none_or_come_from_a_file(self) -> None:
        self.assertEqual(self.json_of("-j", "configerrors"), [""])
        errors = self.dir / "errors.json"
        errors.write_text(json.dumps(["custom/x.lua:1: boom"]), encoding="utf-8")
        result = self.run_stub("-j", "configerrors", HYPRCTL_CONFIGERRORS=str(errors))
        self.assertEqual(json.loads(result.stdout), ["custom/x.lua:1: boom"])

    def test_eval_fails_only_when_the_expression_matches(self) -> None:
        result = self.run_stub("eval", "hl.config({general={gaps_in=2}})", HYPRCTL_FAIL_MATCH=r"hl\.animation")
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "ok"))
        expr = 'hl.animation({leaf="windowsIn", enabled=true})'
        result = self.run_stub("eval", expr, HYPRCTL_FAIL_MATCH=r"hl\.animation")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stderr.strip(), f"error: stub failure for {expr}")
        for command in (["reload", "config-only"], ["dispatch", "exec", "x"], ["keyword", "a", "b"], ["version"]):
            result = self.run_stub(*command)
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "ok"), command)

    def test_every_call_is_logged(self) -> None:
        self.run_stub("-j", "devices")
        self.run_stub("eval", "hl.config({})")
        self.assertEqual(self.log.read_text(encoding="utf-8").splitlines(), ["-j devices", "eval hl.config({})"])


class RunScriptArgumentsTest(unittest.TestCase):
    def test_help_documents_the_hyprland_stub(self) -> None:
        result = subprocess.run(["bash", str(RUN), "--help"], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--hyprland-stub", result.stdout)
        self.assertIn("hypr/custom", result.stdout)

    def test_invalid_size_is_a_usage_error(self) -> None:
        result = subprocess.run(["bash", str(RUN), "--sizes", "800by600"], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("invalid size", result.stderr)

    def test_unknown_option_is_a_usage_error(self) -> None:
        result = subprocess.run(["bash", str(RUN), "--bogus"], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 2, result.stderr)


if __name__ == "__main__":
    unittest.main()
