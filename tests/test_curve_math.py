"""Golden values of the Hyprland curve math (tests/curve_reference.py).

The fixture tests/fixtures/curve-golden.json is generated, never hand-edited:
    python3 tests/curve_reference.py --write
This test fails when the fixture drifts from the reference, and runs
tests/qml_settings/tst_CurveMath.qml, which checks CurveMath.js against it.
"""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QMLTESTRUNNER = Path("/usr/lib/qt6/bin/qmltestrunner")
QML_TEST = ROOT / "tests/qml_settings/tst_CurveMath.qml"

_spec = importlib.util.spec_from_file_location("curve_reference", ROOT / "tests/curve_reference.py")
ref = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ref)

DOTFILES_CURVES = {"expressiveFastSpatial", "expressiveSlowSpatial", "expressiveDefaultSpatial", "emphasizedDecel",
                   "emphasizedAccel", "standardDecel", "menu_decel", "menu_accel", "stall"}


def exact_bezier_y(points: list[float], x: float) -> float:
    """y of the cubic at x, solving x(t) = x by bisection (x must be monotonic)."""
    low, high = 0.0, 1.0
    for _ in range(200):
        mid = (low + high) / 2
        if ref.cubic(mid, 0, points[0], points[2], 1) < x:
            low = mid
        else:
            high = mid
    return ref.cubic((low + high) / 2, 0, points[1], points[3], 1)


class CurveGoldenTest(unittest.TestCase):
    def test_fixture_matches_the_reference(self) -> None:
        self.assertEqual(ref.FIXTURE.read_text(encoding="utf-8"), ref.render(),
                         "curve-golden.json is stale: run python3 tests/curve_reference.py --write")

    def test_fixture_covers_the_required_curves(self) -> None:
        golden = json.loads(ref.FIXTURE.read_text(encoding="utf-8"))
        self.assertTrue({"default", "linear"} | DOTFILES_CURVES <= set(golden["beziers"]))
        self.assertTrue({"ii_spring_soft", "ii_spring_bouncy"} <= set(golden["springs"]))
        self.assertEqual(golden["beziers"]["emphasizedDecel"]["points"], [0.05, 0.7, 0.1, 1])

    def test_dotfiles_curves_come_from_general_lua(self) -> None:
        parsed = ref.dotfiles_beziers(ref.GENERAL_LUA.read_text(encoding="utf-8"))
        self.assertEqual(set(parsed), DOTFILES_CURVES)

    def test_bezier_lookup_stays_close_to_the_exact_curve(self) -> None:
        for name, points in {**ref.BUILTIN_BEZIERS, **ref.dotfiles_beziers(ref.GENERAL_LUA.read_text())}.items():
            curve = ref.Bezier(points)
            for i in range(1, 100):
                x = i / 100
                with self.subTest(curve=name, x=x):
                    self.assertAlmostEqual(curve.y_for_point(x), exact_bezier_y(points, x), delta=0.02)
        linear = ref.Bezier([0, 0, 1, 1])
        for x in (0.001, 0.25, 0.5, 0.9):
            self.assertAlmostEqual(linear.y_for_point(x), x, places=12)

    def test_bezier_ends_are_exact(self) -> None:
        curve = ref.Bezier([0.5, -1, 0.5, 2])
        self.assertEqual(curve.y_for_point(0), 0)
        self.assertEqual(curve.y_for_point(-1), 0)
        self.assertEqual(curve.y_for_point(1), 1)
        self.assertEqual(curve.y_for_point(2), 1)

    def test_spring_position_does_not_depend_on_the_tick_rate(self) -> None:
        for spring in ref.SPRINGS.values():
            for t in (16.667, 100, 333, 500):
                one_step = ref.spring_progress(spring, t)
                for tick in (1, 1000 / 60, 1000 / 144):
                    with self.subTest(spring=spring, t=t, tick=tick):
                        self.assertAlmostEqual(ref.spring_progress_stepped(spring, t, tick), one_step, places=9)

    def test_app_spring_settle_times(self) -> None:
        # Hyprland ends the animation when |1 - value| and |velocity| both
        # drop to 0.001; the visible motion is over much earlier (the
        # contract's ~330/~440 ms are the 4/gamma envelope estimate).
        self.assertEqual(ref.spring_settle_ms(ref.SPRINGS["ii_spring_soft"]), 647)
        self.assertEqual(ref.spring_settle_ms(ref.SPRINGS["ii_spring_bouncy"]), 924)
        bouncy = ref.SPRINGS["ii_spring_bouncy"]
        self.assertGreater(max(ref.spring_progress(bouncy, t) for t in range(0, 900)), 1.1)

    def test_qml_port_matches_the_fixture(self) -> None:
        if not QMLTESTRUNNER.is_file():
            self.skipTest(f"Qt 6 qmltestrunner not found at {QMLTESTRUNNER}")
        result = subprocess.run(
            [str(QMLTESTRUNNER), "-input", str(QML_TEST)],
            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QML_XHR_ALLOW_FILE_READ": "1"},
            capture_output=True, text=True, timeout=120,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn(", 0 failed, 0 skipped", output)


if __name__ == "__main__":
    unittest.main()
