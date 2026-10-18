from __future__ import annotations

import hashlib
import importlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "config/quickshell/ii/scripts"
FORK = Path(os.environ.get("OPENCODE_QUOTA_ROOT", str(Path.home() / "dev/opencode")))
sys.path.insert(0, str(SCRIPTS))
link = importlib.import_module("ai_quotas.browser_link")
a = importlib.import_module("ai_quotas.accounts")


class BrowserLinkTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.environment = patch.dict(os.environ, {"HOME": self.temp.name,
            "XDG_DATA_HOME": self.temp.name + "/data", "XDG_STATE_HOME": self.temp.name + "/state",
            "XDG_CONFIG_HOME": self.temp.name + "/config"})
        self.environment.start()

    def tearDown(self):
        self.environment.stop()
        self.temp.cleanup()

    def test_prepare_only_registers_opt_in_native_host_and_copies_extension_not_browser_profile(self):
        with patch.object(link.subprocess, "Popen") as execute:
            path = Path(link.prepare(open_browser=False))
        execute.assert_not_called()
        manifest = json.loads((path / "manifest.json").read_text())
        self.assertNotIn("cookies", manifest["permissions"])
        self.assertNotIn("debugger", manifest["permissions"])
        import base64
        raw = hashlib.sha256(base64.b64decode(manifest["key"])).digest()[:16]
        extension_id = "".join(chr(97 + (byte >> 4)) + chr(97 + (byte & 15)) for byte in raw)
        self.assertEqual(extension_id, link.EXTENSION_ID)
        host = self.root / "config/BraveSoftware/Brave-Browser/NativeMessagingHosts" / (link.HOST + ".json")
        registered = json.loads(host.read_text())
        self.assertEqual(registered["allowed_origins"], [f"chrome-extension://{link.EXTENSION_ID}/"])
        self.assertEqual(Path(registered["path"]).stat().st_mode & 0o777, 0o700)
        self.assertEqual(list(self.root.rglob("Cookies")), [])

    def test_native_manager_launch_reuses_browser_without_profile_or_debug_flags(self):
        with patch.object(link.shutil, "which", return_value="/usr/bin/brave"), patch.object(link.subprocess, "Popen") as start:
            link.open_extension_manager()
        self.assertEqual(start.call_args.args[0], ["/usr/bin/brave", "brave://extensions/"])

    def test_no_provider_is_requested_before_setup_or_explicit_login(self):
        self.assertEqual(link.state(), {"ok": True, "requests": []})

    def active(self):
        state = a.Accounts()
        account_id = state.add("cursor", "browser-extension", "Cursor", "a" * 32)
        return state, next(item for item in state.read()["accounts"] if item["id"] == account_id)

    def test_single_use_publish_binds_to_selected_account_and_preserves_measurement_time(self):
        state, account = self.active()
        task = link.state()["requests"][0]
        command = {"provider": "cursor", "nonce": task["nonce"], "identity": "a" * 64,
            "usage": {"individualUsage": {"plan": {"autoPercentUsed": 24}}}}
        self.assertEqual(link.publish(command), {"ok": True})
        measured = link.fetch(account)
        self.assertEqual(measured["windows"][0]["usedPercent"], 24)
        self.assertTrue(measured["identityVerified"])
        self.assertLessEqual(measured["observedAt"], time.time())
        self.assertEqual(link.state()["requests"], [])
        with self.assertRaisesRegex(a.QuotaError, "account-changed"):
            link.publish(command)
        state.mutate("invalidate", account["id"])
        with self.assertRaisesRegex(a.QuotaError, "waiting-browser-usage"):
            link.fetch(account)

    def test_disabled_account_stops_requests_and_rejects_inflight_response(self):
        state, account = self.active()
        task = link.state()["requests"][0]
        state.mutate("disable", account["id"])
        self.assertEqual(link.state()["requests"], [])
        with self.assertRaises(a.QuotaError):
            link.publish({"provider": "cursor", "nonce": task["nonce"], "identity": None,
                "usage": {"individualUsage": {"plan": {"totalPercentUsed": 50}}}})

    def test_unknown_quota_or_forged_identity_never_completes_ticket(self):
        _, _account = self.active()
        task = link.state()["requests"][0]
        for usage, identity in (({}, None), ({"individualUsage": {"plan": {"totalPercentUsed": None}}}, None),
                                ({"individualUsage": {"plan": {"totalPercentUsed": 4}}}, "raw-user-id")):
            with self.assertRaises(a.QuotaError):
                link.publish({"provider": "cursor", "nonce": task["nonce"], "usage": usage, "identity": identity})
        self.assertEqual(link.state()["requests"][0]["nonce"], task["nonce"])

    def test_progress_reports_are_fixed_codes_bound_to_the_current_ticket(self):
        self.active()
        task = link.state()["requests"][0]
        self.assertEqual(link.report({"provider": "cursor", "nonce": task["nonce"], "code": "login-required"}), {"ok": True})
        value = a.read_json(link.root_path() / "cursor.status.json", {})
        self.assertEqual(value, {"nonce": task["nonce"], "code": "login-required"})
        with self.assertRaises(a.QuotaError):
            link.report({"provider": "cursor", "nonce": "0" * 64, "code": "login-required"})
        with self.assertRaises(a.QuotaError):
            link.report({"provider": "cursor", "nonce": task["nonce"], "code": "CANARY_RAW_ERROR"})

    def test_login_opens_default_url_and_only_completes_after_quota_publication(self):
        link.state()  # Installed extension heartbeat, no credentials.
        cancelled = threading.Event()
        seen, result, errors = [], [], []

        def login():
            try:
                result.append(link.login("zed", cancelled, seen.append))
            except Exception as error:
                errors.append(error)

        worker = threading.Thread(target=login)
        worker.start()
        deadline = time.monotonic() + 5
        while not seen and time.monotonic() < deadline:
            time.sleep(.01)
        try:
            task = link.state()["requests"][0]
            self.assertTrue(task["login"])
            self.assertEqual(seen, ["https://dashboard.zed.dev/account"])
            self.assertTrue(worker.is_alive())
            link.publish({"provider": "zed", "nonce": task["nonce"], "identity": None,
                "usage": {"current_usage": {"token_spend": {"spend_in_cents": 300, "limit_in_cents": 4200}}}})
            worker.join(timeout=5)
            self.assertEqual(errors, [])
            state = a.Accounts()
            account_id = state.add("zed", "browser-extension", "Zed", "b" * 32)
            link.bind("zed", result[0])
            account = next(item for item in state.read()["accounts"] if item["id"] == account_id)
            self.assertEqual(link.fetch(account)["windows"][0]["usedAmount"], 3)
        finally:
            cancelled.set()
            worker.join(timeout=5)

    def test_cancelled_login_invalidates_its_ticket(self):
        link.state()
        cancelled = threading.Event()
        cancelled.set()
        with self.assertRaisesRegex(a.QuotaError, "cancelled"):
            link.login("cursor", cancelled, lambda _url: None)
        self.assertEqual(link.state()["requests"], [])

    def test_missing_extension_fails_immediately_instead_of_launching_fresh_browser(self):
        with self.assertRaisesRegex(a.QuotaError, "browser-link-required"):
            link.login("cursor", threading.Event(), lambda _url: self.fail("must not open browser"))

    def test_native_message_framing_and_origin_are_checked(self):
        def invoke(origin, payload):
            raw = json.dumps(payload).encode()
            return subprocess.run([sys.executable, "-B", str(SCRIPTS / "browser-quota-host.py"), origin],
                input=struct.pack("<I", len(raw)) + raw, capture_output=True, timeout=5)
        rejected = invoke("chrome-extension://untrusted/", {"action": "state"})
        self.assertEqual(rejected.returncode, 1)
        self.assertEqual(rejected.stdout, b"")
        accepted = invoke(f"chrome-extension://{link.EXTENSION_ID}/", {"action": "state"})
        size = struct.unpack("<I", accepted.stdout[:4])[0]
        self.assertEqual(size, len(accepted.stdout[4:]))
        self.assertEqual(json.loads(accepted.stdout[4:]), {"ok": True, "requests": []})
        self.assertEqual(accepted.stderr, b"")

    @unittest.skipUnless(shutil.which("bun") and shutil.which("brave") and (FORK / "packages/opencode/src/provider/quota-browser.ts").is_file(),
                         "real Native Messaging smoke requires the local OpenCode fork, Bun and Brave")
    def test_actual_brave_extension_native_messaging_with_empty_temporary_profile(self):
        extension = Path(link.prepare(open_browser=False))
        executable = shutil.which("brave")
        wrapper = self.root / "test-browser"
        wrapper.write_text("#!/usr/bin/python3\nimport os,sys\n"
            f"os.execv({executable!r}, [{executable!r}, '--load-extension={extension}',"
            f" '--disable-extensions-except={extension}', *sys.argv[1:]])\n")
        wrapper.chmod(0o700)
        profile = self.root / "config/BraveSoftware/Brave-Browser"
        script = f"""
            const {{QuotaBrowserPipe}} = await import({json.dumps(str(FORK / 'packages/opencode/src/provider/quota-browser.ts'))});
            const browser = new QuotaBrowserPipe({json.dumps(str(wrapper))}, {json.dumps(str(profile))}, false);
            try {{
                await browser.call('Browser.getVersion');
                let target;
                for(let i=0;i<40;i++) {{
                    const result=await browser.call('Target.getTargets');
                    target=result.targetInfos.find(item=>item.type==='service_worker' && item.url.startsWith('chrome-extension://{link.EXTENSION_ID}/'));
                    if(target) break;
                    await Bun.sleep(250);
                }}
                if(!target) throw Error('extension service worker did not start');
                const attached=await browser.call('Target.attachToTarget',{{targetId:target.targetId,flatten:true}});
                const result=await browser.evaluate(attached.sessionId,
                    "chrome.runtime.sendNativeMessage('{link.HOST}',{{action:'state'}}).catch(error=>({{nativeError:error.message}}))");
                if(!result?.ok) throw Error(JSON.stringify(result));
                console.log(JSON.stringify(result));
            }} finally {{ await browser.close(); }}
        """
        bun = shutil.which("bun")
        assert bun is not None
        process = subprocess.run([bun, "-e", script], cwd=FORK / "packages/opencode",
            capture_output=True, text=True, timeout=35)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(json.loads(process.stdout), {"ok": True, "requests": []})


if __name__ == "__main__":
    unittest.main()
