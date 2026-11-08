.pragma library

// Pure helpers of AdvancedPage.qml (tests/qml_settings/tst_SettingsAdvancedLogic.qml).

// At most this many error lines are shown; the rest are counted.
var MAX_ERRORS = 100;

// `hyprctl -j configerrors` -> { ok, errors, hidden }.
// Hyprland prints a JSON list with one string per error line and `[""]` when
// there are none, so empty and blank strings are dropped. Anything that is not
// a list of strings (truncated output, an error message) is not ok.
function parseConfigErrors(text) {
    var data;
    try {
        data = JSON.parse(String(text === undefined || text === null ? "" : text));
    } catch (error) {
        return { ok: false, errors: [], hidden: 0 };
    }
    if (!Array.isArray(data))
        return { ok: false, errors: [], hidden: 0 };
    var errors = [];
    for (var i = 0; i < data.length; i++) {
        if (typeof data[i] !== "string")
            return { ok: false, errors: [], hidden: 0 };
        var line = data[i].replace(/\s+$/, "");
        if (line.trim().length > 0)
            errors.push(line);
    }
    return { ok: true, errors: errors.slice(0, MAX_ERRORS), hidden: Math.max(0, errors.length - MAX_ERRORS) };
}
