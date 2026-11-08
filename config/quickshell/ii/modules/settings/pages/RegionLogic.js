.pragma library
.import "../../common/functions/TimeFormat.js" as TimeFormat

// The shell clock's own rule (services/DateTime.qml uses the same
// function), so the preview always matches what the bar shows.
function formatTime(date, format, seconds, formatter) {
    return TimeFormat.formatTime(date, format, seconds, false, formatter);
}

// hyprlock has $TIME (24-hour) and $TIME12; only "hh:mm" is 24-hour among
// the offered formats.
function hyprlockMode(format) {
    return format === "hh:mm" ? "24h" : "12h";
}

// Native names, so each language is recognizable whatever the UI language.
var LANGUAGE_NAMES = {
    "de_DE": "Deutsch", "en_US": "English (US)", "es_CO": "Español (Colombia)", "es_MX": "Español (México)",
    "fr_FR": "Français", "he_HE": "עברית", "id_ID": "Bahasa Indonesia", "it_IT": "Italiano", "ja_JP": "日本語",
    "pt_BR": "Português (Brasil)", "ru_RU": "Русский", "tr_TR": "Türkçe", "uk_UA": "Українська",
    "vi_VN": "Tiếng Việt", "zh_CN": "简体中文"
};

var LANGUAGE_CODE = /^[a-z]{2,3}(_[A-Z]{2})?$/;

function languageName(code) {
    return LANGUAGE_NAMES[code] || code;
}

// "auto" first, then the available translations sorted by name. The stored
// value is kept even without its own file (es_CO falls back to es_MX).
function languageChoices(available, stored, autoLabel) {
    var codes = [];
    var list = available || [];
    for (var i = 0; i < list.length; i++) {
        if (LANGUAGE_CODE.test(list[i]) && codes.indexOf(list[i]) < 0)
            codes.push(list[i]);
    }
    if (stored && stored !== "auto" && codes.indexOf(stored) < 0)
        codes.push(stored);
    codes.sort(function (a, b) { return languageName(a).localeCompare(languageName(b)); });
    return [{ value: "auto", label: autoLabel }].concat(codes.map(function (code) {
        return { value: code, label: languageName(code) };
    }));
}

function isLanguageValue(value) {
    return value === "auto" || LANGUAGE_CODE.test(String(value));
}
