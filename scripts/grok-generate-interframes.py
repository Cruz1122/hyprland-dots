#!/usr/bin/env python3
"""Generate reusable vector in-between frames for Grok avatar keyframes.

The extracted Grok SVGs use M/L/A/Z path data. Compatible consecutive frames
are normalized to sampled closed paths and interpolated offline. If a pair
changes path topology, the generator keeps the original keyframe interval
instead of inventing a malformed expression.
"""

from __future__ import annotations

import argparse
import copy
import math
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Sequence


SVG_NAMESPACE = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NAMESPACE)

TOKEN_RE = re.compile(
    r"[A-Za-z]|[-+]?(?:(?:\d+\.\d*)|(?:\.\d+)|(?:\d+))"
    r"(?:[eE][-+]?\d+)?"
)
NUMBER_RE = re.compile(
    r"[-+]?(?:(?:\d+\.\d*)|(?:\.\d+)|(?:\d+))"
    r"(?:[eE][-+]?\d+)?"
)
COMMAND_ARITY = {"M": 2, "L": 2, "A": 7}
SUPPORTED_COMMANDS = set(COMMAND_ARITY) | {"Z"}
EPSILON = 1e-9

Point = tuple[float, float]


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _distance(left: Point, right: Point) -> float:
    return math.hypot(right[0] - left[0], right[1] - left[1])


def _lerp(left: float, right: float, amount: float) -> float:
    return left + (right - left) * amount


@dataclass(frozen=True)
class LineSegment:
    start: Point
    end: Point

    @property
    def length(self) -> float:
        return _distance(self.start, self.end)

    def point_at(self, amount: float) -> Point:
        return (
            _lerp(self.start[0], self.end[0], amount),
            _lerp(self.start[1], self.end[1], amount),
        )


@dataclass(frozen=True)
class ArcSegment:
    start: Point
    end: Point
    radius_x: float
    radius_y: float
    rotation: float
    large_arc: bool
    sweep: bool
    center_x: float = field(init=False)
    center_y: float = field(init=False)
    start_angle: float = field(init=False)
    delta_angle: float = field(init=False)

    def __post_init__(self) -> None:
        rx = abs(self.radius_x)
        ry = abs(self.radius_y)
        phi = math.radians(self.rotation % 360.0)
        cos_phi = math.cos(phi)
        sin_phi = math.sin(phi)
        dx = (self.start[0] - self.end[0]) / 2.0
        dy = (self.start[1] - self.end[1]) / 2.0
        x_prime = cos_phi * dx + sin_phi * dy
        y_prime = -sin_phi * dx + cos_phi * dy

        if rx <= EPSILON or ry <= EPSILON or _distance(self.start, self.end) <= EPSILON:
            object.__setattr__(self, "center_x", self.start[0])
            object.__setattr__(self, "center_y", self.start[1])
            object.__setattr__(self, "start_angle", 0.0)
            object.__setattr__(self, "delta_angle", 0.0)
            return

        radius_scale = (x_prime * x_prime) / (rx * rx) + (y_prime * y_prime) / (ry * ry)
        if radius_scale > 1.0:
            scale = math.sqrt(radius_scale)
            rx *= scale
            ry *= scale

        denominator = rx * rx * y_prime * y_prime + ry * ry * x_prime * x_prime
        numerator = max(0.0, (rx * rx * ry * ry) - denominator)
        coefficient = math.sqrt(numerator / denominator) if denominator > EPSILON else 0.0
        if self.large_arc == self.sweep:
            coefficient = -coefficient

        center_x_prime = coefficient * (rx * y_prime / ry)
        center_y_prime = coefficient * (-ry * x_prime / rx)
        center_x = cos_phi * center_x_prime - sin_phi * center_y_prime
        center_y = sin_phi * center_x_prime + cos_phi * center_y_prime
        center_x += (self.start[0] + self.end[0]) / 2.0
        center_y += (self.start[1] + self.end[1]) / 2.0

        def angle_between(ux: float, uy: float, vx: float, vy: float) -> float:
            return math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)

        ux = (x_prime - center_x_prime) / rx
        uy = (y_prime - center_y_prime) / ry
        vx = (-x_prime - center_x_prime) / rx
        vy = (-y_prime - center_y_prime) / ry
        start_angle = angle_between(1.0, 0.0, ux, uy)
        delta_angle = angle_between(ux, uy, vx, vy)
        if not self.sweep and delta_angle > 0:
            delta_angle -= 2.0 * math.pi
        elif self.sweep and delta_angle < 0:
            delta_angle += 2.0 * math.pi

        object.__setattr__(self, "center_x", center_x)
        object.__setattr__(self, "center_y", center_y)
        object.__setattr__(self, "start_angle", start_angle)
        object.__setattr__(self, "delta_angle", delta_angle)
        object.__setattr__(self, "radius_x", rx)
        object.__setattr__(self, "radius_y", ry)

    @property
    def length(self) -> float:
        if abs(self.delta_angle) <= EPSILON:
            return _distance(self.start, self.end)
        # Good enough for distributing samples along a small avatar SVG.
        return abs(self.delta_angle) * math.sqrt((self.radius_x**2 + self.radius_y**2) / 2.0)

    def point_at(self, amount: float) -> Point:
        if abs(self.delta_angle) <= EPSILON:
            return LineSegment(self.start, self.end).point_at(amount)
        phi = math.radians(self.rotation % 360.0)
        angle = self.start_angle + self.delta_angle * amount
        cos_phi = math.cos(phi)
        sin_phi = math.sin(phi)
        cos_angle = math.cos(angle)
        sin_angle = math.sin(angle)
        return (
            self.center_x + cos_phi * self.radius_x * cos_angle - sin_phi * self.radius_y * sin_angle,
            self.center_y + sin_phi * self.radius_x * cos_angle + cos_phi * self.radius_y * sin_angle,
        )


