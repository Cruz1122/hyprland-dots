"""Behavioral tests for config/quickshell/ii/scripts/settings/open-settings.sh with stub qs/hyprctl."""

from __future__ import annotations

import os
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "config/quickshell/ii/scripts/settings/open-settings.sh"

# The qs stub logs argv plus the deep-link env, and reports a running
# instance only when STUB_RUNNING_PID is set.
QS_STUB = r"""#!/usr/bin/env bash
{ printf '%s\0' "$@"; printf 'PAGE=%s\0KEY=%s\0' "${II_SETTINGS_PAGE-<unset>}" "${II_SETTINGS_KEY-<unset>}"; printf '\n'; } >> "$STUB_LOG_DIR/qs.log"
if [[ "$3" == "list" ]]; then
    if [[ -n "${STUB_RUNNING_PID:-}" ]]; then
        printf '[{"pid": %s, "id": "abc"}]\n' "$STUB_RUNNING_PID"
    else
        printf 'No running instances for "%s"\n' "$2"
    fi
    exit 0
fi
if [[ "$3" == "ipc" ]]; then
    exit "${STUB_IPC_STATUS:-0}"
fi
exit 0
"""

HYPRCTL_STUB = r"""#!/usr/bin/env bash
{ printf '%s\0' "$@"; printf '\n'; } >> "$STUB_LOG_DIR/hyprctl.log"
case "$1" in
    clients) echo '[{"pid": 1, "address": "0xaaa"}, {"pid": 4242, "address": "0xbeef"}]' ;;
    systeminfo) printf 'Hyprland 0.57.0\nconfigProvider: lua\n' ;;
esac
exit 0
"""


@unittest.skipUnless(shutil.which("jq"), "jq is required")
class OpenSettingsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="open-settings-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.bin = self.tmp / "bin"
        self.logs = self.tmp / "logs"
        self.bin.mkdir()
        self.logs.mkdir()
        for name, body in (("qs", QS_STUB), ("hyprctl", HYPRCTL_STUB)):
            path = self.bin / name
            path.write_text(body, encoding="utf-8")
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
        self.qml = str(self.tmp / "cfg/settings.qml")

    def run_script(self, *args: str, **env_extra: str) -> subprocess.CompletedProcess[str]:
        env = {
            "HOME": str(self.tmp / "home"),
            "PATH": f"{self.bin}:{os.environ.get('PATH', '/usr/bin:/bin')}",
            "STUB_LOG_DIR": str(self.logs),
            "II_SETTINGS_QML": self.qml,
            **env_extra,
        }
        return subprocess.run(["bash", str(SCRIPT), *args], env=env, capture_output=True, text=True, timeout=10)

    def calls(self, name: str) -> list[list[str]]:
        log = self.logs / f"{name}.log"
        if not log.exists():
            return []
        return [line.split("\0")[:-1] for line in log.read_text(encoding="utf-8").splitlines()]

    def qs_calls(self) -> list[list[str]]:
        # Drop the PAGE/KEY env markers for argv assertions.
        return [c[:-2] for c in self.calls("qs")]

    def test_starts_new_instance_with_deep_link_env(self) -> None:
        result = self.run_script("network", "bar.weather.enableGPS")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls("qs")
        self.assertEqual(calls[-1], ["-p", self.qml, "PAGE=network", "KEY=bar.weather.enableGPS"])
        self.assertEqual(len(calls), 2)
        self.assertEqual(self.calls("hyprctl"), [])

    def test_starts_new_instance_without_args_leaves_env_unset(self) -> None:
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls("qs")[-1], ["-p", self.qml, "PAGE=<unset>", "KEY=<unset>"])

    def test_default_path_uses_qs_config(self) -> None:
        env = {"qsConfig": "other"}
        result = subprocess.run(
            ["bash", str(SCRIPT)],
            env={
                "HOME": str(self.tmp / "home"),
                "PATH": f"{self.bin}:{os.environ.get('PATH', '/usr/bin:/bin')}",
                "STUB_LOG_DIR": str(self.logs),
                **env,
            },
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = str(self.tmp / "home/.config/quickshell/other/settings.qml")
        self.assertEqual(self.qs_calls()[-1], ["-p", expected])

    def test_running_instance_gets_ipc_and_focus(self) -> None:
        result = self.run_script("network", "bar.weather.enableGPS", STUB_RUNNING_PID="4242")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.qs_calls(),
            [
                ["-p", self.qml, "list", "-j"],
                ["-p", self.qml, "ipc", "call", "settingsApp", "open", "network"],
                ["-p", self.qml, "ipc", "call", "settingsApp", "reveal", "bar.weather.enableGPS"],
            ],
        )
        self.assertIn(["dispatch", 'hl.dsp.focus({ window = "address:0xbeef" })'], self.calls("hyprctl"))

    def test_running_instance_without_page_only_focuses(self) -> None:
        result = self.run_script(STUB_RUNNING_PID="4242")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.qs_calls(), [["-p", self.qml, "list", "-j"]])
        self.assertIn(["dispatch", 'hl.dsp.focus({ window = "address:0xbeef" })'], self.calls("hyprctl"))

    def test_ipc_failure_exits_1_without_starting_instance(self) -> None:
        result = self.run_script("network", STUB_RUNNING_PID="4242", STUB_IPC_STATUS="3")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn(["-p", self.qml], self.qs_calls())
        self.assertEqual(self.calls("hyprctl"), [])

    def test_rejects_invalid_arguments(self) -> None:
        for args in (
            ["bad page"],
            ["page;rm"],
            ["$(id)"],
            [""],
            ["network", "key with space"],
            ["network", ""],
            ["a", "b", "c"],
        ):
            with self.subTest(args=args):
                result = self.run_script(*args)
                self.assertEqual(result.returncode, 2)
                self.assertIn("Usage:", result.stderr)
        self.assertEqual(self.calls("qs"), [])
        self.assertEqual(self.calls("hyprctl"), [])


