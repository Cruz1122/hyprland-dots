#!/usr/bin/env python3
"""Print the dotfiles' own Hyprland values (the "base") as JSON.

Usage:
    hyprbase.py --json [--config-dir DIR] [--options FILE]

Runs DIR/hyprland.lua (default DIR: $XDG_CONFIG_HOME/hypr or ~/.config/hypr)
with /usr/bin/lua and a stub `hl` that records hl.config, hl.curve and
hl.animation, so the settings app knows what a reset falls back to. The
settings app's own files and Game Mode (custom.shell-settings,
custom.shell-animations, hyprland.shellOverrides.main) are skipped: the base is
what applies when none of them overrides an option.

The Lua code runs sandboxed: `require` resolves modules only inside DIR,
io.open is read-only and confined to DIR (paths under $HOME/.config/hypr map
into DIR), os.execute/io.popen/os.remove/os.rename/os.exit/load/loadfile/dofile
are blocked, the process has no file-size allowance (RLIMIT_FSIZE 0) and is
killed after TIMEOUT_S seconds. Nothing is written and nothing is executed
besides lua itself.

Output: one JSON object, also on failure:
    {"ok": bool, "errors": [str], "config": {getoption name: value},
     "curves": {name: {"type": "bezier", "points": [x1, y1, x2, y2]} | {"type": "spring", ...}},
     "animations": {leaf: {"enabled", "speed", "bezier" | "spring", "style"}}}
Later calls override earlier ones, as in Hyprland. `errors` lists non-fatal
problems too (missing modules, blocked calls, non-literal values such as NaN or
infinite numbers and, with
--options, option names Hyprland does not know).

--options FILE: getoption names to check the recorded names against, as a JSON
object keyed by name (tests/fixtures/hyprland-options.json) or the list printed
by `hyprctl -j descriptions`.

Exit codes: 0 ok, 1 the base could not be read (ok=false), 2 invalid arguments.
"""
from __future__ import annotations

import argparse
import json
import os
import resource
import subprocess
import sys
from pathlib import Path
from typing import Any

LUA = "/usr/bin/lua"
TIMEOUT_S = 5
MARKER = "@@hyprbase-result@@ "
# Modules that are not part of the base: the settings app's files and Game Mode.
SKIPPED_MODULES = ("custom.shell-settings", "custom.shell-animations", "hyprland.shellOverrides.main")

