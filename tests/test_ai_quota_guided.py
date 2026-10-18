from __future__ import annotations

import hashlib
import importlib
import io
import json
import os
import queue
from pathlib import Path
import select
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "config/quickshell/ii/scripts"
sys.path.insert(0, str(SCRIPTS))
guided = importlib.import_module("ai_quotas.guided")
capture = importlib.import_module("ai_quotas.claude_statusline")
accounts = importlib.import_module("ai_quotas.accounts")
main = importlib.import_module("ai_quotas.main")
bridge = importlib.import_module("ai_quotas.bridge")


class GuidedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.environment = patch.dict(os.environ, {"HOME": self.temp.name, "PATH": self.temp.name,
            "XDG_DATA_HOME": self.temp.name + "/data", "XDG_STATE_HOME": self.temp.name + "/state",
            "XDG_CACHE_HOME": self.temp.name + "/cache", "CLAUDE_CONFIG_DIR": self.temp.name + "/claude-config"})
        self.environment.start()

    def tearDown(self):
        self.environment.stop()
        self.temp.cleanup()

    def install(self, name, payload, digest=None):
        expected = digest or hashlib.sha256(payload).hexdigest()
        opener = Mock()
        opener.open.return_value = io.BytesIO(payload)
        with patch.dict(guided.RELEASES, {name: ("test", "https://fixed.invalid/artifact", "sha256", expected)}), \
             patch.object(guided.urllib.request, "build_opener", return_value=opener), \
             patch.object(guided.platform, "machine", return_value="x86_64"), \
             patch.object(guided.subprocess, "Popen") as execute:
            result = guided.install_client(name, threading.Event())
            execute.assert_not_called()
        return Path(result)

    def test_explicit_install_checks_hash_and_never_executes_installer_or_changes_path(self):
        result = self.install("claude", b"synthetic-not-an-executable")
        self.assertEqual(result.read_bytes(), b"synthetic-not-an-executable")
        self.assertEqual(result.stat().st_mode & 0o777, 0o700)
        self.assertEqual(os.environ["PATH"], self.temp.name)

    def test_bad_hash_leaves_no_executable_and_no_temporary_download(self):
        with self.assertRaisesRegex(accounts.QuotaError, "checksum-mismatch"):
            self.install("claude", b"untrusted", "0" * 64)
        self.assertEqual(list(self.root.rglob("download-*")), [])
        self.assertFalse((self.root / "data/illogical-impulse/ai-quotas/clients/claude/test/claude").exists())

    def test_archive_extracts_only_the_expected_regular_member(self):
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode="w:gz") as archive:
            info = tarfile.TarInfo("antigravity")
            info.size = 7
            archive.addfile(info, io.BytesIO(b"payload"))
            other = tarfile.TarInfo("../../escaped")
            other.size = 3
            archive.addfile(other, io.BytesIO(b"bad"))
        result = self.install("agy", stream.getvalue())
        self.assertEqual(result.read_bytes(), b"payload")
        self.assertFalse((self.root / "escaped").exists())

    def test_archive_symlink_and_unknown_archive_are_rejected(self):
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode="w:gz") as archive:
            info = tarfile.TarInfo("antigravity")
            info.type = tarfile.SYMTYPE
            info.linkname = "/bin/sh"
            archive.addfile(info)
        with self.assertRaisesRegex(accounts.QuotaError, "download-failed"):
            self.install("agy", stream.getvalue())
        with self.assertRaisesRegex(accounts.QuotaError, "download-failed"):
            self.install("agy", b"not an archive")

    def test_cancelled_download_never_opens_network(self):
        cancelled = threading.Event()
        cancelled.set()
        with patch.object(guided.urllib.request, "build_opener") as network:
            with self.assertRaisesRegex(accounts.QuotaError, "cancelled"):
                guided.install_client("claude", cancelled)
            network.assert_not_called()

    def test_cancel_during_download_discards_partial_payload(self):
        cancelled = threading.Event()

        class CancelledStream(io.BytesIO):
            def read(self, size: int | None = -1) -> bytes:
                cancelled.set()
                return super().read(size)

        opener = Mock()
        opener.open.return_value = CancelledStream(b"partial")
        with patch.object(guided.urllib.request, "build_opener", return_value=opener), \
             patch.object(guided.platform, "machine", return_value="x86_64"):
            with self.assertRaisesRegex(accounts.QuotaError, "cancelled"):
                guided.install_client("claude", cancelled)
        self.assertEqual(list(self.root.rglob("download-*")), [])

    def test_redirect_download_cannot_forward_to_another_host(self):
        with self.assertRaisesRegex(accounts.QuotaError, "redirect-rejected"):
            guided.providers.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.invalid")

    def test_native_login_url_allowlists(self):
        for provider, url in (("antigravity", "https://accounts.google.com/o/oauth2/v2/auth?state=test"),
                              ("claude", "https://claude.ai/oauth/authorize?state=test")):
            self.assertEqual(guided.login_url(url, provider), url)
        for url in ("http://claude.ai/oauth/authorize", "https://claude.ai@evil.invalid/oauth/authorize",
                    "https://claude.ai/oauth/authorize#x", "https://accounts.google.com/not-oauth"):
            with self.assertRaises(accounts.QuotaError):
                guided.login_url(url, "claude")

    def test_official_login_helper_forwards_only_authorization_url_not_cli_diagnostics(self):
        executable = self.root / "claude"
        executable.write_text("#!/usr/bin/python3\nimport os,subprocess,sys\n"
            "subprocess.run([os.environ['BROWSER'],'https://claude.ai/oauth/authorize?state=synthetic'], check=True)\n"
            "print('CANARY-NATIVE-OUTPUT')\nprint('CANARY-NATIVE-ERROR',file=sys.stderr)\n")
        executable.chmod(0o700)
        seen = []
        guided.native_login("claude", threading.Event(), seen.append)
        self.assertEqual(seen, ["https://claude.ai/oauth/authorize?state=synthetic"])

    def test_native_printed_authorization_is_forwarded_but_other_output_is_not(self):
        executable = self.root / "claude"
        executable.write_text("#!/usr/bin/python3\nimport sys\n"
            "print('CANARY-TOKEN https://evil.invalid/oauth/authorize')\n"
            "print('https://claude.ai/oauth/authorize?state=synthetic', file=sys.stderr)\n")
        executable.chmod(0o700)
        seen = []
        guided.native_login("claude", threading.Event(), seen.append)
        self.assertEqual(seen, ["https://claude.ai/oauth/authorize?state=synthetic"])

    def test_native_code_reaches_controlling_tty_without_echo_or_command_arguments(self):
        executable = self.root / "claude"
        executable.write_text("#!/usr/bin/python3\nimport sys,termios\n"
            "with open('/dev/tty','r') as tty:\n"
            " assert not termios.tcgetattr(tty.fileno())[3] & termios.ECHO\n"
            " code=tty.readline().strip()\n"
            " assert code == 'synthetic-code-123'\n"
            " assert code not in ' '.join(sys.argv)\n")
        executable.chmod(0o700)
        replies = queue.Queue()
        replies.put("synthetic-code-123")
        seen = []
        guided.native_login("claude", threading.Event(), seen.append, replies=replies)
        self.assertEqual(seen, [])
        self.assertTrue(replies.empty())

    def test_authorization_code_validation_rejects_urls_and_control_characters(self):
        self.assertEqual(guided.validate_login_code(" synthetic-code-123 \n"), "synthetic-code-123")
        for value in (None, "short", "a\nb12345678", "https://example.invalid/code", "a" * 2049):
            with self.assertRaisesRegex(accounts.QuotaError, "invalid-login-code"):
                guided.validate_login_code(value)

    def test_gui_authorization_code_roundtrip_is_private_and_completes_native_login(self):
        executable = self.root / "claude"
        executable.write_text("#!/usr/bin/python3\nimport sys\n"
            "print('https://claude.ai/oauth/authorize?state=synthetic',file=sys.stderr,flush=True)\n"
            "with open('/dev/tty','r') as stream: value=stream.readline().strip()\n"
            "assert value == 'synthetic-private-code-123'\n")
        executable.chmod(0o700)
        process = subprocess.Popen([sys.executable, "-B", str(SCRIPTS / "ai-quotas.py"), "serve"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        frames = []
        try:
            assert process.stdin is not None and process.stdout is not None
            stdin, stdout = process.stdin, process.stdout

            def receive(predicate):
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline:
                    if select.select([stdout], [], [], max(0, deadline - time.monotonic()))[0]:
                        raw = stdout.readline()
                        frames.append(raw)
                        frame = json.loads(raw)
                        if predicate(frame):
                            return frame
                self.fail("native login did not respond")

            receive(lambda frame: frame.get("version") == 1)
            stdin.write(json.dumps({"action": "login", "provider": "claude", "source": "claude-statusline", "requestId": 77}) + "\n")
            stdin.flush()
            receive(lambda frame: (frame.get("operationResult") or {}).get("requiresCode") is True)
            stdin.write(json.dumps({"action": "authorize-code", "requestId": 77, "code": "synthetic-private-code-123"}) + "\n")
            stdin.flush()
            result = receive(lambda frame: (frame.get("operationResult") or {}).get("requestId") == 77
                             and not (frame.get("operationResult") or {}).get("pending"))
            self.assertTrue(result["operationResult"]["ok"], result["operationResult"])
            self.assertNotIn("synthetic-private-code-123", "".join(frames))
            for path in self.root.rglob("*.json"):
                self.assertNotIn("synthetic-private-code-123", path.read_text())
        finally:
            if process.stdin:
                process.stdin.close()
            process.terminate()
            process.wait(timeout=5)
            for stream in (process.stdout, process.stderr):
                if stream:
                    stream.close()

    def test_authorization_fold_is_visibility_only_and_does_not_send_cancel(self):
        services = (ROOT / "config/quickshell/ii/services/AiQuotaUsage.qml").read_text()
        panel = (ROOT / "config/quickshell/ii/modules/common/aiQuotaPanel/AiQuotaPanel.qml").read_text()
        dialog = (ROOT / "config/quickshell/ii/modules/common/aiQuotaPanel/AiQuotaConnectDialog.qml").read_text()
        emblem = (ROOT / "config/quickshell/ii/modules/ii/bar/AiEmblem.qml").read_text()
        collapse = services.split("function collapseOverlay()", 1)[1].split("\n    }", 1)[0]
        self.assertIn("overlayCollapsed = true", collapse)
        self.assertNotIn("cancel(", collapse)
        self.assertIn("!AiQuotaUsage.overlayCollapsed", panel)
        self.assertIn("if (AiQuotaUsage.overlayCollapsed) return", dialog)
        self.assertIn('buttonText: "Plegar overlay y continuar"', dialog)
        self.assertIn("AiQuotaUsage.overlayCollapsed", emblem)

    def test_missing_browser_link_automatically_prepares_existing_brave_instead_of_showing_an_unknown_link(self):
        dialog = (ROOT / "config/quickshell/ii/modules/common/aiQuotaPanel/AiQuotaConnectDialog.qml").read_text()
        service = (ROOT / "config/quickshell/ii/services/AiQuotaUsage.qml").read_text()
        self.assertIn('result.code === "browser-link-required" && root.browserLinked', dialog)
        self.assertIn("AiQuotaUsage.prepareBrowser()", dialog)
        self.assertIn("function continueBrowserSetup(path)", service)
        self.assertIn("root.openExtensionManager()", service)
        self.assertIn("root.collapseOverlay()", service)
        self.assertIn("Activa Modo desarrollador → Cargar descomprimida", dialog)
        self.assertIn("No vuelvas a iniciar sesión", dialog)

    def test_expired_manual_cookie_copy_tells_user_to_stop_reusing_it(self):
        backend = (ROOT / "config/quickshell/ii/scripts/ai_quotas/main.py").read_text()
        self.assertIn('"session-cookie-expired": "Ese valor de sesión expiró', backend)
        self.assertIn("un código de login no sirve como cookie", backend)
        self.assertIn("Conectar con navegador habitual", backend)

    def test_native_login_cancellation_terminates_owned_process_and_closes_descriptors(self):
        executable = self.root / "claude"
        pidfile = self.root / "pid"
        executable.write_text("#!/usr/bin/python3\nimport os,time\nfrom pathlib import Path\n"
            f"Path({str(pidfile)!r}).write_text(str(os.getpid()))\n"
            "time.sleep(30)\n")
        executable.chmod(0o700)
        cancelled = threading.Event()
        errors = []

        def run():
            try:
                guided.native_login("claude", cancelled, lambda _: None)
            except accounts.QuotaError as error:
                errors.append(error.code)

        worker = threading.Thread(target=run)
        worker.start()
        deadline = time.monotonic() + 5
        while not pidfile.exists() and time.monotonic() < deadline:
            time.sleep(.01)
        cancelled.set()
        worker.join(timeout=5)
        self.assertFalse(worker.is_alive())
        self.assertEqual(errors, ["cancelled"])
        pid = int(pidfile.read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_statusline_configuration_preserves_settings_and_original_command(self):
        directory = Path(os.environ["CLAUDE_CONFIG_DIR"])
        directory.mkdir()
        path = directory / "settings.json"
        original = {"env": {"SECRET": "CANARY-UNRELATED"}, "statusLine": {
            "type": "command", "command": "printf existing-statusline", "padding": 2}}
        path.write_text(json.dumps(original))
        capture.configure()
        configured = json.loads(path.read_text())
        self.assertEqual(configured["env"], original["env"])
        self.assertEqual(configured["statusLine"]["padding"], 2)
        self.assertIn("claude-statusline.py", configured["statusLine"]["command"])
        backup = capture.root_path() / "claude-statusline.previous.json"
        self.assertEqual(json.loads(backup.read_text()), {"statusLine": original["statusLine"]})
        self.assertNotIn("CANARY", backup.read_text())
        previous = path.read_bytes()
        capture.configure()
        self.assertEqual(path.read_bytes(), previous)

    def test_statusline_input_persists_only_valid_limits_and_chains_original_output(self):
        capture.configure()
        accounts.write_json(capture.root_path() / "claude-statusline.previous.json", {
            "statusLine": {"type": "command", "command": "printf existing-statusline"}})
        payload = {"cwd": "CANARY-PATH", "transcript_path": "CANARY-TRANSCRIPT", "rate_limits": {
            "five_hour": {"used_percentage": 12, "resets_at": time.time() + 3600},
            "seven_day": {"used_percentage": 140, "resets_at": time.time() + 604800}}}
        result = subprocess.run([sys.executable, "-B", str(SCRIPTS / "claude-statusline.py")],
            input=json.dumps(payload), capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "existing-statusline")
        stored = (capture.root_path() / "claude-statusline.json").read_text()
        self.assertNotIn("CANARY", stored)
        measurement = capture.fetch()
        self.assertEqual([w["usedPercent"] for w in measurement["windows"]], [12, 100])
        self.assertEqual(measurement["windows"][1]["usedAmount"], 140)
        self.assertFalse(measurement["identityVerified"])

    def test_statusline_restore_preserves_unrelated_edits_and_refuses_recursive_wrapper(self):
        directory = Path(os.environ["CLAUDE_CONFIG_DIR"])
        directory.mkdir()
        path = directory / "settings.json"
        original = {"type": "command", "command": "printf original", "padding": 3}
        path.write_text(json.dumps({"statusLine": original, "theme": "dark"}))
        capture.configure()
        configured = json.loads(path.read_text())
        configured["theme"] = "light"
        accounts.write_json(path, configured)
        capture.unconfigure()
        self.assertEqual(json.loads(path.read_text()), {"statusLine": original, "theme": "light"})
        accounts.write_json(path, {"statusLine": {"type": "command", "command": "python /old/claude-statusline.py"}})
        with self.assertRaisesRegex(accounts.QuotaError, "statusline-conflict"):
            capture.configure()

    def test_statusline_restore_accepts_settings_rewritten_with_default_permissions(self):
        directory = Path(os.environ["CLAUDE_CONFIG_DIR"])
        directory.mkdir()
        path = directory / "settings.json"
        original = {"type": "command", "command": "printf original"}
        path.write_text(json.dumps({"statusLine": original}))
        path.chmod(0o644)
        capture.configure()
        path.chmod(0o644)
        capture.unconfigure()
        self.assertEqual(json.loads(path.read_text())["statusLine"], original)
        path.write_text(json.dumps({"statusLine": original, "theme": "light"}))
        path.chmod(0o644)
        before = path.read_bytes()
        capture.unconfigure()
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(path.stat().st_mode & 0o777, 0o644)

    def test_statusline_setup_never_overwrites_invalid_or_symlinked_settings(self):
        directory = Path(os.environ["CLAUDE_CONFIG_DIR"])
        directory.mkdir()
        path = directory / "settings.json"
        path.write_text("not-json")
        with self.assertRaisesRegex(accounts.QuotaError, "invalid-storage"):
            capture.configure()
        self.assertEqual(path.read_text(), "not-json")
        path.unlink()
        elsewhere = self.root / "elsewhere"
        elsewhere.write_text("{}")
        path.symlink_to(elsewhere)
        with self.assertRaises(OSError):
            capture.configure()
        self.assertEqual(elsewhere.read_text(), "{}")

    def test_statusline_unknown_stale_or_expired_limits_never_become_full_allowance(self):
        for payload in ({}, {"rate_limits": {"five_hour": {"used_percentage": True, "resets_at": time.time() + 10}}},
                        {"rate_limits": {"five_hour": {"used_percentage": 20, "resets_at": 1}}}):
            with self.assertRaisesRegex(accounts.QuotaError, "waiting-usage"):
                capture.parse(payload)
        accounts.write_json(capture.root_path() / "claude-statusline.json", {
            "observedAt": time.time() - 901, "rate_limits": {"five_hour": {"used_percentage": 20, "resets_at": time.time() + 10}}})
        with self.assertRaisesRegex(accounts.QuotaError, "waiting-usage"):
            capture.fetch()

    def test_browser_amount_windows_and_no_exported_credentials(self):
        value = bridge.measurement({"measurement": {"windows": [
            {"label": "Presupuesto", "usedPercent": None, "usedAmount": 3, "limitAmount": 42}],
            "identity": None, "identityVerified": False}})
        self.assertEqual(value["windows"][0]["usedAmount"], 3)
        self.assertIsNone(value["windows"][0]["usedPercent"])

    def test_waiting_statusline_retries_quickly_and_preserves_capture_time(self):
        state = accounts.Accounts(self.root / "accounts")
        state.add("claude", "claude-statusline", "Claude", "a" * 32)
        controller = main.Controller(state, self.root / "cache", fetcher=Mock(side_effect=accounts.QuotaError("waiting-usage")))
        data = state.read()
        selected = controller.selected(data, "claude")
        controller.refresh(selected, data["generations"]["claude"])
        record = accounts.read_json(controller.cache_path(selected, data["generations"]["claude"]), {})
        self.assertLessEqual(record["nextAttemptAt"] - time.time(), 5)
        self.assertEqual(controller.view()["providers"]["claude"]["status"], "waiting-usage")

    def test_poll_does_not_open_browser_profile_while_its_login_is_active(self):
        state = accounts.Accounts(self.root / "accounts")
        state.add("zed", "browser-session", "Zed", "a" * 32)
        controller = main.Controller(state, self.root / "cache", fetcher=Mock())
        executor = Mock()
        controller.poll(executor, {}, blocked={"zed"})
        executor.submit.assert_not_called()

    def test_backend_requires_browser_opt_in_and_rejects_install_for_other_providers(self):
        process = subprocess.Popen([sys.executable, "-B", str(SCRIPTS / "ai-quotas.py"), "serve"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        try:
            assert process.stdin is not None and process.stdout is not None
            stdin, stdout = process.stdin, process.stdout
            self.assertTrue(select.select([stdout], [], [], 5)[0])
            json.loads(stdout.readline())
            for command, message in (({"action": "login", "provider": "cursor", "consent": False}, "Acepta"),
                                     ({"action": "install-login", "provider": "codex"}, "Operación no disponible")):
                command["requestId"] = "test-" + command["provider"]
                stdin.write(json.dumps(command) + "\n")
                stdin.flush()
                deadline = time.monotonic() + 5
                result = None
                while time.monotonic() < deadline:
                    if not select.select([stdout], [], [], max(0, deadline - time.monotonic()))[0]:
                        break
                    result = json.loads(stdout.readline()).get("operationResult")
                    if result and result["requestId"] == command["requestId"]:
                        break
                self.assertIsNotNone(result)
                assert result is not None
                self.assertFalse(result["ok"])
                self.assertIn(message, result["message"])
        finally:
            if process.stdin:
                process.stdin.close()
            process.terminate()
            process.wait(timeout=5)
            for stream in (process.stdout, process.stderr):
                if stream:
                    stream.close()


if __name__ == "__main__":
    unittest.main()