Segment = LineSegment | ArcSegment


@dataclass
class Subpath:
    start: Point
    segments: list[Segment] = field(default_factory=list)
    closed: bool = False
    point_count: int = 1


def _read_numbers(tokens: Sequence[str], position: int, count: int) -> tuple[list[float], int]:
    if position + count > len(tokens):
        raise ValueError("truncated SVG path command")
    values = tokens[position : position + count]
    if any(value.isalpha() for value in values):
        raise ValueError("SVG path command has too few numeric arguments")
    return [float(value) for value in values], position + count


def parse_path(data: str) -> list[Subpath]:
    tokens = TOKEN_RE.findall(data)
    position = 0
    command: str | None = None
    current: Point = (0.0, 0.0)
    subpath_start: Point = (0.0, 0.0)
    active: Subpath | None = None
    subpaths: list[Subpath] = []

    while position < len(tokens):
        token = tokens[position]
        if token.isalpha():
            command = token
            position += 1
            if command.upper() not in SUPPORTED_COMMANDS:
                raise ValueError(f"unsupported SVG path command: {command}")
            if command.upper() == "Z":
                if active is None:
                    raise ValueError("SVG path closes before it starts")
                if _distance(current, subpath_start) > EPSILON:
                    active.segments.append(LineSegment(current, subpath_start))
                active.closed = True
                current = subpath_start
                command = None
                continue

        if command is None:
            raise ValueError("SVG path contains coordinates without a command")

        upper = command.upper()
        relative = command.islower()
        values, position = _read_numbers(tokens, position, COMMAND_ARITY[upper])

        if upper == "M":
            x, y = values
            if relative:
                x += current[0]
                y += current[1]
            if active is not None:
                subpaths.append(active)
            current = (x, y)
            subpath_start = current
            active = Subpath(start=current)
            command = "l" if relative else "L"
            continue

        if active is None:
            raise ValueError("SVG path segment appears before moveto")

        if upper == "L":
            x, y = values
            if relative:
                x += current[0]
                y += current[1]
            target = (x, y)
            active.segments.append(LineSegment(current, target))
            active.point_count += 1
            current = target
            continue

        radius_x, radius_y, rotation, large_arc, sweep, x, y = values
        if relative:
            x += current[0]
            y += current[1]
        target = (x, y)
        active.segments.append(
            ArcSegment(
                current,
                target,
                radius_x,
                radius_y,
                rotation,
                bool(round(large_arc)),
                bool(round(sweep)),
            )
        )
        active.point_count += 1
        current = target

    if active is not None:
        subpaths.append(active)
    if not subpaths:
        raise ValueError("SVG path contains no subpaths")
    return subpaths


