.pragma library

// Picks translation files for a locale. Pure so tests/qml_settings can cover it.

// Preferred file for a bare language when the exact locale has none.
var PREFERRED = { "es": "es_MX", "pt": "pt_BR", "zh": "zh_CN", "en": "en_US" };

// "es_CO.UTF-8", "es-CO" and "es_CO@euro" all become "es_CO".
function normalize(code) {
    var text = String(code || "").trim();
    text = text.split(".")[0].split("@")[0].replace("-", "_");
    var parts = text.split("_");
    if (parts.length >= 2 && parts[0].length > 0)
        return parts[0].toLowerCase() + "_" + parts[1].toUpperCase();
    return parts[0].toLowerCase();
}

// Ordered file basenames to try: the exact locale, the preferred file of its
// language, <lang>_<LANG>, then any other available file of the same
// language. An empty list means English source strings.
function candidates(code, available) {
    var exact = normalize(code);
    if (exact.length === 0 || exact === "c" || exact === "posix")
        return [];
    var lang = exact.split("_")[0];
    var list = [exact];
    if (PREFERRED[lang])
        list.push(PREFERRED[lang]);
    list.push(lang + "_" + lang.toUpperCase());
    var same = (available || []).map(String).filter(function (name) {
        return name.split("_")[0] === lang;
    }).sort();
    list = list.concat(same);
    return list.filter(function (name, index) {
        return list.indexOf(name) === index;
    });
}

// Parsed translation JSON that is not a plain object (null, arrays, numbers)
// counts as an empty dictionary.
function sanitize(data) {
    if (data === null || typeof data !== "object" || Array.isArray(data))
        return {};
    return data;
}
