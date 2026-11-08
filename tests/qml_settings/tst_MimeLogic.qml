import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/settings/backends/MimeLogic.js" as MimeLogic

TestCase {
    name: "MimeLogic"

    readonly property var listOutput: JSON.stringify({
        desktops: ["Hyprland"],
        roles: {
            browser: { role: "browser", current: "firefox.desktop", currentName: "Firefox", mixed: false,
                candidates: [{ id: "chromium.desktop", name: "Chromium", icon: "chromium", handlesAll: false },
                             { id: "firefox.desktop", name: "Firefox", icon: "firefox", handlesAll: true }] },
            text: { role: "text", current: "code.desktop", currentName: "Visual Studio Code", mixed: false,
                candidates: [{ id: "kate.desktop", name: "Kate", icon: "kate", handlesAll: true }] },
            mail: { role: "mail", current: null, currentName: null, mixed: false, candidates: [] }
        }
    })

    function test_role_of_entry() {
        compare(MimeLogic.roleOf({ key: "mime.browser" }), "browser");
        compare(MimeLogic.roleOf({ key: "mime.x", path: "mime.pdf" }), "pdf");
    }

    function test_parse_list_and_values() {
        const parsed = MimeLogic.parseList(listOutput);
        verify(parsed.ok);
        compare(MimeLogic.valuesFrom(parsed.roles), { "mime.browser": "firefox.desktop", "mime.text": "code.desktop", "mime.mail": "" });
        verify(!MimeLogic.parseList("not json").ok);
        verify(!MimeLogic.parseList("{}").ok);
        verify(!MimeLogic.parseList("null").ok);
    }

    function test_choices_keep_a_current_default_that_is_not_a_candidate() {
        const roles = MimeLogic.parseList(listOutput).roles;
        compare(MimeLogic.choices(roles.browser), [{ value: "chromium.desktop", label: "Chromium" }, { value: "firefox.desktop", label: "Firefox" }]);
        compare(MimeLogic.choices(roles.text), [{ value: "code.desktop", label: "Visual Studio Code" }, { value: "kate.desktop", label: "Kate" }]);
        compare(MimeLogic.choices(roles.mail), []);
        compare(MimeLogic.choices(undefined), []);
        const unnamed = { current: "x.desktop", currentName: null, candidates: [] };
        compare(MimeLogic.choices(unnamed), [{ value: "x.desktop", label: "x.desktop" }]);
    }

    function test_parse_set_refreshes_one_role() {
        const roles = MimeLogic.parseList(listOutput).roles;
        const out = JSON.stringify({ written: ["/tmp/mimeapps.list"], role: { role: "text", current: "kate.desktop", currentName: "Kate", candidates: [] } });
        const parsed = MimeLogic.parseSet(out);
        verify(parsed.ok);
        compare(parsed.role, "text");
        const next = MimeLogic.withRole(roles, parsed.role, parsed.state);
        compare(MimeLogic.valuesFrom(next)["mime.text"], "kate.desktop");
        compare(MimeLogic.valuesFrom(roles)["mime.text"], "code.desktop", "the previous state is not mutated");
        verify(!MimeLogic.parseSet("{}").ok);
        verify(!MimeLogic.parseSet("").ok);
    }

    function test_error_message() {
        compare(MimeLogic.errorMessage("default-apps: warning: x\ndefault-apps: error: 'a.desktop' is not a candidate\n", "fallback"), "'a.desktop' is not a candidate");
        compare(MimeLogic.errorMessage("Traceback\nOSError: boom\n", "fallback"), "OSError: boom");
        compare(MimeLogic.errorMessage("", "fallback"), "fallback");
    }
}
