import importlib.util
import base64
import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path
from urllib.parse import unquote
import xml.etree.ElementTree as ET


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "config/quickshell/ii/scripts/grok-roster.py"
TEMPLATE_DIR = ROOT / "config/quickshell/ii/assets/grok-avatar-templates"
ANIMATION_DIR = ROOT / "config/quickshell/ii/assets/grok-avatar-animations"
DENSE_ANIMATION_DIR = ROOT / "config/quickshell/ii/assets/grok-avatar-animations-interpolated"
AVATAR_QML = ROOT / "config/quickshell/ii/modules/common/widgets/GrokAvatar.qml"
MOTION_CACHE_QML = ROOT / "config/quickshell/ii/modules/common/GrokAvatarMotionCache.qml"
BAR_PREVIEW_QML = ROOT / "config/quickshell/ii/modules/ii/bar/GrokUnreadPreview.qml"
NATIVE_ANIMATION_STATES = (
    "neutral", "attentive", "surprised", "excited", "happy", "laughing",
    "angry", "sad", "scared", "suspicious", "confused", "curious",
    "proud", "shy", "unimpressed", "sleepy",
)
SPEC = importlib.util.spec_from_file_location("grok_roster", SCRIPT)
assert SPEC and SPEC.loader
grok_roster = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(grok_roster)


