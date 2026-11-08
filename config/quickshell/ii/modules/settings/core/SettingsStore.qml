pragma Singleton

import QtQuick
import Quickshell
import qs.modules.settings.backends

// Single entry point for reading and changing settings (docs/settings.md).
// The logic lives in SettingsStoreImpl; this singleton wires the real
// registry and one instance of every backend.
Singleton {
    id: root

    readonly property var pendingConfirmation: impl.pendingConfirmation
    readonly property int revision: impl.revision

    signal committed(string key)
    signal failed(string key, string message)

    function entry(key) { return impl.entry(key); }
    function value(key) { return impl.value(key); }
    function defaultValue(key) { return impl.defaultValue(key); }
    function isModified(key) { return impl.isModified(key); }
    function isAvailable(key) { return impl.isAvailable(key); }
    function unavailableReason(key) { return impl.unavailableReason(key); }
    function hasCapability(name) { return impl.hasCapability(name); }
    function isEnabled(key) { return impl.isEnabled(key); }
    function isVisible(key) { return impl.isVisible(key); }
    function blockingCondition(key) { return impl.blockingCondition(key); }
    // Backend-provided choices (devices, applications); falls back to the entry options.
    function choices(key) {
        const e = impl.entry(key);
        const b = impl.backendFor(e);
        void impl.revision;
        return (b && typeof b.choices === "function" ? b.choices(e) : null) ?? e?.options ?? [];
    }
    function write(key, value) { return impl.write(key, value); }
    function reset(key) { return impl.reset(key); }
    function resetPage(pageId) { return impl.resetPage(pageId); }
    function modifiedCount(pageId) { void impl.revision; return impl.modifiedCount(pageId); }
    function confirm() { impl.confirm(); }
    function revert() { impl.revert(); }
    // Before quitting: revert, flush and wait for the backends (SettingsStoreImpl.finish).
    function finish(done) { impl.finish(done); }
    function cancelFinish() { impl.cancelFinish(); }

    ConfigBackend { id: configBackend }
    HyprlandBackend { id: hyprlandBackend }
    AnimationBackend { id: animationBackend }
    IdleBackend { id: idleBackend }
    DisplayBackend { id: displayBackend }
    MimeBackend { id: mimeBackend }
    AudioBackend { id: audioBackend }
    PowerBackend { id: powerBackend }
    IpcBackend { id: ipcBackend }
    SystemBackend { id: systemBackend }

    SettingsStoreImpl {
        id: impl
        registry: SettingsRegistry
        backends: ({
            config: configBackend,
            hyprland: hyprlandBackend,
            animation: animationBackend,
            idle: idleBackend,
            display: displayBackend,
            mime: mimeBackend,
            audio: audioBackend,
            power: powerBackend,
            ipc: ipcBackend,
            system: systemBackend
        })
        onCommitted: key => root.committed(key)
        onFailed: (key, message) => root.failed(key, message)
    }
}
