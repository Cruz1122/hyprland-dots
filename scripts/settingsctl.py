#!/usr/bin/env python3
"""Small settings control helper for illogical-impulse local development.

The helper intentionally starts narrow: validate and migrate config.json without
changing the live session unless explicitly pointed at the live file.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


CURRENT_SCHEMA_VERSION = 1
SCHEMA_KEY = "_schemaVersion"


class SettingsError(Exception):
    """Raised for user-facing settings errors."""


@dataclass(frozen=True)
class MigrationResult:
    data: dict[str, Any]
    changed: bool
    from_version: int
    to_version: int


def load_config(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as file_obj:
            data = json.load(file_obj)
    except FileNotFoundError as exc:
        raise SettingsError(f"Config file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SettingsError(f"Invalid JSON in {path}: {exc}") from exc

    if not isinstance(data, dict):
        raise SettingsError("Config root must be a JSON object")
    return data


def validate_config(data: dict[str, Any]) -> None:
    schema_version = data.get(SCHEMA_KEY, 0)
    if not isinstance(schema_version, int):
        raise SettingsError(f"{SCHEMA_KEY} must be an integer when present")
    if schema_version < 0:
        raise SettingsError(f"{SCHEMA_KEY} must not be negative")
    if schema_version > CURRENT_SCHEMA_VERSION:
        raise SettingsError(
            f"Unsupported future schema version {schema_version}; "
            f"tool supports {CURRENT_SCHEMA_VERSION}"
        )


def migrate_config(data: dict[str, Any]) -> MigrationResult:
    validate_config(data)
    original_version = data.get(SCHEMA_KEY, 0)
    migrated = dict(data)
    changed = False

    if original_version == 0:
        migrated[SCHEMA_KEY] = 1
        changed = True

    validate_config(migrated)
    return MigrationResult(
        data=migrated,
        changed=changed,
        from_version=original_version,
        to_version=migrated[SCHEMA_KEY],
    )


def atomic_write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    original_mode = path.stat().st_mode & 0o7777 if path.exists() else None
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temp_path = Path(temp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as file_obj:
            json.dump(data, file_obj, ensure_ascii=False, indent=4, sort_keys=True)
            file_obj.write("\n")
            file_obj.flush()
            os.fsync(file_obj.fileno())
        if original_mode is not None:
            os.chmod(temp_path, original_mode)
        os.replace(temp_path, path)
    finally:
        if temp_path.exists():
            temp_path.unlink()


def backup_file(path: Path) -> Path:
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = path.with_name(f"{path.name}.pre-settingsctl-{timestamp}")
    shutil.copy2(path, backup_path)
    return backup_path


def command_validate(args: argparse.Namespace) -> int:
    data = load_config(args.config)
    validate_config(data)
    print(f"OK schema={data.get(SCHEMA_KEY, 0)} path={args.config}")
    return 0


def command_migrate(args: argparse.Namespace) -> int:
    data = load_config(args.config)
    result = migrate_config(data)
    if args.dry_run:
        print(
            "DRY-RUN "
            f"from={result.from_version} to={result.to_version} "
            f"changed={str(result.changed).lower()} path={args.config}"
        )
        return 0

    if not result.changed:
        print(f"OK unchanged schema={result.to_version} path={args.config}")
        return 0

    backup_path = backup_file(args.config)
    atomic_write_json(args.config, result.data)
    print(f"OK migrated from={result.from_version} to={result.to_version} backup={backup_path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate and migrate illogical-impulse settings")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate", help="Validate a config JSON file")
    validate.add_argument("config", type=Path)
    validate.set_defaults(func=command_validate)

    migrate = subparsers.add_parser("migrate", help="Migrate a config JSON file")
    migrate.add_argument("config", type=Path)
    migrate.add_argument("--dry-run", action="store_true")
    migrate.set_defaults(func=command_migrate)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except SettingsError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
