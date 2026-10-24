"""Build WS4-ENTRY-05 from signed v04, retaining its complete gameplay body.

Default is a read-only plan. --build alone creates explicit new external
outputs. Only addoninfo, a fixed prefix on the frozen server entry, and three
new launcher resources may differ. No upload, installation or game launch.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_web_auth_candidate as web

pack = web.pack
ROOT = web.ROOT
BASE = Path("D:/Survival_发布候选/20261024_ws4_web_auth_v04")
BASE_TRUSTED = BASE.with_name(BASE.name + "_trusted_source")
BASE_SHA = "f5be8205cd107797f75c5b930224933de8c15f10e9a9e17932b3d6d747f91eb7"
BASE_FILES = 6627
BASE_SEQUENCE = 2026102404
RELEASE_SEQUENCE = 2026102405
REVISION = "WS4-ENTRY-05"
ADDONINFO = "addoninfo.txt"
MAIN = "scripts/vscripts/addon_game_mode.lua"
ENTRY_MAP = "maps/ws4_entry.vpk"
ENTRY_MODULE = "scripts/vscripts/systems/workshop_entry.lua"
CLIENT_MODULE = "scripts/vscripts/addon_game_mode_client.lua"
MODIFIED = frozenset((ADDONINFO, MAIN))
ADDED = frozenset((ENTRY_MAP, ENTRY_MODULE, CLIENT_MODULE))
ALLOWLIST = MODIFIED | ADDED
POLICY_MODULE = "scripts/vscripts/core/release_policy.lua"
WEB_CONFIG = "scripts/vscripts/config/player_web_auth.lua"
ENTRY_PREFIX = (
    b"-- Keep the Workshop entry independent of gameplay and cloud initialization.\n"
    b'if type(GetMapName) == "function" and GetMapName() == "ws4_entry" then\n'
    b'    local entry = require("systems/workshop_entry")\n'
    b"    function Precache() end\n"
    b"    function Activate()\n"
    b"        local ok, reason = entry.activate()\n"
    b'        if not ok then print("[WS4-ENTRY-05] server_unavailable reason=" .. tostring(reason)) end\n'
    b"    end\n"
    b"    return\n"
    b"end\n\n"
)
ENTRY_LAYOUT = {"addoninfo": {"maps": "ws4_entry", "isplayable": "1", "enablepickrules": "0",
                              "ws4_entry": {"maxplayers": "1"}, "template_map": {"maxplayers": "4"}}}


def authenticate_base():
    pinned, _ = pack.handoff.trusted_policy(pack.handoff.POLICY)
    with web.trusted_root(BASE_TRUSTED):
        base, manifest, signature, _ = pack.authenticate(BASE)
    web.need(manifest["content_sha256"] == BASE_SHA and manifest["file_count"] == BASE_FILES,
             "Immutable v04 entry baseline identity mismatch")
    web.need(signature["release_sequence"] == BASE_SEQUENCE, "Unexpected v04 release sequence")
    web.need(signature["key_id"] == pinned["integrity"]["trusted_key_id"],
             "v04 trusted key differs from checkout pin")
    pack.runtime.require_production(base)
    web.need(b"enabled = true" in pack.protect_data.source_path(base, WEB_CONFIG).read_bytes(),
             "Frozen web authorization must stay enabled")
    return base, manifest, signature


def validate_entry_map(raw):
    """Bound and CRC-check the self-contained compiled entry VPK; never load it."""
    web.need(28 <= len(raw) <= 16 * 1024 * 1024, "Entry map VPK absent or oversized")
    magic, version, tree_size, payload_size, archive_md5, other_md5, signature = struct.unpack_from("<7I", raw)
    web.need(magic == 0x55AA1234 and version == 2 and tree_size > 0
             and 28 + tree_size + payload_size + archive_md5 + other_md5 + signature == len(raw),
             "Entry map VPK header invalid")
    cursor, end, paths = 28, 28 + tree_size, set()

    def string():
        nonlocal cursor
        terminator = raw.find(b"\0", cursor, end)
        web.need(terminator >= cursor, "Entry map VPK tree string is truncated")
        value = raw[cursor:terminator].decode("utf-8")
        cursor = terminator + 1
        return value

    while (extension := string()):
        while (directory := string()):
            while (name := string()):
                web.need(cursor + 18 <= end, "Entry map VPK tree record is truncated")
                crc, preload, archive, offset, length, terminator = struct.unpack_from("<IHHIIH", raw, cursor)
                cursor += 18
                web.need(terminator == 65535 and archive == 32767 and cursor + preload <= end
                         and offset + length <= payload_size, "Entry map VPK record is invalid or external")
                path = (directory + "/" if directory != " " else "") + name + "." + extension
                web.need(pack.runtime.safe_relative(path) and path.casefold() not in paths
                         and (path.startswith("maps/ws4_entry/") or path.startswith("maps/ws4_entry.")),
                         "Entry map VPK path is outside the reviewed map")
                paths.add(path.casefold())
                data = raw[cursor:cursor + preload] + raw[end + offset:end + offset + length]
                web.need(zlib.crc32(data) == crc, "Entry map VPK entry CRC mismatch")
                cursor += preload
    web.need(cursor == end and {"maps/ws4_entry.vmap_c", "maps/ws4_entry/world.vwrld_c",
                               "maps/ws4_entry/entities/default_ents.vents_c"} <= paths,
             "Entry map VPK tree or required world resources invalid")
    return {"entries": len(paths), "crc32_verified": True, "external_archives": False}


def capture_inputs(base):
    snapshots = {name: pack.protect_data.source_path(ROOT, name).read_bytes() for name in sorted(ALLOWLIST)}
    web.need(pack.handoff.kv(snapshots[ADDONINFO].decode("utf-8-sig")) == ENTRY_LAYOUT,
             "Entry addoninfo must expose only ws4_entry 1 and retain internal template_map 4")
    web.need(web.lf(snapshots[MAIN]).startswith(ENTRY_PREFIX), "Reviewed server entry prefix differs")
    for name in (ENTRY_MODULE, CLIENT_MODULE):
        web.need(REVISION.encode("ascii") in snapshots[name], "Entry Lua is missing WS4-ENTRY-05: " + name)
    map_review = validate_entry_map(snapshots[ENTRY_MAP])
    frozen_main = pack.protect_data.source_path(base, MAIN).read_bytes()
    web.need(not web.lf(frozen_main).startswith(ENTRY_PREFIX), "Frozen v04 already contains the entry prefix")
    patches = {**snapshots, MAIN: ENTRY_PREFIX + frozen_main}
    return snapshots, patches, map_review


def require_review_unchanged(snapshots, head):
    for name, raw in snapshots.items():
        web.need(pack.protect_data.source_path(ROOT, name).read_bytes() == raw,
                 "Reviewed Workshop entry input changed during build")
    web.need(web.git("rev-parse", "HEAD").decode("ascii").strip() == head, "Reviewed HEAD changed during build")


def audit_changes(baseline, candidate, patches, protected):
    before = {row["path"]: row for row in baseline["files"]}
    after = {row["path"]: row for row in candidate["files"]}
    web.need(not before.keys() - after.keys() and after.keys() - before.keys() == ADDED,
             "Entry runtime must add exactly its three launcher resources")
    web.need(baseline["file_count"] == len(before) == BASE_FILES
             and candidate["file_count"] == len(after) == BASE_FILES + 3,
             "Entry release must retain 6627 old paths and exactly 6630 total files")
    web.need(set(patches) == ALLOWLIST, "Entry replacements must match the five-file allowlist")
    changed = {name for name in before if before[name] != after[name]}
    web.need(changed == MODIFIED, "Only addoninfo and the frozen server entry may change")
    web.need(len(protected) == len(set(protected)) == 180 and POLICY_MODULE in protected
             and set(protected) <= before.keys() and not set(protected) & ALLOWLIST,
             "The complete protected 180-module set must stay outside the entry overlay")
    for name, raw in patches.items():
        web.need(after[name]["sha256"] == web.sha(raw) and after[name]["bytes"] == len(raw),
                 "Entry overlay changed during staging")
    web.need(all(before[name] == after[name] for name in protected), "A protected runtime module changed")
    frozen = before[MAIN]
    suffix = patches[MAIN][len(ENTRY_PREFIX):]
    web.need(patches[MAIN].startswith(ENTRY_PREFIX) and len(suffix) == frozen["bytes"]
             and web.sha(suffix) == frozen["sha256"], "Frozen server entry body must remain byte-identical")
    web.need(pack.handoff.kv(patches[ADDONINFO].decode("utf-8-sig")) == ENTRY_LAYOUT, "Entry addoninfo layout changed")
    return [{"path": name, "before": before.get(name), "after": after[name]} for name in sorted(ALLOWLIST)]


def trusted_snapshot(destination, trusted, base):
    web.need(set(pack.handoff.ENTRY_GATE_FILES) == {ENTRY_MODULE, CLIENT_MODULE}
             and len(pack.handoff.GATE_FILES) == 7 and MAIN in pack.handoff.GATE_FILES,
             "Reviewed entry gate inventory differs")
    trusted.mkdir(parents=True, exist_ok=False)
    for name in (*pack.handoff.GATE_FILES, *pack.handoff.ENTRY_GATE_FILES,
                 pack.handoff.ACCESS_FILE, *web.POLICY_FILES):
        origin = BASE_TRUSTED if name in web.POLICY_FILES else destination if name in {MAIN, ENTRY_MODULE, CLIENT_MODULE} else base
        target = trusted / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(pack.protect_data.source_path(origin, name).read_bytes())


def build(args):
    web.need(args.sequence == RELEASE_SEQUENCE, "WS4-ENTRY-05 requires the fixed v05 release sequence")
    base, baseline, signature = authenticate_base()
    protected = web.protected_paths(baseline)
    head = web.git("rev-parse", "HEAD").decode("ascii").strip()
    snapshots, patches, map_review = capture_inputs(base)
    result = {"ok": True, "status": "READ_ONLY_PLAN", "revision": REVISION,
              "base_content_sha256": BASE_SHA, "base_files": BASE_FILES,
              "base_signature_sequence": signature["release_sequence"], "release_sequence": args.sequence,
              "expected_files": BASE_FILES + 3, "allowed_changes": sorted(ALLOWLIST),
              "protected_modules_preserved": len(protected), "reviewed_head": head,
              "sources": {name: web.sha(raw) for name, raw in snapshots.items()},
              "patches": {name: web.sha(raw) for name, raw in patches.items()}, "entry_map": map_review,
              "frozen_main_body_preserved": True, "development_main_body_substituted": False,
              "online_authentication_changed": False, "online_cheats_allowed": False,
              "four_account_only": True, "workshop_upload_performed": False, "game_started": False}
    if not args.build:
        return result
    web.need(args.signing_key is not None, "--build requires --signing-key")
    destination, trusted, package_output, key = web.output_paths(args, base)
    web.need(web.LUA_COMPILER.is_file(), "Reviewed Lua 5.1 compiler is unavailable")
    web.protect_runtime_lua.syntax_check([pack.protect_data.source_path(ROOT, name)
                                        for name in (MAIN, ENTRY_MODULE, CLIENT_MODULE)], web.LUA_COMPILER)
    destination.mkdir(parents=True, exist_ok=False)
    for row in baseline["files"]:
        target = destination / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(pack.protect_data.source_path(base, row["path"]), target)
    for name, raw in patches.items():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
    manifest = pack.runtime.manifest(destination)
    changed = audit_changes(baseline, manifest, patches, protected)
    pack.runtime.require_production(destination)
    pack.handoff.require_single_map(destination)
    web.protect_runtime_lua.syntax_check([destination / name for name in (MAIN, ENTRY_MODULE, CLIENT_MODULE)], web.LUA_COMPILER)
    require_review_unchanged(snapshots, head)
    trusted_snapshot(destination, trusted, base)
    pack.runtime.atomic_write_json(destination / pack.handoff.MANIFEST, manifest)
    pack.protect_data.sign_manifest(destination / pack.handoff.MANIFEST, key, destination / pack.handoff.SIGNATURE, args.sequence)
    with web.trusted_root(trusted):
        _, authenticated, signed, _ = pack.authenticate(destination)
        web.need(authenticated["content_sha256"] == manifest["content_sha256"], "Signed entry candidate identity mismatch")
        packaged = None
        if package_output is not None:
            package_output.mkdir(parents=True, exist_ok=False)
            packaged = pack.package(destination, package_output, "3824360109", build=True)
    result.update(status="SIGNED_ENTRY_REQUIRES_NATIVE_TEST", content_sha256=manifest["content_sha256"],
                  files=manifest["file_count"], changed=changed, signature_valid=signed["signature_valid"],
                  protected_modules_rebuilt=0, plaintext_substitution=False, all_other_runtime_bytes_preserved=True,
                  private_key_copied=False, destination=str(destination), trusted_source=str(trusted), packaged=packaged,
                  lua_syntax="PASS", native_dota_smoke="NOT_RUN")
    pack.runtime.atomic_write_json(destination / "_workshop_entry_provenance.json", result)
    return result


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--build", action="store_true")
    result.add_argument("--destination", type=Path)
    result.add_argument("--trusted-source", type=Path)
    result.add_argument("--signing-key", type=Path)
    result.add_argument("--sequence", type=int, default=RELEASE_SEQUENCE)
    result.add_argument("--package-output", type=Path)
    return result


def main():
    try:
        print(json.dumps(build(parser().parse_args()), ensure_ascii=True))
        return 0
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(json.dumps({"ok": False, "error": "workshop_entry_build_failed", "detail": str(error)[:500]}, ensure_ascii=True))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
