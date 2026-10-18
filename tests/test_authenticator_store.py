"""Exercise the real QML store against a fake keyring in a headless shell."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "config/quickshell/ii/modules/common/authenticator"


class AuthenticatorStoreTest(unittest.TestCase):
    def test_headless_store_load_generation_errors_and_pause(self) -> None:
        executable = shutil.which("qs")
        if executable is None:
            self.skipTest("Quickshell is unavailable; never fall back to the live shell")
        scenarios = ("accounts", "empty", "invalid", "lookup_error", "code_error", "missing_tool", "missing_python")
        for scenario in scenarios:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory(prefix="authenticator-store-") as temporary:
                root = Path(temporary)
                (root / "auth").mkdir()
                (root / "scripts").mkdir()
                (root / "bin").mkdir()
                for name in ("AuthenticatorStore.qml", "AuthenticatorModel.js"):
                    shutil.copyfile(SOURCE / name, root / "auth" / name)
                if scenario == "missing_python":
                    store_path = root / "auth/AuthenticatorStore.qml"
                    store_path.write_text(store_path.read_text().replace('"/usr/bin/python"', '"/nonexistent/authenticator-test-python"'))
                backend = ROOT / "config/quickshell/ii/scripts/authenticator.py"
                if scenario == "code_error":
                    (root / "scripts/authenticator.py").write_text("raise SystemExit(1)\n")
                else:
                    shutil.copyfile(backend, root / "scripts/authenticator.py")
                accounts = [{"issuer": "Public example", "account": "demo", "digits": 6,
                             "period": 30, "algorithm": "SHA1",
                             "secret": "JBSWY3DPEHPK3PXP"}]
                payload = json.dumps(accounts)
                fake_keyring = "#!/usr/bin/python\nimport sys\n"
                if scenario == "empty":
                    fake_keyring += "raise SystemExit(1)\n"
                elif scenario == "lookup_error":
                    fake_keyring += "print('Synthetic lookup failure', file=sys.stderr)\nraise SystemExit(1)\n"
                elif scenario == "invalid":
                    fake_keyring += "print('{}')\n"
                else:
                    fake_keyring += f"print({payload!r})\n"
                (root / "bin/secret-tool").write_text(fake_keyring)
                (root / "bin/secret-tool").chmod(0o755)
                if scenario == "missing_tool":
                    (root / "bin/secret-tool").unlink()
                error_expected = scenario in ("invalid", "lookup_error", "missing_tool")
                code_error_expected = scenario in ("code_error", "missing_python")
                has_accounts = scenario in ("accounts", "code_error", "missing_python")
                shell = '''import QtQuick
import Quickshell
import "auth"
ShellRoot {
    id: root
    property int stage: 0
    property int revision: 0
    property int waited: 0
    property var store: AuthenticatorStore
    function fail() { console.error("Synthetic store assertion failed"); Qt.exit(1); }
    Component.onCompleted: root.store.viewing = true
    Timer {
        interval: 50; running: true; repeat: true
        onTriggered: {
            if (root.stage === 0) {
                if (!root.store.loaded) return;
                if (root.store.loadError !== LOAD_ERROR) { root.fail(); return; }
                if (root.store.entries.length !== ENTRY_COUNT) { root.fail(); return; }
                if (ENTRY_COUNT && ("secret" in root.store.entries[0])) { root.fail(); return; }
                if (ENTRY_COUNT && !root.store.codeError && root.store.codeGeneratedAt < 0) return;
                if (root.store.codeError !== CODE_ERROR) { root.fail(); return; }
                if (ENTRY_COUNT && !CODE_ERROR && !root.store.codeFor(root.store.entries[0])) return;
                if (ENTRY_COUNT && !CODE_ERROR && !/^[0-9]{6}$/.test(root.store.codeFor(root.store.entries[0]))) { root.fail(); return; }
                root.store.viewing = false;
                root.revision = root.store.codeRevision;
                root.stage = 1;
            } else {
                root.waited += 50;
                if (root.waited < 1200) return;
                if (root.store.codeRevision !== root.revision || Object.keys(root.store.codes).length) { root.fail(); return; }
                console.info("Synthetic store checks passed"); Qt.quit();
            }
        }
    }
    Timer { interval: 8000; running: true; onTriggered: root.fail() }
}
'''
                shell = shell.replace("LOAD_ERROR", str(error_expected).lower())
                shell = shell.replace("CODE_ERROR", str(code_error_expected).lower())
                shell = shell.replace("ENTRY_COUNT", "1" if has_accounts else "0")
                (root / "shell.qml").write_text(shell)
                environment = {**os.environ, "QT_QPA_PLATFORM": "offscreen",
                               "QT_QUICK_CONTROLS_STYLE": "Basic",
                               "PATH": str(root / "bin")}
                for key in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
                    environment.pop(key, None)
                result = subprocess.run(
                    [executable, "--path", str(root / "shell.qml"), "--no-color"],
                    env=environment, capture_output=True, text=True, timeout=12,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Synthetic store checks passed", result.stdout + result.stderr)
