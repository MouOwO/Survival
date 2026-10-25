"""Build the project's own ws4_lobby using its reviewed minimal-map generator.

The default only reads a plan. --build creates the two fixed new map files and
ignored logs. No old map, material, entry source, or generator is replaced.
Player limits belong to addoninfo; this map is intended for its one-player lobby.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time
import types

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT.parents[2]
CONTENT = ENGINE / "content/dota_addons/Survival"
GENERATOR = ROOT / "tools/build_workshop_entry_map.py"
GENERATOR_SHA256 = "e8124a270ca942e9f0f2b7aae5642c33b118e7411c19d9a3586c6141087c2b27"
NAME = "ws4_lobby"
SOURCE = CONTENT / f"maps/{NAME}.vmap"
RUNTIME = ROOT / f"maps/{NAME}.vpk"
ASSET_ROOTS = (ROOT / "maps", ROOT / "materials", CONTENT / "maps", CONTENT / "materials")
REPARSE = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)


def need(value, reason):
    if not value:
        raise ValueError(reason)


def safe_path(path, *, absent=False):
    """Check the actual path and every ancestor without resolving links away."""
    for item in (*path.parents, path):
        try:
            info = item.lstat()
        except FileNotFoundError:
            need(absent and item == path, "A required path is missing")
            continue
        need(not stat.S_ISLNK(info.st_mode) and not getattr(info, "st_file_attributes", 0) & REPARSE,
             "Links and reparse points are forbidden")
        if item != path:
            need(stat.S_ISDIR(info.st_mode), "A parent is not a regular directory")


def sha_file(path):
    safe_path(path)
    need(stat.S_ISREG(path.lstat().st_mode), "Expected a regular file")
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def generator():
    safe_path(GENERATOR)
    raw = GENERATOR.read_bytes()
    # Git checkout line endings do not change the reviewed Python generator.
    need(hashlib.sha256(raw.replace(b"\r\n", b"\n")).hexdigest() == GENERATOR_SHA256,
         "Reviewed own-map generator changed")
    # A private namespace prevents changing the original entry generator globals.
    own = types.ModuleType("_ws4_hosted_lobby_own_generator")
    own.__file__ = str(GENERATOR)
    exec(compile(raw, str(GENERATOR), "exec"), own.__dict__)
    own.NAME, own.SOURCE, own.RUNTIME = NAME, SOURCE, RUNTIME
    own.ENTITY_NAMES = {key: value.replace("ws4_entry_", "ws4_lobby_")
                        for key, value in own.ENTITY_NAMES.items()}
    need(all(value.startswith("ws4_lobby_") for value in own.ENTITY_NAMES.values()),
         "Lobby entity namespace is invalid")
    return own


def inventory(*, exclude=()):
    """Hash original assets, without copying them or following directory links."""
    result = {}
    excluded = frozenset(exclude)
    for root in ASSET_ROOTS:
        safe_path(root)
        need(root.is_dir(), "An original asset directory is unavailable")
        for folder, directories, files in os.walk(root, followlinks=False):
            for name in directories:
                safe_path(Path(folder) / name)
            for name in files:
                path = Path(folder) / name
                safe_path(path)
                if path not in excluded:
                    result[path.relative_to(ENGINE).as_posix()] = {
                        "bytes": path.stat().st_size, "sha256": sha_file(path)}
    return result


def inventory_sha(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def require_new_outputs():
    for path in (SOURCE, RUNTIME):
        safe_path(path, absent=True)
        need(not os.path.lexists(path), "Lobby output exists; overwrite is forbidden")
    # A previous unpacked build would also collide with this fixed map namespace.
    for folder in (ROOT / f"maps/{NAME}", CONTENT / f"maps/{NAME}"):
        safe_path(folder, absent=True)
        need(not os.path.lexists(folder), "Lobby build directory already exists")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true", help="Create only the fixed new lobby map and ignored logs")
    args = parser.parse_args()
    own = generator()
    safe_path(own.TEMPLATE)
    raw = own.TEMPLATE.read_bytes()
    text = own.generate(raw)
    need(b"ws4_entry_" not in text and all(value.encode() in text for value in own.ENTITY_NAMES.values()),
         "Lobby source contains an unexpected entity namespace")
    for path in (SOURCE, RUNTIME, ROOT / f"maps/{NAME}", CONTENT / f"maps/{NAME}"):
        safe_path(path, absent=True)
    result = dict(ok=True, status="READ_ONLY_PLAN", map=NAME, intended_entry_max_players=1,
        generator_sha256=GENERATOR_SHA256, template_sha256=own.sha(raw),
        text_source_sha256=own.sha(text), text_source_bytes=len(text), grid=[16, 16],
        meshes=2, entities=7, decoration_entities=0, material_dependencies=[own.FLOOR_MATERIAL],
        source=str(SOURCE), runtime=str(RUNTIME), source_exists=SOURCE.exists(), runtime_exists=RUNTIME.exists(),
        game_started=False)
    if not args.build:
        print(json.dumps(result, ensure_ascii=True))
        return

    require_new_outputs()
    convert = ENGINE / "game/bin/win64/dmxconvert.exe"
    compiler = ENGINE / "game/bin/win64/resourcecompiler.exe"
    for executable in (convert, compiler):
        safe_path(executable)
        need(executable.is_file(), "Valve map compilation tools are unavailable")
    original = inventory()
    # Existing output/ is ignored. Validate its ancestors before making a new
    # unique log directory, then check again before launching native programs.
    output = ROOT / "output"
    safe_path(output)
    need(output.is_dir(), "The existing ignored output directory is unavailable")
    work = output / ("hosted_lobby_map_" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ"))
    safe_path(work, absent=True)
    work.mkdir(exist_ok=False)
    safe_path(work)
    authored, binary = work / f"{NAME}.vmap", work / f"{NAME}_binary.vmap"
    with authored.open("xb") as stream:
        stream.write(text)
    result.update(logs=str(work), original_asset_files=len(original), original_assets_sha256=inventory_sha(original))
    try:
        with (work / "convert.log").open("xb") as log:
            converted = subprocess.run([str(convert), "-i", str(authored), "-o", str(binary), "-oe", "binary"],
                stdout=log, stderr=subprocess.STDOUT, timeout=120)
        need(converted.returncode == 0 and binary.is_file(), "Lobby DMX conversion failed; inspect convert.log")
        safe_path(binary)
        binary_raw = binary.read_bytes()
        need(binary_raw.startswith(b"<!-- dmx encoding binary"), "Unexpected binary map source")
        require_new_outputs()
        with SOURCE.open("xb") as stream:
            stream.write(binary_raw)
        started = time.time_ns()
        with (work / "compile.log").open("xb") as log:
            compiled = subprocess.run([str(compiler), "-i", str(SOURCE), "-game", str(ENGINE / "game/dota"),
                "-fshallow", "-nop4"], stdout=log, stderr=subprocess.STDOUT, timeout=600)
        log_text = (work / "compile.log").read_text(encoding="utf-8", errors="replace")
        need(compiled.returncode == 0 and "--> Map build finished." in log_text
             and not re.search(r"(?im)^Write .+\.vpk Failed!", log_text), "Lobby compilation failed; inspect compile.log")
        safe_path(RUNTIME)
        need(RUNTIME.is_file() and RUNTIME.stat().st_size > 0 and RUNTIME.stat().st_mtime_ns >= started,
             "Lobby VPK is missing, empty or stale")
        entries = own.verify_vpk(RUNTIME)
        need(SOURCE.read_bytes() == binary_raw, "Lobby source changed during compilation")
        after = inventory(exclude=(SOURCE, RUNTIME))
        need(after == original, "An original map/material changed or an unexpected asset was added")
        result.update(status="COMPILED_CRC_VERIFIED", source_sha256=own.sha(binary_raw), source_bytes=len(binary_raw),
            runtime_sha256=sha_file(RUNTIME), runtime_bytes=RUNTIME.stat().st_size, vpk_entries=entries,
            all_payload_crcs_valid=True, original_maps_and_materials_unchanged=True, compiler_exit_code=compiled.returncode)
    except Exception as error:
        result.update(ok=False, status="FAILED_OUTPUTS_PRESERVED", error_type=type(error).__name__,
                      detail=str(error), partial_outputs_preserved=True)
        with (work / "result.json").open("x", encoding="utf-8") as stream:
            json.dump(result, stream, ensure_ascii=True, indent=2)
        raise
    with (work / "result.json").open("x", encoding="utf-8") as stream:
        json.dump(result, stream, ensure_ascii=True, indent=2)
    print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    main()
