"""Hardcoded shell animation durations stay counted and can only go down.

"Speed of menus and transitions" and "Reduce motion in the shell"
(appearance.animations) reach an animation only when its duration comes from
an Appearance preset (Appearance.animation.*), Appearance.scaled() or
MotionScale. A literal such as `duration: 300` ignores both settings.

The scanner counts, in config/quickshell/ii/**/*.qml except the waffle family
(retired, it has its own Looks presets), every duration binding or assignment
whose expression holds a nonzero number literal and does not go through
Appearance or MotionScale, unless the line carries `// motion-ok: <reason>`.
Durations that must never scale (endless loops, spinners, clock ticks,
timeouts, hardware writes) carry that marker. Timer intervals are not scanned:
most are timeouts or polling; a timer that waits for an animation reads the
same Appearance preset (Overlay.qml, BottomWidgetGroup.qml).

Separate rules: nobody outside Appearance.qml reads the raw
animationCurves.*Duration constants (they do not scale), and a looping
animation never uses a scaled duration without `motion-ok` (reduceMotion would
turn it into a 1 ms loop). Arithmetic on a preset duration keeps a 1 ms floor
(Math.max(1, ...) or Appearance.scaled()), the Authenticator and AI quota
reveals pass their floors through Appearance.scaled(), and every
SmoothedAnimation in the shell, waffle included, reads a preset velocity or
Appearance.scaledVelocity().
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / "config/quickshell/ii"
EXCLUDED_PARTS = {"waffle"}

# Hardcoded durations left after phase A (A2 migrated the Appearance presets
# and their direct readers only; the plan defers the rest, E15). When you
# migrate a site to Appearance.animation.* / Appearance.scaled(), or mark one
# that must not scale with `// motion-ok: <reason>`, lower this number to the
# new count printed by the failure message. Never raise it: route new motion
# through Appearance instead.
MAX_UNMIGRATED = 55

MARKER = "motion-ok:"
SCALED = re.compile(r"\bAppearance\s*\??\.|\bMotionScale\s*\.|\bscaled(?:Velocity|Interval)?\s*\(")
# An expression derived from another duration (`rippleDuration * 2`) is not
# counted again: the duration it reads is checked where it is declared.
DERIVED = re.compile(r"[\w.]*(?:duration|Duration)\b")
# `duration: <expr>`, `fooDuration: <expr>` (QML bindings and property
# declarations) and `x.duration = <expr>` (imperative assignments).
DURATION = re.compile(
    r"(?:(?<![\w.])(?:duration|[a-z]\w*Duration)\s*:(?!:)|\.duration\s*=(?!=))\s*(?P<expr>[^;}\n]*)")
NUMBER = re.compile(r"(?<![\w.])(?:\d+\.?\d*|\.\d+)(?![\w.])")
RAW_CURVE = re.compile(r"animationCurves\s*\.\s*\w+Duration\b")
LOOPS = re.compile(r"\bloops\s*:")


def strip_comment(line: str) -> str:
    # QML strings with "//" are rare on duration lines; good enough here.
    return line.split("//", 1)[0]


def hardcoded_durations(text: str) -> list[tuple[int, str]]:
    """(line number, line) of each duration that ignores the shell motion settings."""
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        if MARKER in line:
            continue
        code = strip_comment(line)
        for match in DURATION.finditer(code):
            expr = match.group("expr")
            literals = [float(n) for n in NUMBER.findall(expr)]
            if not any(literals) or SCALED.search(expr) or DERIVED.search(expr):
                continue
            found.append((number, line.strip()))
            break
    return found


def raw_curve_readers(text: str) -> list[tuple[int, str]]:
    return [(n, line.strip()) for n, line in enumerate(text.splitlines(), 1)
            if RAW_CURVE.search(strip_comment(line)) and not re.search(r"property\s+\w+\s+\w+Duration\s*:", line)]


def block_bounds(text: str, index: int) -> tuple[int, int]:
    """Start and end offsets of the innermost {...} block around `index`."""
    depth = 0
    start = 0
    for i in range(index - 1, -1, -1):
        if text[i] == "}":
            depth += 1
        elif text[i] == "{":
            if depth == 0:
                start = i
                break
            depth -= 1
    depth = 0
    end = len(text)
    for i in range(index, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            if depth == 0:
                end = i
                break
            depth -= 1
    return start, end


def scaled_loops(text: str) -> list[tuple[int, str]]:
    """Scaled durations inside a looping animation without `motion-ok`."""
    found = []
    for match in LOOPS.finditer(text):
        start, end = block_bounds(text, match.start())
        first_line = text.count("\n", 0, start) + 1
        for offset, line in enumerate(text[start:end].splitlines()):
            if MARKER in line:
                continue
            for duration in DURATION.finditer(strip_comment(line)):
                if SCALED.search(duration.group("expr")):
                    found.append((first_line + offset, line.strip()))
    return found


# `Appearance.animation.<preset>.duration` (optionally with `?.`).
PRESET_DURATION = r"Appearance\s*\??\.\s*animation\s*\??\.\s*\w+\s*\??\.\s*duration\b"
PRESET_ARITHMETIC = re.compile(rf"{PRESET_DURATION}\s*[*/]|[*/]\s*{PRESET_DURATION}")
FLOORED = re.compile(r"Math\.max\(\s*1\s*,|\bscaled\s*\(")


def unfloored_preset_arithmetic(text: str) -> list[tuple[int, str]]:
    """A preset duration divided or multiplied without a 1 ms floor.

    Under reduceMotion every preset is 1 ms, so `elementMove.duration / 2`
    rounds to 0 and Qt finishes the animation inside start(). The result must
    be wrapped in Math.max(1, ...) or go through Appearance.scaled().
    """
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        code = strip_comment(line)
        for match in PRESET_ARITHMETIC.finditer(code):
            if not FLOORED.search(code[:match.start()]):
                found.append((number, line.strip()))
                break
    return found


REVEAL_ASSIGNMENT = re.compile(r"revealAnimation\.duration\s*=(?!=)\s*(?P<expr>[^;\n]*)")


def unscaled_reveals(text: str) -> list[tuple[int, str]]:
    """`revealAnimation.duration = ...` whose value (floors included) skips Appearance.scaled()."""
    return [(text.count("\n", 0, m.start()) + 1, m.group(0).strip())
            for m in REVEAL_ASSIGNMENT.finditer(text)
            if not m.group("expr").strip().startswith("Appearance.scaled(")]


SMOOTHED = re.compile(r"\bSmoothedAnimation\s*\{")
VELOCITY = re.compile(r"(?<![\w.])velocity\s*:\s*(?P<expr>[^;}\n]*)")
SCALED_VELOCITY = re.compile(
    r"^(?:Appearance\s*\??\.\s*animation\s*\??\.\s*\w+\s*\??\.\s*velocity|Appearance\.scaledVelocity\s*\()")


def unscaled_velocities(text: str) -> list[tuple[int, str]]:
    """SmoothedAnimation blocks whose velocity ignores the shell motion settings.

    A missing velocity is Qt's fixed default (200), so it is reported too.
    """
    found = []
    for match in SMOOTHED.finditer(text):
        start, end = block_bounds(text, match.end())
        block = text[start:end]
        line = text.count("\n", 0, match.start()) + 1
        velocities = [v for v in VELOCITY.finditer(block)]
        if not velocities:
            found.append((line, "SmoothedAnimation without velocity"))
        for v in velocities:
            if not SCALED_VELOCITY.match(v.group("expr").strip()):
                found.append((text.count("\n", 0, start + v.start()) + 1, v.group(0).strip()))
    return found


def all_shell_files() -> list[Path]:
    """Every shell QML file, waffle included (its velocities share Appearance)."""
    return sorted(SHELL.rglob("*.qml"))


def shell_files() -> list[Path]:
    return sorted(path for path in SHELL.rglob("*.qml")
                  if not EXCLUDED_PARTS.intersection(path.relative_to(SHELL).parts))


def scan(check, files=None) -> list[str]:
    hits = []
    for path in shell_files() if files is None else files:
        for number, line in check(path.read_text(encoding="utf-8")):
            hits.append(f"{path.relative_to(SHELL)}:{number}: {line}")
    return hits


class ScannerSelfTest(unittest.TestCase):
    def test_flags_literal_durations(self) -> None:
        text = "\n".join([
            "NumberAnimation { duration: 300; easing.type: Easing.OutCubic }",
            "    duration: 1000",
            "    duration: 300 / 2",
            "    duration: failed ? 10000 : 1000",
            "    property int rippleDuration: 1200",
            "    highlightMoveDuration: 100",
            "    anim.duration = 250;",
            "    duration: .5",
        ])
        self.assertEqual([n for n, _ in hardcoded_durations(text)], [1, 2, 3, 4, 5, 6, 7, 8])

    def test_ignores_scaled_marked_and_non_literal_durations(self) -> None:
        text = "\n".join([
            "    duration: Appearance.animation.elementMove.duration",
            "    duration: Appearance.animation.elementMove.duration / 2",
            "    duration: Appearance.scaled(300)",
            "    duration: root.scaled(400)",
            "    duration: MotionScale.duration(300, f)",
            "    duration: 12000 // motion-ok: endless spinner",
            "    duration: 0",
            "    duration: root.rippleDuration",
            "    duration: 1000 * root.factor // motion-ok: real time",
            "    // duration: 300 (commented out)",
            "    property int duration",
            "    if (anim.duration == 300) {}",
            "    revealAnimation.duration = Math.max(Appearance.scaled(160), full);",
            "    durationLabel: 300",
            "    duration: Appearance?.animation.elementMoveFast.duration ?? 200",
            "    duration: rippleDuration * 2",
            "    width: 300",
        ])
        self.assertEqual(hardcoded_durations(text), [])

    def test_raw_curve_readers(self) -> None:
        self.assertEqual(len(raw_curve_readers("duration: Appearance.animationCurves.expressiveFastSpatialDuration")), 1)
        self.assertEqual(raw_curve_readers("readonly property real expressiveFastSpatialDuration: 350"), [])
        self.assertEqual(raw_curve_readers("easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial"), [])

    def test_loop_rule(self) -> None:
        bad = "RotationAnimation {\n    loops: Animation.Infinite\n    duration: Appearance.animation.elementMove.duration\n}\n"
        self.assertEqual([n for n, _ in scaled_loops(bad)], [3])
        marked = bad.replace(".duration\n", ".duration // motion-ok: test\n")
        self.assertEqual(scaled_loops(marked), [])
        nested = ("SequentialAnimation {\n    loops: 2\n    NumberAnimation { duration: 300 }\n"
                  "    NumberAnimation { duration: Appearance.scaled(300) }\n}\n"
                  "NumberAnimation { duration: Appearance.scaled(300) }\n")
        self.assertEqual([n for n, _ in scaled_loops(nested)], [4])

    def test_preset_arithmetic_rule(self) -> None:
        text = "\n".join([
            "    duration: Appearance.animation.elementMove.duration / 2",
            "    interval: Appearance?.animation.elementMove.duration * 0.5",
            "    duration: 2 * Appearance.animation.elementMoveFast.duration",
            "    readonly property int half: Math.max(1, Math.round(Appearance.animation.elementMove.duration / 2))",
            "    duration: Appearance.scaled(Appearance.animation.elementMove.duration / 2)",
            "    duration: Appearance.animation.elementMove.duration",
            "    // duration: Appearance.animation.elementMove.duration / 2",
            "    duration: Math.max(10, Appearance.animation.elementMove.duration / 2)",
        ])
        self.assertEqual([n for n, _ in unfloored_preset_arithmetic(text)], [1, 2, 3, 8])

    def test_reveal_rule(self) -> None:
        head = "revealAnimation.duration = Math.max(160, fullDuration * Math.abs(to - p));"
        fixed = "revealAnimation.duration = Appearance.scaled(Math.max(160, fullDuration * Math.abs(to - p)));"
        self.assertEqual(len(unscaled_reveals(head)), 1)
        self.assertEqual(unscaled_reveals(fixed), [])
        self.assertEqual(unscaled_reveals("if (revealAnimation.duration == 1) {}"), [])

    def test_velocity_rule(self) -> None:
        good = "\n".join([
            "SmoothedAnimation {",
            "    velocity: Appearance.animation.elementMoveFast.velocity",
            "}",
            "SmoothedAnimation { velocity: Appearance.scaledVelocity(Looks.transition.velocity) }",
        ])
        self.assertEqual(unscaled_velocities(good), [])
        bad = "\n".join([
            "SmoothedAnimation {",
            "    velocity: Looks.transition.velocity",
            "}",
            "SmoothedAnimation { velocity: 400 }",
            "SmoothedAnimation { duration: 200 }",
        ])
        self.assertEqual([n for n, _ in unscaled_velocities(bad)], [2, 4, 5])

    def test_waffle_is_excluded(self) -> None:
        files = shell_files()
        self.assertTrue(files)
        self.assertFalse([p for p in files if "waffle" in p.relative_to(SHELL).parts])
        self.assertIn(SHELL / "modules/common/Appearance.qml", files)


class MotionContractTest(unittest.TestCase):
    def test_hardcoded_durations_do_not_grow(self) -> None:
        hits = scan(hardcoded_durations)
        self.assertLessEqual(
            len(hits), MAX_UNMIGRATED,
            f"{len(hits)} hardcoded animation durations (limit {MAX_UNMIGRATED}). Route new motion through "
            "Appearance.animation.* or Appearance.scaled(), or mark a duration that must not scale with "
            "'// motion-ok: <reason>'. Sites:\n" + "\n".join(hits))
        if len(hits) < MAX_UNMIGRATED:
            print(f"\ntest_motion_contract: {len(hits)} hardcoded durations; lower MAX_UNMIGRATED "
                  f"from {MAX_UNMIGRATED} to {len(hits)}.")

    def test_raw_curve_durations_are_only_read_by_appearance(self) -> None:
        hits = [hit for hit in scan(raw_curve_readers) if not hit.startswith("modules/common/Appearance.qml:")]
        self.assertEqual(hits, [], "read Appearance.animation.<preset>.duration instead (it scales)")

    def test_loops_never_scale(self) -> None:
        self.assertEqual(scan(scaled_loops), [])

    def test_preset_arithmetic_keeps_a_floor(self) -> None:
        self.assertEqual(scan(unfloored_preset_arithmetic, all_shell_files()), [],
                         "wrap the result in Math.max(1, ...) or Appearance.scaled(): a 0 ms "
                         "duration finishes inside start() under reduceMotion")

    def test_panel_reveals_scale_their_floors(self) -> None:
        for relative in ("modules/common/authenticator/Authenticator.qml",
                         "modules/common/aiQuotaPanel/AiQuotaPanel.qml"):
            text = (SHELL / relative).read_text(encoding="utf-8")
            with self.subTest(relative):
                self.assertTrue(REVEAL_ASSIGNMENT.search(text), "revealAnimation.duration assignment not found")
                self.assertEqual(unscaled_reveals(text), [])

    def test_smoothed_velocities_scale(self) -> None:
        files = all_shell_files()
        self.assertTrue([p for p in files if "waffle" in p.relative_to(SHELL).parts])
        self.assertEqual(scan(unscaled_velocities, files), [])

    def test_appearance_reads_both_settings(self) -> None:
        appearance = (SHELL / "modules/common/Appearance.qml").read_text(encoding="utf-8")
        self.assertIn("appearance?.animations?.durationScale", appearance)
        self.assertIn("appearance?.animations?.reduceMotion", appearance)
        self.assertIn('import "functions/MotionScale.js" as MotionScale', appearance)
        presets = re.findall(r"property int duration: (.+)", appearance)
        self.assertEqual(len(presets), 9, presets)
        for expr in presets:
            self.assertTrue(expr.startswith("root.scaled("), expr)
        velocities = re.findall(r"property \w+ velocity: (.+)", appearance)
        self.assertEqual(len(velocities), 7, velocities)
        for expr in velocities:
            self.assertTrue(expr.startswith("root.scaledVelocity("), expr)


if __name__ == "__main__":
    unittest.main()
