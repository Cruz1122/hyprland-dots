from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
CURTAIN = ROOT / "config/quickshell/ii/modules/common/aiQuotaPanel/AiQuotaPanelCurtain.qml"
DOCS = ROOT / "docs/ai-quotas.md"


class AiQuotaPanelContractTests(unittest.TestCase):
    """Guard the quota panel fixes: 1080p fit, icon sampling and Grok Bot default."""

    def test_two_quota_rows_fit_below_the_icon(self) -> None:
        source = CURTAIN.read_text()
        # A 1080p card needs roughly 130 px for two wrapped quota rows; the
        # vertical inset buys the extra 32 px without shrinking icons or text.
        self.assertIn("readonly property real cellVerticalInset: 66", source)

    def test_optical_sizing_does_not_scale_the_layered_item(self) -> None:
        source = CURTAIN.read_text()
        # Scaling a layered item resamples its texture with nearest filtering,
        # flattening the glyph tips that sit flush against the trimmed viewBox.
        self.assertNotIn("scale: cell.modelData.scale", source)
        self.assertIn("anchors.centerIn: parent", source)
        self.assertIn("width: parent.width * cell.modelData.scale", source)
        self.assertIn("height: parent.height * cell.modelData.scale", source)
        self.assertIn("layer.smooth: true", source)

    def test_zed_card_shows_grokbot_by_default(self) -> None:
        source = CURTAIN.read_text()
        self.assertIn("property bool altView: true", source)
        self.assertIn(
            'cell.switchable && cell.altView ? "grokbot" : cell.providerId', source)
        self.assertIn(
            '? "Mostrar el límite de Zed" : "Mostrar el límite de Grok Bot"', source)

    def test_docs_describe_the_default_reading(self) -> None:
        docs = " ".join(DOCS.read_text().split())
        self.assertIn(
            "the Zed card shows the **Grok Bot** weekly reading by default", docs)


if __name__ == "__main__":
    unittest.main()
