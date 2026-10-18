from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import importlib
import importlib.util
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "config/quickshell/ii/scripts"
sys.path.insert(0, str(SCRIPTS))
accounts_module = importlib.import_module("ai_quotas.accounts")
Accounts, QuotaError, Vault, APPLICATION = (accounts_module.Accounts, accounts_module.QuotaError,
                                          accounts_module.Vault, accounts_module.APPLICATION)
quota_main = importlib.import_module("ai_quotas.main")
bridge = importlib.import_module("ai_quotas.bridge")
Controller = quota_main.Controller
p = importlib.import_module("ai_quotas.providers")


class ProviderTests(unittest.TestCase):
    def test_opencode_windows_are_used_percent_and_not_manual_values(self):
        result = p.parse_opencode({"usage": {
            "rolling": {"percent": 0, "resetsAt": None},
            "weekly": {"percent": 10, "resetsAt": "2026-10-18T23:45:00Z"},
            "monthly": {"percent": 36},
        }})
        self.assertEqual([w["usedPercent"] for w in result["windows"]], [0, 10, 36])
        self.assertEqual(result["windows"][1]["resetsAt"], "2026-10-18T23:45:00+00:00")
        # No preformatted reset instant or timezone is ever emitted for display.
        self.assertNotIn("resetLabel", result["windows"][1])
        self.assertNotIn("Bogotá", json.dumps(result))
        self.assertFalse(result["identityVerified"])

    def test_unknown_values_are_not_zero_or_unlimited(self):
        for value in (None, "20", True, -1, float("nan"), float("inf"), 101):
            with self.subTest(value=value):
                self.assertIsNone(p.window("test", value)["usedPercent"])
        self.assertEqual(p.window("test", 0)["usedPercent"], 0)
        self.assertEqual(p.window("test", 100)["usedPercent"], 100)

    def test_window_exposes_reset_instant_only_never_a_formatted_label(self):
        entry = p.window("5 h", 10, "2026-10-18T23:45:00Z", reset_text="descripción del proveedor")
        self.assertEqual(entry["resetsAt"], "2026-10-18T23:45:00+00:00")
        self.assertNotIn("resetLabel", entry)
        self.assertEqual(entry["resetText"], "descripción del proveedor")
        self.assertIsNone(p.window("Sin reinicio", 1)["resetsAt"])

    def test_codex_window_duration_not_position_defines_label(self):
        data = {"accountId": "synthetic-account", "rateLimits": {
            "primary": {"usedPercent": 5, "windowDurationMins": 10080, "resetsAt": 1792309500},
            "secondary": {"usedPercent": 20, "windowDurationMins": 300}}}
        result = p.parse_codex(data)
        self.assertEqual([w["label"] for w in result["windows"]], ["Semanal", "5 h"])
        self.assertTrue(result["identityVerified"])
        self.assertNotIn("synthetic-account", json.dumps(result))

    def test_antigravity_report_drops_gemini_weekly_and_promotes_argon(self):
        report = {"status": "SUCCESS", "command": {"name": "usage", "data": {"groups": [
            {"name": "Gemini Models", "buckets": [
                {"name": "Weekly", "window": "weekly", "remaining_fraction": .8},
                {"name": "Session", "window": "5h"},
            ]},
            {"name": "Claude and GPT models", "buckets": [
                {"name": "Weekly", "window": "weekly", "remaining_fraction": .5},
            ]},
            {"name": "Gemini 4 Argon", "buckets": [
                {"name": "Weekly", "window": "weekly", "remaining_fraction": 1},
            ]},
        ]}}}
        result = p.parse_antigravity(report)
        # Redundant Gemini weekly is dropped and Argon is promoted to first.
        self.assertEqual([w["label"] for w in result["windows"]],
                         ["Gemini 4 Argon · Semanal", "Gemini Models · 5 h", "Claude and GPT models · Semanal"])
        self.assertAlmostEqual(result["windows"][2]["usedPercent"], 50)
        self.assertIsNone(result["windows"][1]["usedPercent"])
        self.assertIsNone(result["identity"])
        self.assertFalse(result["identityVerified"])
        self.assertEqual(p.parse_antigravity({"event": "result", "result": report}), result)
        for report in ({"status": "SUCCESS", "usage": {"input_tokens": 200}},
                       {"status": "ERROR"}, {"status": "SUCCESS", "command": {"name": "chat"}}):
            with self.assertRaises(QuotaError):
                p.parse_antigravity(report)

    def test_cursor_percentage_units_and_missing_total(self):
        result = p.parse_cursor({"individualUsage": {"plan": {"autoPercentUsed": .36, "apiPercentUsed": 48}},
                                 "billingCycleEnd": "2026-11-03T00:00:00Z"})
        self.assertEqual([w["usedPercent"] for w in result["windows"]], [.36, 48])
        self.assertEqual(len(result["windows"]), 2)
        # A reported plan total is deliberately not surfaced as a bar.
        with_total = p.parse_cursor({"individualUsage": {"plan": {
            "autoPercentUsed": .36, "apiPercentUsed": 48, "totalPercentUsed": 37}}})
        self.assertEqual([w["label"] for w in with_total["windows"]], ["Modelos de Cursor", "Otros modelos"])

    def test_grokbot_reads_only_the_weekly_cache_blob(self):
        import base64
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def blob(key: bytes, payload: dict) -> None:
                name = base64.b32encode(key).decode().lower() + ".blob"
                (root / name).write_text(json.dumps(payload), encoding="utf-8")
            blob(b"sand.client.slice.account.google-oauth2%7Cuser_x.weekly-usage.cache", {
                "schemaVersion": 2, "value": {"kind": "present", "reading": {
                    "usage": {"percentUsed": 10.745133, "nextResetMs": 1792867455507,
                              "grokPlanLabel": "Grok Bot Plan"}, "readAtMs": 1792336069565}}})
            # A conversation blob must never be read or leaked.
            blob(b"sand.client.slice.account.x.transcript", {
                "value": {"entries": [{"content": "private transcript"}]}})
            self.assertEqual(len(p.grokbot_cache_files(root)), 1)
            reading = p.grokbot_reading(root)
            self.assertAlmostEqual(reading["percentUsed"], 10.745133)
            parsed = p.parse_grokbot(reading)
            self.assertEqual(parsed["windows"][0]["label"], "Semanal")
            self.assertAlmostEqual(parsed["windows"][0]["usedPercent"], 10.745133)
            self.assertIsNotNone(parsed["windows"][0]["resetsAt"])
            self.assertEqual(parsed["plan"], "Grok Bot Plan")
            self.assertNotIn("transcript", json.dumps(parsed))

    def test_grokbot_fetch_reads_cache_or_reports_missing_app(self):
        account = {"provider": "grokbot", "source": "grokbot-cache", "credential": "0" * 32}
        with patch.object(p, "grokbot_reading", return_value={"percentUsed": 5}):
            self.assertEqual(p.fetch(account, None)["windows"][0]["usedPercent"], 5)
        with patch.object(p, "grokbot_reading", return_value=None):
            with self.assertRaises(QuotaError):
                p.fetch(account, None)

    def test_zed_uses_reported_budget_not_student_constant(self):
        result = p.parse_zed({"plan": "zed_student", "current_usage": {
            "token_spend": {"spend_in_cents": 300, "limit_in_cents": 4200}}})
        self.assertEqual(result["windows"][0]["usedAmount"], 3)
        self.assertEqual(result["windows"][0]["limitAmount"], 42)
        self.assertIsNone(result["windows"][0]["resetsAt"])
        self.assertFalse(result["identityVerified"])
        result = p.parse_zed({"current_usage": {"token_spend": {"spend_in_cents": 0}}})
        self.assertIsNone(result["windows"][0]["limitAmount"])
        self.assertIsNone(result["windows"][0]["usedPercent"])

    def test_claude_subscription_usage_is_not_api_billing(self):
        result = p.parse_claude({"five_hour": {"utilization": 12, "resets_at": "2026-10-18T23:45:00Z"},
                                 "seven_day": {"utilization": 42}, "seven_day_sonnet": None})
        self.assertEqual([w["usedPercent"] for w in result["windows"]], [12, 42])
        self.assertFalse(result["identityVerified"])
        for payload in ({}, {"five_hour": {"utilization": None}}, {"usage": {"input_tokens": 100}}):
            with self.assertRaises(QuotaError):
                p.parse_claude(payload)
        with self.assertRaises(QuotaError):
            p.validate_secret("claude-oauth", "sk-ant-api03-not-a-subscription-token")

    def test_claude_only_reads_the_fixed_usage_endpoint(self):
        vault = Mock()
        vault.get.return_value = "sk-ant-oat01-synthetic"
        with patch.object(p, "http_json", return_value={"five_hour": {"utilization": 17}}) as http:
            value = p.fetch({"provider": "claude", "source": "claude-oauth", "credential": "a" * 32}, vault)
        self.assertEqual(value["windows"][0]["usedPercent"], 17)
        self.assertEqual(http.call_args.args[0], "https://api.anthropic.com/api/oauth/usage")

    def test_unknown_schema_rejected(self):
        for parser in (p.parse_opencode, p.parse_codex, p.parse_cursor, p.parse_zed):
            with self.subTest(parser=parser.__name__), self.assertRaises(QuotaError):
                parser({})

    def test_redirect_never_forwards_credentials(self):
        with self.assertRaisesRegex(QuotaError, "redirect-rejected"):
            p.NoRedirect().redirect_request(None, None, 302, "", {}, "https://other.invalid")

    def test_header_injection_and_full_cookie_headers_rejected(self):
        for secret in ("a\r\nCookie: stolen", "a; extra=1", "", "spaces here", "WorkosCursorSessionToken=xyz"):
            with self.assertRaises(QuotaError):
                p.validate_secret("cursor-cookie", secret)
        with self.assertRaises(QuotaError):
            p.validate_secret("zed-cookie", "zed.session=abc")
        self.assertEqual(p.validate_secret("zed-cookie", "padded-value=="), "padded-value==")

    def test_no_client_calls_when_executable_missing(self):
        with patch.object(p.shutil, "which", return_value=None), patch.object(p.subprocess, "Popen") as popen:
            with self.assertRaisesRegex(QuotaError, "dependency-missing"):
                p.fetch_codex()
            popen.assert_not_called()

    def test_agy_older_version_never_sends_usage_prompt(self):
        process = Mock()
        process.collect.return_value = b"1.1.10"
        context = Mock()
        context.__enter__ = Mock(return_value=process)
        context.__exit__ = Mock(return_value=False)
        with patch("ai_quotas.guided.client_path", return_value="agy"), patch.object(p, "native_client", return_value=context) as native:
            with self.assertRaisesRegex(QuotaError, "unsupported-client-version"):
                p.fetch_antigravity()
            native.assert_called_once_with(["agy", "--version"])

    def test_cursor_identity_change_discards_usage(self):
        account = {"provider": "cursor", "source": "cursor-cookie", "credential": "a" * 32}
        vault = Mock()
        vault.get.return_value = "synthetic-cookie"
        with patch.object(p, "http_json", side_effect=[{"id": "A"}, {}, {"id": "B"}]):
            with self.assertRaisesRegex(QuotaError, "account-changed"):
                p.fetch(account, vault)

    def test_cursor_and_zed_manual_session_rejections_have_specific_expired_cookie_error(self):
        for provider, source, urls in (
            ("cursor", "cursor-cookie", ["https://cursor.com/api/auth/me"]),
            ("zed", "zed-cookie", ["https://cloud.zed.dev/frontend/billing/usage"]),
        ):
            vault = Mock()
            vault.get.return_value = "synthetic-expired-cookie"
            with patch.object(p, "http_json", side_effect=QuotaError("session-cookie-expired")) as http:
                with self.assertRaisesRegex(QuotaError, "session-cookie-expired"):
                    p.fetch({"provider": provider, "source": source, "credential": "a" * 32}, vault)
            self.assertEqual(http.call_args.args[0], urls[0])


class AccountsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.accounts = Accounts(self.root / "state")
        self.controller = Controller(self.accounts, self.root / "cache")

    def tearDown(self):
        self.temporary.cleanup()

    def add(self, alias="A"):
        return self.accounts.add("opencode", "api-key", alias, "a" * 32)

    def test_private_storage_and_no_secret_in_metadata(self):
        account = self.add()
        self.assertEqual(self.accounts.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.accounts.root.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.accounts.read()["selected"]["opencode"], account)
        output = self.controller.view()
        self.assertNotIn("credential", json.dumps(output))

    def test_grokbot_account_is_provisioned_once_when_the_app_cache_exists(self):
        with patch.object(quota_main.providers, "grokbot_available", return_value=True):
            quota_main.ensure_builtin_accounts(self.accounts)
            quota_main.ensure_builtin_accounts(self.accounts)
        data = self.accounts.read()
        grokbot = [a for a in data["accounts"] if a["provider"] == "grokbot"]
        self.assertEqual(len(grokbot), 1)
        self.assertEqual(grokbot[0]["source"], "grokbot-cache")
        self.assertEqual(data["selected"]["grokbot"], grokbot[0]["id"])
        # Without the app's cache nothing is provisioned.
        other = Accounts(self.root / "other")
        with patch.object(quota_main.providers, "grokbot_available", return_value=False):
            quota_main.ensure_builtin_accounts(other)
        self.assertFalse(any(a["provider"] == "grokbot" for a in other.read()["accounts"]))

    def test_cannot_select_account_for_another_provider(self):
        a = self.add()
        self.accounts.add("cursor", "cursor-cookie", "Cursor B", "b" * 32)
        self.accounts.mutate("select", a)
        data = self.accounts.read()
        self.assertNotEqual(data["selected"]["cursor"], a)

    def test_switch_immediately_discards_previous_quota(self):
        a = self.add()
        data = self.accounts.read()
        first = self.controller.selected(data, "opencode")
        self.controller.fetcher = lambda *_: p.result([p.window("Semanal", 17)])
        self.controller.refresh(first, data["generations"]["opencode"])
        self.assertEqual(self.controller.view()["providers"]["opencode"]["windows"][0]["usedPercent"], 17)
        b = self.add("B")
        view = self.controller.view()["providers"]["opencode"]
        self.assertEqual(view["accountId"], b)
        self.assertEqual(view["windows"], [])
        self.accounts.mutate("select", a)
        self.assertEqual(self.controller.view()["providers"]["opencode"]["windows"], [])

    def test_late_response_after_switch_never_published(self):
        self.add()
        data = self.accounts.read()
        account = self.controller.selected(data, "opencode")
        started, finish = threading.Event(), threading.Event()

        def delayed(*_):
            started.set()
            self.assertTrue(finish.wait(5))
            return p.result([p.window("Weekly", 99)])

        self.controller.fetcher = delayed
        with ThreadPoolExecutor(1) as executor:
            future = executor.submit(self.controller.refresh, account, data["generations"]["opencode"])
            self.assertTrue(started.wait(5))
            selected = self.add("B")
            finish.set()
            future.result(timeout=5)
        self.assertFalse(self.controller.cache_path(account, data["generations"]["opencode"]).exists())
        self.assertEqual(self.controller.view()["providers"]["opencode"]["accountId"], selected)
        self.assertEqual(self.controller.view()["providers"]["opencode"]["windows"], [])

    def test_credential_replacement_is_generation_checked(self):
        account_id = self.add()
        self.accounts.replace_credential(account_id, "a" * 32, "b" * 32)
        with self.assertRaisesRegex(QuotaError, "account-changed"):
            self.accounts.replace_credential(account_id, "a" * 32, "c" * 32)
        self.assertEqual(self.accounts.read()["accounts"][0]["credential"], "b" * 32)

    def test_failure_has_no_fallback_and_no_secret_in_errors(self):
        self.add()
        self.add("B")
        data = self.accounts.read()
        selected = self.controller.selected(data, "opencode")
        self.controller.fetcher = Mock(side_effect=ValueError("SECRET-MUST-NOT-LEAK"))
        self.controller.refresh(selected, data["generations"]["opencode"])
        view = self.controller.view()["providers"]["opencode"]
        self.assertEqual(view["status"], "internal-error")
        self.assertEqual(view["windows"], [])
        self.assertNotIn("SECRET", json.dumps(view))
        self.controller.fetcher.assert_called_once()

    def test_single_flight_and_manual_refresh_throttle(self):
        self.add()
        data = self.accounts.read()
        account = self.controller.selected(data, "opencode")
        self.controller.fetcher = Mock(return_value=p.result([p.window("Weekly", 0)]))
        for force in (False, False, True, True):
            self.controller.refresh(account, data["generations"]["opencode"], force)
        self.controller.fetcher.assert_called_once()

    def test_no_fake_multiple_native_profiles(self):
        self.accounts.add("antigravity", "agy-cli", "Active session", "a" * 32)
        with self.assertRaisesRegex(QuotaError, "active-session-exists"):
            self.accounts.add("antigravity", "agy-cli", "Not actually another account", "b" * 32)

    def test_symlink_metadata_refused_without_touching_target(self):
        target = self.root / "unrelated"
        target.write_text("do not touch")
        self.accounts.path.symlink_to(target)
        with self.assertRaises(OSError):
            self.accounts.read()
        self.assertEqual(target.read_text(), "do not touch")

    def test_disabled_and_unconfigured_are_not_zero(self):
        a = self.add()
        self.accounts.mutate("disable", a)
        view = self.controller.view()
        self.assertEqual(view["providers"]["opencode"]["status"], "disabled")
        self.assertEqual(view["providers"]["claude"]["status"], "not-subscribed")
        for snapshot in view["providers"].values():
            self.assertEqual(snapshot["windows"], [])


