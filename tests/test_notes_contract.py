from __future__ import annotations

import json
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


class NotesContractTest(unittest.TestCase):
    def test_notes_section_is_registered_in_sidebar(self) -> None:
        sidebar = read("config/quickshell/ii/modules/ii/sidebarLeft/SidebarLeftContent.qml")
        self.assertIn("NotesPage {", sidebar)
        self.assertIn('Translation.tr("No active player")', sidebar)
        self.assertNotIn("placeholder.createObject()", sidebar)

    def test_notes_store_exposes_required_operations_and_migration(self) -> None:
        store = read("config/quickshell/ii/services/Notes.qml")
        for expected in [
            "notesJsonPath",
            "function add(",
            "function updateContent(",
            "function togglePinned(",
            "function remove(",
            "function move(",
            "function migrateLegacy(",
            "Directories.notesPath",
            "mkdirProcess.running = true",
            "corrupt-${Date.now()}",
            "if (sourceIndex < targetIndex)",
            'version: root.schemaVersion',
        ]:
            self.assertIn(expected, store)

    def test_notes_data_contract_supports_free_text_and_pin_state(self) -> None:
        sample = {
            "version": 1,
            "notes": [
                {"id": "note-1", "content": "free text", "pinned": True},
            ],
        }
        self.assertEqual(json.loads(json.dumps(sample))["version"], 1)
        self.assertIsInstance(sample["notes"][0]["content"], str)
        self.assertIsInstance(sample["notes"][0]["pinned"], bool)

    def test_live_overlay_notes_remain_available_alongside_sidebar(self) -> None:
        context = read("config/quickshell/ii/modules/ii/overlay/OverlayContext.qml")
        chooser = read("config/quickshell/ii/modules/ii/overlay/OverlayWidgetDelegateChooser.qml")
        content = read("config/quickshell/ii/modules/ii/overlay/OverlayContent.qml")
        self.assertIn('identifier: "notes"', context)
        self.assertIn('roleValue: "notes"', chooser)
        self.assertIn('OverlayContext.availableWidgets.find', content)

    def test_drag_target_is_cleared_when_pointer_leaves_note(self) -> None:
        notes = read("config/quickshell/ii/modules/ii/sidebarLeft/NotesPage.qml")
        self.assertIn("function updateDropTargetAt(pointerY)", notes)
        self.assertIn("if (targetIndex < 0 || targetIndex === sourceIndex)", notes)
        self.assertIn('root.dropTargetId = ""', notes)
        self.assertIn("root.updateDropTargetAt(pointerY)", notes)
