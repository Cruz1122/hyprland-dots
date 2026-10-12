from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SETTINGS_ROOT = REPO_ROOT / "config/quickshell/ii"
PAGES_ROOT = SETTINGS_ROOT / "modules/settings"
COMPONENTS_ROOT = PAGES_ROOT / "components"
MATRIX = REPO_ROOT / "docs/settings-parity-matrix.md"


class SettingsParityContractTest(unittest.TestCase):
    def test_settings_page_order_matches_matrix(self) -> None:
        settings_qml = (SETTINGS_ROOT / "settings.qml").read_text(encoding="utf-8")
        expected = [
            "QuickConfig.qml",
            "GeneralConfig.qml",
            "BarConfig.qml",
            "BackgroundConfig.qml",
            "InterfaceConfig.qml",
            "ServicesConfig.qml",
            "ScreenRecordingConfig.qml",
            "AdvancedConfig.qml",
            "FoundationConfig.qml",
            "About.qml",
        ]
        positions = [settings_qml.index(f"modules/settings/{page}") for page in expected]
        self.assertEqual(positions, sorted(positions))

        matrix = MATRIX.read_text(encoding="utf-8")
        for page in expected:
            self.assertIn(f"modules/settings/{page}", matrix)

    def test_every_current_config_path_is_recorded(self) -> None:
        matrix = MATRIX.read_text(encoding="utf-8")
        path_pattern = re.compile(r"Config\.options(?:\?\.|\.)([A-Za-z0-9_?.]+)")
        paths: set[str] = set()
        for page in sorted(PAGES_ROOT.glob("*.qml")):
            content = page.read_text(encoding="utf-8")
            paths.update(path_pattern.findall(content))

        self.assertNotIn("", paths)
        for path in paths:
            self.assertIn(f"- `{path}`", matrix, msg=f"Missing parity path: {path}")

    def test_baseline_loader_waits_for_config_without_losing_initial_page(self) -> None:
        host_qml = (COMPONENTS_ROOT / "SettingsPageHost.qml").read_text(encoding="utf-8")
        self.assertIn("active: root.ready && root.pages", host_qml)
        self.assertIn("Quickshell.shellPath(root.pages[root.currentIndex].component)", host_qml)
        self.assertNotIn("source = root.pages[0].component", host_qml)

    def test_invalid_rowlayout_property_is_absent(self) -> None:
        quick_qml = (PAGES_ROOT / "QuickConfig.qml").read_text(encoding="utf-8")
        self.assertNotIn("uniformCellSizes:", quick_qml)

    def test_phase_three_and_four_component_catalog_exists(self) -> None:
        expected = {
            "SettingsMetrics.qml",
            "SettingsGallery.qml",
            "SettingsDevicePicker.qml",
            "SettingsPage.qml",
            "SettingsPageHeader.qml",
            "SettingsCard.qml",
            "SettingsSection.qml",
            "SettingsSubsection.qml",
            "SettingsFormRow.qml",
            "SettingsResponsiveRow.qml",
            "SettingsDivider.qml",
            "SettingsButton.qml",
            "SettingsIconButton.qml",
            "SettingsLinkButton.qml",
            "SettingsActionButton.qml",
            "SettingsToggleButton.qml",
            "SettingsSwitchRow.qml",
            "SettingsNumberRow.qml",
            "SettingsSliderRow.qml",
            "SettingsSegmentedControl.qml",
            "SettingsSelectRow.qml",
            "SettingsTextField.qml",
            "SettingsTextArea.qml",
            "SettingsPathField.qml",
            "SettingsBanner.qml",
            "SettingsTooltip.qml",
            "SettingsHelpButton.qml",
            "SettingsStatusBadge.qml",
            "SettingsActionTile.qml",
            "SettingsPreviewCard.qml",
            "SettingsFocusRing.qml",
            "SettingsTabBar.qml",
            "SettingsTabButton.qml",
        }
        self.assertTrue(COMPONENTS_ROOT.is_dir())
        self.assertTrue(expected.issubset({path.name for path in COMPONENTS_ROOT.glob("*.qml")}))

    def test_gallery_has_a_configuration_root_harness(self) -> None:
        harness = (SETTINGS_ROOT / "settings-gallery.qml").read_text(encoding="utf-8")
        self.assertIn("SettingsGallery", harness)
        self.assertIn("visible: true", harness)

    def test_phase_five_uses_new_shell_and_preserves_navigation_contract(self) -> None:
        settings_qml = (SETTINGS_ROOT / "settings.qml").read_text(encoding="utf-8")
        self.assertIn("SettingsShell", settings_qml)
        self.assertNotIn("Key_PageDown", settings_qml)
        self.assertNotIn("Key_PageUp", settings_qml)
        self.assertNotIn("Key_Tab", settings_qml)
        self.assertNotIn("Key_Backtab", settings_qml)

        shell = (COMPONENTS_ROOT / "SettingsShell.qml").read_text(encoding="utf-8")
        for component in ["SettingsNavigation", "SettingsPageHost"]:
            self.assertIn(component, shell)
        for shortcut in ["Key_PageDown", "Key_PageUp", "Key_Tab", "Key_Backtab"]:
            self.assertIn(shortcut, shell)
        self.assertIn("Config.ready", (COMPONENTS_ROOT / "SettingsPageHost.qml").read_text(encoding="utf-8"))

        navigation_item = (COMPONENTS_ROOT / "SettingsNavigationItem.qml").read_text(encoding="utf-8")
        settings_button = (COMPONENTS_ROOT / "SettingsButton.qml").read_text(encoding="utf-8")
        self.assertIn("root.page.iconRotation || 0", navigation_item)
        self.assertIn("rotation: root.iconRotation", settings_button)

    def test_settings_entrypoint_has_no_legacy_shell_components(self) -> None:
        settings_qml = (SETTINGS_ROOT / "settings.qml").read_text(encoding="utf-8")
        for legacy in ["NavigationRail", "RippleButton", "FloatingActionButton", "StyledToolTip"]:
            self.assertNotIn(legacy, settings_qml)

    def test_phase_six_pages_have_no_legacy_component_references(self) -> None:
        legacy_names = re.compile(
            r"\b(?:ContentPage|ContentSection|ContentSubsection|ContentSubsectionLabel|"
            r"ConfigRow|ConfigSwitch|ConfigSpinBox|ConfigSlider|ConfigSelectionArray|"
            r"MaterialTextArea|StyledToolTip|NoticeBox|RippleButtonWithIcon)\b"
        )
        for page in PAGES_ROOT.glob("*.qml"):
            self.assertIsNone(legacy_names.search(page.read_text(encoding="utf-8")), msg=page.name)

    def test_phase_six_pages_use_settings_page_root(self) -> None:
        for page in PAGES_ROOT.glob("*.qml"):
            content = page.read_text(encoding="utf-8")
            self.assertIn("SettingsPage {", content, msg=page.name)

    def test_settings_components_do_not_write_config_options(self) -> None:
        for component in COMPONENTS_ROOT.glob("*.qml"):
            content = component.read_text(encoding="utf-8")
            self.assertNotRegex(content, r"Config\.options[^=\n]*=", msg=component.name)

    def test_preview_and_status_components_guard_edge_states(self) -> None:
        preview = (COMPONENTS_ROOT / "SettingsPreviewCard.qml").read_text(encoding="utf-8")
        badge = (COMPONENTS_ROOT / "SettingsStatusBadge.qml").read_text(encoding="utf-8")
        self.assertIn("Math.max(0.001, root.previewAspectRatio)", preview)
        self.assertIn("colSecondaryContainer", badge)
        self.assertIn("colOnSecondaryContainer", badge)


if __name__ == "__main__":
    unittest.main()