class GrokRosterTests(unittest.TestCase):
    def write_blob(self, directory: Path, name: str, payload: object) -> Path:
        path = directory / name
        path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        return path

    def test_missing_or_irrelevant_directory_is_unavailable(self):
        with tempfile.TemporaryDirectory() as temp:
            snapshot = grok_roster.read_snapshot(Path(temp) / "missing")
        self.assertEqual(snapshot, {"available": False, "bots": []})

    def test_latest_valid_roster_wins_and_sensitive_fields_are_removed(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            self.write_blob(directory, "damaged.blob", "not json")
            self.write_blob(directory, "other.blob", {"schemaVersion": 1, "value": {"sections": []}})
            older = self.write_blob(
                directory,
                "older.blob",
                {"schemaVersion": 4, "value": {"rows": [{"id": "861e7ebb-7152-4967-8c4a-3b8336fdc094", "name": "Old", "hasUnread": False}] }},
            )
            newer = self.write_blob(
                directory,
                "newer.blob",
                {
                    "schemaVersion": 4,
                    "value": {
                        "rows": [
                            {
                                "id": "861e7ebb-7152-4967-8c4a-3b8336fdc094",
                                "name": "Alfredo ñ",
                                "description": "private prompt",
                                "path": "/private/store.db",
                                "avatarShape": "cloud",
                                "avatarColor": "blue",
                                "hasUnread": False,
                                "unreadCount": "2",
                                "lastActivityAt": 42,
                                "lastEntry": {"kind": "text", "text": "Mensaje ✅\ncon segunda línea"},
                            },
                            {
                                "id": "not-a-uuid",
                                "name": "Should not leak",
                                "hasUnread": True,
                            },
                        ]
                    },
                },
            )
            os.utime(older, (1, 1))
            os.utime(newer, (2, 2))

            snapshot = grok_roster.read_snapshot(directory)

        self.assertTrue(snapshot["available"])
        self.assertEqual(len(snapshot["bots"]), 1)
        bot = snapshot["bots"][0]
        self.assertEqual(bot["name"], "Alfredo ñ")
        self.assertTrue(bot["hasUnread"])
        self.assertEqual(bot["unreadCount"], 2)
        self.assertEqual(bot["preview"], "Mensaje ✅\ncon segunda línea")
        self.assertTrue(bot["avatarSvg"].startswith("data:image/svg+xml,"))
        self.assertIn("%23", bot["avatarSvg"])
        self.assertNotIn("description", bot)
        self.assertNotIn("path", bot)
        self.assertNotIn("private prompt", json.dumps(snapshot))

    def test_non_text_entry_and_inconsistent_counters_are_safe(self):
        with tempfile.TemporaryDirectory() as temp:
            self.write_blob(
                Path(temp),
                "roster.blob",
                {
                    "schemaVersion": 3,
                    "value": {
                        "rows": [
                            {
                                "id": "861e7ebb-7152-4967-8c4a-3b8336fdc094",
                                "name": "Bot",
                                "hasUnread": False,
                                "unreadCount": -99,
                                "lastEntry": {"kind": "image", "url": "/private"},
                            }
                        ]
                    },
                },
            )
            bot = grok_roster.read_snapshot(Path(temp))["bots"][0]
        self.assertFalse(bot["hasUnread"])
        self.assertEqual(bot["unreadCount"], 0)
        self.assertEqual(bot["entryKind"], "image")
        self.assertEqual(bot["preview"], "")

    def test_string_false_does_not_create_a_phantom_unread(self):
        with tempfile.TemporaryDirectory() as temp:
            self.write_blob(
                Path(temp),
                "roster.blob",
                {
                    "schemaVersion": 4,
                    "value": {
                        "rows": [
                            {
                                "id": "861e7ebb-7152-4967-8c4a-3b8336fdc094",
                                "name": "Bot",
                                "hasUnread": "false",
                                "unreadCount": 0,
                            }
                        ]
                    },
                },
            )
            bot = grok_roster.read_snapshot(Path(temp))["bots"][0]
        self.assertFalse(bot["hasUnread"])

    def test_only_valid_inline_avatar_images_are_forwarded(self):
        valid = "data:image/png;base64," + base64.b64encode(b"png-bytes").decode()
        with tempfile.TemporaryDirectory() as temp:
            self.write_blob(
                Path(temp),
                "roster.blob",
                {
                    "schemaVersion": 4,
                    "value": {
                        "rows": [
                            {
                                "id": "861e7ebb-7152-4967-8c4a-3b8336fdc094",
                                "name": "Photo bot",
                                "avatarPhoto": valid,
                            },
                            {
                                "id": "9c0e1b2b-29d5-4788-9293-f161357b116b",
                                "name": "Remote bot",
                                "avatarPhoto": "https://private.example/avatar.png",
                                "avatarDataUrl": "data:image/png;base64,not base64!",
                            },
                        ]
                    },
                },
            )
            bots = grok_roster.read_snapshot(Path(temp))["bots"]

        self.assertEqual(bots[0]["avatarPhoto"], valid)
        self.assertEqual(bots[0]["avatarSvg"], "")
        self.assertEqual(bots[1]["avatarPhoto"], "")

    def test_grok_renderer_avatar_is_not_an_application_icon(self):
        with tempfile.TemporaryDirectory() as temp:
            self.write_blob(
                Path(temp),
                "roster.blob",
                {
                    "schemaVersion": 4,
                    "value": {
                        "rows": [
                            {
                                "id": "861e7ebb-7152-4967-8c4a-3b8336fdc094",
                                "name": "Alfredo",
                                "avatarShape": "cloud",
                                "avatarColor": "blue",
                            }
                        ]
                    },
                },
            )
            bot = grok_roster.read_snapshot(Path(temp))["bots"][0]
        self.assertTrue(bot["avatarSvg"].startswith("data:image/svg+xml,"))
        self.assertNotIn("grok-bot.png", bot["avatarSvg"])
        self.assertNotIn("NotificationAppIcon", bot["avatarSvg"])
        template = unquote((TEMPLATE_DIR / "cloud.svg.tmpl").read_text(encoding="ascii").strip())
        style_start = template.index("<style>")
        style_end = template.index("</style>", style_start) + len("</style>")
        template = template[:style_start] + template[style_end:]
        for field, ink in (("avatarSvg", "#2a92fe"), ("avatarSvgDark", "#0e74e0")):
            with self.subTest(field=field):
                svg = unquote(bot[field].split(",", 1)[1])
                expected = template.replace("var(--grok-bot-still-ink)", ink)
                self.assertEqual(svg, expected)
                self.assertIn(f'fill="{ink}"', svg)
                self.assertNotIn("var(--grok-bot-still-ink)", svg)
                self.assertNotIn("<style>", svg)

    def test_missing_avatar_metadata_gets_stable_grok_style_fallbacks(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            self.write_blob(
                directory,
                "roster.blob",
                {
                    "schemaVersion": 4,
                    "value": {
                        "rows": [
                            {
                                "id": "861e7ebb-7152-4967-8c4a-3b8336fdc094",
                                "name": "Partial avatar",
                                "avatarShape": "blob",
                            },
                            {
                                "id": "9c0e1b2b-29d5-4788-9293-f161357b116b",
                                "name": "Missing avatar",
                            },
                        ]
                    },
                },
            )
            first = grok_roster.read_snapshot(directory)["bots"]
            second = grok_roster.read_snapshot(directory)["bots"]

        self.assertEqual(first, second)
        for bot in first:
            with self.subTest(bot=bot["name"]):
                self.assertIn(bot["avatarShape"], grok_roster.ALLOWED_SHAPES)
                self.assertIn(bot["avatarColor"], grok_roster.ALLOWED_COLORS)
                self.assertTrue(bot["avatarSvg"].startswith("data:image/svg+xml,"))
                self.assertTrue(bot["avatarSvgDark"].startswith("data:image/svg+xml,"))
        self.assertEqual(first[0]["avatarShape"], "blob")
        self.assertEqual(first[0]["avatarColor"], "magenta")
        self.assertEqual(first[1]["avatarShape"], "squircle")
        self.assertEqual(first[1]["avatarColor"], "blue")
        self.assertNotEqual(
            (first[0]["avatarShape"], first[0]["avatarColor"]),
            (first[1]["avatarShape"], first[1]["avatarColor"]),
        )

    def test_id_defaults_match_grok_bot_0712_reference_vectors(self):
        # These are hard-coded outputs from BN/Iy and hb/j1 in the 0.71.2
        # bundle, not values generated by the bridge's implementation.
        expected = {
            "861e7ebb-7152-4967-8c4a-3b8336fdc094": ("teardrop", "magenta"),
            "9c0e1b2b-29d5-4788-9293-f161357b116b": ("squircle", "blue"),
            "00000000-0000-4000-8000-000000000000": ("wedge", "orange"),
        }
        self.assertEqual(
            grok_roster.GROK_DEFAULT_SHAPES,
            ("blob", "pebble", "squircle", "tablet", "wedge", "hex", "cloud", "teardrop"),
        )
        self.assertEqual(
            grok_roster.GROK_DEFAULT_COLORS,
            ("brown", "red", "orange", "yellow", "green", "cyan", "blue", "violet", "magenta", "gray"),
        )
        for bot_id, style in expected.items():
            with self.subTest(bot_id=bot_id):
                self.assertEqual(grok_roster._avatar_style(bot_id, "", ""), style)
                self.assertEqual(grok_roster._avatar_style(bot_id, "blob", ""), ("blob", style[1]))
                self.assertEqual(grok_roster._avatar_style(bot_id, "", "black"), (style[0], "black"))

    def test_renderer_uses_groks_exact_zf_ink_palette(self):
        expected = {
            "black": ("000000", "FFFFFF"),
            "brown": ("a27952", "855c36"),
            "red": ("ff3e51", "e02135"),
            "orange": ("ff781c", "ff6700"),
            "yellow": ("ffaf38", "ff9800"),
            "green": ("00c972", "009957"),
            "cyan": ("1cc3b0", "00a592"),
            "blue": ("2a92fe", "0e74e0"),
            "violet": ("a97efe", "804ee0"),
            "magenta": ("ff5eb1", "e02a88"),
            "gray": ("959595", "777777"),
        }
        self.assertEqual(grok_roster.GROK_INK, expected)
        palette = json.loads((TEMPLATE_DIR / "palette.json").read_text(encoding="utf-8"))
        self.assertEqual(
            {name: tuple(color.lower() for color in pair) for name, pair in palette.items()},
            {name: tuple(color.lower() for color in pair) for name, pair in expected.items()},
        )

    def test_original_grok_svg_template_exists_for_every_supported_shape(self):
        templates = {path.name.removesuffix(".svg.tmpl") for path in TEMPLATE_DIR.glob("*.svg.tmpl")}
        self.assertEqual(templates, grok_roster.ALLOWED_SHAPES)

        for shape in sorted(grok_roster.ALLOWED_SHAPES):
            with self.subTest(shape=shape):
                template = unquote((TEMPLATE_DIR / f"{shape}.svg.tmpl").read_text(encoding="ascii").strip())
                svg = ET.fromstring(template)
                self.assertEqual(svg.tag.rsplit("}", 1)[-1], "svg")
                self.assertGreater(len(svg.findall(".//{*}path")), 0)
                self.assertIn("__LIGHT__", template)
                self.assertIn("__DARK__", template)
                self.assertEqual(len(svg.findall(".//{*}svg")), 0)

    def test_unread_bar_shows_only_each_bot_avatar_and_its_count(self):
        qml = BAR_PREVIEW_QML.read_text(encoding="utf-8")
        self.assertIn("model: root.unreadBots", qml)
        self.assertIn("GrokAvatar", qml)
        self.assertIn("modelData.unreadCount", qml)
        self.assertIn("Accessible.name", qml)
        self.assertIn("onClicked: GrokBots.openBot(modelData.id)", qml)
        self.assertIn("hoverEnabled: true", qml)
        self.assertIn("cursorShape: Qt.PointingHandCursor", qml)
        self.assertIn("property real interactionScale", qml)
        self.assertIn("property real introScale", qml)
        self.assertIn("Behavior on scale", qml)
        self.assertNotIn("animateEyes", qml)
        self.assertNotIn("eyeCutoutColor", qml)
        self.assertNotIn("modelData.preview", qml)
        self.assertNotIn("latestUnread", qml)
        self.assertIn("background: Item {}", qml)

    def test_qml_uses_white_circular_default_without_app_icon(self):
        qml = AVATAR_QML.read_text(encoding="utf-8")
        self.assertIn("import Qt5Compat.GraphicalEffects", qml)
        self.assertNotIn("MaterialShape", qml)
        self.assertNotIn("NotificationAppIcon", qml)
        self.assertIn("Appearance.m3colors.darkmode", qml)
        self.assertIn("bot?.avatarSvgDark", qml)
        self.assertIn("nativeAnimationAvailable", qml)
        self.assertIn("nativeAnimationFrameCount", qml)
        self.assertIn("nativeAnimationState", qml)
        self.assertIn("nativeAnimationStateKey", qml)
        self.assertIn("nativeAnimationDirection", qml)
        self.assertIn("nativeAnimationVisualScale: 1.45", qml)
        self.assertIn('visible: Appearance.m3colors.darkmode && root.avatarColor === "black"', qml)
        self.assertIn('color: "#FFFFFF"', qml)
        for key in (
            "blob-violet",
            "heart-red",
            "sparkle-magenta",
            "teardrop-black",
            "hex-green",
            "star-yellow",
            "cloud-blue",
            "tablet-violet",
        ):
            self.assertIn(f'"{key}"', qml)
        for state in NATIVE_ANIMATION_STATES:
            self.assertIn(f'"{state}"', qml)
        self.assertNotIn("SequentialAnimation", qml)
        self.assertIn("nativeAnimationFrameCount: GrokAvatarMotionCache.frameCount", qml)
        self.assertIn("nativeAnimationFrameInterval: GrokAvatarMotionCache.frameIntervalMs", qml)
        self.assertNotIn("nativeAnimationSupersample", qml)
        self.assertNotIn("nativeAnimationPreloader", qml)
        self.assertIn("GrokAvatarMotionCache", qml)
        self.assertIn("nativeAnimationTextureSize", qml)
        self.assertIn("nativeAnimationPhaseOffset", qml)
        self.assertIn("nativeAnimationPhaseStep", qml)
        self.assertIn("nativeAnimationCycleStepCount", qml)
        self.assertIn("currentCycleStep", qml)
        self.assertIn("nativeAnimationClockOwner", qml)
        self.assertIn("FrameAnimation", qml)
        self.assertIn("registerClock", qml)
        self.assertIn("updateClock", qml)
        self.assertIn("nativeAnimationTransitionFromStateKey", qml)
        self.assertIn("nativeAnimationTransitionToStateKey", qml)
        self.assertIn("nativeAnimationTransitionOpacity", qml)
        self.assertIn("nativeAnimationTransitionAnimation", qml)
        self.assertIn("duration: 220", qml)
        self.assertIn("sourceSize: Qt.size", qml)
        self.assertIn("mipmap: false", qml)
        self.assertIn("Easing.OutCubic", qml)
        self.assertIn("nativeAnimationFrameSource", qml)
        self.assertIn("retainWhileLoading: true", qml)
        self.assertIn("source: root.avatarSvg", qml)
        self.assertIn(
            'visible: root.avatarPhoto.length === 0 && !root.nativeAnimationAvailable && root.avatarSvg.length === 0',
            qml,
        )
        self.assertIn("radius: width / 2", qml)
        self.assertIn('color: "#FFFFFF"', qml)
        self.assertNotIn("animateEyes", qml)
        self.assertNotIn("eyeLayouts", qml)
        self.assertNotIn("gazeX", qml)
        self.assertNotIn("blinkScale", qml)

        cache_qml = MOTION_CACHE_QML.read_text(encoding="utf-8")
        self.assertIn("pragma Singleton", cache_qml)
        self.assertNotIn("\n    FrameAnimation {", cache_qml)
        self.assertIn("clockOwner", cache_qml)
        self.assertIn("activeAvatarCount", cache_qml)
        self.assertIn("registerAvatar", cache_qml)
        self.assertIn("unregisterAvatar", cache_qml)
        self.assertIn("registerClock", cache_qml)
        self.assertIn("unregisterClock", cache_qml)
        self.assertIn("updateClock", cache_qml)
        self.assertIn("textureSize: 112", cache_qml)
        self.assertIn("frameCount: 181", cache_qml)
        self.assertIn("frameIntervalMs: 25", cache_qml)
        self.assertIn("currentCycleStep", cache_qml)
        self.assertIn("lastClockFrameStep", cache_qml)
        self.assertIn("FrameAnimation is compositor-synchronised", cache_qml)
        self.assertIn("grok-avatar-animations-interpolated", cache_qml)
        self.assertIn("/${stateKey}/frame-", cache_qml)
        self.assertNotIn("requestedSequences", cache_qml)
        self.assertNotIn("ensureSequence", cache_qml)

    def test_interpolated_motion_assets_preserve_keyframes(self):
        sequences = sorted(path for path in DENSE_ANIMATION_DIR.glob("*/*") if path.is_dir())
        self.assertEqual(len(sequences), 128)
        for sequence in sequences:
            with self.subTest(sequence=sequence.relative_to(DENSE_ANIMATION_DIR)):
                frames = sorted(sequence.glob("frame-*.svg"))
                self.assertEqual(len(frames), 181)
                relative = sequence.relative_to(DENSE_ANIMATION_DIR)
                native_sequence = ANIMATION_DIR / relative
                for native_index in range(46):
                    dense = sequence / f"frame-{native_index * 4:03d}.svg"
                    native = native_sequence / f"frame-{native_index:03d}.svg"
                    self.assertEqual(dense.read_bytes(), native.read_bytes())
                for dense_index in (1, 2, 3, 90, 179):
                    parsed = ET.fromstring((sequence / f"frame-{dense_index:03d}.svg").read_text(encoding="utf-8"))
                    self.assertEqual(parsed.tag.rsplit("}", 1)[-1], "svg")
                    self.assertGreater(len(parsed.findall(".//{*}path")), 0)

        bar_qml = BAR_PREVIEW_QML.read_text(encoding="utf-8")
        self.assertIn('nativeAnimationState: botButton.down', bar_qml)
        self.assertIn('"excited"', bar_qml)
        self.assertIn('"curious"', bar_qml)

        notification_qml = (ROOT / "config/quickshell/ii/modules/common/widgets/NotificationGroup.qml").read_text(
            encoding="utf-8"
        )
        self.assertIn('root.bot?.avatarShape === "teardrop"', notification_qml)
        self.assertIn('root.bot?.avatarColor === "black"', notification_qml)
        self.assertIn('root.bot?.avatarShape === "tablet"', notification_qml)
        self.assertIn('root.bot?.avatarColor === "violet"', notification_qml)
        self.assertIn(') ? "curious" : "neutral"', notification_qml)
        self.assertNotIn('nativeAnimationState: root.containsMouse ? "attentive" : "neutral"', notification_qml)

    def test_native_motion_assets_are_vector_sequences_from_grok(self):
        expected = {
            "blob-violet": "#a97efe",
            "heart-red": "#ff3e51",
            "sparkle-magenta": "#ff5eb1",
            "teardrop-black": "#000000",
            "hex-green": "#00c972",
            "star-yellow": "#ffaf38",
            "cloud-blue": "#2a92fe",
            "tablet-violet": "#a97efe",
        }
        for key, ink in expected.items():
            dynamic_states = 0
            for state in NATIVE_ANIMATION_STATES:
                with self.subTest(key=key, state=state):
                    frames = sorted((ANIMATION_DIR / key / state).glob("frame-*.svg"))
                    self.assertEqual(len(frames), 46)
                    self.assertEqual([frame.name for frame in frames], [f"frame-{index:03d}.svg" for index in range(46)])
                    hashes = set()
                    for frame in frames:
                        svg = frame.read_text(encoding="utf-8")
                        parsed = ET.fromstring(svg)
                        self.assertEqual(parsed.tag.rsplit("}", 1)[-1], "svg")
                        self.assertGreater(len(parsed.findall(".//{*}path")), 0)
                        self.assertIn(f'fill="{ink}"', svg)
                        self.assertNotIn("var(--grok-bot-ink)", svg)
                        self.assertNotIn("<style>", svg)
                        self.assertNotIn("data:image", svg)
                        hashes.add(hashlib.sha256(svg.encode("utf-8")).digest())
                    # Some native reaction recipes intentionally settle on a
                    # still expression before their one-shot finishes.
                    if len(hashes) > 1:
                        dynamic_states += 1
            self.assertGreater(dynamic_states, 1)


if __name__ == "__main__":
    unittest.main()