# The prelude reads DIR and HOME from arg[1], arg[2]. Every real function it
# needs is captured in a local before the sandboxed environment is built, so
# the dotfiles cannot reach or replace them; prelude code never uses method
# syntax on strings (s:gmatch would go through the shared string metatable).
PRELUDE = r"""
local DIR, HOME = arg[1], arg[2]
local SKIP = {}
for i = 3, #arg do SKIP[arg[i]] = true end
local real_open, real_loadfile, iotype, stdout = io.open, loadfile, io.type, io.stdout
local sformat, sgsub, smatch, ssub, sbyte, sfind = string.format, string.gsub, string.match, string.sub, string.byte, string.find
local sgmatch = string.gmatch
local mtype, tconcat, tsort, HUGE = math.type, table.concat, table.sort, math.huge
local pairs, ipairs, type, tostring, rawlen, select = pairs, ipairs, type, tostring, rawlen, select
local setmetatable, getmetatable, pcall, xpcall, error = setmetatable, getmetatable, pcall, xpcall, error

local errors, config, curves, animations = {}, {}, {}, {}
local function note(msg) errors[#errors + 1] = tostring(msg) end

-- Permissive stand-in for every hl.* field the base does not record.
local dummy
local function give_dummy() return dummy end
local dummy_mt = {
  __index = give_dummy, __call = give_dummy, __newindex = function() end,
  __add = give_dummy, __sub = give_dummy, __mul = give_dummy, __div = give_dummy, __mod = give_dummy,
  __pow = give_dummy, __unm = give_dummy, __idiv = give_dummy, __concat = give_dummy,
  __len = function() return 0 end, __lt = function() return false end, __le = function() return false end,
  __tostring = function() return "hl-stub" end,
}
dummy = setmetatable({}, dummy_mt)

-- NaN and the infinities (0/0, 1/0) have no JSON form: not literal values.
local function is_literal(v)
  local t = type(v)
  if t == "number" then return v == v and v ~= HUGE and v ~= -HUGE end
  return t == "boolean" or t == "string"
end

-- Array of literals (a vec2 such as shadow.offset = {0, 2}).
local function literal_array(t)
  local n = rawlen(t)
  if n == 0 then return nil end
  local count = 0
  for k, v in pairs(t) do
    count = count + 1
    if mtype(k) ~= "integer" or k < 1 or k > n or not is_literal(v) then return nil end
  end
  if count ~= n then return nil end
  local out = {}
  for i = 1, n do out[i] = t[i] end
  return out
end

-- hl.config({ general = { col = { active_border = x } } }) -> "general:col.active_border".
local function flatten(prefix, t)
  for k, v in pairs(t) do
    if type(k) ~= "string" then
      note("hl.config: non-string key under '" .. prefix .. "'")
    else
      local name = k
      if prefix ~= "" then
        local last = smatch(prefix, "[^:.]+$")
        name = prefix .. (last == "col" and "." or ":") .. k
      end
      if is_literal(v) then
        config[name] = v
      elseif type(v) == "table" and getmetatable(v) == nil then
        local arr = literal_array(v)
        if arr then config[name] = arr else flatten(name, v) end
      else
        note("hl.config: non-literal value for '" .. name .. "'")
      end
    end
  end
end

local function copy_literals(spec, skip)
  local out = {}
  for k, v in pairs(spec) do
    if type(k) == "string" and k ~= skip then
      if is_literal(v) then out[k] = v
      elseif type(v) == "table" then
        local arr = literal_array(v)
        if arr then out[k] = arr end
      end
    end
  end
  return out
end

local hl = setmetatable({}, { __index = give_dummy, __newindex = function() end })
rawset(hl, "config", function(t)
  if type(t) ~= "table" then note("hl.config: argument is not a table"); return end
  flatten("", t)
end)
rawset(hl, "curve", function(name, spec)
  if type(name) ~= "string" or type(spec) ~= "table" then note("hl.curve: invalid arguments"); return end
  local out = copy_literals(spec, nil)
  local p = spec.points
  if type(p) == "table" and type(p[1]) == "table" and type(p[2]) == "table" then
    out.points = { p[1][1], p[1][2], p[2][1], p[2][2] }
  end
  curves[name] = out
end)
rawset(hl, "animation", function(spec)
  if type(spec) ~= "table" or type(spec.leaf) ~= "string" then note("hl.animation: invalid arguments"); return end
  animations[spec.leaf] = copy_literals(spec, "leaf")
end)

-- Paths: HOME/.config/hypr/... maps into DIR; anything outside DIR is refused.
local CFG = HOME .. "/.config/hypr"
local function confine(path)
  if type(path) ~= "string" or sfind(path, "\0", 1, true) then return nil end
  if path == CFG or ssub(path, 1, #CFG + 1) == CFG .. "/" then path = DIR .. ssub(path, #CFG + 1) end
  if ssub(path, 1, 1) ~= "/" then return nil end
  local parts = {}
  for seg in sgmatch(path, "[^/]+") do
    if seg == ".." then
      if #parts == 0 then return nil end
      parts[#parts] = nil
    elseif seg ~= "." then
      parts[#parts + 1] = seg
    end
  end
  local norm = "/" .. tconcat(parts, "/")
  if norm == DIR or ssub(norm, 1, #DIR + 1) == DIR .. "/" then return norm end
  return nil
end

local function blocked(what)
  return function()
    note("blocked " .. what)
    return nil, "hyprbase: " .. what .. " is not allowed"
  end
end

local safe_io = {}
function safe_io.open(path, mode)
  mode = mode or "r"
  if mode ~= "r" and mode ~= "rb" then
    note("blocked io.open('" .. tostring(path) .. "', '" .. tostring(mode) .. "')")
    return nil, "hyprbase: writes are not allowed"
  end
  local real = confine(path)
  if not real then return nil, tostring(path) .. ": outside the config directory" end
  return real_open(real, mode)
end
function safe_io.close(f) if f then return f:close() end end
function safe_io.lines(path, ...)
  local f, err = safe_io.open(path, "r")
  if not f then error(err, 2) end
  return f:lines(...)
end
safe_io.write = blocked("io.write")
safe_io.popen = blocked("io.popen")
safe_io.tmpfile = blocked("io.tmpfile")
safe_io.output = blocked("io.output")
safe_io.input = blocked("io.input")
safe_io.read = blocked("io.read")

local ENV_VALUES = { HOME = HOME, XDG_CONFIG_HOME = HOME .. "/.config" }
local safe_os = {
  getenv = function(name) return ENV_VALUES[name] end,
  time = os.time, clock = os.clock, date = os.date, difftime = os.difftime,
  execute = blocked("os.execute"), remove = blocked("os.remove"), rename = blocked("os.rename"),
  exit = blocked("os.exit"), tmpname = blocked("os.tmpname"), setlocale = blocked("os.setlocale"),
}

-- The metatables of strings and file handles are shared with this prelude
-- (their __index is the real string table / file methods): handing them out
-- would let the dotfiles replace what confine() and the result writer call.
local function safe_getmetatable(v)
  if type(v) == "string" or iotype(v) then return nil end
  return getmetatable(v)
end

local function shallow(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
local env = {
  assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs, pcall = pcall, xpcall = xpcall,
  select = select, tonumber = tonumber, tostring = tostring, type = type, rawequal = rawequal, rawget = rawget,
  rawset = rawset, rawlen = rawlen, setmetatable = setmetatable, getmetatable = safe_getmetatable,
  _VERSION = _VERSION, string = shallow(string), table = shallow(table), math = shallow(math), utf8 = shallow(utf8),
  coroutine = shallow(coroutine), print = function() end, os = safe_os, io = safe_io, hl = hl,
  load = blocked("load"), loadfile = blocked("loadfile"), dofile = blocked("dofile"),
  collectgarbage = function() return 0 end,
}
env._G = env

local loaded = {}
local function load_module(path, name)
  local chunk, err = real_loadfile(path, "t", env)
  if not chunk then error(err, 0) end
  loaded[name] = true
  local result = chunk(name, path)
  if result ~= nil then loaded[name] = result end
  return loaded[name]
end

env.require = function(name)
  if type(name) ~= "string" then error("require: module name must be a string", 2) end
  local mod = sgsub(sgsub(name, "%.lua$", ""), "/", ".")
  if loaded[mod] ~= nil then return loaded[mod] end
  if SKIP[mod] then loaded[mod] = true; return true end
  if not smatch(mod, "^[%w_%-]+[%w_%-%.]*$") or sfind(mod, "..", 1, true) or ssub(mod, -1) == "." then
    note("require: invalid module name '" .. name .. "'")
    return true
  end
  local rel = DIR .. "/" .. sgsub(mod, "%.", "/")
  for _, path in ipairs({ rel .. ".lua", rel .. "/init.lua" }) do
    local f = real_open(path, "r")
    if f then
      f:close()
      return load_module(path, mod)
    end
  end
  note("module '" .. mod .. "' not found")
  loaded[mod] = true
  return true
end

local function encode(v, depth)
  depth = depth or 0
  if depth > 32 then return "null" end
  local t = type(v)
  if t == "boolean" then return v and "true" or "false" end
  if t == "number" then
    if mtype(v) == "integer" then return sformat("%d", v) end
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    return sformat("%.17g", v)
  end
  if t == "string" then
    return '"' .. sgsub(v, '[%c"\\\127]', function(c) return sformat("\\u%04x", sbyte(c)) end) .. '"'
  end
  if t == "table" then
    local n = rawlen(v)
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    if n > 0 and #keys == n then
      local out = {}
      for i = 1, n do out[i] = encode(v[i], depth + 1) end
      return "[" .. tconcat(out, ",") .. "]"
    end
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = encode(tostring(k)) .. ":" .. encode(v[k], depth + 1) end
    tsort(out)
    return "{" .. tconcat(out, ",") .. "}"
  end
  return "null"
end

local ok, err = xpcall(function()
  local entry = DIR .. "/hyprland.lua"
  local chunk, lerr = real_loadfile(entry, "t", env)
  if not chunk then error(lerr, 0) end
  chunk()
end, function(e) return tostring(e) end)

stdout:write("\n@@hyprbase-result@@ ", encode({ ok = ok, fatal = ok and nil or err, errors = errors,
  config = config, curves = curves, animations = animations }), "\n")
stdout:flush()
"""


