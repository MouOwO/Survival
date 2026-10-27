"""Plan or explicitly sign the fixed WS4 connection-helper payment candidate.

Never install, upload, launch, package, copy credentials, or refresh gameplay.
All files outside the exact payment overlay remain the authenticated v04 bytes.
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
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workshop_test"))
import build_native_shop_candidate as previous
web, pack, frozen = previous.web, previous.pack, previous.frozen
CONTENT = frozen.CONTENT
BASE = Path("D:/Survival_发布候选/20261026_ws4_native_shop_v04")
BASE_TRUSTED = BASE.with_name(BASE.name + "_trusted_source")
BASE_SHA = "b38b10b76aaa4674c8a2d0ffc436922723a793f4b71665916956b4323f40b744"
BASE_FILES, BASE_SEQUENCE = 6637, 2026102604
RELEASE_SEQUENCE, REVISION = 2026102701, "WS4-PAYMENT-HELPER-01"
DESTINATION = Path("D:/Survival_发布候选/20261027_ws4_payment_helper_v01")
TRUSTED_DESTINATION = DESTINATION.with_name(DESTINATION.name + "_trusted_source")
COMPILE_REPORT = ROOT / "output/arcade_payment_link_20261027/compile.json"
COMPILE_REPORT_SHA = "12cc7e26dd622d8a6337da16fbb2023dae6ae1b815c628917c6085126bbc08f2"
COMPILE_LOG_DIRECTORY = ROOT / "output/arcade_payment_link_20261027/compile_64b7cfdb9d524d6aa714f28d28f593ae"
MAIN = "scripts/vscripts/addon_game_mode.lua"
PROFILE = "scripts/vscripts/systems/player_profile_service.lua"
PROVIDER = "scripts/vscripts/systems/player_profile_providers/http_fishing_provider.lua"
WEB_CONFIG = "scripts/vscripts/config/player_web_auth.lua"
SESSION_CONFIG = "scripts/vscripts/config/session_multiplayer_test.lua"
CASH_CONFIG = "scripts/vscripts/config/commerce_payment_access.lua"
WEB_AUTH = "scripts/vscripts/systems/player_web_auth.lua"
CASH_POLICY = "scripts/vscripts/core/commerce_release_policy.lua"
PAYMENT = "scripts/vscripts/systems/payment_service.lua"
LUA_PINS = {
    CASH_POLICY: "2865bc9c4752cf2978481eb1d3e2da13939d876aad5636f7347073628718d0ce",
    PAYMENT: "ecd829bb8d43d8c8546436efa29d5f330be701c3cbcee6a0005a558e8cb6afd1",
    CASH_CONFIG: "33994875cf45d4702169e305da24383db8cc89972989883b330ddcd8ca03e680",
    WEB_AUTH: "c84b7994a93f7df0fd5ce95bd64581cc933d76db2c001bb135a576ad875d600b",
}
WEB_AUTH_OUTPUT_SHA = "c35acb19d20f2d7734969748cce6b4cdeb4755e0a2305d392d14b2870ddfded5"
FROZEN_CODE_PINS = {
    MAIN: "2720298a60e3fa61313ecdc7a1b6688f67e1e5415167f4415705c2d14629dc34",
    PROFILE: "e746f72e24dd76d53d11da62d501346178018783ad8ce3ed20ce0301b6039894",
    PROVIDER: "a23590896713bf4d3abbbb05c8d96853b35933a875c596e97be9bae6e4b3a83b",
}
SPACE_RESERVE = 256 * 1024 * 1024
PINS = {'scripts/custom_game/payment_capability.js': ('c02d4b23b455c4c82d379cd02865362cd14298ce017a0418eb4cfa4eb73a3022', 'panorama/scripts/custom_game/payment_capability.vjs_c', '71286f42392c494db45cece76c9ef376c7597d2a35e3f807725308bd6f4b6e01', 8257), 'scripts/custom_game/payment_test.js': ('70afc987e07e494577b563f69ae0a6cb08ce80fb9b31b87deee0c6be42332acf', 'panorama/scripts/custom_game/payment_test.vjs_c', '297223b0e062db7c6014b0017932a665e996fd43cf0bdea4b94a0e84c7b22b6c', 54419), 'scripts/custom_game/black_lion_market.js': ('72c22bf9ace1a487a54a40e80da486583cf2e787c631c80783cfd496af5d859a', 'panorama/scripts/custom_game/black_lion_market.vjs_c', '89ba8c531959a9ca372dce337c1601a85bc3d0de6fa7afe5c220b23d9f4c2ff3', 19421), 'scripts/custom_game/commerce_remaining_5d5c1152eb.js': ('3b69324120330e8a7fac57b26aaffbab76cfc3f54d037c6c3168fc0a4097c1b9', 'panorama/scripts/custom_game/commerce_remaining_5d5c1152eb.vjs_c', '8d797eb39f8154a01016d3a6d8fc6f092b187f7c9136a7b369aa92828c9ddefe', 32562), 'scripts/custom_game/daily_remaining_5d5c1152eb.js': ('2c05fb451283c33553c86215ea49c993c1a7c17faaec0d5e33aef1edb526811f', 'panorama/scripts/custom_game/daily_remaining_5d5c1152eb.vjs_c', '46a9e1745941f432817821329b0b32e1542d619edfd5f1ceb06a493e52eb306c', 49404), 'layout/custom_game/payment_test.xml': ('1b99484d620d3498aae8ff6d0f477a60bdc490736eaebcf80b2eafcbc6cc04d7', 'panorama/layout/custom_game/payment_test.vxml_c', '4682e35465d443ed3fc2971080244b1e976dbb0b7f4c07cf0fe7d8611c677e2e', 4317)}

UI = frozenset(row[1] for row in PINS.values())
ADDED = frozenset((CASH_CONFIG, "panorama/scripts/custom_game/payment_capability.vjs_c"))
MODIFIED = frozenset((CASH_POLICY, PAYMENT, WEB_AUTH, WEB_CONFIG, SESSION_CONFIG)) | (UI - ADDED)
ALLOWLIST, EXPECTED_FILES = MODIFIED | ADDED, BASE_FILES + len(ADDED)


def require_review_pins():
    values = [BASE_SHA, COMPILE_REPORT_SHA, WEB_AUTH_OUTPUT_SHA, *LUA_PINS.values(), *FROZEN_CODE_PINS.values()]
    for row in PINS.values(): values.extend((row[0], row[2]))
    web.need(len(PINS) == 6 and len(UI) == 6 and len(ALLOWLIST) == 12 and len(MODIFIED) == 10
             and len(ADDED) == 2 and EXPECTED_FILES == 6639
             and not ALLOWLIST & set(FROZEN_CODE_PINS)
             and all(isinstance(v, str) and re.fullmatch(r"[a-f0-9]{64}", v) for v in values),
             "Helper review pins or exact overlay scope differ")


def read_input(path, snapshots):
    path = pack.protect_data.source_path(path.parent, path.name)
    raw = path.read_bytes(); snapshots[path] = raw
    return raw


def replace_once(raw, old, new):
    web.need(old != new and raw.count(old) == 1, "Frozen configuration context absent or ambiguous")
    return raw.replace(old, new, 1)


def invalidate_only(base_raw, current_raw):
    source = web.lf(current_raw)
    found = re.search(rb"function M\.invalidate\(account, session\)\n.*?\nend\n(?=\nfunction M\.resolve)", source, re.S)
    anchor = b"function M.resolve(account, session, success, failure)"
    web.need(found is not None and source.count(b"function M.invalidate") == 1 and b"function M.invalidate" not in base_raw and base_raw.count(anchor) == 1,
             "Frozen web-auth invalidate insertion absent or ambiguous")
    block = found.group()
    if b"\r\n" in base_raw: block = block.replace(b"\n", b"\r\n")
    newline = b"\r\n" if b"\r\n" in base_raw else b"\n"
    return base_raw.replace(anchor, block + newline + anchor, 1)


def no_credentials(patches):
    for name, raw in patches.items():
        web.need(pack.runtime.safe_relative(name) and name in ALLOWLIST,
                 "Unknown or unsafe helper overlay path")
        web.need(not re.search(rb"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----|Bearer [A-Za-z0-9_.~-]{20,}", raw)
                 and not re.search(rb"(?:access_token|api_token|merchant_secret)\s*=\s*[\"'][A-Za-z0-9_.~-]{20,}[\"']", raw),
                 "Credential literal cannot enter the helper runtime")


def authenticate_base():
    pinned, _ = pack.handoff.trusted_policy(pack.handoff.POLICY)
    with web.trusted_root(BASE_TRUSTED): base, manifest, signature, metadata = pack.authenticate(BASE)
    web.need(manifest["content_sha256"] == BASE_SHA and manifest["file_count"] == BASE_FILES
             and signature["release_sequence"] == BASE_SEQUENCE
             and signature["key_id"] == pinned["integrity"]["trusted_key_id"], "Immutable helper v04 baseline differs")
    web.need(RELEASE_SEQUENCE > BASE_SEQUENCE and RELEASE_SEQUENCE >= pinned["integrity"]["minimum_release_sequence"],
             "Helper release sequence is below the trusted floor")
    pack.runtime.require_production(base); pack.handoff.configured_ids(base)
    return base, manifest, signature, metadata


def protected_paths(manifest):
    paths = frozen.protected_paths(manifest)
    web.need(len(paths) == len(set(paths)) == 180 and not set(paths) & ALLOWLIST,
             "Helper protected 180-module inventory differs")
    return paths


def capture_ui(snapshots):
    patches = {}
    raw = read_input(COMPILE_REPORT, snapshots)
    web.need(web.sha(raw) == COMPILE_REPORT_SHA, "Reviewed helper compile receipt changed")
    receipt = pack.handoff.decode_json(raw); rows = receipt.get("records")
    web.need(receipt.get("ok") is True and receipt.get("kind") == "WS4_PAYMENT_LINK_COMPILE"
             and receipt.get("original_102_bytes_preserved") is True and isinstance(rows, list)
             and len(rows) == 6 and all(isinstance(row, dict) for row in rows), "Helper native compile receipt differs")
    indexed = {row.get("source"): row for row in rows}
    web.need(len(indexed) == 6 and set(indexed) == {"panorama/src/" + name for name in PINS},
             "Helper compile receipt contains duplicate or unknown sources")
    for source, (source_sha, compiled, compiled_sha, size) in PINS.items():
        row = indexed["panorama/src/" + source]; log = COMPILE_LOG_DIRECTORY / (Path(source).name + ".log")
        web.need(row.get("source_sha256") == source_sha and row.get("content") == "panorama/" + source
                 and row.get("compiled") == compiled and row.get("compiled_sha256") == compiled_sha
                 and row.get("compiled_bytes") == size and Path(row.get("log", "")) == log,
                 "Helper native compile association differs")
        game = read_input(ROOT / "panorama/src" / source, snapshots)
        mirror = read_input(CONTENT / "panorama" / source, snapshots)
        runtime = read_input(ROOT / compiled, snapshots)
        web.need(game == mirror and web.sha(game) == source_sha and web.sha(runtime) == compiled_sha
                 and len(runtime) == size, "Helper source mirror or compiled hash differs")
        data = frozen.compiled_data(runtime)
        web.need(data and (not source.endswith(".js") or data == game), "Helper native DATA differs from source")
        log_raw = read_input(log, snapshots)
        web.need(log_raw.count(b"1 compiled, 0 failed, 0 skipped") == 1, "Helper native compile log failed")
        patches[compiled] = runtime
    return patches


def capture_inputs(base):
    snapshots = {}
    patches = capture_ui(snapshots)
    for name, expected in LUA_PINS.items():
        raw = read_input(ROOT / name, snapshots)
        web.need(web.sha(raw) == expected, "Reviewed helper Lua source changed: " + name)
        if name in (CASH_POLICY, PAYMENT): patches[name] = raw
        elif name == CASH_CONFIG:
            patches[name] = replace_once(replace_once(raw, b"enabled = false", b"enabled = true"),
                                         b"connection_helper = false", b"connection_helper = true")
        else:
            original = read_input(base / WEB_AUTH, snapshots)
            patches[WEB_AUTH] = invalidate_only(original, raw)
            web.need(web.sha(patches[WEB_AUTH]) == WEB_AUTH_OUTPUT_SHA, "Web-auth patch exceeds invalidate-only review")
    patches[WEB_CONFIG] = replace_once(read_input(base / WEB_CONFIG, snapshots), b"enabled = false", b"enabled = true")
    patches[SESSION_CONFIG] = replace_once(read_input(base / SESSION_CONFIG, snapshots), b"enabled = true", b"enabled = false")
    for name, expected in FROZEN_CODE_PINS.items():
        raw = read_input(base / name, snapshots)
        web.need(web.sha(raw) == expected, "Frozen main/profile/HTTP provider differs")
        if name == PROVIDER:
            web.need(b"if web_auth.enabled() then" in raw and b"web_auth.resolve(body.account_id, session, send, on_error)" in raw,
                     "Frozen HTTP provider lacks its per-player PWA branch")
    web.need(set(patches) == ALLOWLIST, "Helper captured overlay scope differs")
    no_credentials(patches)
    # Pin supporting code/policy for the duration; never copy the worktree main,
    # provider, general gameplay, CSVs, launcher configuration or credential files.
    for path in (Path(__file__), ROOT / "tools/lua_protection_policy.json", ROOT / "tools/workshop_test/build_native_shop_candidate.py"):
        read_input(path, snapshots)
    return snapshots, patches


def trust_inputs(base):
    snapshots = {}
    for name in previous.trust_names():
        raw = read_input(BASE_TRUSTED / name, snapshots)
        if name not in web.POLICY_FILES:
            web.need(read_input(base / name, snapshots) == raw, "Frozen helper gate/trust bytes differ")
    for name in web.POLICY_FILES: read_input(ROOT / name, snapshots)
    return snapshots


def require_unchanged(snapshots, head):
    for path, raw in snapshots.items():
        web.need(pack.protect_data.source_path(path.parent, path.name).read_bytes() == raw, "Reviewed helper input changed")
    web.need(web.git("rev-parse", "HEAD", root=ROOT).decode("ascii").strip() == head, "Reviewed helper HEAD changed")


def projected_manifest(baseline, patches):
    pack.runtime.validate_manifest(baseline)
    web.need(set(patches) == ALLOWLIST, "Helper projection overlay scope differs")
    rows = {row["path"]: dict(row) for row in baseline["files"]}
    web.need(MODIFIED <= rows.keys() and not ADDED & rows.keys(), "Helper addition/modification baseline differs")
    for name, raw in patches.items():
        rows[name] = dict(path=name, bytes=len(raw), sha256=web.sha(raw), md5=hashlib.md5(raw, usedforsecurity=False).hexdigest())
    result = {name: baseline[name] for name in ("schema", "kind", "hash_algorithms")}
    result.update(files=[rows[name] for name in sorted(rows)], file_count=len(rows), bytes=sum(row["bytes"] for row in rows.values()))
    result["content_sha256"] = web.sha(pack.runtime.manifest_payload(result)); return result


def audit_changes(baseline, candidate, patches, protected):
    pack.runtime.validate_manifest(baseline); pack.runtime.validate_manifest(candidate)
    before, after = ({row["path"]: row for row in document["files"]} for document in (baseline, candidate))
    web.need(not before.keys() - after.keys() and after.keys() - before.keys() == ADDED, "Helper runtime additions/removals differ")
    web.need(baseline["file_count"] == len(before) == BASE_FILES and candidate["file_count"] == len(after) == EXPECTED_FILES,
             "Helper exact runtime count differs")
    web.need(set(patches) == ALLOWLIST and {name for name in before.keys() & after.keys() if before[name] != after[name]} == MODIFIED,
             "Helper modifies files outside its payment-only overlay")
    web.need(len(protected) == len(set(protected)) == 180 and set(protected) == set(protected_paths(baseline))
             and not set(protected) & ALLOWLIST and all(before[name] == after[name] for name in protected),
             "Helper protected 180-module bytes differ")
    for name, raw in patches.items():
        web.need(after[name]["sha256"] == web.sha(raw) and after[name]["bytes"] == len(raw), "Helper patch bytes changed while staging")
    return [dict(path=name, before=before.get(name), after=after[name]) for name in sorted(ALLOWLIST)]


def check_lua(patches):
    web.need(web.LUA_COMPILER.is_file(), "Reviewed Lua 5.1 syntax compiler missing")
    for name, raw in patches.items():
        if name.endswith(".lua"):
            checked = subprocess.run([str(web.LUA_COMPILER), "-p", "-"], input=raw, capture_output=True, timeout=30)
            web.need(checked.returncode == 0, "Helper Lua syntax failed: " + name)


def stage_runtime(base, destination, baseline, patches):
    destination.mkdir(parents=True, exist_ok=False)
    for row in baseline["files"]:
        target = destination / row["path"]; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(pack.protect_data.source_path(base, row["path"]), target)
    for name, raw in patches.items():
        target = destination / name; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(raw)


def trusted_snapshot(destination):
    destination.mkdir(parents=True, exist_ok=False)
    for name in previous.trust_names():
        target = destination / name; target.parent.mkdir(parents=True, exist_ok=True)
        pack.protect_data.write_new(target, pack.protect_data.source_path(BASE_TRUSTED, name).read_bytes())


def build(args):
    web.need(args.sequence == RELEASE_SEQUENCE, "Helper requires fixed sequence 2026102701")
    web.need(args.package_output is None, "Helper builder never creates a VPK package")
    if args.build:
        web.need(args.destination == DESTINATION and args.trusted_source == TRUSTED_DESTINATION,
                 "Helper requires fixed new candidate/trusted paths")
        web.need(args.signing_key is not None, "--build requires an external signing key")
    require_review_pins()
    base, baseline, signature, metadata = authenticate_base(); protected = protected_paths(baseline)
    head = web.git("rev-parse", "HEAD", root=ROOT).decode("ascii").strip()
    snapshots, patches = capture_inputs(base); snapshots.update(trust_inputs(base))
    check_lua(patches)
    projected = projected_manifest(baseline, patches); changes = audit_changes(baseline, projected, patches, protected)
    result = dict(ok=True, status="READ_ONLY_PLAN", revision=REVISION, release_sequence=RELEASE_SEQUENCE,
        base_content_sha256=BASE_SHA, base_files=BASE_FILES, base_release_sequence=BASE_SEQUENCE,
        expected_files=EXPECTED_FILES, projected_content_sha256=projected["content_sha256"], reviewed_head=head,
        compile_receipt_sha256=COMPILE_REPORT_SHA, allowed_changes=sorted(MODIFIED), allowed_additions=sorted(ADDED),
        allowed_removals=[], changed=changes, patches={name:web.sha(raw) for name,raw in patches.items()},
        protected_modules_preserved=180, protected_modules_rebuilt=0, all_other_base_files_preserved=True,
        frozen_main_profile_http_provider_preserved=True, unpublished_gameplay_changes_excluded=True,
        unpublished_blood_attack_fixes_included=False, web_auth_patch="invalidate_only_no_hosted_lobby_change",
        production_preserved=True, four_accounts_preserved=True, default_map="template_map", online_cheats_allowed=False,
        cloud_archive_code_enabled=True, session_only=False, cash_code_enabled=True, connection_helper=True,
        backend_orders_opened=False, actual_payment_verified=False, ready_for_public_release=False,
        private_key_copied=False, workshop_upload_performed=False, alias_install_performed=False,
        game_started=False, vpk_packaged=False, native_acceptance="NOT_RUN")
    require_unchanged(snapshots, head)
    if not args.build: return result
    destination, trusted, package, key = web.output_paths(args, base)
    web.need(package is None, "Helper may not package")
    web.need(destination.parent.is_dir() and shutil.disk_usage(destination.parent).free >= projected["bytes"] + SPACE_RESERVE,
             "Insufficient space for one helper candidate and reserve")
    stage_runtime(base, destination, baseline, patches)
    manifest = pack.runtime.manifest(destination); changes = audit_changes(baseline, manifest, patches, protected)
    previous.require_projection(manifest, projected)
    pack.runtime.require_production(destination); pack.handoff.require_single_map(destination)
    web.need(pack.handoff.configured_ids(destination) == pack.handoff.configured_ids(base), "Helper four-account list changed")
    frozen.previous.require_base_unchanged(base, baseline, metadata); require_unchanged(snapshots, head)
    trusted_snapshot(trusted)
    pack.protect_data.write_new(destination / pack.handoff.MANIFEST, pack.runtime.canonical_bytes(manifest) + b"\n")
    pack.protect_data.sign_manifest(destination / pack.handoff.MANIFEST, key, destination / pack.handoff.SIGNATURE, RELEASE_SEQUENCE)
    with web.trusted_root(trusted):
        _, verified, signed, _ = pack.authenticate(destination)
        web.need(pack.runtime.manifest_payload(verified) == pack.runtime.manifest_payload(manifest)
                 and signed["signature_valid"] is True and signed["release_sequence"] == RELEASE_SEQUENCE
                 and signed["key_id"] == signature["key_id"], "Signed helper identity/key/sequence differs")
    frozen.previous.require_base_unchanged(base, baseline, metadata); require_unchanged(snapshots, head)
    result.update(status="SIGNED_HELPER_REQUIRES_NATIVE_TEST", content_sha256=manifest["content_sha256"],
                  signature_valid=True, destination=str(destination), trusted_source=str(trusted), changed=changes)
    pack.protect_data.write_new(destination / "_payment_helper_provenance.json", pack.runtime.canonical_bytes(result) + b"\n")
    return result


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--build", action="store_true")
    result.add_argument("--destination", type=Path, default=DESTINATION)
    result.add_argument("--trusted-source", type=Path, default=TRUSTED_DESTINATION)
    result.add_argument("--signing-key", type=Path)
    result.add_argument("--sequence", type=int, default=RELEASE_SEQUENCE)
    result.set_defaults(package_output=None)
    return result


def main():
    try: result = build(parser().parse_args())
    except (OSError, ValueError, KeyError, TypeError, struct.error, subprocess.SubprocessError) as error:
        print(json.dumps(dict(ok=False,error="payment_helper_candidate_failed",detail=str(error)[:300])));return 2
    print(json.dumps(result, ensure_ascii=True));return 0


if __name__ == "__main__": raise SystemExit(main())
