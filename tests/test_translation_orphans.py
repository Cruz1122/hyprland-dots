"""scripts/settings/translation-orphans.py: unused keys of translations/es_MX.json."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "scripts/settings/translation-orphans.py"
ES_MX = REPO / "config/quickshell/ii/translations/es_MX.json"

TRANSLATIONS = {
    "Used key": "Clave usada",
    "Unused key": "Clave sin usar",
    "Dynamic key": "Clave dinámica",
    "Registry label": "Etiqueta del registro",
    "Main shell only": "Solo la interfaz principal",
    "Group title": "Título del grupo",
    "Page title": "Título de la página",
    "Page text.": "Texto de la página.",
    "Section title": "Título de la sección",
    "Entry text.": "Texto del ajuste.",
    "Note text.": "Texto de la nota.",
    "Min label": "Etiqueta mínima",
    "Max label": "Etiqueta máxima",
    "Placeholder text": "Texto de ejemplo",
    "Action label": "Etiqueta de la acción",
    "Section text.": "Texto de la sección.",
    "Help text.": "Texto de ayuda.",
    "Option label": "Opción",
    "Option text": "Texto de la opción",
    "samples": "muestras",
    "Settings message": "Mensaje de Configuración",
    "Line\nbreak": "Salto\nde línea",
    "it's": "es",
    "Saved": "Guardado",
    "Keyword only": "Solo palabra clave",
}


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def make_shell(root: Path) -> Path:
    shell = root / "config/quickshell/ii"
    write(shell / "translations/es_MX.json", json.dumps(TRANSLATIONS, ensure_ascii=False, indent=2) + "\n")
    registry = shell / "modules/settings/registry"
    write(registry / "pages.json", json.dumps({"groups": [{"title": "Group title", "pages": ["demo"]}], "footer": []}))
    write(registry / "retired.json", json.dumps({"retired": ["Unused key"], "managedElsewhere": []}))
    # Every translated registry field carries its own string, so dropping any
    # one field from the scan turns exactly that key into an orphan.
    write(registry / "demo.json", json.dumps({
        "id": "demo", "title": "Page title", "description": "Page text.",
        "sections": [{"id": "s", "title": "Section title", "description": "Section text."}],
        "entries": [{
            "key": "demo.value", "section": "s", "label": "Registry label", "description": "Entry text.",
            "note": "Note text.", "help": "Help text.", "unit": "samples", "minLabel": "Min label",
            "maxLabel": "Max label", "keywords": ["Keyword only"],
            "options": [{"value": 1, "label": "Option label", "description": "Option text"}],
        }, {
            "key": "demo.text", "section": "s", "label": "Registry label", "placeholder": "Placeholder text",
            "actionLabel": "Action label",
        }],
    }))
    # Main shell: only literals passed to Translation.tr count.
    write(shell / "modules/ii/Widget.qml", textwrap.dedent("""\
        Text {
            text: Translation.tr("Main shell only")
            property string other: "Unused key"
            property string multi: Translation.tr(
                "Line\\nbreak")
            property string quote: Translation.tr('it\\'s')
            property string padded: Translation.tr("Saved    ")
            property string built: Translation.tr(`${prefix} key`)
        }
        """))
    write(shell / "services/Used.js", 'function f() { return Translation.tr(`Used key`); }\n')
    # Settings app: any literal counts (messages are translated later).
    write(shell / "modules/settings/backends/Demo.qml", textwrap.dedent("""\
        // Two apostrophes around a literal on one line must not hide it.
        QtObject { property string reason: /* don't */ "Settings message" /* won't */ }
        """))
    return shell


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, check=False)


class TranslationOrphansFixtureTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.shell = make_shell(self.root)
        self.allowlist = self.root / "allowlist.txt"
        write(self.allowlist, textwrap.dedent("""\
            # Runtime-built keys.
            "Dynamic key"  # modules/ii/Widget.qml builds it with Translation.tr(variable)
            """))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def report(self, *extra: str) -> dict:
        result = run("--json", "--shell", str(self.shell), "--allowlist", str(self.allowlist), *extra)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_only_unused_keys_are_orphans(self) -> None:
        report = self.report()
        # "Unused key" is a plain literal outside the settings app and a
        # retired path; "Saved" only matches Translation.tr("Saved    ")
        # loosely; "Keyword only" is a search keyword, never translated.
        self.assertEqual(report["orphans"], ["Keyword only", "Saved", "Unused key"])
        self.assertEqual(report["keys"], len(TRANSLATIONS))
        self.assertEqual(report["staleAllowlist"], [])

    def test_each_kind_of_use_is_recognized(self) -> None:
        orphans = set(self.report()["orphans"])
        for key in ["Used key", "Main shell only", "Line\nbreak", "it's", "Settings message", "Dynamic key",
                    "Registry label", "Group title", "Page title", "Page text.", "Section title", "Section text.",
                    "Entry text.", "Note text.", "Help text.", "Min label", "Max label", "Placeholder text",
                    "Action label", "Option label", "Option text", "samples"]:
            with self.subTest(key=key):
                self.assertNotIn(key, orphans)

    def test_without_the_allowlist_the_dynamic_key_is_an_orphan(self) -> None:
        write(self.allowlist, "# nothing\n")
        self.assertIn("Dynamic key", self.report()["orphans"])

    def test_stale_allowlist_entries_are_reported(self) -> None:
        write(self.allowlist, '"Used key"  # covered by a literal\n"Gone"  # not in the file\n')
        self.assertEqual(self.report()["staleAllowlist"], ["Gone", "Used key"])

    def test_allowlist_entries_need_a_comment(self) -> None:
        write(self.allowlist, '"Dynamic key"\n')
        result = run("--shell", str(self.shell), "--allowlist", str(self.allowlist))
        self.assertEqual(result.returncode, 2)
        self.assertIn("# comment", result.stderr)

    def test_check_fails_only_when_there_are_orphans(self) -> None:
        base = ["--shell", str(self.shell), "--allowlist", str(self.allowlist)]
        self.assertEqual(run("--check", *base).returncode, 1)
        clean = {key: value for key, value in TRANSLATIONS.items() if key not in {"Unused key", "Saved", "Keyword only"}}
        write(self.shell / "translations/es_MX.json", json.dumps(clean))
        result = run("--check", *base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(result.stdout.startswith("0 of "), result.stdout)

    def test_text_report_lists_one_json_string_per_line(self) -> None:
        result = run("--shell", str(self.shell), "--allowlist", str(self.allowlist))
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertTrue(lines[0].startswith(f"3 of {len(TRANSLATIONS)} keys"), lines[0])
        self.assertEqual([json.loads(line) for line in lines[1:]], ["Keyword only", "Saved", "Unused key"])

    def test_bad_input_exits_2(self) -> None:
        self.assertEqual(run("--shell", str(self.root / "missing")).returncode, 2)
        write(self.shell / "translations/es_MX.json", "{not json")
        self.assertEqual(run("--shell", str(self.shell), "--allowlist", str(self.allowlist)).returncode, 2)


class TranslationOrphansRepositoryTest(unittest.TestCase):
    def test_repository_report(self) -> None:
        # Report mode only: the orphan list is cleaned up after wave 2, so its
        # length is printed, not asserted.
        result = run("--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        keys = json.loads(ES_MX.read_text(encoding="utf-8"))
        self.assertEqual(report["keys"], len(keys))
        self.assertLessEqual(set(report["orphans"]), set(keys))
        self.assertEqual(report["staleAllowlist"], [], "remove these from translation-orphans-allowlist.txt")
        # Strings this settings page set relies on must never be reported.
        # "Opens plain text (.txt) files." is only an entry description.
        for used in ["Terminal", "Apps pinned in the start menu", "Requires “%1”", "Hyprland is not running",
                     "Opens plain text (.txt) files."]:
            self.assertNotIn(used, report["orphans"])
        print(f"\ntranslation orphans in es_MX.json: {len(report['orphans'])}", file=sys.stderr)
        for key in report["orphans"]:
            print(f"  {json.dumps(key, ensure_ascii=False)}", file=sys.stderr)


if __name__ == "__main__":
    unittest.main()
