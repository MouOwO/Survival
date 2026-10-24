"""Create the project's own lightweight ws4_entry map with Valve's compiler.

Default is a read-only source plan. --build creates only the new entry source,
its runtime map and logs. Existing gameplay maps and resources are never replaced.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import time
import zlib


ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT.parents[2]
CONTENT = ENGINE / "content/dota_addons/Survival"
TEMPLATE = CONTENT / "maps/gold_training_room_review.vmap"
TEMPLATE_SHA256 = "197f6af542847748fa95d06acabe9db95a968a9daed9cbf01e8f706b03e89b8f"
NAME = "ws4_entry"
SOURCE = CONTENT / f"maps/{NAME}.vmap"
RUNTIME = ROOT / f"maps/{NAME}.vpk"
FLOOR_MATERIAL = "materials/gold_training_room/floor_support.vmat"
ENTITY_NAMES = {"world_bounds": "ws4_entry_bounds", "info_player_start_goodguys": "ws4_entry_start_good",
                "info_player_start_badguys": "ws4_entry_start_bad", "info_player_start": "ws4_entry_start",
                "ent_dota_game_events": "ws4_entry_events", "env_global_light": "ws4_entry_light",
                "env_tonemap_controller": "ws4_entry_tonemap"}


def need(value, reason):
    if not value:
        raise ValueError(reason)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def end_of(text, start, opening="{", closing="}"):
    need(text[start] == opening, "Unexpected DMX opening delimiter")
    depth, quoted, escaped = 0, False, False
    for index in range(start, len(text)):
        char = text[index]
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
        elif char == opening:
            depth += 1
        elif char == closing:
            depth -= 1
            if depth == 0:
                return index + 1
    raise ValueError("Unbalanced DMX structure")


def world_children(text):
    world = text.index('"world" "CMapWorld"')
    array = text.index('"children" "element_array"', world)
    opening = text.index("[", array)
    closing = end_of(text, opening, "[", "]") - 1
    cursor, children = opening + 1, []
    while cursor < closing:
        while cursor < closing and text[cursor] in " \t\r\n,":
            cursor += 1
        if cursor == closing:
            break
        match = re.match(r'"([A-Za-z0-9_]+)"\s*\{', text[cursor:closing])
        need(match is not None, "Unexpected top-level map child")
        block_end = end_of(text, cursor + match.end() - 1)
        need(block_end <= closing, "Map child escapes world array")
        children.append((match.group(1), text[cursor:block_end]))
        cursor = block_end
    return opening, closing, children


def property_value(block, name):
    result = re.search(r'"' + re.escape(name) + r'"\s+"(?:string|int)"\s+"([^"\r\n]*)"', block)
    need(result is not None, "Missing map property: " + name)
    return result.group(1)


def generate(raw):
    need(sha(raw) == TEMPLATE_SHA256, "The reviewed own-map template changed")
    text = raw.decode("utf-8-sig")
    need(text.startswith("<!-- dmx encoding keyvalues2 4 format vmap 40 -->"), "Unexpected template DMX encoding")
    need(property_value(text, "mapUsageType") == "standard", "Entry template must be a standard game map")
    opening, closing, children = world_children(text)
    grids = [block for kind, block in children if kind == "CMapDotaTileGrid"]
    meshes = [block for kind, block in children if kind == "CMapMesh"]
    entities = [block for kind, block in children if kind == "CMapEntity"]
    need(len(grids) == 1 and len(meshes) == 3, "Unexpected own-map geometry inventory")
    need(property_value(grids[0], "gridWidth") == property_value(grids[0], "gridHeight") == "16",
         "Entry template must retain the proven 16 by 16 grid")
    need(all(FLOOR_MATERIAL in block and "materials/gold_training_room/earth.vmat" not in block
             for block in meshes[:2]), "Unexpected floor geometry material")
    classes = Counter(property_value(block, "classname") for block in entities)
    need(classes == Counter({"prop_static": 599, "info_target": 10, **{name: 1 for name in ENTITY_NAMES}}),
         "Unexpected own-map entity inventory")
    minimal = []
    for block in entities:
        classname = property_value(block, "classname")
        if classname not in ENTITY_NAMES:
            continue
        renamed, count = re.subn(r'("targetname"\s+"string"\s+")[^"\r\n]*(")',
                                lambda match: match.group(1) + ENTITY_NAMES[classname] + match.group(2), block)
        need(count == 1, "Unexpected entry entity targetname")
        minimal.append(renamed)
    # Retain the complete Hammer root, world properties and editor bookkeeping;
    # excessively small hand-written roots have caused native compiler crashes.
    result = (text[:opening + 1] + "\n" + ",\n".join([grids[0], *meshes[:2], *minimal])
              + "\n\t\t" + text[closing:])
    _, _, built = world_children(result)
    need(len(built) == 10 and len(minimal) == 7, "Entry map must contain only the reviewed minimal children")
    need('"prop_static"' not in result and '"info_target"' not in result, "Room decoration leaked into entry")
    need(property_value(result, "mapUsageType") == "standard", "Entry must remain a standard game map")
    return result.encode("utf-8")


def verify_vpk(path):
    raw = path.read_bytes()
    need(len(raw) >= 12, "Empty or truncated entry VPK")
    magic, version, tree_size = struct.unpack_from("<III", raw)
    need(magic == 0x55AA1234 and version in (1, 2), "Invalid entry VPK header")
    cursor = 28 if version == 2 else 12
    tree_end = cursor + tree_size
    need(tree_end <= len(raw), "Entry VPK tree escapes file")

    def string():
        nonlocal cursor
        stop = raw.index(b"\0", cursor, tree_end)
        value = raw[cursor:stop].decode("utf-8")
        cursor = stop + 1
        return value

    entries = []
    while extension := string():
        while directory := string():
            while name := string():
                need(cursor + 18 <= tree_end, "Entry VPK record is truncated")
                crc, preload_size, archive, offset, length, terminator = struct.unpack_from("<IHHIIH", raw, cursor)
                cursor += 18
                need(terminator == 0xFFFF and archive == 0x7FFF and cursor + preload_size <= tree_end,
                     "Entry VPK must be a valid self-contained package")
                preload = raw[cursor:cursor + preload_size]
                cursor += preload_size
                start = tree_end + offset
                need(start + length <= len(raw), "Entry VPK payload is truncated")
                need(zlib.crc32(preload + raw[start:start + length]) == crc, "Entry VPK payload CRC mismatch")
                relative = (directory + "/" if directory != " " else "") + name + "." + extension
                need(relative not in entries, "Duplicate entry VPK path")
                need(relative == f"maps/{NAME}.vmap_c" or relative.startswith(f"maps/{NAME}/")
                     or relative in {f"maps/{NAME}.vhcg", f"maps/{NAME}.trm", f"maps/{NAME}.gnv"},
                     "Entry VPK contains another map's resources")
                entries.append(relative)
    need(cursor == tree_end and f"maps/{NAME}.vmap_c" in entries
         and f"maps/{NAME}/world.vwrld_c" in entries, "Entry VPK map/world resources are missing")
    return entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true")
    args = parser.parse_args()
    original = TEMPLATE.read_bytes()
    text = generate(original)
    result = {"ok": True, "status": "READ_ONLY_PLAN", "map": NAME, "template_sha256": sha(original),
              "text_source_sha256": sha(text), "text_source_bytes": len(text), "grid": [16, 16],
              "meshes": 2, "entities": 7, "decoration_entities": 0,
              "material_dependencies": [FLOOR_MATERIAL], "game_started": False}
    if not args.build:
        print(json.dumps(result, ensure_ascii=True))
        return
    need(not SOURCE.exists() and not RUNTIME.exists(), "Entry output exists; existing files will not be replaced")
    binaries = ENGINE / "game/bin/win64"
    convert, compiler = binaries / "dmxconvert.exe", binaries / "resourcecompiler.exe"
    need(convert.is_file() and compiler.is_file(), "Valve map compilation tools are unavailable")
    # Snapshot existing files which this build must not change, including the
    # user's current bytes rather than their Git versions.
    preserved = {path: path.read_bytes() for path in (TEMPLATE, ROOT / "maps/template_map.vpk",
                 ROOT / "maps/gold_training_room_review.vpk", ROOT / (FLOOR_MATERIAL + "_c"))}
    work = ROOT / "output/workshop_entry_map" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
    work.mkdir(parents=True, exist_ok=False)
    authored, binary = work / f"{NAME}.vmap", work / f"{NAME}_binary.vmap"
    authored.write_bytes(text)
    with (work / "convert.log").open("wb") as log:
        converted = subprocess.run([str(convert), "-i", str(authored), "-o", str(binary), "-oe", "binary"],
                                   stdout=log, stderr=subprocess.STDOUT, timeout=120)
    need(converted.returncode == 0 and binary.is_file(), "Entry DMX conversion failed; inspect convert.log")
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    with SOURCE.open("xb") as stream:
        stream.write(binary.read_bytes())
    started = time.time_ns()
    with (work / "compile.log").open("wb") as log:
        compiled = subprocess.run([str(compiler), "-i", str(SOURCE), "-game", str(ENGINE / "game/dota"),
                                   "-fshallow", "-nop4"], stdout=log, stderr=subprocess.STDOUT, timeout=600)
    log_text = (work / "compile.log").read_text(encoding="utf-8", errors="replace")
    need(compiled.returncode == 0 and "--> Map build finished." in log_text
         and not re.search(r"(?im)^Write .+\.vpk Failed!", log_text), "Entry compilation failed; inspect compile.log")
    need(RUNTIME.is_file() and RUNTIME.stat().st_size > 0 and RUNTIME.stat().st_mtime_ns >= started,
         "Entry VPK is missing, empty or stale")
    entries = verify_vpk(RUNTIME)
    need(all(path.read_bytes() == raw for path, raw in preserved.items()), "An original gameplay map/resource changed")
    need(SOURCE.read_bytes() == binary.read_bytes(), "Entry source changed during compilation")
    result.update(status="COMPILED_CRC_VERIFIED", source=str(SOURCE), source_sha256=sha(SOURCE.read_bytes()),
                  source_bytes=SOURCE.stat().st_size, runtime=str(RUNTIME), runtime_sha256=sha(RUNTIME.read_bytes()),
                  runtime_bytes=RUNTIME.stat().st_size, vpk_entries=entries, all_payload_crcs_valid=True,
                  original_maps_unchanged=True, compiler_exit_code=compiled.returncode, logs=str(work))
    (work / "result.json").write_text(json.dumps(result, ensure_ascii=True, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    main()
