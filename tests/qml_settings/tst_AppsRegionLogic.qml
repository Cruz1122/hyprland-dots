import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/settings/pages/AppsLogic.js" as AppsLogic
import "../../config/quickshell/ii/modules/settings/pages/RegionLogic.js" as RegionLogic

TestCase {
    name: "AppsRegionLogic"

    function test_parse_variables() {
        const text = [
            "-- comment",
            "hl.env(\"qsConfig\", \"ii\")",
            "terminal = \"~/x/launch_first_available.sh 'foot' 'kitty -1'\"",
            "browser = 'firefox' -- trailing comment",
            "fileManager = \"dolphin \\\"quoted\\\"\"",
            "workspaceGroupSize = 10",
            "unknownVar = \"ignored\"",
            "codeEditor = os.getenv('EDITOR')"
        ].join("\n");
        compare(AppsLogic.parseVariables(text), {
            terminal: "~/x/launch_first_available.sh 'foot' 'kitty -1'",
            browser: "firefox",
            fileManager: "dolphin \"quoted\""
        });
        compare(AppsLogic.parseVariables(""), {});
    }

    function test_info_values_merge_custom_over_base() {
        const merged = AppsLogic.merge({ terminal: "a", browser: "b" }, { browser: "c" });
        compare(merged, { terminal: "a", browser: "c" });
        compare(AppsLogic.infoValues(merged, "info.apps."), { "info.apps.terminal": "a", "info.apps.browser": "c" });
        compare(AppsLogic.summarize("~/s/launch_first_available.sh 'foot' 'kitty -1' \"wezterm\""), "foot, kitty -1, wezterm");
        compare(AppsLogic.summarize("XDG_CURRENT_DESKTOP=gnome ~/s/launch_first_available.sh 'qs -p x'"), "qs -p x");
        compare(AppsLogic.summarize("kitty"), "kitty");
    }

    function test_time_preview_matches_the_shell_clock() {
        const date = new Date(2026, 0, 2, 0, 5, 9);
        const fmt = (d, f) => "Q:" + f;
        compare(RegionLogic.formatTime(date, "h:mm", false, fmt), "12:05");
        compare(RegionLogic.formatTime(date, "h:mm", true, fmt), "12:05:09");
        compare(RegionLogic.formatTime(new Date(2026, 0, 2, 13, 0, 0), "h:mm", false, fmt), "1:00");
        compare(RegionLogic.formatTime(date, "hh:mm", true, fmt), "Q:hh:mm:ss");
        compare(RegionLogic.formatTime(date, "h:mm ap", true, fmt), "Q:h:mm:ss ap");
        compare(RegionLogic.formatTime(date, "hh:mm", false, fmt), "Q:hh:mm");
        compare(RegionLogic.hyprlockMode("hh:mm"), "24h");
        compare(RegionLogic.hyprlockMode("h:mm ap"), "12h");
        compare(RegionLogic.hyprlockMode("h:mm"), "12h");
    }

    function test_language_choices_keep_the_stored_value() {
        const choices = RegionLogic.languageChoices(["es_MX", "en_US", "bad value", "es_MX"], "es_CO", "Auto");
        compare(choices[0], { value: "auto", label: "Auto" });
        compare(choices.map(c => c.value).sort(), ["auto", "en_US", "es_CO", "es_MX"]);
        compare(choices.find(c => c.value === "es_CO").label, "Español (Colombia)");
        compare(RegionLogic.languageChoices([], "auto", "Auto").length, 1);
        compare(RegionLogic.languageName("xx_YY"), "xx_YY");
        verify(RegionLogic.isLanguageValue("auto"));
        verify(RegionLogic.isLanguageValue("es_CO"));
        verify(!RegionLogic.isLanguageValue("../etc"));
    }
}
