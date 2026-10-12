from __future__ import annotations

import json
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SETTINGSCTL = REPO_ROOT / "scripts" / "settingsctl.py"


def run_settingsctl(*args: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SETTINGSCTL), *args],
        cwd=cwd or REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


class SettingsCtlTest(unittest.TestCase):
    def test_validate_accepts_existing_unversioned_config(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            config = temp_path / "config.json"
            config.write_text(json.dumps({"appearance": {"fakeScreenRounding": 2}}), encoding="utf-8")

            result = run_settingsctl("validate", str(config))

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("schema=0", result.stdout)

    def test_migrate_dry_run_does_not_write(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            config = temp_path / "config.json"
            config.write_text(json.dumps({"appearance": {"fakeScreenRounding": 2}}), encoding="utf-8")

            result = run_settingsctl("migrate", str(config), "--dry-run")

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("changed=true", result.stdout)
            self.assertNotIn("_schemaVersion", config.read_text(encoding="utf-8"))

    def test_migrate_writes_atomically_and_creates_backup(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            config = temp_path / "config.json"
            config.write_text(json.dumps({"appearance": {"fakeScreenRounding": 2}}), encoding="utf-8")
            config.chmod(0o644)

            result = run_settingsctl("migrate", str(config))

            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(config.read_text(encoding="utf-8"))
            self.assertEqual(data["_schemaVersion"], 1)
            self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o644)
            self.assertTrue(list(temp_path.glob("config.json.pre-settingsctl-*")))

    def test_validate_rejects_future_schema(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            config = temp_path / "config.json"
            config.write_text(json.dumps({"_schemaVersion": 999}), encoding="utf-8")

            result = run_settingsctl("validate", str(config))

            self.assertEqual(result.returncode, 1)
            self.assertIn("Unsupported future schema version", result.stderr)


if __name__ == "__main__":
    unittest.main()
