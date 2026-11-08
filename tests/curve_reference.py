#!/usr/bin/env python3
"""Independent Python port of Hyprland's curve math, for golden values.

Ported straight from hyprutils v0.14.3 (src/animation/BezierCurve.cpp,
Spring.cpp and AnimatedVariable.cpp), not from CurveMath.js, so the two ports
check each other. hyprutils uses 32-bit floats; both ports use doubles with
the same operation order.

Regenerate the fixture after changing the cases below or the curves in
config/hypr/hyprland/general.lua:

    python3 tests/curve_reference.py --write

tests/test_curve_math.py fails when tests/fixtures/curve-golden.json differs
from this script's output, and tests/qml_settings/tst_CurveMath.qml checks
CurveMath.js against the fixture.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/curve-golden.json"
GENERAL_LUA = ROOT / "config/hypr/hyprland/general.lua"

BAKED_POINTS = 255
SPRING_TICK_MS = 1
SPRING_MAX_MS = 10000
SPRING_VALUE_EPSILON = 0.001
SPRING_VELOCITY_EPSILON = 0.001

# Inputs: Hyprland built-ins, the two app springs and edge cases. The
# dotfiles curves are read from general.lua.
BUILTIN_BEZIERS = {"default": [0, 0.75, 0.15, 1], "linear": [0, 0, 1, 1]}
EDGE_BEZIERS = {
    "edge_overshoot": [0.5, -1, 0.5, 2],
    "edge_x_bounds": [0, 2, 1, -1],
    "edge_steep_start": [0, 1, 0, 1],
    "edge_steep_end": [1, 0, 1, 0],
    "edge_flat_step": [1, 0, 0, 1],
}
SPRINGS = {
    "ii_spring_soft": {"mass": 1, "stiffness": 238.1191, "damping": 24.21279333},
    "ii_spring_bouncy": {"mass": 1, "stiffness": 260, "damping": 18},
    "hyprutils_default": {"mass": 1, "stiffness": 250, "damping": 25},
    "edge_critical": {"mass": 1, "stiffness": 100, "damping": 20},
    "edge_overdamped": {"mass": 1, "stiffness": 100, "damping": 40},
}
BEZIER_XS = [-0.5, 0, 1e-6, 0.001, 0.003, 0.01, 0.02, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.333, 0.4, 0.5,
             0.6, 0.7, 0.75, 0.8, 0.9, 0.95, 0.99, 0.999, 0.999999, 1, 1.5]
SPRING_TS = [-5, 0, 0.5, 1, 2, 5, 10, 16.667, 33.333, 50, 75, 100, 150, 200, 250, 300, 350, 400, 500, 600,
             700, 800, 900, 1000, 1500]
SAMPLE_N = 9


def cubic(t: float, p0: float, p1: float, p2: float, p3: float) -> float:
    t2 = t * t
    t3 = t2 * t
    return ((1 - t) * (1 - t) * (1 - t) * p0) + (3 * t * (1 - t) * (1 - t) * p1) + (3 * t2 * (1 - t) * p2) + (t3 * p3)


class Bezier:
    """CBezierCurve with setup(): control points (0,0) p1 p2 (1,1)."""

    def __init__(self, points: list[float]) -> None:
        x1, y1, x2, y2 = points
        self.baked = []
        for i in range(BAKED_POINTS):
            t = (i + 1) * (1 / BAKED_POINTS)
            self.baked.append((cubic(t, 0, x1, x2, 1), cubic(t, 0, y1, y2, 1)))

    def y_for_point(self, x: float) -> float:
        if x >= 1:
            return 1.0
        if x <= 0:
            return 0.0
        index = 0
        below = True
        step = (BAKED_POINTS + 1) // 2
        while step > 0:
            index += step if below else -step
            index = min(max(index, 0), BAKED_POINTS - 1)
            below = self.baked[index][0] < x
            step //= 2
        lower = index - (1 if (not below or index == BAKED_POINTS - 1) else 0)
        lower = min(max(lower, 0), BAKED_POINTS - 2)
        lx, ly = self.baked[lower]
        ux, uy = self.baked[lower + 1]
        dx = ux - lx
        if dx <= 1e-6:
            return ly
        perc = (x - lx) / dx
        if math.isnan(perc) or math.isinf(perc):
            return ly
        return ly + ((uy - ly) * perc)


def advance_spring(value: float, velocity: float, spring: dict, dt: float) -> tuple[float, float]:
    """Animation::advanceSpring (closed form, target 1)."""
    dt = max(dt, 0.0)
    if dt <= 0:
        return value, velocity
    mass = max(spring["mass"], 0.0001)
    stiffness = max(spring["stiffness"], 0.0001)
    damping = max(spring["damping"], 0.0)
    displacement = value - 1
    omega0 = math.sqrt(stiffness / mass)
    gamma = damping / (2 * mass)
    if gamma < omega0:
        omega_d = math.sqrt((omega0 * omega0) - (gamma * gamma))
        e = math.exp(-gamma * dt)
        s = math.sin(omega_d * dt)
        c = math.cos(omega_d * dt)
        new_d = e * ((displacement * c) + (((velocity + (gamma * displacement)) / omega_d) * s))
        new_v = e * ((velocity * c) - (((gamma * velocity) + (omega0 * omega0 * displacement)) / omega_d) * s)
        return 1 + new_d, new_v
    if abs(gamma - omega0) <= max(omega0, 1) * 0.0001:
        e = math.exp(-gamma * dt)
        b = velocity + (gamma * displacement)
        return 1 + (e * (displacement + (b * dt))), e * (velocity - (gamma * b * dt))
    root = math.sqrt((gamma * gamma) - (omega0 * omega0))
    r1 = -gamma + root
    r2 = -gamma - root
    a = (velocity - (r2 * displacement)) / (r1 - r2)
    b = displacement - a
    e1 = math.exp(r1 * dt)
    e2 = math.exp(r2 * dt)
    return 1 + (a * e1) + (b * e2), (a * r1 * e1) + (b * r2 * e2)


def spring_settle_ms(spring: dict) -> int:
    """First 1 ms tick where getCurveStep reports the spring finished."""
    value, velocity, t = 0.0, 0.0, 0
    while t < SPRING_MAX_MS:
        value, velocity = advance_spring(value, velocity, spring, SPRING_TICK_MS / 1000)
        t += SPRING_TICK_MS
        if abs(1 - value) <= SPRING_VALUE_EPSILON and abs(velocity) <= SPRING_VELOCITY_EPSILON:
            break
    return t


def spring_progress(spring: dict, t_ms: float) -> float:
    if not t_ms > 0:
        return 0.0
    if t_ms >= spring_settle_ms(spring):
        return 1.0
    return advance_spring(0.0, 0.0, spring, t_ms / 1000)[0]


def spring_progress_stepped(spring: dict, t_ms: float, tick_ms: float) -> float:
    """Same as spring_progress, advanced tick by tick (frame-rate check)."""
    value, velocity, t = 0.0, 0.0, 0.0
    while t + tick_ms <= t_ms:
        value, velocity = advance_spring(value, velocity, spring, tick_ms / 1000)
        t += tick_ms
    return advance_spring(value, velocity, spring, (t_ms - t) / 1000)[0]


def sample(curve: dict, n: int) -> list[list[float]]:
    count = max(2, n)
    if curve["type"] == "spring":
        settle = spring_settle_ms(curve)
        return [[i / (count - 1), spring_progress(curve, (i / (count - 1)) * settle)] for i in range(count)]
    bezier = Bezier(curve["points"])
    return [[i / (count - 1), bezier.y_for_point(i / (count - 1))] for i in range(count)]


def dotfiles_beziers(text: str) -> dict[str, list[float]]:
    pattern = re.compile(
        r'hl\.curve\("(\w+)",\s*\{\s*type\s*=\s*"bezier",\s*points\s*=\s*'
        r'\{\{\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\}\s*,\s*\{\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\}\}')
    return {m.group(1): [float(v) for v in m.groups()[1:]] for m in pattern.finditer(text)}


def build() -> dict:
    beziers = {**BUILTIN_BEZIERS, **dotfiles_beziers(GENERAL_LUA.read_text(encoding="utf-8")), **EDGE_BEZIERS}
    out_beziers = {}
    for name, points in beziers.items():
        curve = Bezier(points)
        out_beziers[name] = {
            "points": points,
            "values": [[x, curve.y_for_point(x)] for x in BEZIER_XS],
            "sample": sample({"type": "bezier", "points": points}, SAMPLE_N),
        }
    out_springs = {}
    for name, spring in SPRINGS.items():
        curve = {"type": "spring", **spring}
        out_springs[name] = {
            **spring,
            "settleMs": spring_settle_ms(spring),
            "values": [[t, spring_progress(spring, t)] for t in SPRING_TS],
            "sample": sample(curve, SAMPLE_N),
        }
    return {
        "source": "tests/curve_reference.py (hyprutils v0.14.3 port); regenerate with --write",
        "bakedPoints": BAKED_POINTS,
        "springTickMs": SPRING_TICK_MS,
        "beziers": out_beziers,
        "springs": out_springs,
    }


def render() -> str:
    return json.dumps(build(), indent=1) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--write", action="store_true", help=f"write {FIXTURE.relative_to(ROOT)}")
    args = parser.parse_args()
    if args.write:
        FIXTURE.write_text(render(), encoding="utf-8")
    else:
        sys.stdout.write(render())
    return 0


if __name__ == "__main__":
    sys.exit(main())
