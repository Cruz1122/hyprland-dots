from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("authenticator", ROOT / "config/quickshell/ii/scripts/authenticator.py")
assert SPEC is not None
AUTH = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(AUTH)


class AuthenticatorDomainTest(unittest.TestCase):
    def test_rfc6238_sha1_vector(self) -> None:
        secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"  # gitleaks:allow -- public RFC 6238 test vector
        self.assertEqual(AUTH.totp(secret, 59), "287082")
        self.assertEqual(AUTH.totp(secret, 59, 8), "94287082")

    def test_parse_totp_uri(self) -> None:
        account = AUTH.parse_otpauth("otpauth://totp/Example:alice%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example")
        self.assertEqual(account["issuer"], "Example")
        self.assertEqual(account["account"], "alice@example.com")
        self.assertEqual(account["digits"], 6)

    def test_rejects_non_totp_uri(self) -> None:
        with self.assertRaises(ValueError):
            AUTH.parse_otpauth("otpauth://hotp/Example:alice?secret=JBSWY3DPEHPK3PXP")

    def test_parses_google_migration_payload_with_multiple_accounts(self) -> None:
        uri = "otpauth-migration://offline?data=CjgKFDEyMzQ1Njc4OTAxMjM0NTY3ODkwEhFhbGljZUBleGFtcGxlLmNvbRoHRXhhbXBsZSABKAEwAgo2ChQxMjM0NTY3ODkwMTIzNDU2Nzg5MBIPYm9iQGV4YW1wbGUubmV0GgdFeGFtcGxlIAIoAjACEAEYASAAKCo="
        accounts = AUTH.parse_migration_uri(uri)
        self.assertEqual(len(accounts), 2)
        self.assertEqual(accounts[0]["account"], "alice@example.com")
        self.assertEqual(accounts[1]["digits"], 8)

    def test_rejects_malformed_parameters_and_empty_account(self) -> None:
        for uri in (
            "otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&digits=no",
            "otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&period=0",
            "otpauth://totp/?secret=JBSWY3DPEHPK3PXP",
        ):
            with self.assertRaises(ValueError):
                AUTH.parse_otpauth(uri)

    def test_totp_rejects_invalid_runtime_parameters(self) -> None:
        with self.assertRaises(ValueError):
            AUTH.totp("not-base32", 0)
        with self.assertRaises(ValueError):
            AUTH.totp("JBSWY3DPEHPK3PXP", 0, period=0)


if __name__ == "__main__":
    unittest.main()
