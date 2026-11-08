"""Unit tests for the settings harness summarizer; no sandbox or GPU needed."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUMMARIZE = ROOT / "scripts/settings-harness/summarize.py"
RUN = ROOT / "scripts/settings-harness/run.sh"
KNOWN = ROOT / "tests/harness/known-env-warnings.txt"


def report(payload: dict) -> str:
    return f" DEBUG qml: [harness:report] {json.dumps(payload)}"


class SummarizeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.dir = Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def summarize(self, lines: list[str], *, strict: bool = False, before: dict | None = None,
                  after: dict | None = None, exit_code: int = 0, allow_writes: bool = False) -> tuple[int, dict]:
        log = self.dir / "harness.log"
        log.write_text("\n".join(lines) + "\n", encoding="utf-8")
        args = [sys.executable, str(SUMMARIZE), "--log", str(log), "--known", str(KNOWN),
                "--out", str(self.dir / "report.json"), "--exit-code", str(exit_code)]
        if before is not None and after is not None:
            (self.dir / "before.json").write_text(json.dumps(before), encoding="utf-8")
            (self.dir / "after.json").write_text(json.dumps(after), encoding="utf-8")
            args += ["--config-before", str(self.dir / "before.json"), "--config-after", str(self.dir / "after.json")]
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

    def test_missing_completion_or_unsaved_screenshot_always_fails(self) -> None:
        code, data = self.summarize([report(self.page("bar", saved=False))])
        self.assertEqual(code, 1)
        self.assertIn("driver never reported completion", data["problems"])
        self.assertTrue(any("not saved" in problem for problem in data["problems"]))

    def test_timeout_exit_status_fails(self) -> None:
        code, data = self.summarize([report({"type": "done"})], exit_code=124)
        self.assertEqual(code, 1)
        self.assertIn("124", data["problems"][0])


class RunScriptArgumentsTest(unittest.TestCase):
    def test_invalid_size_is_a_usage_error(self) -> None:
        result = subprocess.run(["bash", str(RUN), "--sizes", "800by600"], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("invalid size", result.stderr)

    def test_unknown_option_is_a_usage_error(self) -> None:
        result = subprocess.run(["bash", str(RUN), "--bogus"], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 2, result.stderr)


if __name__ == "__main__":
    unittest.main()