def _point_at_distance(segments: Sequence[Segment], target: float) -> Point:
    remaining = target
    for segment in segments:
        if segment.length <= EPSILON:
            continue
        if remaining <= segment.length:
            return segment.point_at(max(0.0, min(1.0, remaining / segment.length)))
        remaining -= segment.length
    return segments[-1].point_at(1.0)


def sample_subpath(subpath: Subpath, count: int) -> list[Point]:
    if not subpath.segments:
        return [subpath.start]
    total_length = sum(segment.length for segment in subpath.segments)
    if total_length <= EPSILON:
        return [subpath.start for _ in range(count)]

    if subpath.closed:
        return [
            _point_at_distance(subpath.segments, total_length * index / count)
            for index in range(count)
        ]

    return [
        _point_at_distance(subpath.segments, total_length * index / (count - 1))
        for index in range(count)
    ]


def _format_number(value: float) -> str:
    if abs(value) < 0.00005:
        value = 0.0
    return f"{value:.4f}".rstrip("0").rstrip(".") or "0"


def _format_path(subpaths: Iterable[tuple[Sequence[Point], bool]]) -> str:
    parts: list[str] = []
    for points, closed in subpaths:
        if not points:
            continue
        parts.append(f"M {_format_number(points[0][0])} {_format_number(points[0][1])}")
        parts.extend(
            f"L {_format_number(point[0])} {_format_number(point[1])}"
            for point in points[1:]
        )
        if closed:
            parts.append("Z")
    return " ".join(parts)


def _signed_area(points: Sequence[Point]) -> float:
    if len(points) < 3:
        return 0.0
    return 0.5 * sum(
        left[0] * right[1] - right[0] * left[1]
        for left, right in zip(points, (*points[1:], points[0]))
    )


def _reverse_closed_points(points: Sequence[Point]) -> list[Point]:
    """Reverse traversal while preserving the first point as the anchor."""

    return [points[0], *reversed(points[1:])]


