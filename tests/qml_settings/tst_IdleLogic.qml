import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/settings/backends/IdleLogic.js" as IdleLogic

TestCase {
    name: "IdleLogic"

    readonly property var options: [0, 60, 300, 600, 900].map(v => ({ value: v, label: String(v) }))

    function values(lock, dpms, suspend) {
        return { "idle.lockTimeout": lock, "idle.dpmsTimeout": dpms, "idle.suspendTimeout": suspend };
    }

    function test_order_data() {
        return [
            { tag: "never", v: values(0, 0, 0), problem: "" },
            { tag: "ordered", v: values(300, 600, 900), problem: "" },
            { tag: "equal", v: values(300, 300, 300), problem: "" },
            { tag: "gap", v: values(600, 0, 900), problem: "" },
            { tag: "lock-after-dpms", v: values(600, 300, 0), problem: "The screen must lock before it turns off" },
            { tag: "dpms-after-suspend", v: values(0, 900, 600), problem: "The screen must turn off before the system suspends" },
            { tag: "lock-after-suspend", v: values(900, 0, 600), problem: "The screen must lock before the system suspends" },
            { tag: "too-short", v: values(10, 0, 0), problem: "Use a time between 30 seconds and 24 hours" },
            { tag: "fraction", v: values(60.5, 0, 0), problem: "Use a time between 30 seconds and 24 hours" }
        ];
    }

    function test_order(data) {
        compare(IdleLogic.orderProblem(data.v), data.problem);
    }

    function test_allowedChoices() {
        const current = values(300, 600, 0);
        compare(IdleLogic.allowedChoices(options, current, "idle.lockTimeout").map(o => o.value), [0, 60, 300, 600]);
        compare(IdleLogic.allowedChoices(options, current, "idle.dpmsTimeout").map(o => o.value), [0, 300, 600, 900]);
        compare(IdleLogic.allowedChoices(options, current, "idle.suspendTimeout").map(o => o.value), [0, 600, 900]);
        verify(IdleLogic.allowedChoices(options, current, "idle.lockTimeout").every(o => o.translate === true));
    }

    function test_generatorArgs() {
        compare(IdleLogic.generatorArgs("/s/idlegen.py", "/h/out.conf", values(300, 0, 900), "write", false),
            ["python3", "/s/idlegen.py", "--lock", "300", "--dpms", "0", "--suspend", "900", "--output", "/h/out.conf"]);
        compare(IdleLogic.generatorArgs("/s/idlegen.py", "/h/out.conf", values(0, 0, 0), "print", false).slice(-1), ["--print"]);
        compare(IdleLogic.generatorArgs("/s/idlegen.py", "/h/out.conf", values(0, 0, 0), "write", true).slice(-1), ["--force"]);
    }

    function test_applyArgs() {
        compare(IdleLogic.outputPath("/home/u"), "/home/u/.config/hypr/custom/shell-idle.conf");
        compare(IdleLogic.applyArgs("/s/idlegen.py", "/home/u", values(60, 0, 0), true),
            ["python3", "/s/idlegen.py", "--lock", "60", "--dpms", "0", "--suspend", "0",
             "--output", "/home/u/.config/hypr/custom/shell-idle.conf", "--force", "--restart"]);
    }

    function test_syncState() {
        const managed = IdleLogic.IDLE_MARKER + "\nbody\n";
        compare(IdleLogic.syncState(managed, managed, true, false), "synced");
        compare(IdleLogic.syncState(managed, IdleLogic.IDLE_MARKER + "\nother\n", true, false), "outOfSync");
        compare(IdleLogic.syncState(managed, "listener {}\n", true, false), "unmanaged");
        compare(IdleLogic.syncState(managed, "", false, true), "synced");
        compare(IdleLogic.syncState(managed, "", false, false), "outOfSync");
        verify(IdleLogic.allNever(values(0, 0, 0)));
        verify(!IdleLogic.allNever(values(0, 60, 0)));
    }
}
