#!/usr/bin/env python3
"""Backport upstream 5d5d498 to the pinned 7511545 source (GPL-3.0)."""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])


def replace(relative: str, old: str, new: str) -> None:
    path = root / relative
    text = path.read_text()
    if text.count(old) != 1:
        raise RuntimeError(f'Unexpected pinned source: {relative}: {old!r}')
    path.write_text(text.replace(old, new))


def move_methods(directory: str, filename: str, owner: str, names: list[str]) -> None:
    header = root / directory / (filename + '.hpp')
    text = header.read_text()
    definitions = []
    for name in names:
        pattern = rf'(QBindable<[^\n]+?>) {name}\(\)( const)? \{{\s*(return &this->\w+;)\s*\}};?'
        matches = list(re.finditer(pattern, text))
        if len(matches) != 1:
            raise RuntimeError(f'Unexpected method: {header}: {name}')
        match = matches[0]
        const = match[2] or ''
        definitions.append(f'{match[1]} {owner}::{name}(){const} {{ {match[3]} }}')
        text = text[:match.start()] + f'{match[1]} {name}(){const};' + text[match.end():]
    header.write_text(text)
    cpp = root / directory / (filename + '.cpp')
    text = cpp.read_text()
    namespace = 'namespace qs::hyprland::ipc {' if 'hyprland' in directory else 'namespace qs::i3::ipc {'
    if text.count(namespace) != 1:
        raise RuntimeError(f'Unexpected namespace: {cpp}')
    cpp.write_text(text.replace(namespace, namespace + '\n\n' + '\n\n'.join(definitions)))


hypr = 'src/wayland/hyprland/ipc'
i3 = 'src/x11/i3/ipc'
replace(f'{hypr}/connection.hpp',
        'Q_DECLARE_OPAQUE_POINTER(qs::hyprland::ipc::HyprlandWorkspace*);\n'
        'Q_DECLARE_OPAQUE_POINTER(qs::hyprland::ipc::HyprlandMonitor*);\n'
        'Q_DECLARE_OPAQUE_POINTER(qs::hyprland::ipc::HyprlandToplevel*);',
        'Q_MOC_INCLUDE("hyprland_toplevel.hpp")\nQ_MOC_INCLUDE("monitor.hpp")\nQ_MOC_INCLUDE("workspace.hpp")')
replace(f'{i3}/controller.hpp',
        'Q_DECLARE_OPAQUE_POINTER(qs::i3::ipc::I3Workspace*);\nQ_DECLARE_OPAQUE_POINTER(qs::i3::ipc::I3Monitor*);',
        'Q_MOC_INCLUDE("monitor.hpp")\nQ_MOC_INCLUDE("workspace.hpp")')
replace('src/services/pipewire/peak.hpp', '#include "node.hpp"', '#include "node.hpp"\n#include "qml.hpp"')
replace('src/services/pipewire/peak.hpp', 'class PwNodeIface;\n', '')
replace('src/services/pipewire/peak.hpp',
        '} // namespace qs::service::pipewire\n\nQ_DECLARE_OPAQUE_POINTER(qs::service::pipewire::PwNodeIface*);\n\nnamespace qs::service::pipewire {\n', '')
replace(f'{hypr}/hyprland_toplevel.cpp', '#include "connection.hpp"', '#include "connection.hpp"\n#include "monitor.hpp"')
move_methods(hypr, 'connection', 'HyprlandIpc', ['bindableFocusedMonitor', 'bindableFocusedWorkspace', 'bindableActiveToplevel'])
move_methods(hypr, 'monitor', 'HyprlandMonitor', ['bindableActiveWorkspace'])
move_methods(hypr, 'workspace', 'HyprlandWorkspace', ['bindableMonitor'])
move_methods(hypr, 'hyprland_toplevel', 'HyprlandToplevel', ['bindableWorkspace', 'bindableMonitor'])
move_methods(i3, 'controller', 'I3IpcController', ['bindableFocusedMonitor', 'bindableFocusedWorkspace'])
move_methods(i3, 'monitor', 'I3Monitor', ['bindableActiveWorkspace'])
move_methods(i3, 'workspace', 'I3Workspace', ['bindableMonitor'])
