#!/usr/bin/env python3
"""Capture live dots or install reviewed sources without deleting extra files."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
CAPTURE_PATHS = (
    'hypr', 'quickshell/ii', 'illogical-impulse', 'matugen', 'kitty', 'foot',
    'fuzzel', 'fontconfig', 'Kvantum', 'mpv', 'wlogout', 'xdg-desktop-portal',
    'systemd/user/hyprland-session.target',
)
EXCLUDED = ('__pycache__', '*.pyc', '*.bak*', '*.backup*', '*.old', '*~',
            'installed_listfile', 'installed_true', 'mpvpaper_thumbnails',
            '.venv', '.git', 'states.json', 'notes.json', 'todo.json')


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def inventory(root: Path) -> dict[str, dict[str, str]]:
    result = {}
    for path in sorted(root.rglob('*')):
        relative = str(path.relative_to(root))
        if path.is_symlink():
            result[relative] = {'link': str(path.readlink())}
        elif path.is_file():
            result[relative] = {'sha256': digest(path)}
    return result


def snapshot(source: Path, parent: Path, reason: str, names: set[str] | None = None) -> Path:
    parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup = Path(tempfile.mkdtemp(prefix=reason + '-', dir=parent))
    backup.chmod(0o700)
    if names is None:
        shutil.copytree(source, backup / 'config', symlinks=True)
    else:
        (backup / 'config').mkdir()
        for name in sorted(names):
            src, dst = source / name, backup / 'config' / name
            if src.is_symlink():
                dst.symlink_to(src.readlink())
            elif src.is_dir():
                shutil.copytree(src, dst, symlinks=True)
            elif src.is_file():
                shutil.copy2(src, dst)
    manifest = inventory(backup / 'config')
    (backup / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    verify_snapshot(backup)
    print(f'Verified private backup: {backup}', flush=True)
    return backup


def verify_snapshot(backup: Path) -> None:
    expected = json.loads((backup / 'manifest.json').read_text())
    if inventory(backup / 'config') != expected:
        raise ValueError(f'Backup verification failed: {backup}')


def files(root: Path):
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if any(fnmatch.fnmatch(part, pattern) for part in relative.parts for pattern in EXCLUDED):
            continue
        if path.is_symlink():
            target = path.readlink()
            if target.is_absolute() or not path.resolve().is_relative_to(root.resolve()):
                raise ValueError(f'External source symlink: {path}')
            yield relative
        elif path.is_file():
            yield relative


def reject_target_links(root: Path, relative: Path, allow_leaf: bool = False) -> None:
    candidates = (root, *(root / relative).parents)
    if not allow_leaf:
        candidates += (root / relative,)
    for candidate in candidates:
        if candidate.is_symlink():
            raise ValueError(f'Refusing destination symlink: {candidate}')


def render(data: bytes, home: Path, config: Path) -> bytes:
    try:
        data.decode('utf-8')
    except UnicodeDecodeError:
        return data
    return data.replace(b'@HOME@', str(home).encode()).replace(b'@CONFIG@', str(config).encode())


def portable(data: bytes, home: Path, config: Path) -> bytes:
    try:
        data.decode('utf-8')
    except UnicodeDecodeError:
        return data
    return data.replace(str(config).encode(), b'@CONFIG@').replace(str(home).encode(), b'@HOME@')


@contextmanager
def locked(state: Path):
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock = state / 'operation.lock'
    lock.mkdir(mode=0o700)
    try:
        yield
    finally:
        lock.rmdir()


def copy_file(source: Path, target: Path, data: bytes | None) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        if target.exists() or target.is_symlink():
            target.unlink()
        target.symlink_to(source.readlink())
        return
    fd, temporary = tempfile.mkstemp(prefix='.dots-', dir=target.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data if data is not None else source.read_bytes())
        shutil.copymode(source, temporary)
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)


def user_owned(relative: Path) -> bool:
    text = relative.as_posix()
    return (text.startswith('hypr/custom/') or text in (
        'illogical-impulse/config.json', 'hypr/monitors.lua', 'hypr/workspaces.lua',
        'hypr/hyprland.conf'))


def transfer(source: Path, target: Path, home: Path, config: Path,
             capture: bool, dry_run: bool, replace_user: bool) -> list[str]:
    changes = []
    if source.is_symlink():
        raise ValueError(f'Refusing source root symlink: {source}')
    paths = list(files(source))
    for relative in paths:
        src, dst = source / relative, target / relative
        reject_target_links(target, relative, allow_leaf=src.is_symlink())
        if dst.exists() and dst.is_dir():
            raise ValueError(f'File/directory conflict: {dst}')
        if not capture and dst.exists() and user_owned(relative) and not replace_user:
            continue
        data = None if src.is_symlink() else src.read_bytes()
        if data is not None:
            data = portable(data, home, config) if capture else render(data, home, config)
        if src.is_symlink():
            # Destination symlinks are rejected rather than followed.
            same = dst.is_symlink() and dst.readlink() == src.readlink()
        else:
            same = dst.is_file() and dst.read_bytes() == data and (dst.stat().st_mode & 0o777) == (src.stat().st_mode & 0o777)
        if same:
            continue
        changes.append(relative.as_posix())
    # Preflight the whole tree before the first write.
    for relative in changes:
        src, dst = source / relative, target / relative
        print(f'{"CAPTURE" if capture else "INSTALL"} {relative}')
        if not dry_run:
            data = None if src.is_symlink() else src.read_bytes()
            if data is not None:
                data = portable(data, home, config) if capture else render(data, home, config)
            copy_file(src, dst, data)
    return changes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('capture', 'install', 'backup', 'verify-backup'))
    parser.add_argument('--repo', type=Path, default=REPO)
    parser.add_argument('--config-home', type=Path,
                        default=Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))))
    parser.add_argument('--state-home', type=Path,
                        default=Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))))
    parser.add_argument('--backup', type=Path)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--yes', action='store_true')
    parser.add_argument('--replace-user', action='store_true', help='Also replace existing custom files and settings')
    args = parser.parse_args()
    home = Path.home()
    config = args.config_home.absolute()
    state = args.state_home.absolute() / 'hyprland-dots'
    repo = args.repo.absolute()
    if args.action == 'verify-backup':
        if args.backup is None:
            parser.error('--backup is required')
        verify_snapshot(args.backup)
        print('Backup verified.')
        return 0
    if not args.dry_run and not args.yes:
        parser.error('Explicit --yes is required for writes; use --dry-run first')
    if args.action == 'backup':
        if not args.dry_run:
            config.mkdir(parents=True, exist_ok=True)
            snapshot(config, state / 'backups', 'pre-install',
                     {p.name for p in (repo / 'config').iterdir()})
        return 0
    if args.action == 'install':
        source, target = repo / 'config', config
        for marker in ('hypr/hyprland.lua', 'quickshell/ii/shell.qml', 'illogical-impulse/config.json'):
            if not (source / marker).is_file():
                raise ValueError(f'Missing source marker: {marker}')
        # Validate before making even a backup, and before changing any file.
        transfer(source, target, home, config, False, True, args.replace_user)
        if not args.dry_run:
            with locked(state):
                if target.exists():
                    snapshot(target, state / 'backups', 'pre-install',
                             {p.name for p in source.iterdir()})
                transfer(source, target, home, config, False, False, args.replace_user)
    else:
        # Only the explicit desktop allowlist is captured, never all ~/.config.
        if args.dry_run:
            for relative in CAPTURE_PATHS:
                path = config / relative
                if path.is_dir():
                    transfer(path, repo / 'config' / relative, home, config, True, True, True)
                elif path.is_symlink():
                    raise ValueError(f'Refusing capture root symlink: {path}')
                elif path.is_file():
                    reject_target_links(repo / 'config', Path(relative))
                    print(f'CAPTURE {relative}')
            return 0
        with locked(state):
            snapshot(repo / 'config', state / 'backups', 'pre-capture')
            for relative in CAPTURE_PATHS:
                path = config / relative
                target = repo / 'config' / relative
                if path.is_symlink():
                    raise ValueError(f'Refusing capture root symlink: {path}')
                if path.is_dir():
                    transfer(path, target, home, config, True, False, True)
                elif path.is_file():
                    reject_target_links(repo / 'config', Path(relative))
                    copy_file(path, target, portable(path.read_bytes(), home, config))
    print('Complete. No files deleted; no session restarted; no automatic rollback.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f'Stopped: {error}. No automatic rollback. Check printed backup paths.', file=sys.stderr)
        sys.exit(1)