def default_config_dir() -> Path:
    xdg = os.environ.get("XDG_CONFIG_HOME")
    base = Path(xdg) if xdg and os.path.isabs(xdg) else Path.home() / ".config"
    return base / "hypr"


def result(ok: bool, errors: list[str], config: Any = None, curves: Any = None, animations: Any = None) -> dict:
    return {"ok": ok, "errors": errors, "config": config or {}, "curves": curves or {}, "animations": animations or {}}


def load_known_options(path: str) -> set[str]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if isinstance(data, dict):
        return {name for name in data if not name.startswith("_")}
    return {item["name"] for item in data if isinstance(item, dict) and isinstance(item.get("name"), str)}


def limit_resources() -> None:
    # Runs in the child: no file may grow (no writes), bounded CPU and memory.
    resource.setrlimit(resource.RLIMIT_FSIZE, (0, 0))
    resource.setrlimit(resource.RLIMIT_CPU, (TIMEOUT_S, TIMEOUT_S + 1))
    resource.setrlimit(resource.RLIMIT_AS, (512 << 20, 512 << 20))


def read_base(config_dir: Path, home: str) -> dict:
    entry = config_dir / "hyprland.lua"
    if not entry.is_file():
        return result(False, [f"{entry}: not found"])
    if not os.access(LUA, os.X_OK):
        return result(False, [f"{LUA} is not installed"])
    argv = [LUA, "-E", "-", str(config_dir), home, *SKIPPED_MODULES]
    try:
        proc = subprocess.run(
            argv, input=PRELUDE.encode(), capture_output=True, timeout=TIMEOUT_S,
            cwd="/", env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"}, preexec_fn=limit_resources,
        )
    except subprocess.TimeoutExpired:
        return result(False, [f"timed out after {TIMEOUT_S} s"])
    except OSError as exc:
        return result(False, [f"cannot run {LUA}: {exc}"])
    stdout = proc.stdout.decode("utf-8", errors="replace")
    payload_line = None
    for line in stdout.split("\n"):
        if line.startswith(MARKER):
            payload_line = line[len(MARKER):]
    if payload_line is None:
        stderr = proc.stderr.decode("utf-8", errors="replace").strip()
        return result(False, [f"lua exited with {proc.returncode}" + (f": {stderr[-500:]}" if stderr else "")])
    try:
        payload = json.loads(payload_line)
    except json.JSONDecodeError as exc:
        return result(False, [f"unreadable lua output: {exc}"])
    errors = [str(e) for e in payload.get("errors") or []]
    if not payload.get("ok"):
        return result(False, [str(payload.get("fatal") or "lua error")] + errors)
    return result(True, errors, payload.get("config"), payload.get("curves"), payload.get("animations"))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Print the dotfiles' Hyprland base values as JSON.")
    parser.add_argument("--json", action="store_true", required=True, help="JSON output (the only format).")
    parser.add_argument("--config-dir", metavar="DIR", help="Hyprland config dir (default: $XDG_CONFIG_HOME/hypr).")
    parser.add_argument("--options", metavar="FILE", help="Known getoption names; unknown names go to errors.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    config_dir = Path(os.path.abspath(args.config_dir)) if args.config_dir else default_config_dir()
    # HOME/.config/hypr must name DIR: identity when DIR is the usual place,
    # otherwise the real HOME's path is mapped into DIR by the prelude.
    parts = config_dir.parts
    if len(parts) > 2 and parts[-2:] == (".config", "hypr"):
        home = str(Path(*parts[:-2]))
    else:
        home = os.environ.get("HOME") or str(Path.home())
    out = read_base(config_dir, home)
    if args.options and out["ok"]:
        try:
            known = load_known_options(args.options)
        except (OSError, ValueError, KeyError, TypeError) as exc:
            out["errors"].append(f"cannot read {args.options}: {exc}")
        else:
            out["errors"].extend(f"unknown option '{name}'" for name in sorted(out["config"]) if name not in known)
    print(json.dumps(out, sort_keys=True))
    return 0 if out["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