class LaunchSitesTest(unittest.TestCase):
    """SUPER+I and the sidebar button open settings through the launcher."""

    def test_keybind_command_runs_the_launcher(self) -> None:
        variables = (REPO_ROOT / "config/hypr/hyprland/variables.lua").read_text(encoding="utf-8")
        match = re.search(r'^settingsApp = "([^"\\]*)"$', variables, re.MULTILINE)
        self.assertIsNotNone(match, "settingsApp must stay a plain Lua string")
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            launcher = home / ".config/quickshell/ii/scripts/settings/open-settings.sh"
            launcher.parent.mkdir(parents=True)
            log = home / "launcher.log"
            launcher.write_text(
                f'#!/usr/bin/env bash\nprintf "%s|%s\\n" "$XDG_CURRENT_DESKTOP" "$#" > {shlex.quote(str(log))}\n',
                encoding="utf-8",
            )
            launcher.chmod(0o755)
            # hl.dsp.exec_cmd runs the string through sh with Hyprland's env (qsConfig from hl.env).
            result = subprocess.run(
                ["sh", "-c", match.group(1)],
                env={"HOME": str(home), "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "qsConfig": "ii"},
                capture_output=True, text=True, timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(log.read_text(encoding="utf-8"), "gnome|0\n")

    def test_sidebar_button_runs_the_launcher_for_its_own_shell(self) -> None:
        sidebar = (REPO_ROOT / "config/quickshell/ii/modules/ii/sidebarRight/SidebarRightContent.qml").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            'Quickshell.execDetached(["env", `II_SETTINGS_QML=${root.settingsQmlPath}`, '
            'Quickshell.shellPath("scripts/settings/open-settings.sh")]);',
            sidebar,
        )
        self.assertNotIn('"qs", "-p", root.settingsQmlPath', sidebar)

    def test_launcher_is_executable(self) -> None:
        self.assertTrue(os.access(SCRIPT, os.X_OK), f"{SCRIPT} must be executable")


if __name__ == "__main__":
    unittest.main()
