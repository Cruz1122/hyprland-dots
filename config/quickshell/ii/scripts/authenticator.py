#!/usr/bin/env python3
"""Local primitives for the Quickshell authenticator.

Secrets are accepted through stdin whenever possible and are never logged.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import struct
import subprocess
import sys
import time
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse

def parse_otpauth(uri: str) -> dict:
    parsed = urlparse(uri.strip())
    if parsed.scheme != "otpauth" or parsed.netloc.lower() != "totp":
        raise ValueError("Only otpauth://totp URIs are supported")
    query = parse_qs(parsed.query)
    secret = query.get("secret", [""])[0].replace(" ", "").upper()
    if not secret:
        raise ValueError("The URI does not contain a secret")
    try:
        base64.b32decode(secret + "=" * (-len(secret) % 8), casefold=True)
    except Exception as exc:
        raise ValueError("The secret is not valid Base32") from exc
    algorithm = query.get("algorithm", ["SHA1"])[0].upper()
    if algorithm not in {"SHA1", "SHA256", "SHA512"}:
        raise ValueError("Unsupported algorithm")
    try:
        digits = int(query.get("digits", ["6"])[0])
        period = int(query.get("period", ["30"])[0])
    except (TypeError, ValueError) as exc:
        raise ValueError("Invalid digits or period") from exc
    if digits not in {6, 8} or period <= 0 or period > 3600:
        raise ValueError("Invalid digits or period")
    label = unquote(parsed.path.lstrip("/"))
    issuer = query.get("issuer", [""])[0]
    account = label.split(":", 1)[-1] if ":" in label else label
    if not account:
        raise ValueError("The URI does not contain an account")
    return {"issuer": issuer, "account": account, "secret": secret,
            "algorithm": algorithm, "digits": digits, "period": period}


def _migration_message(raw: bytes):
    """Build the de-facto Google migration protobuf without a generated file."""
    from google.protobuf import descriptor_pb2, descriptor_pool, message_factory
    file = descriptor_pb2.FileDescriptorProto(name="migration.proto", package="ii")
    enum_specs = [("Algorithm", [("ALGORITHM_UNSPECIFIED", 0), ("ALGORITHM_SHA1", 1), ("ALGORITHM_SHA256", 2), ("ALGORITHM_SHA512", 3), ("ALGORITHM_MD5", 4)]),
                  ("Digits", [("DIGITS_UNSPECIFIED", 0), ("DIGITS_SIX", 1), ("DIGITS_EIGHT", 2)]),
                  ("OtpType", [("OTP_UNSPECIFIED", 0), ("OTP_HOTP", 1), ("OTP_TOTP", 2)])]
    for name, values in enum_specs:
        enum = file.enum_type.add(name=name)
        for value, number in values: enum.value.add(name=value, number=number)
    account = file.message_type.add(name="OtpParameters")
    for name, number, kind, type_name in [("secret", 1, 12, ""), ("name", 2, 9, ""), ("issuer", 3, 9, ""),
                                          ("algorithm", 4, 14, ".ii.Algorithm"), ("digits", 5, 14, ".ii.Digits"),
                                          ("type", 6, 14, ".ii.OtpType"), ("counter", 7, 3, "")]:
        field = account.field.add(name=name, number=number, label=1, type=kind)
        if type_name: field.type_name = type_name
    payload = file.message_type.add(name="MigrationPayload")
    field = payload.field.add(name="otp_parameters", number=1, label=3, type=11, type_name=".ii.OtpParameters")
    for name, number in [("version", 2), ("batch_size", 3), ("batch_index", 4), ("batch_id", 5)]:
        payload.field.add(name=name, number=number, label=1, type=5)
    pool = descriptor_pool.DescriptorPool(); pool.Add(file)
    cls = message_factory.GetMessageClass(pool.FindMessageTypeByName("ii.MigrationPayload"))
    result = cls(); result.ParseFromString(raw); return result


def parse_migration_uri(uri: str) -> list[dict]:
    parsed = urlparse(uri.strip())
    if parsed.scheme != "otpauth-migration" or parsed.netloc != "offline":
        raise ValueError("Unsupported migration URI")
    data = next((unquote(item.split("=", 1)[1]) for item in parsed.query.split("&") if item.startswith("data=")), "")
    if not data: raise ValueError("Migration URI has no data")
    try: raw = base64.b64decode(data, validate=True)
    except Exception as exc: raise ValueError("Invalid migration Base64") from exc
    payload: Any = _migration_message(raw)
    algorithms = {1: "SHA1", 2: "SHA256", 3: "SHA512"}; digits = {1: 6, 2: 8}
    accounts = []
    for item in payload.otp_parameters:
        if item.type != 2 or item.algorithm not in algorithms or item.digits not in digits or not item.secret or not item.name:
            raise ValueError("Migration contains unsupported or invalid account")
        accounts.append({"issuer": item.issuer, "account": item.name, "secret": base64.b32encode(item.secret).decode().rstrip("="),
                         "algorithm": algorithms[item.algorithm], "digits": digits[item.digits], "period": 30})
    if not accounts: raise ValueError("Migration contains no accounts")
    return accounts


def totp(secret: str, timestamp: int, digits: int = 6, period: int = 30,
         algorithm: str = "SHA1") -> str:
    if algorithm.upper() not in {"SHA1", "SHA256", "SHA512"} or digits not in {6, 8} or period <= 0 or period > 3600:
        raise ValueError("Invalid TOTP parameters")
    normalized = secret.replace(" ", "").upper()
    try:
        key = base64.b32decode(normalized + "=" * (-len(normalized) % 8), casefold=True)
    except Exception as exc:
        raise ValueError("The secret is not valid Base32") from exc
    counter = int(timestamp) // period
    digest = getattr(hashlib, algorithm.lower())
    mac = hmac.new(key, struct.pack(">Q", counter), digest).digest()
    offset = mac[-1] & 0x0F
    value = (struct.unpack(">I", mac[offset:offset + 4])[0] & 0x7FFFFFFF) % (10 ** digits)
    return f"{value:0{digits}d}"


def qr_decode(path: str) -> list[str]:
    result = subprocess.run(["zbarimg", "--raw", "--quiet", path], check=False,
                            capture_output=True, text=True, timeout=10)
    values = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if result.returncode != 0 or not values:
        raise ValueError("No QR code detected")
    return values


def export_encrypted(accounts: list[dict], password: str) -> str:
    if not password:
        raise ValueError("A password is required")
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    except ImportError as exc:
        raise ValueError("Python cryptography is required for encrypted export") from exc
    salt = os.urandom(16)
    nonce = os.urandom(12)
    key = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 300_000, 32)
    payload = json.dumps(accounts, separators=(",", ":")).encode()
    ciphertext = AESGCM(key).encrypt(nonce, payload, b"illogical-impulse-authenticator-v1")
    return json.dumps({"format": "ii-authenticator-v1", "salt": base64.b64encode(salt).decode(),
                       "nonce": base64.b64encode(nonce).decode(), "data": base64.b64encode(ciphertext).decode()})


def import_encrypted(package: str, password: str) -> list[dict]:
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
        value = json.loads(package)
        if value.get("format") != "ii-authenticator-v1":
            raise ValueError("Unsupported authenticator export")
        salt = base64.b64decode(value["salt"])
        nonce = base64.b64decode(value["nonce"])
        ciphertext = base64.b64decode(value["data"])
        key = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 300_000, 32)
        accounts = json.loads(AESGCM(key).decrypt(nonce, ciphertext, b"illogical-impulse-authenticator-v1"))
        if not isinstance(accounts, list) or not all(isinstance(item, dict) for item in accounts):
            raise ValueError("Invalid authenticator account list")
        return accounts
    except ImportError as exc:
        raise ValueError("Python cryptography is required for encrypted import") from exc
    except Exception as exc:
        raise ValueError("Invalid password or authenticator export") from exc


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if command == "parse":
            print(json.dumps(parse_otpauth(sys.stdin.read().strip())))
        elif command == "totp":
            args = json.loads(sys.stdin.read())
            print(totp(args["secret"], args.get("timestamp", int(time.time())),
                       args.get("digits", 6), args.get("period", 30), args.get("algorithm", "SHA1")))
        elif command == "qr":
            for value in qr_decode(sys.argv[2]):
                if value.startswith("otpauth-migration://"):
                    print(json.dumps(parse_migration_uri(value)))
                else:
                    print(value)
        elif command == "totps":
            accounts = json.loads(sys.stdin.read())
            if not isinstance(accounts, list):
                raise ValueError("Invalid authenticator account list")
            now = int(time.time())
            print(json.dumps({f'{item.get("issuer", "")}\u0000{item["account"]}': totp(
                item["secret"], now, item.get("digits", 6), item.get("period", 30), item.get("algorithm", "SHA1"))
                for item in accounts}))
        elif command == "export":
            request = json.loads(sys.stdin.read())
            print(export_encrypted(request["accounts"], request["password"]))
        elif command == "import":
            request = json.loads(sys.stdin.read())
            print(json.dumps(import_encrypted(request["package"], request["password"])))
        else:
            raise ValueError("Unknown authenticator command")
    except ImportError:
        print("Missing Python dependency: install python-protobuf and python-cryptography", file=sys.stderr)
        return 1
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
