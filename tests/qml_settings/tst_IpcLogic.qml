import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/settings/backends/IpcLogic.js" as IpcLogic

TestCase {
    name: "IpcLogic"

    readonly property string dir: "/home/u/.config/quickshell/ii"
    readonly property string showText: "target notifications\n  function isSilent(): bool\n  function setSilent(enabled: bool): void\n"
        + "  function toggleSilent(): void\ntarget region\n  function record(): void\n  function recordWithSound(): void\n"
        + "target aiQuotaPanel\n  function close(): void\n  function connectProvider(provider: string): void\n"

    function test_parse_show() {
        const targets = IpcLogic.parseShow(showText);
        compare(Object.keys(targets), ["notifications", "region", "aiQuotaPanel"]);
        compare(targets.notifications, ["isSilent", "setSilent", "toggleSilent"]);
        verify(IpcLogic.hasFunction(targets, "region", "record"));
        verify(!IpcLogic.hasFunction(targets, "region", "stop"));
        verify(!IpcLogic.hasFunction(targets, "missing", "record"));
        compare(Object.keys(IpcLogic.parseShow("")), []);
        compare(Object.keys(IpcLogic.parseShow("No running instances for \"x\"\n")), []);
    }

    function test_capabilities_follow_exposed_functions() {
        const caps = IpcLogic.capabilitiesFor(IpcLogic.parseShow(showText));
        compare(caps, ["mainShell", "ipc:regionRecord", "ipc:aiQuotaConnect"]);
        compare(IpcLogic.capabilitiesFor({}), ["mainShell"]);
    }

    function test_read_and_write_argv() {
        compare(IpcLogic.readArgv(dir, "ipc.notifications.silent"),
            ["qs", "-p", dir, "ipc", "call", "notifications", "isSilent"]);
        compare(IpcLogic.writeArgv(dir, "ipc.notifications.silent", true),
            ["qs", "-p", dir, "ipc", "call", "notifications", "setSilent", "true"]);
        compare(IpcLogic.writeArgv(dir, "ipc.notifications.silent", false)[7], "false");
        compare(IpcLogic.writeArgv(dir, "ipc.notifications.silent", "true"), null, "type is enforced");
        compare(IpcLogic.writeArgv(dir, "ipc.unknown", true), null);
        compare(IpcLogic.showArgv(dir), ["qs", "-p", dir, "ipc", "show"]);
    }

    function test_named_calls_validate_arguments() {
        compare(IpcLogic.namedCallArgv(dir, "regionRecord", []),
            ["qs", "-p", dir, "ipc", "call", "region", "record"]);
        compare(IpcLogic.namedCallArgv(dir, "aiQuotaConnect", ["codex"]),
            ["qs", "-p", dir, "ipc", "call", "aiQuotaPanel", "connectProvider", "codex"]);
        compare(IpcLogic.namedCallArgv(dir, "aiQuotaConnect", ["--help"]), null);
        compare(IpcLogic.namedCallArgv(dir, "aiQuotaConnect", ["unknown"]), null);
        compare(IpcLogic.namedCallArgv(dir, "aiQuotaConnect", []), null);
        compare(IpcLogic.namedCallArgv(dir, "regionRecord", ["x"]), null);
        compare(IpcLogic.namedCallArgv(dir, "nope", []), null);
    }

    function test_call_argv_rejects_unsafe_items() {
        compare(IpcLogic.callArgv(dir, "a;b", "f", []), null);
        compare(IpcLogic.callArgv(dir, "t", "f()", []), null);
        compare(IpcLogic.callArgv(dir, "t", "f", ["-x"]), null);
        compare(IpcLogic.callArgv(dir, "t", "f", ["a\nb"]), null);
        compare(IpcLogic.callArgv(dir, "t", "f", [""]), null);
        compare(IpcLogic.callArgv(dir, "t", "f", [NaN]), null);
        compare(IpcLogic.callArgv(dir, "t", "f", ["$(id) 'x'", 3, true]),
            ["qs", "-p", dir, "ipc", "call", "t", "f", "$(id) 'x'", "3", "true"]);
    }

    function test_decode_value() {
        compare(IpcLogic.decodeValue("bool", "true\n"), { ok: true, value: true });
        compare(IpcLogic.decodeValue("bool", "false"), { ok: true, value: false });
        verify(!IpcLogic.decodeValue("bool", "").ok);
        verify(!IpcLogic.decodeValue("bool", "yes").ok);
        compare(IpcLogic.decodeValue("int", " 4.6 ").value, 5);
        verify(!IpcLogic.decodeValue("int", "x").ok);
    }
}
