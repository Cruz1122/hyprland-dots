.pragma library

// Pure settings logic shared by SettingsRegistry, SettingsStoreImpl and the
// backends. No Quickshell or QML object dependencies, so tests/qml_settings
// can exercise it with plain qmltestrunner.

var BACKENDS = ["config", "hyprland", "idle", "display", "mime", "audio", "power", "ipc", "action", "readonly"];
var TYPES = ["bool", "int", "real", "enum", "string", "path", "font", "color", "list", "time", "url", "action", "info", "custom"];
var WIDGETS = ["switch", "slider", "spin", "segmented", "select", "text", "textarea", "path", "font", "color", "list", "time", "device", "action", "info", "custom"];
// Backends that never persist anything: their rows render from the page.
var PASSIVE_BACKENDS = ["action", "readonly"];
var CONFIRM_SECONDS = 15;

function isArrayLike(value) {
    return value !== null && typeof value === "object" && typeof value.length === "number" && typeof value !== "string";
}

// QML list properties and JsonObjects are not plain JS values; copy them so
// comparisons, JSON and snapshots behave.
function toPlain(value) {
    if (value === null || value === undefined)
        return value;
    if (typeof value !== "object")
        return value;
    if (isArrayLike(value)) {
        var out = [];
        for (var i = 0; i < value.length; i++)
            out.push(toPlain(value[i]));
        return out;
    }
    var obj = {};
    for (var key in value) {
        var child = value[key];
        if (typeof child === "function" || key === "objectName" || key.indexOf("__") === 0)
            continue;
        obj[key] = toPlain(child);
    }
    return obj;
}

function deepEqual(a, b) {
    if (a === b)
        return true;
    if (typeof a === "number" && typeof b === "number")
        return a === b || (isNaN(a) && isNaN(b));
    if (a === null || b === null || a === undefined || b === undefined)
        return false;
    if (typeof a !== "object" || typeof b !== "object")
        return false;
    if (isArrayLike(a) !== isArrayLike(b))
        return false;
    if (isArrayLike(a)) {
        if (a.length !== b.length)
            return false;
        for (var i = 0; i < a.length; i++) {
            if (!deepEqual(a[i], b[i]))
                return false;
        }
        return true;
    }
    var pa = toPlain(a);
    var pb = toPlain(b);
    var ka = Object.keys(pa);
    var kb = Object.keys(pb);
    if (ka.length !== kb.length)
        return false;
    for (var j = 0; j < ka.length; j++) {
        if (!Object.prototype.hasOwnProperty.call(pb, ka[j]) || !deepEqual(pa[ka[j]], pb[ka[j]]))
            return false;
    }
    return true;
}

function splitPath(path) {
    return String(path).split(".").filter(function (part) { return part.length > 0; });
}

// Reads obj.a.b.c; undefined when any step is missing.
function getPath(obj, path) {
    var parts = splitPath(path);
    var cur = obj;
    for (var i = 0; i < parts.length; i++) {
        if (cur === null || cur === undefined)
            return undefined;
        cur = cur[parts[i]];
    }
    return cur;
}

// Assigns obj.a.b.c = value without creating intermediate objects: config
// paths must already exist in the schema. Returns false when a parent is
// missing or the property does not exist.
function setPath(obj, path, value) {
    var parts = splitPath(path);
    if (parts.length === 0)
        return false;
    var cur = obj;
    for (var i = 0; i < parts.length - 1; i++) {
        if (cur === null || cur === undefined)
            return false;
        cur = cur[parts[i]];
    }
    if (cur === null || cur === undefined || typeof cur !== "object" || !(parts[parts.length - 1] in cur))
        return false;
    cur[parts[parts.length - 1]] = value;
    return true;
}

function clamp(value, min, max) {
    if (typeof min === "number" && value < min)
        return min;
    if (typeof max === "number" && value > max)
        return max;
    return value;
}

function validateText(entry, text) {
    var rules = entry.validate || {};
    if (rules.nonEmpty && text.trim().length === 0)
        return "This field cannot be empty";
    if (typeof rules.maxLength === "number" && text.length > rules.maxLength)
        return "Too long";
    if (rules.regex && text.length > 0 && !(new RegExp(rules.regex)).test(text))
        return "Invalid format";
    return "";
}

