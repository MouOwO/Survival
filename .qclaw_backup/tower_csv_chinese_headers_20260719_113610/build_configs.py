"""Build generated Lua config modules from categorized CSV files."""
from __future__ import annotations
import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CSV_ROOT = ROOT / "data" / "csv"
OUT_ROOT = ROOT / "scripts" / "vscripts" / "config" / "generated"
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def lua_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "\\r").replace("\n", "\\n")


def value(raw: str, kind: str) -> str:
    raw = raw.strip()
    if not raw:
        return ""
    if kind == "number":
        if not re.fullmatch(r"[-+]?\d+(?:\.\d+)?", raw):
            raise ValueError(f"invalid number: {raw}")
        return raw
    if kind == "boolean":
        return "true" if raw.lower() in {"1", "true", "yes", "y", "on"} else "false"
    if kind == "list":
        return "{" + ", ".join(f'"{lua_escape(x.strip())}"' for x in raw.split("|")) + "}"
    return f'"{lua_escape(raw)}"'


def build(source: Path, output: Path) -> None:
    raw = source.read_bytes()
    for encoding in ("utf-8-sig", "utf-8", "gb18030", "gbk"):
        try:
            text = raw.decode(encoding)
            break
        except UnicodeDecodeError:
            text = None
    if text is None:
        raise UnicodeDecodeError("unknown", raw, 0, 1, f"unsupported CSV encoding: {source}")
    rows = list(csv.reader(text.splitlines()))
    if len(rows) < 2:
        raise ValueError(f"CSV requires header and #types row: {source}")
    headers = rows[0]
    types = rows[1]
    if types and types[0].startswith("#types:"):
        types[0] = types[0][7:]
    if len(headers) != len(types):
        raise ValueError(f"header/type count mismatch: {source}")
    lines = [
        "-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.",
        f"-- Source: {source.name}",
        "local M = {}",
        "M.rows = {",
    ]
    for fields in rows[2:]:
        if not fields or (len(fields) == 1 and not fields[0].strip()):
            continue
        parts = []
        for key, raw, kind in zip(headers, fields, types):
            converted = value(raw, kind)
            if not converted:
                continue
            lua_key = key if IDENT.fullmatch(key) else f'["{lua_escape(key)}"]'
            parts.append(f"{lua_key} = {converted}")
        lines.append("    { " + ", ".join(parts) + " },")
    lines += [
        "}",
        "M.by_id = {}",
        "for _, row in ipairs(M.rows) do",
        f'    local key = row["{headers[0]}"]',
        "    if key ~= nil then M.by_id[key] = row end",
        "end",
        "return M",
        "",
    ]
    output.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def main() -> int:
    files = sorted(CSV_ROOT.rglob("*.csv"))
    if not files:
        print(f"ERROR: no CSV files under {CSV_ROOT}", file=sys.stderr)
        return 11
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    for old in OUT_ROOT.glob("*.lua"):
        old.unlink()
    for source in files:
        print(f"[CSV -> Lua] {source.relative_to(CSV_ROOT)}")
        build(source, OUT_ROOT / f"{source.stem}.lua")
    names = sorted(source.stem for source in files)
    index = ["-- AUTO-GENERATED CONFIG REGISTRY.", "local M = {}", ""]
    index += [f'M["{name}"] = require("config/generated/{name}")' for name in names]
    index += ["", "return M", ""]
    (OUT_ROOT / "index.lua").write_text("\n".join(index), encoding="utf-8", newline="\n")
    print(f"SUCCESS: generated {len(names)} Lua config modules")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
