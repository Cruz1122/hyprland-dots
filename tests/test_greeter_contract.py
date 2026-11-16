from __future__ import annotations

import re
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
GREETER = REPO_ROOT / "system/greeter"
SESSION_GENERAL = REPO_ROOT / "config/hypr/hyprland/general.lua"
INSTALLER = REPO_ROOT / "scripts/install-greeter.sh"
LOCK_SURFACE = REPO_ROOT / "config/quickshell/ii/modules/ii/lock/LockSurface.qml"


def code_lines(path: Path) -> list[str]:
    lines = (line.strip() for line in path.read_text(encoding="utf-8").splitlines())
    return [line for line in lines if line and not line.startswith("//")]


def kb_layout(path: Path) -> str:
    match = re.search(r'kb_layout\s*=\s*"([^"]+)"', path.read_text(encoding="utf-8"))
    assert match, f"no kb_layout in {path}"
    return match.group(1)


class GreeterContractTest(unittest.TestCase):
    def test_keyboard_layout_matches_the_session(self) -> None:
        # A different layout makes the same keys type a different password.
        self.assertEqual(kb_layout(GREETER / "hyprland.lua"), kb_layout(SESSION_GENERAL))

    def test_time_format_matches_the_shell(self) -> None:
        shell = REPO_ROOT / "config/quickshell/ii/modules/common/functions/TimeFormat.js"
        self.assertEqual(code_lines(GREETER / "quickshell/TimeFormat.js"), code_lines(shell))

    def test_lock_screen_shares_the_greeter_identity(self) -> None:
        # Same name and avatar on the login and lock screens.
        lock = LOCK_SURFACE.read_text(encoding="utf-8")
        self.assertIn('"/etc/greetd/quickshell/theme"', lock)
        self.assertIn("user.json", lock)
        self.assertIn("/avatar", lock)

    def test_installer_ships_scripts_next_to_qml(self) -> None:
        # GreeterSurface.qml imports TimeFormat.js; a missing file breaks the greeter.
        self.assertIn('"$src"/quickshell/*.js', INSTALLER.read_text(encoding="utf-8"))

    def test_pam_unlocks_the_keyring(self) -> None:
        pam = (GREETER / "greetd/pam.d/greetd").read_text(encoding="utf-8")
        self.assertRegex(pam, r"(?m)^-auth\s+optional\s+pam_gnome_keyring\.so")
        self.assertRegex(pam, r"(?m)^-session\s+optional\s+pam_gnome_keyring\.so\s+auto_start")

    def test_greeter_compositor_exits_with_quickshell(self) -> None:
        # Otherwise greetd never gets the VT back to start the user session.
        lua = (GREETER / "hyprland.lua").read_text(encoding="utf-8")
        self.assertIn("qs -p /etc/greetd/quickshell; hyprctl dispatch", lua)
        self.assertIn("hl.dsp.exit()", lua)

    def test_greetd_runs_the_installed_config(self) -> None:
        config = (GREETER / "greetd/config.toml").read_text(encoding="utf-8")
        self.assertIn('command = "start-hyprland -- --config /etc/greetd/hyprland.lua"', config)
        self.assertIn('user = "greeter"', config)

    def test_greeter_stays_out_of_user_config(self) -> None:
        # dotsctl install copies config/ into ~/.config; the greeter belongs in /etc.
        self.assertFalse((REPO_ROOT / "config/greeter").exists())

    def test_installer_syntax(self) -> None:
        subprocess.run(["bash", "-n", str(INSTALLER)], check=True)


if __name__ == "__main__":
    unittest.main()