var COLOR_RE = /^(#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?)?$/;
var TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

// Validates and converts a value to the entry type.
// Returns { ok: true, value } or { ok: false, error } (English message).
function coerce(entry, value) {
    var type = entry.type;
    if (type === "bool") {
        if (typeof value !== "boolean")
            return { ok: false, error: "Expected on or off" };
        return { ok: true, value: value };
    }
    if (type === "int" || type === "real") {
        if (typeof value === "string" && value.trim().length === 0)
            return { ok: false, error: "Expected a number" };
        if (typeof value !== "number" && typeof value !== "string")
            return { ok: false, error: "Expected a number" };
        var n = Number(value);
        if (!isFinite(n))
            return { ok: false, error: "Expected a number" };
        if (type === "int")
            n = Math.round(n);
        else if (typeof entry.decimals === "number")
            n = Number(n.toFixed(entry.decimals));
        return { ok: true, value: clamp(n, entry.min, entry.max) };
    }
    if (type === "enum") {
        var options = entry.options || [];
        for (var i = 0; i < options.length; i++) {
            if (deepEqual(options[i].value, value))
                return { ok: true, value: toPlain(options[i].value) };
        }
        return { ok: false, error: "Not one of the allowed values" };
    }
    if (type === "string" || type === "path" || type === "font" || type === "url" || type === "color" || type === "time") {
        if (typeof value !== "string" && typeof value !== "number")
            return { ok: false, error: "Expected text" };
        var text = String(value);
        if (type === "color" && !COLOR_RE.test(text))
            return { ok: false, error: "Use #RRGGBB" };
        if (type === "time" && !TIME_RE.test(text))
            return { ok: false, error: "Use HH:MM" };
        var problem = validateText(entry, text);
        if (problem)
            return { ok: false, error: problem };
        return { ok: true, value: text };
    }
    if (type === "list") {
        if (!isArrayLike(value))
            return { ok: false, error: "Expected a list" };
        var items = [];
        for (var j = 0; j < value.length; j++) {
            var item = value[j];
            if (typeof item !== "string" && typeof item !== "number")
                return { ok: false, error: "Expected a list of text" };
            item = String(item);
            var itemProblem = validateText(entry, item);
            if (itemProblem)
                return { ok: false, error: itemProblem };
            items.push(item);
        }
        return { ok: true, value: items };
    }
    if (type === "custom")
        return { ok: true, value: toPlain(value) };
    return { ok: false, error: "This setting cannot be changed here" };
}

// others: [{ key, value }] of the other members of entry.validate.unique.
function uniqueConflict(entry, value, others) {
    for (var i = 0; i < others.length; i++) {
        if (others[i].key !== entry.key && deepEqual(others[i].value, value))
            return others[i].key;
    }
    return "";
}

// Conditions: { key, equals | notEquals | in }, { capability },
// { all: [] }, { any: [] }, { not: {} }. A missing condition is true.
function evalCondition(cond, valueOf, hasCapability) {
    if (cond === undefined || cond === null)
        return true;
    if (cond.all !== undefined)
        return cond.all.every(function (c) { return evalCondition(c, valueOf, hasCapability); });
    if (cond.any !== undefined)
        return cond.any.some(function (c) { return evalCondition(c, valueOf, hasCapability); });
    if (cond.not !== undefined)
        return !evalCondition(cond.not, valueOf, hasCapability);
    if (cond.capability !== undefined)
        return !!hasCapability(cond.capability);
    if (cond.key !== undefined) {
        var v = valueOf(cond.key);
        if (cond.equals !== undefined)
            return deepEqual(v, cond.equals);
        if (cond.notEquals !== undefined)
            return !deepEqual(v, cond.notEquals);
        if (cond["in"] !== undefined)
            return cond["in"].some(function (x) { return deepEqual(v, x); });
        return !!v;
    }
    return false;
}

// First failing leaf of a condition, for "why is this disabled" texts.
function blockingCondition(cond, valueOf, hasCapability) {
    if (cond === undefined || cond === null || evalCondition(cond, valueOf, hasCapability))
        return null;
    if (cond.all !== undefined) {
        for (var i = 0; i < cond.all.length; i++) {
            var inner = blockingCondition(cond.all[i], valueOf, hasCapability);
            if (inner)
                return inner;
        }
    }
    if (cond.any !== undefined && cond.any.length > 0)
        return blockingCondition(cond.any[0], valueOf, hasCapability);
    return cond;
}

function conditionKeys(cond, acc) {
    acc = acc || [];
    if (!cond)
        return acc;
    if (cond.key !== undefined)
        acc.push(cond.key);
    (cond.all || []).forEach(function (c) { conditionKeys(c, acc); });
    (cond.any || []).forEach(function (c) { conditionKeys(c, acc); });
    if (cond.not)
        conditionKeys(cond.not, acc);
    return acc;
}

// ---------------------------------------------------------------- registry

function isRetired(path, retired) {
    var list = (retired && retired.retired) || [];
    for (var i = 0; i < list.length; i++) {
        if (path === list[i] || path.indexOf(list[i] + ".") === 0)
            return true;
    }
    return false;
}

function pageSource(id) {
    return "modules/settings/pages/" + id.charAt(0).toUpperCase() + id.slice(1) + "Page.qml";
}

// pagesDoc: parsed pages.json. pageDocs: { id: parsed <id>.json or null }.
// Returns the registry model; problems found are listed in `errors` and the
// offending page or entry is skipped, so one broken file cannot hide others.
function buildRegistry(pagesDoc, pageDocs, retired) {
    var model = {
        groups: [],
        pages: [],
        footerPages: [],
        pageById: {},
        entryByKey: {},
        ownerByKey: {},
        errors: [],
        retired: retired || { retired: [], managedElsewhere: [] }
    };
    function addPage(id, group) {
        var doc = pageDocs[id];
        var page = {
            id: id,
            group: group,
            title: id,
            icon: "settings",
            iconRotation: 0,
            description: "",
            source: pageSource(id),
            sections: [],
            entries: [],
            broken: false
        };
        if (!doc || typeof doc !== "object" || isArrayLike(doc)) {
            page.broken = true;
            model.errors.push("registry/" + id + ".json: missing or not a JSON object");
        } else {
            if (doc.id !== id)
                model.errors.push("registry/" + id + ".json: id is " + JSON.stringify(doc.id));
            page.title = typeof doc.title === "string" ? doc.title : id;
            page.icon = typeof doc.icon === "string" ? doc.icon : "settings";
            page.iconRotation = typeof doc.iconRotation === "number" ? doc.iconRotation : 0;
            page.description = typeof doc.description === "string" ? doc.description : "";
            var sectionIds = {};
            (isArrayLike(doc.sections) ? doc.sections : []).forEach(function (section) {
                if (!section || typeof section.id !== "string" || sectionIds[section.id]) {
                    model.errors.push("registry/" + id + ".json: invalid or duplicate section " + JSON.stringify(section && section.id));
                    return;
                }
                sectionIds[section.id] = true;
                page.sections.push({
                    id: section.id,
                    pageId: id,
                    title: String(section.title || ""),
                    icon: String(section.icon || ""),
                    description: String(section.description || "")
                });
            });
            (isArrayLike(doc.entries) ? doc.entries : []).forEach(function (raw) {
                if (raw && raw.ref !== undefined) {
                    // Aliases resolve once every page is loaded (see resolveAliases).
                    if (typeof raw.ref !== "string" || typeof raw.section !== "string" || !sectionIds[raw.section]) {
                        model.errors.push("registry/" + id + ".json: invalid alias " + JSON.stringify(raw));
                        return;
                    }
                    page.entries.push({ __ref: raw.ref, section: raw.section });
                    return;
                }
                var problem = entryProblem(raw, sectionIds, model.retired);
                if (!problem && model.entryByKey[raw.key])
                    problem = "duplicate key";
                if (problem) {
                    model.errors.push("registry/" + id + ".json: " + (raw && raw.key) + ": " + problem);
                    return;
                }
                var entry = normalizeEntry(raw, page);
                page.entries.push(entry);
                model.entryByKey[entry.key] = entry;
                (entry.keys || []).forEach(function (k) {
                    model.ownerByKey[k] = entry;
                });
            });
        }
        model.pageById[id] = page;
        model.pages.push(page);
        return page;
    }
    var groups = pagesDoc && isArrayLike(pagesDoc.groups) ? pagesDoc.groups : [];
    if (!pagesDoc || groups.length === 0)
        model.errors.push("registry/pages.json: no groups");
    groups.forEach(function (group) {
        var g = { id: String(group.id), title: String(group.title || group.id), pages: [] };
        (group.pages || []).forEach(function (id) {
            if (model.pageById[id]) {
                model.errors.push("registry/pages.json: page listed twice: " + id);
                return;
            }
            g.pages.push(addPage(id, g.id));
        });
        model.groups.push(g);
    });
    ((pagesDoc && pagesDoc.footer) || []).forEach(function (id) {
        if (model.pageById[id]) {
            model.errors.push("registry/pages.json: page listed twice: " + id);
            return;
        }
        model.footerPages.push(addPage(id, "footer"));
    });
    resolveAliases(model);
    return model;
}

// An alias ({ ref, section }) shows a canonical entry of another page. It is a
// copy of that entry with this page's section, aliasOf and homePageId; the key
// stays canonical so the store, objectName and search treat it as one setting.
function resolveAliases(model) {
    model.pages.forEach(function (page) {
        var seen = {};
        page.entries = page.entries.filter(function (item) {
            if (item.__ref === undefined)
                return true;
            var target = model.entryByKey[item.__ref];
            var problem = "";
            if (!target)
                problem = "unknown entry";
            else if (target.pageId === page.id)
                problem = "targets its own page";
            else if (seen[item.__ref])
                problem = "duplicate alias";
            if (problem) {
                model.errors.push("registry/" + page.id + ".json: alias " + item.__ref + ": " + problem);
                return false;
            }
            seen[item.__ref] = true;
            return true;
        }).map(function (item) {
            if (item.__ref === undefined)
                return item;
            var target = model.entryByKey[item.__ref];
            var alias = {};
            for (var k in target)
                alias[k] = target[k];
            alias.section = item.section;
            alias.aliasOf = target.key;
            alias.homePageId = target.pageId;
            return alias;
        });
    });
}

function entryProblem(raw, sectionIds, retired) {
    if (!raw || typeof raw !== "object")
        return "not an object";
    if (typeof raw.key !== "string" || raw.key.length === 0)
        return "missing key";
    if (typeof raw.section !== "string" || !sectionIds[raw.section])
        return "unknown section " + JSON.stringify(raw.section);
    if (typeof raw.label !== "string" || raw.label.length === 0)
        return "missing label";
    if (BACKENDS.indexOf(raw.backend) < 0)
        return "unknown backend " + JSON.stringify(raw.backend);
    if (TYPES.indexOf(raw.type) < 0)
        return "unknown type " + JSON.stringify(raw.type);
    if (raw.widget !== undefined && WIDGETS.indexOf(raw.widget) < 0)
        return "unknown widget " + JSON.stringify(raw.widget);
    if (raw.type === "enum" && (!isArrayLike(raw.options) || raw.options.length === 0))
        return "enum without options";
    var path = raw.path || raw.key;
    if (raw.backend === "config" && isRetired(path, retired))
        return "retired path";
    return "";
}

function normalizeEntry(raw, page) {
    var entry = {};
    for (var k in raw)
        entry[k] = raw[k];
    entry.pageId = page.id;
    entry.homePageId = page.id;
    entry.aliasOf = "";
    entry.path = raw.path || raw.key;
    entry.description = raw.description || "";
    entry.note = raw.note || "";
    entry.keywords = isArrayLike(raw.keywords) ? raw.keywords.map(String) : [];
    entry.icon = raw.icon || "";
    entry.risky = raw.risky === true;
    entry.widget = raw.widget || defaultWidget(raw);
    return entry;
}

function defaultWidget(entry) {
    switch (entry.type) {
    case "bool": return "switch";
    case "int": return (typeof entry.min === "number" && typeof entry.max === "number" && (entry.max - entry.min) / (entry.step || 1) > 20) ? "slider" : "spin";
    case "real": return "slider";
    case "enum": return entry.options.length <= 3 ? "segmented" : "select";
    case "string": return "text";
    case "url": return "text";
    case "path": return "path";
    case "font": return "font";
    case "color": return "color";
    case "list": return "list";
    case "time": return "time";
    case "action": return "action";
    case "info": return "info";
    default: return "custom";
    }
}

function isWritable(entry) {
    return PASSIVE_BACKENDS.indexOf(entry.backend) < 0 && entry.type !== "action" && entry.type !== "info";
}

// ------------------------------------------------------------------ search

function fold(text) {
    return String(text === undefined || text === null ? "" : text)
        .normalize("NFD")
        .replace(/[̀-ͯ]/g, "")
        .toLowerCase()
        .trim();
}

function words(folded) {
    return folded.split(/[^a-z0-9]+/).filter(function (w) { return w.length > 0; });
}

var SCORE_LABEL_PREFIX = 100;
var SCORE_LABEL_WORD = 80;
var SCORE_LABEL_CONTAINS = 60;
var SCORE_KEYWORD = 50;
var SCORE_CONTEXT = 40;
var SCORE_DESCRIPTION = 20;
var SCORE_EXACT = 20;
var KIND_RANK = { entry: 0, page: 1, section: 2 };

// Scores one search token against a document; 0 when it does not match.
// doc fields are lists of already folded strings.
function scoreToken(doc, token) {
    var best = 0;
    doc.labels.forEach(function (label) {
        if (label.indexOf(token) === 0)
            best = Math.max(best, SCORE_LABEL_PREFIX);
        else if (words(label).some(function (w) { return w.indexOf(token) === 0; }))
            best = Math.max(best, SCORE_LABEL_WORD);
        else if (label.indexOf(token) >= 0)
            best = Math.max(best, SCORE_LABEL_CONTAINS);
    });
    if (best)
        return best;
    if (doc.keywords.some(function (k) { return k.indexOf(token) >= 0; }))
        return SCORE_KEYWORD;
    if (doc.context.some(function (c) { return words(c).some(function (w) { return w.indexOf(token) === 0; }); }))
        return SCORE_CONTEXT;
    if (doc.descriptions.some(function (d) { return d.indexOf(token) >= 0; }))
        return SCORE_DESCRIPTION;
    return 0;
}

function pair(text, tr) {
    var out = [fold(text)];
    var translated = fold(tr(text));
    if (translated !== out[0])
        out.push(translated);
    return out.filter(function (s) { return s.length > 0; });
}

// Builds folded search documents. tr translates English source strings.
function searchDocuments(model, tr) {
    var docs = [];
    model.pages.forEach(function (page) {
        var pageTitles = pair(page.title, tr);
        docs.push({
            kind: "page", pageId: page.id, sectionId: "", key: "",
            labels: pageTitles, keywords: [], context: [], descriptions: pair(page.description, tr)
        });
        var sectionTitles = {};
        page.sections.forEach(function (section) {
            sectionTitles[section.id] = pair(section.title, tr);
            docs.push({
                kind: "section", pageId: page.id, sectionId: section.id, key: "",
                labels: sectionTitles[section.id], keywords: [], context: pageTitles,
                descriptions: pair(section.description, tr)
            });
        });
        page.entries.forEach(function (entry) {
            if (entry.aliasOf)
                return;
            docs.push({
                kind: "entry", pageId: page.id, sectionId: entry.section, key: entry.key,
                labels: pair(entry.label, tr),
                keywords: entry.keywords.map(fold).filter(function (k) { return k.length > 0; }),
                context: (sectionTitles[entry.section] || []).concat(pageTitles),
                descriptions: pair(entry.description, tr).concat(pair(entry.note, tr))
            });
        });
    });
    return docs;
}

// Every query word must match; the score adds up per word, and labels that
// start with or equal the whole query get a bonus.
function search(docs, query, limit) {
    var q = fold(query);
    if (q.length === 0)
        return [];
    var tokens = q.split(/\s+/).filter(function (t) { return t.length > 0; });
    var results = [];
    docs.forEach(function (doc, index) {
        var total = 0;
        for (var i = 0; i < tokens.length; i++) {
            var s = scoreToken(doc, tokens[i]);
            if (s === 0)
                return;
            total += s;
        }
        if (tokens.length > 1 && doc.labels.some(function (l) { return l.indexOf(q) === 0; }))
            total += SCORE_LABEL_PREFIX;
        if (doc.labels.indexOf(q) >= 0)
            total += SCORE_EXACT;
        results.push({ kind: doc.kind, pageId: doc.pageId, sectionId: doc.sectionId, key: doc.key, score: total, order: index });
    });
    // Ties: settings before pages before sections, then registry order.
    results.sort(function (a, b) {
        return b.score - a.score || KIND_RANK[a.kind] - KIND_RANK[b.kind] || a.order - b.order;
    });
    return results.slice(0, limit > 0 ? limit : results.length);
}

// ------------------------------------------------------------ confirmation

// Adds keys to the pending risky batch and restarts the countdown.
function joinBatch(pending, keys, seconds) {
    var all = pending ? pending.keys.slice() : [];
    keys.forEach(function (k) {
        if (all.indexOf(k) < 0)
            all.push(k);
    });
    return { keys: all, secondsLeft: seconds || CONFIRM_SECONDS };
}

// One countdown second. Returns { pending, expired }.
function tickBatch(pending) {
    if (!pending)
        return { pending: null, expired: false };
    var left = pending.secondsLeft - 1;
    if (left <= 0)
        return { pending: null, expired: true };
    return { pending: { keys: pending.keys.slice(), secondsLeft: left }, expired: false };
}
