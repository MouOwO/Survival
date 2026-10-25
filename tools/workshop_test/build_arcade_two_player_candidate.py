"""Read-only plan, or explicit new signed MP10 native two-player test candidate.

Patch only the authenticated immutable v08 bytes and reviewed public additions.
No install, Steam operation, GUI, service call, protected-Lua rebuild or key copy.
Unfilled review pins fail closed before baseline/key/output access.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_multiplayer_candidate as previous

web, pack = previous.web, previous.pack
ROOT = previous.ROOT
CONTENT = ROOT.parents[2] / "content/dota_addons/Survival"
BASE, BASE_TRUSTED = previous.BASE, previous.BASE_TRUSTED
BASE_SHA, BASE_FILES, BASE_SEQUENCE = previous.BASE_SHA, 6630, 2026102503
REVISION, RELEASE_SEQUENCE = "WS4-MP-10", 2026102507
DESTINATION = Path("D:/Survival_发布候选/20261025_ws4_arcade_two_player_v10r2")
TRUSTED_DESTINATION = DESTINATION.with_name(DESTINATION.name + "_trusted_source")
PACKAGE_OUTPUT = Path("D:/Survival_工坊输出/20261025_ws4_arcade_two_player_v10r2")
MAIN, WEB_CONFIG = previous.MAIN, previous.WEB_CONFIG
PROFILE = "scripts/vscripts/systems/player_profile_service.lua"
SESSION = "scripts/vscripts/systems/session_multiplayer_test.lua"
SESSION_CONFIG = "scripts/vscripts/config/session_multiplayer_test.lua"
PROBE = "scripts/vscripts/systems/workshop_network_probe.lua"
STATUS = "scripts/vscripts/systems/arcade_multiplayer_test.lua"
ADDONINFO, NETTABLES = "addoninfo.txt", "scripts/custom_net_tables.txt"
ENTRY_MAP, RELEASE_PROFILE = "maps/ws4_entry.vpk", "scripts/vscripts/config/release_profile.lua"
MANIFEST_SOURCE = "layout/custom_game/custom_ui_manifest.xml"
MANIFEST_COMPILED = "panorama/layout/custom_game/custom_ui_manifest.vxml_c"
MANIFEST_COMMIT = "4edea828552ee522bc19bcfaa1c2a8ea14172d2b"
MANIFEST_LINE = b'    <CustomUIElement type="Hud" layoutfile="file://{resources}/layout/custom_game/arcade_multiplayer_test.xml" />'
MANIFEST_OVERLAY = ROOT / "output/arcade_two_player_20261025/manifest_overlay"
COMPILE_DIRECTORY = ROOT / "output/arcade_two_player_20261025"
MANIFEST_REPORT = COMPILE_DIRECTORY / "ui_compile.json"
UI_DIRECTORY = ROOT / "output/arcade_multiplayer_test_20261025"
UI_REPORT = UI_DIRECTORY / "verification.json"
UI_SOURCES = ("layout/custom_game/arcade_multiplayer_test.xml",
              "styles/custom_game/arcade_multiplayer_test.css",
              "scripts/custom_game/arcade_multiplayer_test.js")
UI_COMPILED = ("panorama/layout/custom_game/arcade_multiplayer_test.vxml_c",
               "panorama/styles/custom_game/arcade_multiplayer_test.vcss_c",
               "panorama/scripts/custom_game/arcade_multiplayer_test.vjs_c")
UI_LOGS = ("compile_xml.log", "compile_css.log", "compile_js_native_diag.log")
UI_TEST = "tools/tests/test_arcade_multiplayer_test.cjs"
PUBLIC_SOURCES = frozenset((SESSION, SESSION_CONFIG, PROBE, STATUS))
MODIFIED = frozenset((MAIN, PROFILE, WEB_CONFIG, ADDONINFO, NETTABLES, MANIFEST_COMPILED))
ADDED = frozenset((*PUBLIC_SOURCES, *UI_COMPILED))
ALLOWLIST = MODIFIED | ADDED
REMOVED = frozenset((ENTRY_MAP,))
EXPECTED_FILES = BASE_FILES + len(ADDED) - len(REMOVED)
POLICY_MODULE, LUA_POLICY_SHA = previous.POLICY_MODULE, previous.LUA_POLICY_SHA
BEGIN = b"-- BEGIN WS4-MP-10 NATIVE ACCEPTANCE WRAPPER\r\n"
END = b"-- END WS4-MP-10 NATIVE ACCEPTANCE WRAPPER\r\n"
TAIL = b"return M\r\n"
WRAPPER = BEGIN + (
    b"do\r\n"
    b"    local previous_activate = Activate\r\n"
    b"    if type(previous_activate) == \"function\" then\r\n"
    b"        local function after_activate(...)\r\n"
    b"            pcall(function() require(\"systems/workshop_network_probe\").activate() end)\r\n"
    b"            pcall(function() require(\"systems/arcade_multiplayer_test\").activate() end)\r\n"
    b"            return ...\r\n"
    b"        end\r\n"
    b"        Activate = function(...)\r\n"
    b"            return after_activate(previous_activate(...))\r\n"
    b"        end\r\n"
    b"    end\r\n"
    b"end\r\n"
) + END
MAIN_INIT = b'    require("systems/player_profile_service").init()\r\n'
MAIN_SESSION_INIT = (
    b'    local session_test = require("systems/session_multiplayer_test")\r\n'
    b'    session_test.configure()\r\n'
    b'    require("systems/player_profile_service").init(session_test.profile_options())\r\n'
)
PROFILE_PATCHES = (
    (b"local injected_provider = false\r\n",
     b"local injected_provider = false\r\nlocal session_multiplayer_provider = false\r\n"),
    (b'    if injected_provider then return "injected_fixture" end\r\n',
     b'    if injected_provider and not session_multiplayer_provider then return "injected_fixture" end\r\n'),
    (b'    if injected_provider then return "standard", "injected_fixture" end\r\n',
     b'    if injected_provider and not session_multiplayer_provider then return "standard", "injected_fixture" end\r\n'),
    (b"    if injected_provider then return true end\r\n",
     b"    if injected_provider and not session_multiplayer_provider then return true end\r\n"),
    (b"    if not injected_provider then\r\n        if not validate_progression(snapshot.progression) then\r\n",
     b"    if not injected_provider or session_multiplayer_provider then\r\n        if not validate_progression(snapshot.progression) then\r\n"),
    (b"    injected_provider = options and options.provider ~= nil or false\r\n    if injected_provider then\r\n",
     b"    injected_provider = options and options.provider ~= nil or false\r\n"
     b"    session_multiplayer_provider = options and options.session_multiplayer_test == true or false\r\n"
     b"    if session_multiplayer_provider then\r\n"
     b'        assert(injected_provider and require("systems/session_multiplayer_test").is_provider(options.provider),\r\n'
     b'            "session_multiplayer_provider_required")\r\n'
     b"    end\r\n"
     b"    if injected_provider then\r\n"),
)

# Reviewed after source, frozen-patch, lifecycle and native compile checks.
# These constants, not caller flags or receipt-owned values, authorize bytes.
PATCH_PINS = {
    MAIN: "2720298a60e3fa61313ecdc7a1b6688f67e1e5415167f4415705c2d14629dc34",
    PROFILE: "e746f72e24dd76d53d11da62d501346178018783ad8ce3ed20ce0301b6039894",
    WEB_CONFIG: "214ba155842fbf32b0673e448ea8a620370ecbe14b0a5dc4e88f938a2ad40b6a",
    ADDONINFO: "079accc9976da77481a465a883a2e9991ed217828b5f41cd159bf19258a1d197",
    NETTABLES: "9cf33d531e29d37255e2ada168edd462f9862d05e665c2b8bd4db74db6f75586",
    MANIFEST_COMPILED: "5b5e1fe3707b7f2dacd45bf4f624703a59cfcab9c3c5d27030cd112caf72a94f",
    SESSION_CONFIG: "afd2279e385e1d244db389de2cbb9c52bde8fd44072f9e5fe4d8a651a610b9c0",
    SESSION: "df6fc593f0a99bf5e4c88b25ed946a5efd3664d786c18da77741f1aad75a71b3",
    PROBE: "0f4b1d4cb29b7dfc152a7cd86db94c01364a14f030f56719836759077ab81349",
    STATUS: "ffcff0e35dd9797d199932a85eb17d45ad3f2327da47909fe043f5cfb669a57f",
    UI_COMPILED[0]: "758b18d7f6ad51a3a76f5b6a5956e3046bf85235be2b06e96e0c441b6ac19677",
    UI_COMPILED[1]: "b1f146069f92bd1c29e601970f5a27d01e7672df65e945c7e48df762520e8cdd",
    UI_COMPILED[2]: "8b802c8860d89262ec83af82274356a80da91428dfcf1472462bd036578e416a",
}
SOURCE_PINS = {name: PATCH_PINS[name] for name in PUBLIC_SOURCES}
SOURCE_PINS[SESSION_CONFIG] = "68781cf8bfc5d0f599dd2dd6fa048d9205be2aa14c6b305d0f22a9356ef6572b"
UI_REPORT_SHA = "7c2a8efbb5b3ab544f88cb4edd96e3983b5ed623b55a0c41e69eba6c47424e7b"
MANIFEST_REPORT_SHA = "7123fe748bb01d447dcaaf2bb3cfde07e53b92d5ab7996ee4e01eff1de7daea8"
WRAPPER_SHA = "0121310341fd14af6a1c4c6cc076799948c648d0d819d6ad41c78d3f079f02f8"


def require_review_pins():
    values = [*PATCH_PINS.values(), *SOURCE_PINS.values(), UI_REPORT_SHA, MANIFEST_REPORT_SHA, WRAPPER_SHA]
    web.need(set(PATCH_PINS) == ALLOWLIST and set(SOURCE_PINS) == PUBLIC_SOURCES
             and all(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) for value in values),
             "MP10 source/compiled review pins are not finalized")
    web.need(web.sha(WRAPPER) == WRAPPER_SHA, "Reviewed MP10 wrapper changed")


def replace_once(raw, before, after):
    web.need(before != after and raw.count(before) == 1, "Frozen patch context absent or ambiguous")
    return raw.replace(before, after, 1)


def patch_main(raw):
    web.need(raw.endswith(b"\r\n\r\n" + TAIL) and BEGIN not in raw and END not in raw,
             "Frozen v08 main must retain its original terminal return")
    result = replace_once(raw, MAIN_INIT, MAIN_SESSION_INIT)
    return result[:-len(TAIL)] + WRAPPER + TAIL


def restore_main(raw):
    web.need(raw.count(WRAPPER) == 1 and raw.endswith(WRAPPER + TAIL), "MP10 main wrapper differs")
    return replace_once(raw[:-len(WRAPPER + TAIL)] + TAIL, MAIN_SESSION_INIT, MAIN_INIT)


def patch_profile(raw):
    web.need(b"session_multiplayer_provider" not in raw, "Frozen profile already contains MP10 changes")
    for before, after in PROFILE_PATCHES:
        raw = replace_once(raw, before, after)
    return raw


def restore_profile(raw):
    for before, after in reversed(PROFILE_PATCHES):
        raw = replace_once(raw, after, before)
    return raw


def patch_nettables(raw):
    web.need(b'"survival_arcade_multiplayer_test"' not in raw, "MP10 net table already present")
    anchor = b'        "survival_commerce_actions",'
    web.need(raw.count(anchor) == 1, "Frozen net table anchor absent or ambiguous")
    suffix = raw[raw.index(anchor) + len(anchor):]
    newline = next((value for value in (b"\r\r\n", b"\r\n", b"\n") if suffix.startswith(value)), None)
    web.need(newline is not None, "Frozen net table newline differs")
    return replace_once(raw, anchor, anchor + newline + b'        "survival_arcade_multiplayer_test",')


def manifest_source(raw):
    anchor = b"  </Panel>"
    web.need(b"arcade_multiplayer_test.xml" not in raw and raw.count(anchor) == 1,
             "Historical UI manifest must accept exactly one new HUD line")
    newline = b"\r\n" if b"\r\n" in raw else b"\n"
    return replace_once(raw, anchor, MANIFEST_LINE + newline + anchor)


def read_input(path, snapshots):
    path = pack.protect_data.source_path(path.parent, path.name)
    raw = path.read_bytes()
    snapshots[path] = raw
    return raw


def compiled_data(raw):
    web.need(28 <= len(raw) <= 4 * 1024 * 1024, "Compiled MP10 resource absent or oversized")
    size, version, _, offset, count = struct.unpack_from("<IHHII", raw)
    table = 8 + offset
    web.need(size == len(raw) and version == 12 and 1 <= count <= 64
             and 16 <= table <= len(raw) - 12 * count, "Compiled MP10 header invalid")
    ranges, data = [], []
    for index in range(count):
        entry = table + index * 12
        tag, displacement, length = struct.unpack_from("<4sII", raw, entry)
        start = entry + 4 + displacement
        web.need(all(32 <= value <= 126 for value in tag) and start >= table + count * 12
                 and start + length <= len(raw)
                 and not any(start < end and begin < start + length for begin, end in ranges),
                 "Compiled MP10 block invalid or overlapping")
        ranges.append((start, start + length))
        if tag == b"DATA": data.append(raw[start:start + length])
    web.need(len(data) == 1, "Compiled MP10 resource must contain one DATA block")
    return data[0]


def capture_ui(snapshots):
    raw = read_input(UI_REPORT, snapshots)
    web.need(web.sha(raw) == UI_REPORT_SHA, "Reviewed MP10 UI receipt changed")
    receipt = pack.handoff.decode_json(raw)
    expected = {*[CONTENT / "panorama" / name for name in UI_SOURCES],
                *[ROOT / "panorama/src" / name for name in UI_SOURCES],
                *[ROOT / name for name in UI_COMPILED], ROOT / UI_TEST}
    rows = receipt.get("files")
    web.need(receipt.get("status") == "PASS" and receipt.get("real_orders") == 0
             and receipt.get("payment_requests") == 0 and isinstance(rows, list) and len(rows) == 10,
             "MP10 UI receipt status or ten-file scope differs")
    mapped = {Path(row["path"]): row for row in rows if isinstance(row, dict) and isinstance(row.get("path"), str)}
    web.need(len(mapped) == 10 and set(mapped) == expected, "MP10 UI receipt contains missing/duplicate/unreviewed files")
    files = {}
    for path, row in mapped.items():
        data = read_input(path, snapshots)
        web.need(row.get("sha256") == web.sha(data) and row.get("bytes") == len(data), "MP10 UI receipt file hash differs")
        files[path] = data
    compiles = receipt.get("native_resource_compile")
    web.need(isinstance(compiles, list) and len(compiles) == 3, "MP10 needs exactly three native compile receipts")
    indexed = {Path(row["source"]): row for row in compiles if isinstance(row, dict) and isinstance(row.get("source"), str)}
    web.need(len(indexed) == 3 and set(indexed) == {CONTENT / "panorama" / name for name in UI_SOURCES},
             "MP10 compile source scope differs")
    patches = {}
    for source, compiled, log_name in zip(UI_SOURCES, UI_COMPILED, UI_LOGS):
        path = CONTENT / "panorama" / source
        data = files[path]
        web.need(data == files[ROOT / "panorama/src" / source], "MP10 game/content source mirrors differ")
        row = indexed[path]
        log_path = UI_DIRECTORY / log_name
        web.need(row.get("exit_code") == 0 and row.get("native_one_success") is True
                 and Path(row.get("log", "")) == log_path, "MP10 native compile failed or log path differs")
        web.need(b"1 compiled, 0 failed, 0 skipped" in read_input(log_path, snapshots), "MP10 native compile success log missing")
        runtime = files[ROOT / compiled]
        payload = compiled_data(runtime)
        if source.endswith(".js"):
            web.need(payload == data, "MP10 compiled JS DATA differs from the reviewed source")
        patches[compiled] = runtime
    return patches


def capture_manifest(snapshots):
    # The current checkout manifest contains unrelated lobby/onboarding work.
    # The fixed historical object, plus one literal line, is the only source.
    original = web.git("show", MANIFEST_COMMIT + ":panorama/src/" + MANIFEST_SOURCE, root=ROOT)
    expected = manifest_source(original)
    raw = read_input(MANIFEST_REPORT, snapshots)
    web.need(web.sha(raw) == MANIFEST_REPORT_SHA, "Reviewed MP10 manifest receipt changed")
    receipt = pack.handoff.decode_json(raw)
    names = (*UI_SOURCES, MANIFEST_SOURCE)
    rows = receipt.get("results")
    web.need(receipt.get("ok") is True and receipt.get("check_only") is False and receipt.get("compiled_files") == 4
             and receipt.get("scope") == list(names) and isinstance(rows, list) and len(rows) == 4,
             "MP10 unified compile receipt must contain exactly four reviewed resources")
    indexed = {row["relative"]: row for row in rows if isinstance(row, dict) and isinstance(row.get("relative"), str)}
    web.need(len(indexed) == 4 and set(indexed) == set(names), "MP10 compile receipt has duplicate or unknown resources")
    overlay = receipt.get("overlay", {})
    web.need(overlay.get("historical_commit") == MANIFEST_COMMIT
             and overlay.get("historical_source_sha256") == web.sha(original)
             and overlay.get("sole_insertion") == (MANIFEST_LINE + b"\n").decode("ascii")
             and overlay.get("removing_insertion_restores_historical_source") is True
             and overlay.get("onboarding_or_lobby_added") is False,
             "MP10 historical manifest provenance differs")
    sources = [ROOT / "panorama/src" / name for name in UI_SOURCES]
    contents = [CONTENT / "panorama" / name for name in UI_SOURCES]
    sources.append(COMPILE_DIRECTORY / "manifest_compile_sources/source/panorama/src" / MANIFEST_SOURCE)
    contents.append(COMPILE_DIRECTORY / "manifest_compile_sources/content/panorama" / MANIFEST_SOURCE)
    runtimes = [ROOT / name for name in UI_COMPILED] + [MANIFEST_OVERLAY / MANIFEST_COMPILED]
    logs = ("compile_hud_xml.log", "compile_hud_css.log", "compile_hud_js.log", "compile_manifest_overlay.log")
    manifest_runtime = None
    for name, source, content, runtime_path, log in zip(names, sources, contents, runtimes, logs):
        row = indexed[name]
        log_path = UI_DIRECTORY / UI_LOGS[2] if name == UI_SOURCES[2] else COMPILE_DIRECTORY / log
        web.need(row.get("exit_code") == 0 and row.get("native_one_success") is True
                 and Path(row.get("source_path", "")) == source and Path(row.get("content_path", "")) == content
                 and Path(row.get("runtime_path", "")) == runtime_path and Path(row.get("log_path", "")) == log_path,
                 "MP10 compile source/output path or successful exit differs")
        data = read_input(source, snapshots)
        web.need(read_input(content, snapshots) == data and row.get("source_sha256") == row.get("content_sha256") == web.sha(data)
                 and row.get("source_bytes") == row.get("content_bytes") == len(data), "MP10 native compile source hash/mirror differs")
        runtime = read_input(runtime_path, snapshots)
        web.need(row.get("runtime_sha256") == web.sha(runtime) and row.get("runtime_bytes") == len(runtime), "MP10 native compile runtime hash differs")
        web.need(b"1 compiled, 0 failed, 0 skipped" in read_input(log_path, snapshots), "MP10 native compile success log differs")
        compiled_data(runtime)
        if name == MANIFEST_SOURCE:
            web.need(data == expected, "MP10 manifest differs beyond the sole historical HUD insertion")
            manifest_runtime = runtime
    return manifest_runtime


def capture_inputs(base):
    snapshots, patches = {}, {}
    frozen = {name: read_input(base / name, snapshots) for name in (MAIN, PROFILE, WEB_CONFIG, ADDONINFO, NETTABLES)}
    patches[MAIN], patches[PROFILE] = patch_main(frozen[MAIN]), patch_profile(frozen[PROFILE])
    patches[ADDONINFO] = replace_once(frozen[ADDONINFO], b'"maps"              "ws4_entry"', b'"maps"              "template_map"')
    web.need(pack.handoff.kv(patches[ADDONINFO].decode("utf-8-sig")) == previous.LAYOUT, "MP10 addoninfo layout differs")
    patches[WEB_CONFIG] = replace_once(frozen[WEB_CONFIG], b"enabled = true", b"enabled = false")
    patches[NETTABLES] = patch_nettables(frozen[NETTABLES])
    for name in PUBLIC_SOURCES:
        raw = read_input(ROOT / name, snapshots)
        web.need(web.sha(raw) == SOURCE_PINS[name], "Reviewed MP10 public source changed: " + name)
        if name == SESSION_CONFIG:
            raw = replace_once(raw, b"enabled = false", b"enabled = true")
        patches[name] = raw
    web.need(REVISION.encode("ascii") in patches[PROBE] and b"function M.public_status()" in patches[PROBE],
             "MP10 probe revision or public status missing")
    patches.update(capture_ui(snapshots))
    patches[MANIFEST_COMPILED] = capture_manifest(snapshots)
    web.need(set(patches) == ALLOWLIST and all(web.sha(raw) == PATCH_PINS[name] for name, raw in patches.items()),
             "MP10 reviewed patch hash inventory differs")
    return snapshots, patches


def authenticate_base():
    pinned, _ = pack.handoff.trusted_policy(pack.handoff.POLICY)
    with web.trusted_root(BASE_TRUSTED):
        base, manifest, signature, metadata = pack.authenticate(BASE)
    web.need(manifest["content_sha256"] == BASE_SHA and manifest["file_count"] == BASE_FILES
             and signature["release_sequence"] == BASE_SEQUENCE
             and signature["key_id"] == pinned["integrity"]["trusted_key_id"], "Immutable signed v08 identity differs")
    web.need(RELEASE_SEQUENCE > BASE_SEQUENCE and RELEASE_SEQUENCE >= pinned["integrity"]["minimum_release_sequence"],
             "MP10 sequence is below the trusted release floor")
    pack.runtime.require_production(base)
    pack.handoff.configured_ids(base)
    return base, manifest, signature, metadata


def protected_paths(manifest):
    policy = pack.handoff.load_json(ROOT / "tools/lua_protection_policy.json")
    web.need(web.sha(pack.runtime.canonical_bytes(policy)) == LUA_POLICY_SHA, "Reviewed Lua protection policy changed")
    web.protect_runtime_lua.check_policy(policy)
    paths = [row["path"] for row in web.protect_runtime_lua.selected_files([row["path"] for row in manifest["files"]], policy)]
    web.need(len(paths) == len(set(paths)) == 180 and POLICY_MODULE in paths and not set(paths) & ALLOWLIST,
             "Protected 180-module inventory differs")
    return paths


def trust_names():
    web.need(len(pack.handoff.GATE_FILES) == 7 and {MAIN, PROFILE} <= set(pack.handoff.GATE_FILES)
             and set(pack.handoff.ENTRY_GATE_FILES) == {"scripts/vscripts/systems/workshop_entry.lua",
                                                      "scripts/vscripts/addon_game_mode_client.lua"}, "Frozen gate inventory differs")
    return (*pack.handoff.GATE_FILES, *pack.handoff.ENTRY_GATE_FILES, pack.handoff.ACCESS_FILE, *web.POLICY_FILES)


def trust_inputs(base):
    snapshots = {}
    for name in trust_names():
        raw = read_input(BASE_TRUSTED / name, snapshots)
        if name not in web.POLICY_FILES:
            web.need(read_input(base / name, snapshots) == raw, "Frozen v08 trusted gate differs from signed runtime")
    for name in (*web.POLICY_FILES, "tools/lua_protection_policy.json"):
        read_input(ROOT / name, snapshots)
    return snapshots


def require_review_unchanged(snapshots, head):
    for path, raw in snapshots.items():
        web.need(pack.protect_data.source_path(path.parent, path.name).read_bytes() == raw, "Reviewed MP10 input changed during build")
    web.need(web.git("rev-parse", "HEAD", root=ROOT).decode("ascii").strip() == head, "Reviewed HEAD changed during build")


def projected_manifest(baseline, patches):
    rows = {row["path"]: dict(row) for row in baseline["files"] if row["path"] not in REMOVED}
    for name, raw in patches.items():
        rows[name] = dict(path=name, bytes=len(raw), sha256=web.sha(raw), md5=hashlib.md5(raw, usedforsecurity=False).hexdigest())
    result = {name: baseline[name] for name in ("schema", "kind", "hash_algorithms")}
    result.update(files=[rows[name] for name in sorted(rows)], file_count=len(rows), bytes=sum(row["bytes"] for row in rows.values()))
    result["content_sha256"] = web.sha(pack.runtime.manifest_payload(result))
    return result


def audit_changes(baseline, candidate, patches, protected):
    pack.runtime.validate_manifest(baseline); pack.runtime.validate_manifest(candidate)
    before, after = ({row["path"]: row for row in document["files"]} for document in (baseline, candidate))
    web.need(before.keys() - after.keys() == REMOVED and after.keys() - before.keys() == ADDED, "MP10 additions/removals differ from the exact allowlist")
    web.need(baseline["file_count"] == len(before) == BASE_FILES
             and candidate["file_count"] == len(after) == EXPECTED_FILES, "MP10 must retain 6630 base files plus seven additions minus the old entry map")
    web.need(set(patches) == ALLOWLIST and {name for name in before.keys() & after.keys() if before[name] != after[name]} == MODIFIED,
             "MP10 modifications differ from the exact thirteen-file allowlist")
    web.need(len(protected) == len(set(protected)) == 180 and set(protected) == set(protected_paths(baseline))
             and not set(protected) & ALLOWLIST and all(before[name] == after[name] for name in protected), "Protected 180-module bytes changed")
    for name, raw in patches.items():
        web.need(after[name]["sha256"] == web.sha(raw) == PATCH_PINS[name] and after[name]["bytes"] == len(raw), "MP10 patch bytes changed during staging")
    for name, restore in ((MAIN, restore_main), (PROFILE, restore_profile)):
        raw = restore(patches[name])
        web.need(len(raw) == before[name]["bytes"] and web.sha(raw) == before[name]["sha256"], "MP10 patch cannot restore the entire frozen " + name)
    web.need(ENTRY_MAP in before and ENTRY_MAP not in after and before[RELEASE_PROFILE] == after[RELEASE_PROFILE], "Old entry map removal or production profile differs")
    return [dict(path=name, before=before.get(name), after=after.get(name)) for name in sorted(ALLOWLIST | REMOVED)]


def trusted_snapshot(destination, trusted):
    trusted.mkdir(parents=True, exist_ok=False)
    for name in trust_names():
        origin = destination if name in (MAIN, PROFILE) else BASE_TRUSTED
        target = trusted / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(pack.protect_data.source_path(origin, name).read_bytes())


def stage_runtime(base, destination, baseline, patches):
    pack.runtime.validate_manifest(baseline)
    web.need(set(patches) == ALLOWLIST, "MP10 staging allowlist differs")
    destination.mkdir(parents=True, exist_ok=False)
    for row in baseline["files"]:
        if row["path"] in REMOVED: continue
        target = destination / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(pack.protect_data.source_path(base, row["path"]), target)
    for name, raw in patches.items():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)


def build(args):
    web.need(args.sequence == RELEASE_SEQUENCE, "MP10r2 requires fixed sequence 2026102507")
    require_review_pins()
    if args.build:
        web.need(args.destination == DESTINATION and args.trusted_source == TRUSTED_DESTINATION,
                 "MP10 requires its fixed new candidate/trusted directories")
        web.need(args.package_output is None or args.package_output == PACKAGE_OUTPUT, "MP10 package output differs from fixed directory")
    base, baseline, signature, metadata = authenticate_base()
    protected = protected_paths(baseline)
    head = web.git("rev-parse", "HEAD", root=ROOT).decode("ascii").strip()
    snapshots, patches = capture_inputs(base)
    snapshots.update(trust_inputs(base))
    projected = projected_manifest(baseline, patches)
    changes = audit_changes(baseline, projected, patches, protected)
    result = dict(ok=True, status="READ_ONLY_PLAN", revision=REVISION, release_sequence=RELEASE_SEQUENCE,
                  base_content_sha256=BASE_SHA, base_files=BASE_FILES, expected_files=EXPECTED_FILES,
                  projected_content_sha256=projected["content_sha256"], reviewed_head=head,
                  allowed_changes=sorted(MODIFIED), allowed_additions=sorted(ADDED), allowed_removals=sorted(REMOVED),
                  patches={name: web.sha(raw) for name, raw in patches.items()}, changed=changes,
                  protected_modules_preserved=180, protected_modules_rebuilt=0,
                  frozen_main_and_profile_reversible=True, dormant_entry_map_omitted_from_new_candidate=True, original_entry_map_preserved=True,
                  default_map="template_map", declared_max_players=4, required_real_players_for_acceptance=2,
                  session_only=True, cloud_archive_enabled=False, real_money_payments=False,
                  four_account_only=True, online_cheats_allowed=False, workshop_upload_performed=False,
                  game_started=False, native_two_player_acceptance="NOT_RUN")
    require_review_unchanged(snapshots, head)
    if not args.build: return result
    web.need(args.signing_key is not None, "--build requires an external --signing-key")
    destination, trusted, package_output, key = web.output_paths(args, base)
    web.need(web.LUA_COMPILER.is_file(), "Reviewed Lua 5.1 compiler unavailable")
    stage_runtime(base, destination, baseline, patches)
    manifest = pack.runtime.manifest(destination)
    changes = audit_changes(baseline, manifest, patches, protected)
    web.need(manifest["content_sha256"] == projected["content_sha256"], "Staged candidate differs from read-only plan")
    pack.runtime.require_production(destination); pack.handoff.require_single_map(destination)
    web.need(pack.handoff.configured_ids(destination) == pack.handoff.configured_ids(base), "Frozen four-account list changed")
    web.protect_runtime_lua.syntax_check([destination / name for name in (MAIN, PROFILE, WEB_CONFIG, *PUBLIC_SOURCES)], web.LUA_COMPILER)
    previous.require_base_unchanged(base, baseline, metadata)
    require_review_unchanged(snapshots, head)
    trusted_snapshot(destination, trusted)
    pack.runtime.atomic_write_json(destination / pack.handoff.MANIFEST, manifest)
    pack.protect_data.sign_manifest(destination / pack.handoff.MANIFEST, key, destination / pack.handoff.SIGNATURE, RELEASE_SEQUENCE)
    with web.trusted_root(trusted):
        _, authenticated, signed, _ = pack.authenticate(destination)
        web.need(authenticated["content_sha256"] == manifest["content_sha256"] and signed["key_id"] == signature["key_id"], "Signed MP10 identity/key differs")
        packaged = None
        if package_output is not None:
            package_output.mkdir(parents=True, exist_ok=False)
            packaged = pack.package(destination, package_output, "3824360109", build=True)
    require_review_unchanged(snapshots, head)
    result.update(status="SIGNED_MP10_REQUIRES_NATIVE_TWO_PLAYER_TEST", content_sha256=manifest["content_sha256"],
                  changed=changes, signature_valid=signed["signature_valid"], destination=str(destination),
                  trusted_source=str(trusted), packaged=packaged, private_key_copied=False, lua_syntax="PASS")
    pack.runtime.atomic_write_json(destination / "_arcade_two_player_provenance.json", result)
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
        result = build(parser().parse_args())
    except (OSError, ValueError, KeyError, TypeError, struct.error, subprocess.SubprocessError):
        print(json.dumps(dict(ok=False, error="mp10_candidate_build_failed")))
        return 2
    print(json.dumps(result, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
