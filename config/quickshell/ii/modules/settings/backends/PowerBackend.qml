import QtQuick
import Quickshell.Services.UPower
import "PowerLogic.js" as PowerLogic

// Power profile and battery capability through Quickshell.Services.UPower
// (docs/settings.md, `power` backend). The profile is applied by
// power-profiles-daemon at once; there is nothing to persist.
QtObject {
    id: root

    readonly property string name: "power"
    readonly property bool available: true
    readonly property string unavailableReason: ""
    readonly property var values: ({
        "power.profile": PowerLogic.profileName(PowerProfiles.profile, PowerProfile.PowerSaver, PowerProfile.Performance)
    })
    // `battery` gates the battery rows: only laptops report a laptop battery.
    readonly property var capabilities: UPower.displayDevice?.isLaptopBattery ? ["battery"] : []

    signal succeeded(string key)
    signal failed(string key, string message)

    function read(entry) { return root.values[entry.key]; }
    function defaultValue(entry) { return undefined; }
    function isModified(entry) { return false; }

    function choices(entry) {
        return PowerLogic.profileChoices(entry.options, PowerProfiles.hasPerformanceProfile);
    }

    function write(entry, value) {
        if (value === "performance" && !PowerProfiles.hasPerformanceProfile) {
            root.failed(entry.key, "Performance mode is not available on this device");
            return false;
        }
        const profile = value === "power-saver" ? PowerProfile.PowerSaver
            : value === "performance" ? PowerProfile.Performance
            : value === "balanced" ? PowerProfile.Balanced : null;
        if (profile === null) {
            root.failed(entry.key, "Unknown power profile");
            return false;
        }
        PowerProfiles.profile = profile;
        root.succeeded(entry.key);
        return true;
    }

    function reset(entry) { return true; }
    function snapshot(entries) { return entries.map(e => ({ entry: e, value: root.read(e) })); }
    function preview(entry, value) { return root.write(entry, value); }
    function persist(entries) { return true; }
    function restore(snap) {
        let ok = true;
        for (const item of snap)
            ok = root.write(item.entry, item.value) && ok;
        return ok;
    }
}
