"""Static contract of the settings app (docs/settings.md "Tests").

Generic over every registry file, so pages with no entries pass and pages
filled later are checked without editing this file.
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[1]
SHELL = REPO / "config/quickshell/ii"
SETTINGS = SHELL / "modules/settings"
REGISTRY = SETTINGS / "registry"
PAGES_DIR = SETTINGS / "pages"
COMPONENTS = SETTINGS / "components"
CONFIG_OPTIONS = SHELL / "modules/common/ConfigOptions.qml"
ES_MX = SHELL / "translations/es_MX.json"
HYPRLAND_FIXTURE = REPO / "tests/fixtures/hyprland-options.json"

# Legacy pages that are no longer referenced; phase P3 ports and deletes
# them, so they are exempt from the deny-list, shell-string and size scans.
LEGACY = {
    SETTINGS / "About.qml",
    SETTINGS / "AdvancedConfig.qml",
    SETTINGS / "BackgroundConfig.qml",
    SETTINGS / "BarConfig.qml",
    SETTINGS / "GeneralConfig.qml",
    SETTINGS / "InterfaceConfig.qml",
    SETTINGS / "QuickConfig.qml",
    SETTINGS / "ScreenRecordingConfig.qml",
    SETTINGS / "ServicesConfig.qml",
    COMPONENTS / "AiQuotaSettings.qml",
}

PAGE_IDS = [
    "quick", "appearance", "background", "bar", "panels",
    "windows", "input", "displays",
    "sound", "power", "notifications", "apps", "region",
    "capture", "search", "services",
    "advanced", "about",
]
BACKENDS = {"config", "hyprland", "idle", "display", "mime", "audio", "power", "ipc", "action", "readonly"}
TYPES = {"bool", "int", "real", "enum", "string", "path", "font", "color", "list", "time", "url", "action", "info", "custom"}
WIDGETS = {"switch", "slider", "spin", "segmented", "select", "text", "textarea", "path", "font", "color", "list",
           "time", "device", "action", "info", "custom"}
ENTRY_FIELDS = {"key", "section", "label", "description", "note", "keywords", "icon", "backend", "path", "option",
                "type", "widget", "min", "max", "step", "unit", "uiScale", "decimals", "options", "validate",
                "enabledWhen", "visibleWhen", "risky", "action", "actionLabel", "actionIcon", "actionKind",
                "consumers", "external", "keys", "placeholder", "pick"}
DENIED_SERVICES = ["Battery", "Hyprsunset", "Brightness", "Notifications", "Weather", "Idle", "Ai", "AiQuotaUsage",
                   "Cliphist", "ConflictKiller", "Updates", "SongRec", "TimerService"]
# Config value types each entry type may target.
COMPATIBLE = {
    "bool": {"bool"},
    "int": {"int", "real"},
    "real": {"real"},
    "string": {"string"},
    "path": {"string"},
    "font": {"string"},
    "color": {"string", "color"},
    "url": {"string"},
    "time": {"string"},
    "list": {"list<string>", "list<var>"},
}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def strip_strings_and_comments(line: str) -> str:
    line = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
    line = re.sub(r"'(?:\\.|[^'\\])*'", "''", line)
    line = re.sub(r"`(?:\\.|[^`\\])*`", "``", line)
    return line.split("//", 1)[0]


def parse_config_options(path: Path = CONFIG_OPTIONS) -> dict[str, str]:
    """Flattens ConfigOptions.qml into {dotted.path: type}; JsonObjects map to "object"."""
    tree: dict[str, str] = {}
    stack: list[str | None] = []
    declaration = re.compile(r"^\s*(?:readonly\s+)?property\s+([\w<>]+)\s+(\w+)\s*:")
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = strip_strings_and_comments(raw)
        match = declaration.match(line)
        names = [name for name in stack if name]
        opens_object = False
        if match and len(stack) == 1:
            prop_type, name = match.groups()
            tree[".".join(names + [name])] = "object" if prop_type == "JsonObject" else prop_type
            opens_object = prop_type == "JsonObject" and "{" in line
        elif match and stack and all(item is not None for item in stack[1:]) and stack[-1] is not None:
            prop_type, name = match.groups()
            tree[".".join(names + [name])] = "object" if prop_type == "JsonObject" else prop_type
            opens_object = prop_type == "JsonObject" and "{" in line
        for char in line:
            if char == "{":
                if opens_object:
                    stack.append(match.group(2))
                    opens_object = False
                elif not stack:
                    stack.append("")  # the JsonAdapter root
                else:
                    stack.append(None)
            elif char == "}" and stack:
                stack.pop()
    return tree


def load_registry() -> tuple[dict, dict[str, dict], dict]:
    pages_doc = load_json(REGISTRY / "pages.json")
    docs = {page_id: load_json(REGISTRY / f"{page_id}.json") for page_id in PAGE_IDS}
    retired = load_json(REGISTRY / "retired.json")
    return pages_doc, docs, retired


def is_under(path: str, prefixes: list[str]) -> bool:
    return any(path == prefix or path.startswith(prefix + ".") for prefix in prefixes)


def qml_files(root: Path) -> list[Path]:
    return sorted(path for path in root.rglob("*.qml") if path not in LEGACY)


def page_source(page_id: str) -> Path:
    return PAGES_DIR / f"{page_id[0].upper()}{page_id[1:]}Page.qml"


class SettingsContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.pages_doc, cls.docs, cls.retired = load_registry()
        cls.schema = parse_config_options()
        cls.translations = load_json(ES_MX)
        cls.entries: list[tuple[str, dict]] = []
        cls.refs: list[tuple[str, dict]] = []
        for page_id, doc in cls.docs.items():
            for entry in doc.get("entries", []):
                (cls.refs if "ref" in entry else cls.entries).append((page_id, entry))
        cls.by_key = {entry["key"]: (page_id, entry) for page_id, entry in cls.entries}
        cls.managed = [item["path"] for item in cls.retired["managedElsewhere"]]
        cls.custom_keys = {key for _, entry in cls.entries for key in entry.get("keys", [])}

    # ------------------------------------------------------------ registry

    def test_pages_json_lists_every_page_once_in_the_expected_groups(self) -> None:
        groups = self.pages_doc["groups"]
        self.assertEqual([g["id"] for g in groups], ["personalization", "desktop", "system", "tools"])
        self.assertEqual([g["title"] for g in groups], ["Personalization", "Desktop", "System", "Tools"])
        listed = [page for g in groups for page in g["pages"]] + self.pages_doc["footer"]
        self.assertEqual(listed, PAGE_IDS)
        self.assertEqual(self.pages_doc["footer"], ["advanced", "about"])

    def test_every_page_has_a_registry_file_and_a_page_component(self) -> None:
        self.assertEqual(sorted(p.stem for p in REGISTRY.glob("*.json")), sorted(PAGE_IDS + ["pages", "retired"]))
        self.assertEqual(sorted(p.name for p in PAGES_DIR.glob("*.qml")), sorted(page_source(i).name for i in PAGE_IDS))
        for page_id, doc in self.docs.items():
            with self.subTest(page=page_id):
                self.assertEqual(doc["id"], page_id)
                for field in ("title", "icon", "description"):
                    self.assertIsInstance(doc[field], str)
                    self.assertTrue(doc[field].strip(), field)
                self.assertIsInstance(doc["sections"], list)
                self.assertIsInstance(doc["entries"], list)
                text = page_source(page_id).read_text(encoding="utf-8")
                self.assertIn("SettingsPage {", text)
                self.assertIn(f'pageId: "{page_id}"', text)

    def test_sections_and_entries_follow_the_schema(self) -> None:
        for page_id, doc in self.docs.items():
            section_ids = [s["id"] for s in doc["sections"]]
            self.assertEqual(len(section_ids), len(set(section_ids)), page_id)
            for section in doc["sections"]:
                self.assertTrue(section.get("title"), f"{page_id}/{section['id']}")
            for entry in doc["entries"]:
                where = f"{page_id}: {entry.get('key', entry.get('ref'))}"
                with self.subTest(entry=where):
                    self.assertIn(entry.get("section"), section_ids)
                    if "ref" in entry:
                        self.assertEqual(set(entry), {"ref", "section"}, "aliases only carry ref and section")
                        continue
                    self.assertLessEqual(set(entry) - ENTRY_FIELDS, set(), "unknown fields")
                    self.assertTrue(entry["key"])
                    self.assertTrue(entry.get("label"))
                    self.assertIn(entry["backend"], BACKENDS)
                    self.assertIn(entry["type"], TYPES)
                    if "widget" in entry:
                        self.assertIn(entry["widget"], WIDGETS)
                    if entry.get("description"):
                        self.assertTrue(entry["description"].endswith("."), "description is one sentence")
                    if entry["type"] == "enum":
                        self.assertTrue(entry.get("options"))
                        for option in entry["options"]:
                            self.assertIn("value", option)
                            self.assertTrue(option.get("label"))
                    if "min" in entry and "max" in entry:
                        self.assertLessEqual(entry["min"], entry["max"])
                    if entry["type"] == "action":
                        self.assertTrue(entry.get("action"))
                    if entry["backend"] == "hyprland":
                        self.assertTrue(entry.get("option"), "hyprland entries name their getoption option")
                    if "risky" in entry:
                        self.assertIsInstance(entry["risky"], bool)
                    for field in ("enabledWhen", "visibleWhen"):
                        if field in entry:
                            self.check_condition(entry[field], where)

    def check_condition(self, cond: dict, where: str) -> None:
        self.assertIsInstance(cond, dict, where)
        if "all" in cond or "any" in cond:
            for inner in cond.get("all", cond.get("any")):
                self.check_condition(inner, where)
        elif "not" in cond:
            self.check_condition(cond["not"], where)
        elif "capability" in cond:
            self.assertIsInstance(cond["capability"], str)
        else:
            # Keys of custom entries resolve to synthetic entries in the registry.
            known = cond.get("key") in self.by_key or cond.get("key") in self.custom_keys
            self.assertTrue(known, f"{where}: condition on unknown key {cond.get('key')}")
            self.assertTrue({"equals", "notEquals", "in"} & set(cond), f"{where}: condition without operator")

    def test_keys_are_globally_unique(self) -> None:
        keys = [entry["key"] for _, entry in self.entries]
        duplicates = sorted({key for key in keys if keys.count(key) > 1})
        self.assertEqual(duplicates, [])
        prefixes = ("hyprland.", "display.", "mime.", "audio.", "power.", "ipc.", "action.", "info.", "idle.")
        for _, entry in self.entries:
            if entry["backend"] not in ("config", "idle"):
                self.assertTrue(entry["key"].startswith(prefixes), f"{entry['key']}: backend prefix")

    def test_aliases_point_to_canonical_entries_of_other_pages(self) -> None:
        managed = self.retired["retired"] + self.managed
        per_page: dict[str, set[str]] = {}
        for page_id, alias in self.refs:
            with self.subTest(page=page_id, ref=alias["ref"]):
                self.assertTrue(alias["ref"] in self.by_key, f"{alias['ref']}: ref must target an existing (non-alias) entry")
                target_page, target = self.by_key[alias["ref"]]
                self.assertNotEqual(target_page, page_id, "ref targets another page")
                self.assertFalse(is_under(target.get("path", target["key"]), managed))
                seen = per_page.setdefault(page_id, set())
                self.assertNotIn(alias["ref"], seen, "two refs to the same key on one page")
                seen.add(alias["ref"])

    # ------------------------------------------------------------- config

    def test_config_paths_exist_with_compatible_types(self) -> None:
        for page_id, entry in self.entries:
            if entry["backend"] not in ("config", "idle"):
                continue
            paths = entry.get("keys") if entry["type"] == "custom" else [entry.get("path", entry["key"])]
            self.assertTrue(paths, f"{entry['key']}: custom config entries list their keys")
            for path in paths:
                with self.subTest(key=entry["key"], path=path):
                    self.assertIn(path, self.schema, "path not in ConfigOptions.qml")
                    actual = self.schema[path]
                    if entry["type"] == "custom":
                        continue
                    if entry["type"] == "enum":
                        kinds = {type(o["value"]) for o in entry["options"]}
                        expected = {bool: {"bool"}, int: {"int", "real"}, float: {"real"}, str: {"string"}}
                        for kind in kinds:
                            self.assertIn(actual, expected[kind])
                    else:
                        self.assertIn(actual, COMPATIBLE[entry["type"]])

    def test_config_parser_reads_nested_schema(self) -> None:
        self.assertEqual(self.schema["bar.bottom"], "bool")
        self.assertEqual(self.schema["screenRecord.fps"], "int")
        self.assertEqual(self.schema["appearance.transparency.backgroundTransparency"], "real")
        self.assertEqual(self.schema["background.widgets.clock.cookie.dateInClock"], "bool")
        self.assertEqual(self.schema["sidebar.quickToggles.android.toggles"], "list<var>")
        self.assertEqual(self.schema["appearance"], "object")
        self.assertNotIn("bar.bottom.x", self.schema)

    def test_consumers_exist_and_mention_the_key(self) -> None:
        for _, entry in self.entries:
            if entry["backend"] == "config":
                self.assertTrue(entry.get("consumers"), f"{entry['key']}: config entries need consumers")
            for consumer in entry.get("consumers", []):
                with self.subTest(key=entry["key"], consumer=consumer):
                    base = REPO if consumer.startswith(("config/", "scripts/")) else SHELL
                    path = base / consumer
                    self.assertTrue(path.is_file(), "consumer file missing")
                    keys = entry.get("keys") if entry["type"] == "custom" else [entry.get("path", entry["key"])]
                    leaves = {k.split(".")[-1] for k in keys or [entry["key"]]}
                    text = path.read_text(encoding="utf-8")
                    self.assertTrue(any(leaf in text for leaf in leaves), f"{consumer} never mentions {leaves}")

    # -------------------------------------------------------------- retired

    def test_retired_paths_exist_and_stay_hidden(self) -> None:
        retired = self.retired["retired"]
        managed = self.managed
        for path in retired + managed:
            self.assertIn(path, self.schema, f"{path}: retired/managed path must exist in the schema")
        for _, entry in self.entries:
            paths = [entry.get("path", entry["key"])] + entry.get("keys", [])
            if entry["backend"] not in ("config", "idle"):
                paths = entry.get("keys", [])
            for path in paths:
                self.assertFalse(is_under(path, retired + managed), f"{entry['key']} exposes {path}")
        option_ref = re.compile(r"Config\.options(?:\?\.|\.)([\w.?]+)")
        for path in qml_files(SETTINGS) + [SHELL / "settings.qml"]:
            for match in option_ref.findall(path.read_text(encoding="utf-8")):
                dotted = match.replace("?", "").rstrip(".")
                self.assertFalse(is_under(dotted, retired), f"{path.name} reads retired {dotted}")

    # --------------------------------------------------------- translations

    def test_registry_and_ui_strings_are_translated(self) -> None:
        needed: set[str] = {group["title"] for group in self.pages_doc["groups"]}
        for doc in self.docs.values():
            needed |= {doc["title"], doc["description"]}
            for section in doc["sections"]:
                needed |= {section["title"], section.get("description", "")}
            for entry in doc["entries"]:
                if "ref" in entry:
                    continue
                needed |= {entry["label"], entry.get("description", ""), entry.get("note", ""),
                           entry.get("actionLabel", ""), entry.get("placeholder", "")}
                needed |= {option["label"] for option in entry.get("options", [])}
        tr_literal = re.compile(r'Translation\.tr\("((?:\\.|[^"\\])*)"\)')
        for path in qml_files(COMPONENTS) + qml_files(PAGES_DIR) + [SHELL / "settings.qml"]:
            needed |= set(tr_literal.findall(path.read_text(encoding="utf-8")))
        message = re.compile(r'(?:error: |_fail\([\w.]+, |failed\([\w.]+, |unavailableReason: .*?|return )"([A-Z][^"]+)"')
        for path in [SETTINGS / "core/SettingsLogic.js", SETTINGS / "core/SettingsStoreImpl.qml", *sorted((SETTINGS / "backends").glob("*.qml"))]:
            needed |= set(message.findall(path.read_text(encoding="utf-8")))
        missing = sorted(text for text in needed if text and text not in self.translations)
        self.assertEqual(missing, [], "add these to translations/es_MX.json")

    # ------------------------------------------------------------- hygiene

    def test_settings_process_avoids_side_effect_services(self) -> None:
        pattern = re.compile(r"\b(" + "|".join(DENIED_SERVICES) + r")\.[a-zA-Z]")
        for path in qml_files(SETTINGS) + [SHELL / "settings.qml"]:
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                code = strip_strings_and_comments(line)
                self.assertIsNone(pattern.search(code), f"{path.relative_to(SHELL)}:{number}: {line.strip()}")

    def test_no_shell_strings(self) -> None:
        pattern = re.compile(r'"(?:ba|z|fi)?sh"\s*,\s*"-c"|\b(?:ba|z)?sh\s+-c\b')
        files = qml_files(SETTINGS) + [SHELL / "settings.qml"] + sorted(SETTINGS.rglob("*.js"))
        for path in files:
            self.assertIsNone(pattern.search(path.read_text(encoding="utf-8")), path.name)

    def test_no_explicit_sizes_in_settings_components_and_pages(self) -> None:
        pattern = re.compile(r"^\s*(width|height)\s*:")
        for path in qml_files(COMPONENTS) + qml_files(PAGES_DIR):
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if pattern.match(line) and "// size-ok:" not in line:
                    self.fail(f"{path.relative_to(SHELL)}:{number}: use implicit sizes ({line.strip()})")

    def test_settings_ui_never_writes_config_directly(self) -> None:
        assignment = re.compile(r"Config\.options[\w.?]*\s*=[^=]")
        for path in qml_files(SETTINGS) + [SHELL / "settings.qml"]:
            code = "\n".join(strip_strings_and_comments(line) for line in path.read_text(encoding="utf-8").splitlines())
            self.assertIsNone(assignment.search(code), path.name)
            self.assertNotIn("setNestedValue(", code, path.name)

    def test_pages_use_registered_keys_only(self) -> None:
        known = set(self.by_key)
        for _, entry in self.entries:
            known |= set(entry.get("keys", []))
            if entry.get("action"):
                known.add(entry["action"])
        literal = re.compile(r'"([a-z][\w-]*(?:\.[\w-]+)+)"')
        options = re.compile(r"Config\.options(?:\?\.|\.)([\w.?]+)")
        for path in qml_files(PAGES_DIR):
            text = path.read_text(encoding="utf-8")
            for key in literal.findall(text):
                if re.search(r"\.(qml|js|json|sh|py|png|svg)$", key) or key.startswith("qs."):
                    continue
                self.assertIn(key, known, f"{path.name} uses unregistered key {key}")
            for match in options.findall(text):
                self.assertIn(match.replace("?", "").rstrip("."), known, f"{path.name} reads unregistered option")

    def test_hyprland_entries_match_the_fixture(self) -> None:
        entries = [entry for _, entry in self.entries if entry["backend"] == "hyprland"]
        if not entries:
            self.skipTest("no hyprland entries yet")
        self.assertTrue(HYPRLAND_FIXTURE.is_file(), f"{HYPRLAND_FIXTURE.relative_to(REPO)} is required")
        fixture = load_json(HYPRLAND_FIXTURE)
        if isinstance(fixture, dict):
            names = set(fixture)
        else:
            names = {item.get("value", item.get("name")) for item in fixture}
        for entry in entries:
            self.assertIn(entry["option"], names, entry["key"])

    # ------------------------------------------------------ app entry point

    def test_settings_entry_point_keeps_its_contracts(self) -> None:
        text = (SHELL / "settings.qml").read_text(encoding="utf-8")
        for expected in [
            'title: "illogical-impulse Settings"',
            "readonly property var pages: SettingsRegistry.pages",
            "property int currentPage",
            "readonly property bool pageReady",
            "Config.readWriteDelay = 150",
            'target: "settingsApp"',
            "function open(pageId: string): void",
            "function reveal(key: string): void",
            "II_SETTINGS_PAGE",
            "II_SETTINGS_KEY",
            "SettingsStore.revert()",
            "import qs.modules.settings.core",
            "import qs.modules.settings.components",
        ]:
            self.assertIn(expected, text)
        for removed in ["services/SettingsRegistry.qml", "services/SettingsStore.qml", "modules/settings/FoundationConfig.qml"]:
            self.assertFalse((SHELL / removed).exists(), removed)
        for removed in ["SettingsResponsiveRow", "SettingsFormRow", "SettingsTooltip", "SettingsHelpButton"]:
            self.assertFalse((COMPONENTS / f"{removed}.qml").exists(), removed)

    def test_store_routes_through_backends(self) -> None:
        settings = (SHELL / "settings.qml").read_text(encoding="utf-8")
        self.assertIn("!Config.ready", settings, "pages load only after the config file")
        backend = (SETTINGS / "backends/ConfigBackend.qml").read_text(encoding="utf-8")
        self.assertIn("Logic.setPath(Config.options, entry.path, value)", backend)
        store = (SETTINGS / "core/SettingsStore.qml").read_text(encoding="utf-8")
        for name in ["Config", "Hyprland", "Idle", "Display", "Mime", "Audio", "Power", "Ipc", "System"]:
            self.assertIn(f"{name}Backend {{", store, f"the store instantiates {name}Backend")
            self.assertTrue((SETTINGS / f"backends/{name}Backend.qml").is_file())

    def test_tooltips_need_hover_or_an_explicit_condition(self) -> None:
        tooltip = (SHELL / "modules/common/widgets/StyledToolTip.qml").read_text(encoding="utf-8")
        self.assertIn("parent?.hovered === true", tooltip)
        self.assertNotIn("parent.hovered === undefined", tooltip)


if __name__ == "__main__":
    unittest.main()
