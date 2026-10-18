#!/usr/bin/env python3
"""Read Grok Bot's local roster and emit a privacy-preserving JSON snapshot.

The Electron app stores several unrelated blobs in the same directory.  This
reader deliberately accepts only the roster shape and never forwards fields
that can contain prompts, account data, paths, or conversation history.
"""

from __future__ import annotations

import json
import os
import re
import sys
from base64 import b64decode
from pathlib import Path
from typing import Any
from urllib.parse import quote, unquote

UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)
ALLOWED_SHAPES = {
    "blob",
    "pebble",
    "bean",
    "egg",
    "squircle",
    "tablet",
    "capsule",
    "cylinder",
    "hex",
    "gem",
    "crystal",
    "wedge",
    "shield",
    "dome",
    "arch",
    "cloud",
    "teardrop",
    "leaf",
    "square",
    "sparkle",
    "clover",
    "flower",
    "heart",
    "house",
    "star",
}
ALLOWED_COLORS = {
    "black",
    "brown",
    "red",
    "orange",
    "yellow",
    "green",
    "cyan",
    "blue",
    "violet",
    "magenta",
    "gray",
}
# These are the exact ID-derived defaults used by Grok Bot 0.71.2.  They are
# intentionally separate from the complete validation catalogs above:
# Grok accepts every shape/color in those catalogs when metadata is explicit,
# but its automatic shape default uses only this eight-item subset and its
# automatic color default excludes black.
GROK_DEFAULT_SHAPES = (
    "blob",
    "pebble",
    "squircle",
    "tablet",
    "wedge",
    "hex",
    "cloud",
    "teardrop",
)
GROK_DEFAULT_COLORS = (
    "brown",
    "red",
    "orange",
    "yellow",
    "green",
    "cyan",
    "blue",
    "violet",
    "magenta",
    "gray",
)
MAX_NAME_LENGTH = 120
MAX_PREVIEW_LENGTH = 500
MAX_AVATAR_DATA_LENGTH = 2_000_000
AVATAR_DATA_RE = re.compile(
    r"^data:image/(?:png|jpeg|jpg|webp|gif);base64,[A-Za-z0-9+/]+={0,2}$",
    re.IGNORECASE,
)

