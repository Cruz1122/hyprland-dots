"""Behavioral tests for scripts/videos/record.sh using stub executables.

Nothing is recorded: wf-recorder, pactl, notify-send, hyprctl and slurp are
replaced by stubs on PATH that only log their argv.
"""

from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "config/quickshell/ii/scripts/videos/record.sh"

STUB = """#!/usr/bin/env bash
log="$STUB_LOG_DIR/{name}.log"
printf '%s\\0' "$@" >> "$log"
printf '\\n' >> "$log"
case "{name}" in
    pactl)
        case "$1" in
            get-default-sink) echo default_sink ;;
            get-default-source) echo default_source ;;
            load-module) echo "$((RANDOM + 100))" ;;
        esac
        ;;
    hyprctl) echo '[{{"name":"DP-1","focused":false}},{{"name":"HDMI-A-1","focused":true}}]' ;;
    slurp) echo '10,20 300x200' ;;
esac
exit 0
"""


@unittest.skipUnless(shutil.which("jq") and shutil.which("bash"), "jq and bash are required")
class RecordScriptTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="record-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = self.tmp / "home"
        self.runtime = self.tmp / "runtime"
        self.bin = self.tmp / "bin"
        self.logs = self.tmp / "logs"
        for d in (self.home, self.runtime, self.bin, self.logs):
            d.mkdir()
        for name in ("wf-recorder", "pactl", "notify-send", "hyprctl", "slurp"):
            path = self.bin / name
            path.write_text(STUB.format(name=name), encoding="utf-8")
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
        self.write_config({})

    def write_config(self, screen_record: dict) -> None:
        config_dir = self.home / ".config/illogical-impulse"
        config_dir.mkdir(parents=True, exist_ok=True)
        screen_record = {"savePath": str(self.tmp / "videos"), **screen_record}
        (config_dir / "config.json").write_text(json.dumps({"screenRecord": screen_record}), encoding="utf-8")

    def run_script(self, *args: str) -> subprocess.CompletedProcess[str]:
        # Real tools (jq, date, mkdir, ...) stay reachable after the stubs.
        env = {
            "HOME": str(self.home),
            "XDG_RUNTIME_DIR": str(self.runtime),
            "PATH": f"{self.bin}:{os.environ.get('PATH', '/usr/bin:/bin')}",
            "STUB_LOG_DIR": str(self.logs),
        }
        return subprocess.run(
            ["bash", str(SCRIPT), *args], env=env, capture_output=True, text=True, timeout=20
        )

    def calls(self, name: str) -> list[list[str]]:
        log = self.logs / f"{name}.log"
        if not log.exists():
            return []
        return [line.split("\0")[:-1] for line in log.read_text(encoding="utf-8").splitlines()]

    def recorder_argv(self) -> list[str]:
        calls = self.calls("wf-recorder")
        self.assertEqual(len(calls), 1, calls)
        return calls[0]

    def audio_args(self) -> list[str]:
        return [a for a in self.recorder_argv() if a.startswith("--audio")]

    def assert_ok(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("command not found", result.stderr)

    def test_default_records_system_audio_when_enabled(self) -> None:
        self.write_config({"recordAudioByDefault": True})
        self.assert_ok(self.run_script("--fullscreen"))
        self.assertEqual(self.audio_args(), ["--audio=default_sink.monitor"])

    def test_default_records_no_audio_when_disabled(self) -> None:
        self.write_config({"recordAudioByDefault": False, "audioSource": "system"})
        self.assert_ok(self.run_script("--fullscreen"))
        self.assertEqual(self.audio_args(), [])

    def test_missing_setting_defaults_to_audio(self) -> None:
        self.assert_ok(self.run_script("--fullscreen"))
        self.assertEqual(self.audio_args(), ["--audio=default_sink.monitor"])

    def test_sound_flag_overrides_disabled_default(self) -> None:
        self.write_config({"recordAudioByDefault": False})
        self.assert_ok(self.run_script("--fullscreen", "--sound"))
        self.assertEqual(self.audio_args(), ["--audio=default_sink.monitor"])

    def test_no_audio_flag_wins_over_sound_and_mic(self) -> None:
        self.write_config({"recordAudioByDefault": True, "audioSource": "both"})
        self.assert_ok(self.run_script("--fullscreen", "--sound", "--mic", "--no-audio"))
        self.assertEqual(self.audio_args(), [])
        self.assertEqual(self.calls("pactl"), [])

    def test_audio_source_mic_uses_configured_device(self) -> None:
        self.write_config({"audioSource": "mic", "micDevice": "my mic"})
        self.assert_ok(self.run_script("--fullscreen"))
        self.assertEqual(self.audio_args(), ["--audio=my mic"])

    def test_audio_source_none_records_no_audio(self) -> None:
        self.write_config({"audioSource": "none"})
        self.assert_ok(self.run_script("--fullscreen"))
        self.assertEqual(self.audio_args(), [])

    def test_audio_source_both_creates_and_cleans_mix(self) -> None:
        self.write_config({"audioSource": "both", "systemAudioDevice": "sink_x"})
        self.assert_ok(self.run_script("--fullscreen"))
        [audio] = self.audio_args()
        self.assertRegex(audio, r"^--audio=recording_mix_\d+\.monitor$")
        pactl = self.calls("pactl")
        loads = [c for c in pactl if c[0] == "load-module"]
        self.assertEqual(len(loads), 3)
        self.assertIn("source=sink_x.monitor", loads[1])
        self.assertEqual(len([c for c in pactl if c[0] == "unload-module"]), 3)
        self.assertFalse((self.runtime / "illogical-impulse/combine-pids.txt").exists())

    def test_fullscreen_uses_focused_monitor_and_respects_false(self) -> None:
        self.assert_ok(self.run_script("--fullscreen", "--no-audio"))
        argv = self.recorder_argv()
        self.assertEqual(argv[argv.index("-o") + 1], "HDMI-A-1")

        (self.logs / "wf-recorder.log").unlink()
        self.write_config({"fullscreenUsesFocusedMonitor": False})
        self.assert_ok(self.run_script("--fullscreen", "--no-audio"))
        self.assertNotIn("-o", self.recorder_argv())

    def test_region_flag_passes_geometry_verbatim(self) -> None:
        self.write_config({"fps": 30, "pixelFormat": "auto", "fileFormat": "mkv"})
        self.assert_ok(self.run_script("--region", "1,2 3x4", "--no-audio"))
        argv = self.recorder_argv()
        self.assertEqual(argv[argv.index("--geometry") + 1], "1,2 3x4")
        self.assertEqual(argv[argv.index("--framerate") + 1], "30")
        self.assertNotIn("--pixel-format", argv)
        self.assertTrue(argv[argv.index("-f") + 1].endswith(".mkv"))
        self.assertEqual(self.calls("slurp"), [])

    def test_no_region_flag_uses_slurp(self) -> None:
        self.assert_ok(self.run_script("--no-audio"))
        argv = self.recorder_argv()
        self.assertEqual(argv[argv.index("--geometry") + 1], "10,20 300x200")

    def test_stale_pid_file_cleans_combined_audio_and_starts_recording(self) -> None:
        state = self.runtime / "illogical-impulse"
        state.mkdir()
        dead = subprocess.Popen(["true"])
        dead.wait()
        (state / "wf-recorder.pid").write_text(f"{dead.pid}\n", encoding="utf-8")
        (state / "combine-pids.txt").write_text("41\n42\n", encoding="utf-8")
        result = self.run_script("--fullscreen", "--no-audio")
        self.assert_ok(result)
        self.assertEqual(self.calls("pactl"), [["unload-module", "41"], ["unload-module", "42"]])
        self.assertFalse((state / "combine-pids.txt").exists())
        self.assertFalse((state / "wf-recorder.pid").exists())
        self.recorder_argv()

    def test_stop_without_recording_notifies_and_succeeds(self) -> None:
        self.assert_ok(self.run_script("--stop"))
        self.assertEqual(self.calls("wf-recorder"), [])
        # notify-send is detached, so give the stub a moment to log.
        deadline = time.monotonic() + 5
        while not self.calls("notify-send") and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertIn("No active recording", self.calls("notify-send")[0])

    def test_region_flag_without_value_fails(self) -> None:
        result = self.run_script("--region")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.calls("wf-recorder"), [])


if __name__ == "__main__":
    unittest.main()
