#!/usr/bin/env python3
"""Deploy only the quota feature, backing up existing live code (never account state)."""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile


FILES = (
    "scripts/ai-quotas.py",
    "scripts/ai_quotas/__init__.py",
    "scripts/ai_quotas/accounts.py",
    "scripts/ai_quotas/providers.py",
    "scripts/ai_quotas/main.py",
    "scripts/ai_quotas/bridge.py",
    "scripts/ai_quotas/guided.py",
    "scripts/ai_quotas/native_exec.py",
    "scripts/ai_quotas/browser_link.py",
    "scripts/browser-quota-host.py",
    "browser-extension/manifest.json",
    "browser-extension/background.mjs",
    "browser-extension/usage.mjs",
    "scripts/ai_quotas/claude_statusline.py",
    "scripts/claude-statusline.py",
    "services/AiQuotaUsage.qml",
    "modules/common/aiQuotaPanel/AiQuotaPanel.qml",
    "modules/common/aiQuotaPanel/AiQuotaPanelCurtain.qml",
    "modules/common/aiQuotaPanel/AiQuotaConnectDialog.qml",
    "modules/ii/bar/AiQuotaPresentation.js",
    "modules/ii/bar/AiEmblemState.qml",
    "modules/ii/bar/AiQuotaPopup.qml",
    "modules/settings/components/AiQuotaSettings.qml",
    # Publish new dependencies before the existing entry points change.
    "modules/ii/bar/AiEmblem.qml",
    "modules/ii/bar/Resources.qml",
    "modules/settings/ServicesConfig.qml",
    "assets/icons/swap-symbolic.svg",
    "assets/icons/ai/grokbot.png",
)
SOURCE = Path(__file__).resolve().parents[1] / "config/quickshell/ii"


def checked_file(root: Path, relative: str) -> Path:
    if relative not in FILES:
        raise ValueError("Path is outside the quota deployment scope")
    path = root / relative
    for entry in (path, *path.parents):
        if entry == root.parent:
            break
        if entry.is_symlink():
            raise ValueError("Symlinks are not deployment targets")
    if path.exists() and (not path.is_file() or path.stat().st_uid != os.getuid()):
        raise ValueError("Target is not an owned regular file")
    return path


def atomic_write(path: Path, content: bytes, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".quota-deploy-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def deploy(source: Path, target: Path, backup: Path, *, execute: bool = False) -> dict:
    if target.is_symlink() or not target.is_dir() or target.stat().st_uid != os.getuid():
        raise ValueError("Config root must be an existing owned directory")
    payload, originals = {}, {}
    for relative in FILES:
        src, dst = checked_file(source, relative), checked_file(target, relative)
        payload[relative] = src.read_bytes()
        originals[relative] = dst.read_bytes() if dst.exists() else None
    summary = {"changed": [name for name in FILES if payload[name] != originals[name]], "backup": str(backup)}
    if not execute:
        return summary
    backup.mkdir(parents=True, mode=0o700, exist_ok=False)
    backup.chmod(0o700)
    manifest = {"target": str(target.resolve()), "files": {}}
    for relative in summary["changed"]:
        original = originals[relative]
        manifest["files"][relative] = {"existed": original is not None,
            "originalSha256": hashlib.sha256(original).hexdigest() if original is not None else None,
            "deployedSha256": hashlib.sha256(payload[relative]).hexdigest()}
        if original is not None:
            atomic_write(backup / relative, original, 0o600)
    atomic_write(backup / "manifest.json", json.dumps(manifest, indent=2).encode(), 0o600)
    for relative in summary["changed"]:
        destination = checked_file(target, relative)
        current = destination.read_bytes() if destination.exists() else None
        if current != originals[relative]:
            raise ValueError("Live code changed during deployment; stop and review the backup")
        atomic_write(destination, payload[relative])
    return summary


def restore(backup: Path) -> None:
    if backup.is_symlink() or backup.stat().st_uid != os.getuid():
        raise ValueError("Backup must be owned by the current user")
    manifest = json.loads((backup / "manifest.json").read_text())
    target = Path(manifest["target"])
    if target.is_symlink() or target.stat().st_uid != os.getuid():
        raise ValueError("Unsafe restore target")
    staged = []
    for relative, metadata in manifest["files"].items():
        destination = checked_file(target, relative)
        current_hash = hashlib.sha256(destination.read_bytes()).hexdigest() if destination.exists() else None
        if current_hash == metadata["originalSha256"]:
            continue  # Unchanged file from an interrupted/partial deployment.
        if current_hash != metadata["deployedSha256"]:
            raise ValueError("Live code changed after deployment; automatic restore refused")
        if metadata["existed"]:
            staged.append((destination, checked_file(backup, relative).read_bytes()))
    # Newly added files can stay unused; never remove files belonging to later work.
    for destination, content in staged:
        atomic_write(destination, content)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Copy the explicit manifest; default is preview only")
    parser.add_argument("--restore", type=Path, help="Restore backed-up existing files if live hashes still match")
    args = parser.parse_args()
    if args.restore:
        restore(args.restore)
    else:
        config = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
        backup = config / "illogical-impulse-backups" / ("ai-quotas-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
        print(json.dumps(deploy(SOURCE, config / "quickshell/ii", backup, execute=args.apply), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