# These pairs are the resolved ink colors returned by Grok's own avatar
# renderer (Q7e/ZN in the bundled renderer).  The SVG templates under
# ``assets/grok-avatar-templates`` contain the exact paths emitted by Grok;
# only these theme colors are substituted for the roster's selected color.
GROK_INK = {
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
TEMPLATE_DIR = Path(__file__).resolve().parents[1] / "assets" / "grok-avatar-templates"


def _config_dir() -> Path:
    configured = os.environ.get("XDG_CONFIG_HOME")
    return Path(configured).expanduser() if configured else Path.home() / ".config"


def _roster_dir() -> Path:
    return _config_dir() / "Grok Bot" / "sand-client-persistence"


def _text(value: Any, limit: int) -> str:
    if not isinstance(value, str):
        return ""
    # Keep unicode while removing controls that could affect a tooltip/card.
    clean = "".join(ch for ch in value if ch in "\n\t" or ord(ch) >= 32)
    return clean.strip()[:limit]


def _preview(entry: Any) -> tuple[str, str]:
    if isinstance(entry, dict):
        kind = _text(entry.get("kind"), 32) or "unknown"
        text = _text(entry.get("text"), MAX_PREVIEW_LENGTH)
        if not text:
            # Non-text entries remain identifiable without leaking their data.
            text = ""
        return kind, text
    if isinstance(entry, str):
        return "text", _text(entry, MAX_PREVIEW_LENGTH)
    return "unknown", ""


def _avatar_data(row: dict[str, Any]) -> str:
    """Return only an inline image Grok explicitly exposes for this bot.

    The roster may contain ``avatarPhoto`` or ``avatarDataUrl`` in newer
    versions.  File paths, remote URLs, opaque cache references, and malformed
    data are deliberately ignored so the bridge never invents or dereferences
    private data.
    """

    for key in ("avatarPhoto", "avatarDataUrl"):
        value = row.get(key)
        if not isinstance(value, str) or len(value) > MAX_AVATAR_DATA_LENGTH:
            continue
        value = value.strip()
        if not AVATAR_DATA_RE.fullmatch(value):
            continue
        try:
            payload = value.split(",", 1)[1]
            decoded = b64decode(payload, validate=True)
        except (ValueError, TypeError):
            continue
        if decoded:
            return value
    return ""


def _avatar_svg(shape: str, color: str, *, dark: bool = False) -> str:
    """Return Grok's original SVG paths with a Qt-compatible literal ink.

    Grok's output uses CSS custom properties and a color-scheme media query.
    Qt's SVG image plugin ignores those declarations and paints the unresolved
    ``var()`` fill black, so emit a theme-specific SVG with the exact palette
    color as a literal fill. The geometry and paths remain untouched.
    """

    if shape not in ALLOWED_SHAPES or color not in GROK_INK:
        return ""
    template = TEMPLATE_DIR / f"{shape}.svg.tmpl"
    try:
        svg = unquote(template.read_text(encoding="ascii").strip(), errors="strict")
    except (OSError, UnicodeError, ValueError):
        return ""

    svg, removed_styles = re.subn(r"<style>.*?</style>", "", svg, count=1, flags=re.DOTALL)
    if removed_styles != 1:
        return ""
    light_ink, dark_ink = GROK_INK[color]
    ink = dark_ink if dark else light_ink
    svg = svg.replace("var(--grok-bot-still-ink)", f"#{ink}")
    if "var(--grok-bot-still-ink)" in svg or "__LIGHT__" in svg or "__DARK__" in svg:
        return ""
    encoded = quote(svg, safe="-_.!~*'()")
    return f"data:image/svg+xml,{encoded}"


_U32_MASK = 0xFFFFFFFF
_I32_SIGN = 0x80000000


def _grok_i32(value: int) -> int:
    value &= _U32_MASK
    return value - (1 << 32) if value & _I32_SIGN else value


def _grok_u32(value: int) -> int:
    return value & _U32_MASK


def _grok_ushr(value: int, bits: int) -> int:
    """Replicate JavaScript's unsigned right shift for 32-bit values."""

    return _grok_u32(value) >> bits


def _grok_imul(left: int, right: int) -> int:
    """Replicate JavaScript Math.imul, including its signed int32 result."""

    return _grok_i32(_grok_i32(left) * _grok_i32(right))


def _grok_fnv1a32(bot_id: str) -> int:
    """Return the 0.71.2 bundle's FNV-1a hash for a UUID string."""

    value = 2166136261
    # UUID_RE admits only ASCII characters, so Python code points and the
    # bundle's UTF-16 charCodeAt values are identical here.
    for character in bot_id:
        value = _grok_imul(_grok_i32(value) ^ ord(character), 16777619)
    return _grok_u32(value)


def _grok_default_shape(bot_id: str) -> str:
    """Mirror platform export BN (consumed as Iy by the app renderer)."""

    value = _grok_i32(_grok_fnv1a32(bot_id))
    value = _grok_imul(value ^ _grok_ushr(value, 16), 73244475)
    value = _grok_imul(value ^ _grok_ushr(value, 13), 3266489909)
    value = _grok_u32(value ^ _grok_ushr(value, 16))
    return GROK_DEFAULT_SHAPES[value % len(GROK_DEFAULT_SHAPES)]


def _grok_prng(seed: int) -> float:
    """Return the first value from the bundle's one-step seeded PRNG."""

    state = _grok_u32(seed)
    state = _grok_i32(state + 1831565813)
    value = _grok_imul(
        _grok_i32(state) ^ _grok_ushr(state, 15),
        1 | state,
    )
    value = _grok_i32(
        value + _grok_imul(_grok_i32(value) ^ _grok_ushr(value, 7), 61 | value)
    ) ^ _grok_i32(value)
    return _grok_u32(value ^ _grok_ushr(value, 14)) / 4294967296


def _grok_default_color(bot_id: str) -> str:
    """Mirror platform export hb (consumed as j1 by the app renderer)."""

    # The bundle calls db(ub(id)); both constants are 1 in 0.71.2, so the two
    # identical XORs cancel while retaining the exact call sequence here.
    seed_xor = _grok_imul(1, 2654435769)
    seed = _grok_u32(_grok_fnv1a32(bot_id) ^ seed_xor)
    seed = _grok_u32(seed ^ _grok_imul(1, 2654435769))
    index = int(_grok_prng(seed) * len(GROK_DEFAULT_COLORS))
    return GROK_DEFAULT_COLORS[index]


def _avatar_style(bot_id: str, shape: str, color: str) -> tuple[str, str]:
    """Fill absent metadata with Grok Bot 0.71.2's exact ID defaults."""

    if shape not in ALLOWED_SHAPES:
        shape = _grok_default_shape(bot_id)
    if color not in ALLOWED_COLORS:
        color = _grok_default_color(bot_id)
    return shape, color


def _candidate(path: Path) -> list[dict[str, Any]] | None:
    try:
        with path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None

    if not isinstance(payload, dict) or payload.get("schemaVersion") not in {3, 4}:
        return None
    value = payload.get("value")
    if not isinstance(value, dict) or not isinstance(value.get("rows"), list):
        return None

    bots: list[dict[str, Any]] = []
    for row in value["rows"]:
        if not isinstance(row, dict):
            continue
        bot_id = row.get("id")
        if not isinstance(bot_id, str) or not UUID_RE.fullmatch(bot_id):
            continue
        name = _text(row.get("name"), MAX_NAME_LENGTH)
        if not name:
            continue
        kind, preview = _preview(row.get("lastEntry"))
        avatar_photo = _avatar_data(row)
        try:
            unread_count = max(0, int(row.get("unreadCount", 0)))
        except (TypeError, ValueError):
            unread_count = 0
        raw_has_unread = row.get("hasUnread")
        if isinstance(raw_has_unread, bool):
            has_unread = raw_has_unread
        elif isinstance(raw_has_unread, str):
            has_unread = raw_has_unread.strip().lower() == "true"
        else:
            has_unread = False
        has_unread = has_unread or unread_count > 0
        try:
            activity = max(0, int(row.get("lastActivityAt", 0)))
        except (TypeError, ValueError):
            activity = 0
        shape = _text(row.get("avatarShape"), 32).lower()
        color = _text(row.get("avatarColor"), 32).lower()
        if not avatar_photo:
            shape, color = _avatar_style(bot_id, shape, color)
        bots.append(
            {
                "id": bot_id,
                "name": name,
                "avatarShape": shape if shape in ALLOWED_SHAPES else "",
                "avatarColor": color if color in ALLOWED_COLORS else "",
                "avatarPhoto": avatar_photo,
                "avatarSvg": _avatar_svg(shape, color),
                "avatarSvgDark": _avatar_svg(shape, color, dark=True),
                "hasUnread": has_unread,
                "unreadCount": unread_count,
                "lastActivityAt": activity,
                "entryKind": kind,
                "preview": preview,
            }
        )
    return bots


def read_snapshot(directory: Path | None = None) -> dict[str, Any]:
    root = directory or _roster_dir()
    if not root.is_dir():
        return {"available": False, "bots": []}

    candidates: list[tuple[float, Path, list[dict[str, Any]]]] = []
    try:
        paths = list(root.iterdir())
    except OSError:
        return {"available": False, "bots": []}
    for path in paths:
        if not path.is_file() or path.suffix not in {".blob", ".json", ""}:
            continue
        bots = _candidate(path)
        if bots is None:
            continue
        try:
            mtime = path.stat().st_mtime_ns
        except OSError:
            mtime = 0
        candidates.append((mtime, path, bots))

    if not candidates:
        return {"available": False, "bots": []}
    _, _, bots = max(candidates, key=lambda item: item[0])
    # Keep the most recent row when an interrupted write duplicates an id.
    unique: dict[str, dict[str, Any]] = {}
    for bot in bots:
        unique[bot["id"]] = bot
    return {"available": True, "bots": list(unique.values())}


def main() -> int:
    json.dump(read_snapshot(), sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