class VaultTests(unittest.TestCase):
    def test_locked_item_never_unlocks_or_reads_secret(self):
        api, connection, item = Mock(), Mock(), Mock()
        api.dbus_init.return_value = connection
        api.search_items.return_value = [item]
        item.is_locked.return_value = True
        with patch.object(importlib, "import_module", return_value=api):
            vault = Vault()
            with self.assertRaisesRegex(QuotaError, "locked"):
                vault.get("opencode", "a" * 32)
        item.get_secret.assert_not_called()
        item.unlock.assert_not_called()
        connection.close.assert_called_once()
        attributes = api.search_items.call_args.args[1]
        self.assertEqual(attributes["application"], APPLICATION)
        self.assertNotEqual(APPLICATION, "illogical-impulse")

    def test_locked_collection_never_stores_or_unlocks(self):
        api = Mock()
        collection = api.get_default_collection.return_value
        collection.is_locked.return_value = True
        with patch.object(importlib, "import_module", return_value=api):
            with self.assertRaisesRegex(QuotaError, "locked"):
                Vault().store("zed", "a" * 32, "synthetic-cookie")
        collection.create_item.assert_not_called()
        collection.unlock.assert_not_called()


class IntegrationTests(unittest.TestCase):
    @patch.object(quota_main.shutil, "which", return_value=None)
    def test_codex_gui_connect_reports_missing_official_client(self, which):
        with self.assertRaises(QuotaError) as raised:
            quota_main.store_credential("codex", "", "codex-cli")
        self.assertEqual(raised.exception.code, "dependency-missing")
        which.assert_called_once_with("codex")

    def test_gui_add_returns_missing_codex_error_for_dialog(self):
        with tempfile.TemporaryDirectory() as temp:
            bin_dir = Path(temp) / "bin"
            bin_dir.mkdir()
            env = {**os.environ, "HOME": temp, "PATH": str(bin_dir),
                   "XDG_STATE_HOME": temp + "/state", "XDG_CACHE_HOME": temp + "/cache"}
            process = subprocess.Popen(
                [sys.executable, "-B", str(SCRIPTS / "ai-quotas.py"), "serve"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, bufsize=1, env=env)
            try:
                assert process.stdout is not None and process.stdin is not None
                stdout, stdin = process.stdout, process.stdin
                # Consume the initial snapshot, then submit the same command the GUI sends.
                self.assertTrue(select.select([stdout], [], [], 5)[0])
                json.loads(stdout.readline())
                stdin.write(json.dumps({
                    "action": "add", "provider": "codex", "alias": "ChatGPT",
                    "secret": "", "source": "codex-cli", "requestId": "connect-1"
                }) + "\n")
                stdin.flush()

                result: dict | None = None
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    ready = select.select([stdout], [], [], max(0, deadline - time.monotonic()))[0]
                    if not ready:
                        break
                    frame = json.loads(stdout.readline())
                    if frame.get("operationResult", {}).get("requestId") == "connect-1":
                        result = frame["operationResult"]
                        break
                assert result is not None, "backend did not acknowledge the GUI request"
                self.assertFalse(result["ok"])
                self.assertEqual(result["message"], "Falta el cliente oficial en PATH. No se ha instalado nada.")
            finally:
                if process.stdin:
                    process.stdin.close()
                process.terminate()
                process.wait(timeout=5)
                if process.stdout:
                    process.stdout.close()
                if process.stderr:
                    process.stderr.close()

    def test_empty_home_view_does_not_access_auth_or_network(self):
        with tempfile.TemporaryDirectory() as home:
            env = {**os.environ, "HOME": home, "XDG_STATE_HOME": home + "/state", "XDG_CACHE_HOME": home + "/cache"}
            result = subprocess.run([sys.executable, "-B", str(SCRIPTS / "ai-quotas.py"), "view"],
                                    capture_output=True, text=True, env=env, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(result.stdout)
            self.assertEqual(len(data["providers"]), 7)
            self.assertIn("grokbot", data["providers"])
            self.assertTrue(all(not snapshot["windows"] for snapshot in data["providers"].values()))
            self.assertEqual(list(Path(home).rglob("accounts.json")), [])

    def test_source_contract_secret_and_hover_separation(self):
        shell = ROOT / "config/quickshell/ii"
        service = (shell / "services/AiQuotaUsage.qml").read_text()
        self.assertNotIn("KeyringStorage", service)
        self.assertNotIn("apiKeys", service)
        emblem = (shell / "modules/ii/bar/AiEmblem.qml").read_text()
        self.assertIn("AiEmblemState {", emblem)
        state = (shell / "modules/ii/bar/AiEmblemState.qml").read_text()
        self.assertIn("running: root.active && !root.held", state)
        self.assertIn("transition.stop()", state)
        # The emblem now intentionally opens the AI quota panel on left click.
        self.assertIn("GlobalStates.openAiQuotaPanel", emblem)
        resources = (shell / "modules/ii/bar/Resources.qml").read_text()
        self.assertIn("QuotaPresentation.resourceHovered(root.containsMouse, aiEmblem.hovered)", resources)
        self.assertIn("hoverTarget: resourceHoverTarget", resources)
        # The emblem opens the quota panel on click and no longer shows a hover tooltip.
        self.assertNotIn("AiQuotaPopup", emblem)

    def test_accounts_are_managed_from_the_gui_without_a_terminal(self):
        backend = (SCRIPTS / "ai_quotas/main.py").read_text()
        self.assertNotIn("open_manager", backend)
        self.assertNotIn('action == "manage"', backend)
        self.assertNotIn("terminal", backend)
        for action in ("add", "reconnect", "remove", "rename"):
            self.assertIn(f'action == "{action}"', backend)
        self.assertIn('"operationResult"', backend)
        service = (ROOT / "config/quickshell/ii/services/AiQuotaUsage.qml").read_text()
        self.assertNotIn("Config.options.apps.terminal", service)
        for method in ("function add", "function reconnect", "function remove", "function rename"):
            self.assertIn(method, service)
        dialog = (ROOT / "config/quickshell/ii/modules/common/aiQuotaPanel/AiQuotaConnectDialog.qml").read_text()
        self.assertIn("echoMode: TextInput.Password", dialog)
        self.assertIn("AiQuotaUsage.add(", dialog)
        self.assertIn("function onOperationResultChanged()", dialog)
        self.assertIn("root.errorMessage = result.message", dialog)
        self.assertIn("sesión de la app ChatGPT no se importa automáticamente", dialog)

    def test_bridge_source_uses_no_vault_and_legacy_sources_remain_valid(self):
        with patch.object(bridge, "run", return_value=p.result([p.window("5 h", 22)])) as run:
            vault = Mock()
            p.fetch({"provider": "codex", "source": "opencode-bridge"}, vault)
            run.assert_called_once_with("codex")
            vault.get.assert_not_called()
        with tempfile.TemporaryDirectory() as home:
            accounts = Accounts(Path(home))
            accounts.add("codex", "opencode-bridge", "ChatGPT", "a" * 32)
            accounts.add("opencode", "opencode-bridge", "Go", "b" * 32)
            with self.assertRaisesRegex(QuotaError, "active-session-exists"):
                accounts.add("codex", "opencode-bridge", "Duplicate", "c" * 32)

    def test_bridge_removal_never_deletes_opencode_credentials(self):
        with tempfile.TemporaryDirectory() as home:
            accounts = Accounts(Path(home) / "state")
            account_id = accounts.add("codex", "opencode-bridge", "ChatGPT", "a" * 32)
            with patch.object(quota_main, "Vault") as vault:
                quota_main.remove_account(Controller(accounts, Path(home) / "cache"), {"accountId": account_id})
                vault.assert_not_called()


class BridgeTests(unittest.TestCase):
    def test_async_login_cancel_and_connect_publish_only_current_account(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "packages/opencode/script/quota-bridge.ts"
            script.parent.mkdir(parents=True)
            script.write_text("fixture")
            executable = root / "bun"
            executable.write_text("#!/usr/bin/python3\nimport json, sys, time\nfrom pathlib import Path\n"
                "command = json.loads(sys.stdin.readline())\n"
                "if command['action'] == 'login':\n"
                " print(json.dumps({'version': 1, 'type': 'authorize',"
                " 'url': 'https://auth.openai.com/oauth/authorize?state=synthetic'}), flush=True)\n"
                " while not Path(__file__).with_name('release').exists(): time.sleep(.01)\n"
                "print(json.dumps({'version': 1, 'type': 'result', 'ok': True,"
                " 'measurement': {'primary': {'usedPercent': 23, 'windowMinutes': 300},"
                " 'identity': None, 'identityVerified': False}}), flush=True)\n")
            executable.chmod(0o700)
            env = {**os.environ, "HOME": directory, "PATH": directory,
                   "OPENCODE_QUOTA_ROOT": directory, "XDG_STATE_HOME": directory + "/state",
                   "XDG_CACHE_HOME": directory + "/cache"}
            process = subprocess.Popen([sys.executable, "-B", str(SCRIPTS / "ai-quotas.py"), "serve"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, bufsize=1, env=env)
            try:
                assert process.stdin is not None and process.stdout is not None
                stdin, stdout = process.stdin, process.stdout

                def send(command):
                    stdin.write(json.dumps(command) + "\n")
                    stdin.flush()

                def until(predicate):
                    deadline = time.monotonic() + 10
                    while time.monotonic() < deadline:
                        if select.select([stdout], [], [], max(0, deadline - time.monotonic()))[0]:
                            frame = json.loads(stdout.readline())
                            if predicate(frame):
                                return frame
                    self.fail("backend frame was not received")

                until(lambda frame: frame.get("version") == 1)
                send({"action": "login", "provider": "codex", "requestId": "login"})
                until(lambda frame: bool((frame.get("operationResult") or {}).get("url")))
                send({"action": "cancel", "requestId": "login"})
                send({"action": "rename", "accountId": "invalid", "requestId": "barrier"})
                barrier = until(lambda frame: (frame.get("operationResult") or {}).get("requestId") == "barrier")
                self.assertEqual(barrier["accounts"], [])
                (root / "release").touch()
                send({"action": "add", "provider": "codex", "requestId": "connect"})
                connected = until(lambda frame: (frame.get("operationResult") or {}).get("requestId") == "connect"
                                  and not (frame.get("operationResult") or {}).get("pending"))
                self.assertTrue(connected["operationResult"]["ok"])
                self.assertEqual(len(connected["accounts"]), 1)
                self.assertEqual(connected["accounts"][0]["source"], "opencode-bridge")
                ready = connected if connected["providers"]["codex"]["status"] == "ready" else until(
                    lambda frame: frame["providers"]["codex"]["status"] == "ready")
                self.assertEqual(ready["providers"]["codex"]["windows"][0]["usedPercent"], 23)
            finally:
                if process.stdin:
                    process.stdin.close()
                process.terminate()
                process.wait(timeout=5)
                for stream in (process.stdout, process.stderr):
                    if stream:
                        stream.close()

    def test_strict_measurement_boundary(self):
        value = bridge.measurement({"measurement": {"primary": {"usedPercent": 0, "windowMinutes": 300},
                                    "secondary": {"usedPercent": 80, "windowMinutes": 10080},
                                    "identity": "a" * 64, "identityVerified": True}})
        self.assertEqual([w["usedPercent"] for w in value["windows"]], [0, 80])
        for raw in ({}, {"primary": {"usedPercent": True}}, {"primary": {"usedPercent": 101}},
                    {"primary": {"usedPercent": None}}, {"primary": {"usedPercent": 2},
                     "identity": "raw-account-id", "identityVerified": True}):
            with self.assertRaises(QuotaError):
                bridge.measurement({"measurement": raw})

    def test_authorization_url_allowlist(self):
        self.assertEqual(bridge.authorize_url("https://auth.openai.com/oauth/authorize?state=x"),
                         "https://auth.openai.com/oauth/authorize?state=x")
        for url in ("http://auth.openai.com/oauth/authorize", "https://evil.invalid/oauth/authorize",
                    "https://auth.openai.com@evil.invalid/oauth/authorize", "file:///etc/passwd",
                    "https://auth.openai.com/other", "https://auth.openai.com/oauth/authorize#fragment"):
            with self.assertRaises(QuotaError):
                bridge.authorize_url(url)

    def test_real_process_transport_and_sanitized_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "packages/opencode/script/quota-bridge.ts"
            script.parent.mkdir(parents=True)
            script.write_text("fixture")
            executable = root / "bun"
            executable.write_text("#!/usr/bin/python3\nimport json, sys\n"
                                  "command = json.loads(sys.stdin.readline())\n"
                                  "print(json.dumps({'version': 1, 'type': 'result', 'ok': True,"
                                  " 'measurement': {'primary': {'usedPercent': 23, 'windowMinutes': 300},"
                                  " 'identity': None, 'identityVerified': False}}), flush=True)\n")
            executable.chmod(0o700)
            with patch.dict(os.environ, {"PATH": str(root), "OPENCODE_QUOTA_ROOT": str(root)}):
                value = bridge.run("opencode")
            self.assertEqual(value["windows"][0]["usedPercent"], 23)

    def test_cancelled_bridge_does_not_wait_for_callback(self):
        cancelled = threading.Event()
        cancelled.set()
        with patch.object(bridge, "command", return_value=["python3", "-c", "import time; time.sleep(30)"]):
            with self.assertRaisesRegex(QuotaError, "cancelled"):
                bridge.run("codex", login=True, cancelled=cancelled)


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("deploy_ai_quotas", ROOT / "scripts/deploy-ai-quotas.py")
        assert spec is not None and spec.loader is not None
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source, self.target, self.backup = self.root / "source", self.root / "target", self.root / "backup"
        self.target.mkdir()
        for relative in self.module.FILES:
            source = self.source / relative
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("new quota code")
        self.existing = self.target / "modules/ii/bar/AiEmblem.qml"
        self.existing.parent.mkdir(parents=True)
        self.existing.write_text("previous emblem code")
        (self.target / "authenticator-private-state").write_text("unrelated state")

    def tearDown(self):
        self.temporary.cleanup()

    def test_preview_then_selective_backup_and_restore(self):
        self.module.deploy(self.source, self.target, self.backup)
        self.assertFalse(self.backup.exists())
        self.assertEqual(self.existing.read_text(), "previous emblem code")
        self.module.deploy(self.source, self.target, self.backup, execute=True)
        self.assertEqual(self.backup.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.existing.read_text(), "new quota code")
        self.assertEqual((self.target / "authenticator-private-state").read_text(), "unrelated state")
        self.assertFalse((self.backup / "authenticator-private-state").exists())
        self.module.restore(self.backup)
        self.assertEqual(self.existing.read_text(), "previous emblem code")

    def test_restore_rejects_changed_live_code(self):
        self.module.deploy(self.source, self.target, self.backup, execute=True)
        self.existing.write_text("subsequent user changes")
        with self.assertRaisesRegex(ValueError, "Live code changed"):
            self.module.restore(self.backup)
        self.assertEqual(self.existing.read_text(), "subsequent user changes")

    def test_deployment_rejects_symlink_targets(self):
        self.existing.unlink()
        elsewhere = self.root / "unrelated"
        elsewhere.write_text("unrelated code")
        self.existing.symlink_to(elsewhere)
        with self.assertRaisesRegex(ValueError, "Symlinks"):
            self.module.deploy(self.source, self.target, self.backup, execute=True)
        self.assertEqual(elsewhere.read_text(), "unrelated code")


if __name__ == "__main__":
    unittest.main()
