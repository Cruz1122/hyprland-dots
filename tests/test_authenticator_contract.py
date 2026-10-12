from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class AuthenticatorContractTest(unittest.TestCase):
    def test_authenticator_is_loaded_and_super_o_is_reserved(self) -> None:
        shell = read("config/quickshell/ii/shell.qml")
        states = read("config/quickshell/ii/GlobalStates.qml")
        keybinds = read("config/hypr/hyprland/keybinds.lua")
        self.assertIn("Authenticator {}", shell)
        self.assertIn("authenticatorOpen", states)
        self.assertIn('hl.bind("SUPER + O", hl.dsp.global("quickshell:authenticatorToggle")', keybinds)
        self.assertIn('hl.bind("SUPER + A", hl.dsp.global("quickshell:sidebarLeftToggle")', keybinds)

    def test_authenticator_uses_local_qr_and_secret_service(self) -> None:
        ui = read("config/quickshell/ii/modules/common/authenticator/Authenticator.qml")
        store = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorStore.qml")
        script = read("config/quickshell/ii/scripts/authenticator.py")
        self.assertIn('"zbarimg"', script)
        self.assertIn('"secret-tool", "lookup"', store)
        self.assertIn('"qs", "-c", "ii", "ipc", "call", "region", "screenshot"', ui)
        self.assertIn('"otpauth://totp/"', store)

    def test_installer_supplies_system_python_and_qr_dependencies(self) -> None:
        installer = read("scripts/install-deps.sh")
        store = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorStore.qml")
        self.assertIn('python: "/usr/bin/python"', store)
        for package in ("python-protobuf", "python-cryptography", "zbar", "libsecret"):
            self.assertIn(package, installer)


if __name__ == "__main__":
    unittest.main()