def _align_closed_points(left: Sequence[Point], right: Sequence[Point]) -> tuple[list[Point], int, bool]:
    """Align a closed contour's winding and cyclic start before morphing.

    SVG exporters are free to choose a different starting point (or winding)
    for the same contour in consecutive frames. Point-wise interpolation
    without this alignment can make the contour fold over itself and disappear
    under an even-odd fill rule.
    """

    if len(left) != len(right) or len(left) < 4:
        return list(right), 0, False

    aligned = list(right)
    reversed_winding = False
    left_area = _signed_area(left)
    right_area = _signed_area(aligned)
    if abs(left_area) > EPSILON and abs(right_area) > EPSILON and left_area * right_area < 0:
        aligned = _reverse_closed_points(aligned)
        reversed_winding = True

    # Locate the point nearest to the left contour's first anchor first. The
    # native exporter usually changes the starting point locally, so this gives
    # the cyclic offset in O(n). A small neighborhood scored with distributed
    # anchors resolves the occasional near-symmetric candidate without the
    # O(n²) cost of comparing every point for every shift.
    anchor_count = min(12, len(left))
    anchors = tuple((len(left) * index) // anchor_count for index in range(anchor_count))
    nearest_shift = min(
        range(len(aligned)),
        key=lambda shift: (left[0][0] - aligned[shift][0]) ** 2
        + (left[0][1] - aligned[shift][1]) ** 2,
    )
    neighborhood = min(8, len(left) // 8)
    candidate_shifts = {
        (nearest_shift + offset) % len(left)
        for offset in range(-neighborhood, neighborhood + 1)
    }
    best_shift = nearest_shift
    best_score = float("inf")
    for shift in candidate_shifts:
        score = sum(
            (left[index][0] - aligned[(index + shift) % len(aligned)][0]) ** 2
            + (left[index][1] - aligned[(index + shift) % len(aligned)][1]) ** 2
            for index in anchors
        )
        if score < best_score:
            best_score = score
            best_shift = shift

    return [aligned[(index + best_shift) % len(aligned)] for index in range(len(aligned))], best_shift, reversed_winding


def _subpath_endpoint_area(subpath: Subpath) -> float:
    points = [subpath.start, *(segment.end for segment in subpath.segments)]
    if len(points) > 1 and _distance(points[0], points[-1]) <= EPSILON:
        points.pop()
    return _signed_area(points)


def _direct_contours_are_stable(left: Sequence[Subpath], right: Sequence[Subpath]) -> bool:
    """Keep the compact command morph only when its anchors are trustworthy."""

    for left_subpath, right_subpath in zip(left, right):
        if not left_subpath.closed:
            continue
        left_area = _subpath_endpoint_area(left_subpath)
        right_area = _subpath_endpoint_area(right_subpath)
        if abs(left_area) > EPSILON and abs(right_area) > EPSILON and left_area * right_area < 0:
            return False
        # A large start-point jump means the exporter re-anchored the contour;
        # direct point-wise interpolation would connect unrelated vertices.
        if _distance(left_subpath.start, right_subpath.start) > 32:
            return False
    return True


def _interpolate_attribute(left: str, right: str, amount: float) -> str:
    if left == right:
        return left
    left_matches = list(NUMBER_RE.finditer(left))
    right_matches = list(NUMBER_RE.finditer(right))
    if len(left_matches) != len(right_matches):
        return left

    left_literals = NUMBER_RE.split(left)
    right_literals = NUMBER_RE.split(right)
    if left_literals != right_literals:
        return left

    result: list[str] = []
    for index, literal in enumerate(left_literals[:-1]):
        result.append(literal)
        left_value = float(left_matches[index].group())
        right_value = float(right_matches[index].group())
        result.append(_format_number(_lerp(left_value, right_value, amount)))
    result.append(left_literals[-1])
    return "".join(result)


def _interpolate_tokenized_path(left: str, right: str, amount: float) -> str | None:
    """Interpolate paths without resampling when their command layout matches."""

    left_tokens = TOKEN_RE.findall(left)
    right_tokens = TOKEN_RE.findall(right)
    if len(left_tokens) != len(right_tokens):
        return None

    result: list[str] = []
    command: str | None = None
    parameter_index = 0
    for left_token, right_token in zip(left_tokens, right_tokens):
        if left_token.isalpha() or right_token.isalpha():
            if left_token != right_token:
                return None
            command = left_token.upper()
            parameter_index = 0
            result.append(left_token)
            continue

        if command is None:
            return None
        left_value = float(left_token)
        right_value = float(right_token)
        if command == "A" and parameter_index in (3, 4):
            if left_value != right_value:
                return None
            result.append(left_token)
        else:
            result.append(_format_number(_lerp(left_value, right_value, amount)))
        parameter_index += 1
        if parameter_index == COMMAND_ARITY.get(command, 0):
            parameter_index = 0
            if command == "M":
                command = "L"
    return " ".join(result)


def _interpolate_path(left: str, right: str, amount: float) -> str | None:
    if left == right:
        return left
    try:
        left_subpaths = parse_path(left)
        right_subpaths = parse_path(right)
    except ValueError:
        return None
    if len(left_subpaths) != len(right_subpaths):
        return None

    direct = _interpolate_tokenized_path(left, right, amount)
    if direct is not None and _direct_contours_are_stable(left_subpaths, right_subpaths):
        return direct

    sampled: list[tuple[list[Point], list[Point], bool]] = []
    for left_subpath, right_subpath in zip(left_subpaths, right_subpaths):
        if left_subpath.closed != right_subpath.closed:
            return None
        sample_count = max(
            32,
            min(256, max(left_subpath.point_count, right_subpath.point_count)),
        )
        left_points = sample_subpath(left_subpath, sample_count)
        right_points = sample_subpath(right_subpath, sample_count)
        if left_subpath.closed:
            right_points, _, _ = _align_closed_points(left_points, right_points)
        sampled.append((left_points, right_points, left_subpath.closed))

    interpolated: list[tuple[list[Point], bool]] = []
    for left_points, right_points, closed in sampled:
        points = [
            (
                _lerp(left_point[0], right_point[0], amount),
                _lerp(left_point[1], right_point[1], amount),
            )
            for left_point, right_point in zip(left_points, right_points)
        ]
        interpolated.append((points, closed))
    return _format_path(interpolated)


def interpolate_svg(left: ET.Element, right: ET.Element, amount: float) -> ET.Element | None:
    left_elements = list(left.iter())
    right_elements = list(right.iter())
    if len(left_elements) != len(right_elements):
        return None
    if any(_local_name(a.tag) != _local_name(b.tag) for a, b in zip(left_elements, right_elements)):
        return None
    if any(set(a.attrib) != set(b.attrib) for a, b in zip(left_elements, right_elements)):
        return None

    output = copy.deepcopy(left)
    output_elements = list(output.iter())
    for output_element, left_element, right_element in zip(output_elements, left_elements, right_elements):
        if "d" in left_element.attrib:
            path = _interpolate_path(left_element.attrib["d"], right_element.attrib["d"], amount)
            if path is None:
                return None
            output_element.attrib["d"] = path
        for name, left_value in left_element.attrib.items():
            if name == "d":
                continue
            right_value = right_element.attrib[name]
            output_element.attrib[name] = _interpolate_attribute(left_value, right_value, amount)
    return output


def _write_svg(path: Path, root: ET.Element) -> None:
    path.write_text(ET.tostring(root, encoding="unicode"), encoding="utf-8")


def generate(source: Path, output: Path, steps: int) -> tuple[int, int, int]:
    if output.exists():
        raise FileExistsError(f"output directory already exists: {output}")
    if steps < 2:
        raise ValueError("steps must be at least 2")

    sequences = 0
    compatible_pairs = 0
    fallback_pairs = 0
    output.mkdir(parents=True)

    for key_dir in sorted(path for path in source.iterdir() if path.is_dir()):
        for state_dir in sorted(path for path in key_dir.iterdir() if path.is_dir()):
            frames = sorted(state_dir.glob("frame-*.svg"))
            if len(frames) != 46:
                raise ValueError(f"expected 46 keyframes in {state_dir}, got {len(frames)}")
            sequences += 1
            destination = output / key_dir.name / state_dir.name
            destination.mkdir(parents=True)

            parsed = [ET.parse(frame).getroot() for frame in frames]
            raw = [frame.read_bytes() for frame in frames]
            dense_index = 0
            for index, left_root in enumerate(parsed[:-1]):
                (destination / f"frame-{dense_index:03d}.svg").write_bytes(raw[index])
                right_root = parsed[index + 1]
                pair_is_compatible = True
                for step in range(1, steps):
                    amount = step / steps
                    interpolated = interpolate_svg(left_root, right_root, amount)
                    if interpolated is None:
                        pair_is_compatible = False
                        break
                    dense_index += 1
                    _write_svg(destination / f"frame-{dense_index:03d}.svg", interpolated)
                if not pair_is_compatible:
                    fallback_pairs += 1
                    for step in range(1, steps):
                        dense_index += 1
                        (destination / f"frame-{dense_index:03d}.svg").write_bytes(raw[index])
                else:
                    compatible_pairs += 1
                dense_index += 1

            (destination / f"frame-{dense_index:03d}.svg").write_bytes(raw[-1])

    return sequences, compatible_pairs, fallback_pairs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--steps", type=int, default=4)
    args = parser.parse_args()

    try:
        sequences, compatible_pairs, fallback_pairs = generate(args.source, args.output, args.steps)
    except (OSError, ValueError, ET.ParseError) as error:
        print(f"grok-generate-interframes: {error}", file=sys.stderr)
        return 1

    print(
        f"generated {sequences} sequences at {args.steps}x; "
        f"interpolated_pairs={compatible_pairs}; fallback_pairs={fallback_pairs}; "
        f"output={args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
