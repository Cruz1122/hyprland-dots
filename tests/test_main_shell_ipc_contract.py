"""Static contracts for main-shell services used by the settings app.

These services cannot be instantiated outside a running Quickshell, so the
tests pin the IPC surface and the GPS retry wiring at the source level.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SERVICES = REPO_ROOT / "config/quickshell/ii/services"


def read(name: str) -> str:
    return (SERVICES / name).read_text(encoding="utf-8")


class NotificationsIpcContractTest(unittest.TestCase):
    def test_exposes_do_not_disturb_target(self) -> None:
        source = read("Notifications.qml")
        handler = source[source.index('target: "notifications"'):]
        for signature in (
            "function isSilent(): bool",
            "function setSilent(enabled: bool): void",
            "function toggleSilent(): void",
        ):
            self.assertIn(signature, handler)
        self.assertIn("root.silent = enabled", handler)
        self.assertIn("root.silent = !root.silent", handler)


class WeatherGpsRetryContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.source = read("Weather.qml")

    def test_transient_failure_schedules_retry_instead_of_disabling_forever(self) -> None:
        invalid_branch = self.source[self.source.index("Failed to get the GPS location"):]
        invalid_branch = invalid_branch[: invalid_branch.index("onValidityChanged")]
        self.assertIn("root.scheduleGpsRetry()", invalid_branch)

    def test_retry_is_bounded_and_notifies_once_per_streak(self) -> None:
        schedule = self.source[self.source.index("function scheduleGpsRetry()"):]
        schedule = schedule[: schedule.index("\n    }\n")]
        self.assertIn("if (!root.gpsEnabled)", schedule)
        self.assertRegex(schedule, r"if \(root\.gpsFailureStreak === 0\)\s*\n\s*Quickshell\.execDetached\(\[\"notify-send\"")
        self.assertIn("Math.min(", schedule)
        self.assertIn("root.gpsRetryMaxMs", schedule)

    def test_success_resets_streak_and_retry_restarts_gps(self) -> None:
        self.assertIn("root.gpsFailureStreak = 0;", self.source)
        retry_timer = self.source[self.source.index("id: gpsRetryTimer"):]
        retry_timer = retry_timer[: retry_timer.index("\n    }\n")]
        self.assertIn("positionSource.start()", retry_timer)
        self.assertIn("root.gpsEnabled", retry_timer)

    def test_gps_setting_is_tracked_live(self) -> None:
        self.assertRegex(self.source, r"readonly property bool gpsEnabled: Config\.options\.bar\.weather\.enableGPS")
        self.assertTrue(re.search(r"onGpsEnabledChanged:", self.source))

    def test_fetch_uses_argv_and_encodes_the_city(self) -> None:
        self.assertNotRegex(self.source, r'"(?:ba)?sh"\s*,\s*"-c"')
        self.assertNotIn("jq ", self.source)
        self.assertIn('fetcher.command = ["curl", "-s", "--max-time", "20", `https://wttr.in/${place}?format=j1`]', self.source)
        self.assertIn(".map(encodeURIComponent)", self.source)
        self.assertIn("root.pickData(JSON.parse(text))", self.source)


class ScreenshotActionRecordContractTest(unittest.TestCase):
    def setUp(self) -> None:
        source = (SERVICES.parent / "modules/common/utils/ScreenshotAction.qml").read_text(encoding="utf-8")
        start = source.index("case ScreenshotAction.Action.Record:")
        self.record = source[start:source.index("default:", start)]
        self.with_sound = self.record[self.record.index("case ScreenshotAction.Action.RecordWithSound:"):]
        self.plain = self.record[: self.record.index("case ScreenshotAction.Action.RecordWithSound:")]

    def test_record_commands_are_argv(self) -> None:
        self.assertNotIn('"bash"', self.record)
        self.assertNotIn("'${slurpRegion}'", self.record)
        self.assertEqual(self.record.count('[Directories.recordScriptPath, "--region", slurpRegion]'), 2)

    def test_plain_record_lets_the_script_apply_the_audio_default(self) -> None:
        self.assertIn('return [Directories.recordScriptPath, "--region", slurpRegion];', self.plain)
        self.assertNotIn("--sound", self.plain)
        self.assertNotIn("--mic", self.plain)

    def test_record_with_sound_forces_audio(self) -> None:
        self.assertNotIn("recordAudioByDefault", self.with_sound)
        self.assertIn('command.push("--sound")', self.with_sound)
        self.assertIn('command.push("--sound", "--mic")', self.with_sound)
        self.assertIn('command.push("--mic")', self.with_sound)
        # Every branch adds an audio flag, so sound can never be dropped.
        self.assertRegex(self.with_sound, r'else\s*\n\s*command\.push\("--sound"\);')


if __name__ == "__main__":
    unittest.main()
