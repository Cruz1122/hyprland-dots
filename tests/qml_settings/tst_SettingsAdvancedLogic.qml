import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/settings/pages/AdvancedLogic.js" as AL

// `hyprctl -j configerrors` parsing for the Advanced page's errors row, with
// the harness fixtures (tests/fixtures/hyprctl-configerrors-*.json) and
// variants. Needs QML_XHR_ALLOW_FILE_READ (tests/test_settings_qml.py).
TestCase {
    name: "SettingsAdvancedLogic"

    function fixture(name) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(`../fixtures/hyprctl-configerrors-${name}.json`), false);
        xhr.send();
        return xhr.responseText;
    }

    function test_fixtures() {
        compare(AL.parseConfigErrors(fixture("none")), { ok: true, errors: [], hidden: 0 });
        const two = AL.parseConfigErrors(fixture("two"));
        compare(two.ok, true);
        compare(two.errors.length, 2);
        verify(two.errors[0].indexOf("general.lua") >= 0, two.errors[0]);
        compare(AL.parseConfigErrors(fixture("malformed")).ok, false);
    }

    function test_variants() {
        compare(AL.parseConfigErrors('[""]'), { ok: true, errors: [], hidden: 0 }, "Hyprland's answer without errors");
        compare(AL.parseConfigErrors("[]").errors, []);
        compare(AL.parseConfigErrors('["", "  ", "\\t"]').errors, [], "blank lines are not errors");
        compare(AL.parseConfigErrors('["a error  ", "", "b"]').errors, ["a error", "b"]);
        compare(AL.parseConfigErrors("").ok, false);
        compare(AL.parseConfigErrors(undefined).ok, false);
        compare(AL.parseConfigErrors("ok").ok, false);
        compare(AL.parseConfigErrors('{"errors": []}').ok, false);
        compare(AL.parseConfigErrors('["a", 3]').ok, false);
        compare(AL.parseConfigErrors('["trunc').ok, false);
        const many = [];
        for (let i = 0; i < AL.MAX_ERRORS + 5; i++)
            many.push(`error ${i}`);
        const capped = AL.parseConfigErrors(JSON.stringify(many));
        compare(capped.errors.length, AL.MAX_ERRORS);
        compare(capped.hidden, 5);
    }
}
