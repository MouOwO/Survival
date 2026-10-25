"""Plan, or explicitly sign, exactly three stackable UI resources over v07.

This release-specific tool preserves v07 and all 180 protected Lua modules.
Default mode is read-only. Unreviewed compile pins fail closed. --build alone
does not install an alias, run Dota, contact a service or publish to Workshop.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_ui_qa_candidate as previous

web, pack = previous.web, previous.pack
ROOT, CONTENT = previous.ROOT, previous.CONTENT
BASE = Path("D:/Survival_发布候选/20261025_ws4_ui_font_wallet_v07")
BASE_TRUSTED = BASE.with_name(BASE.name + "_trusted_source")
BASE_SHA = "811170a2c77396faee948bf7a77021fe8ac07c2117a919a6c3eb7163e4525e7e"
BASE_FILES = 6630
BASE_SEQUENCE = 2026102502
RELEASE_SEQUENCE = 2026102503
REVISION = "WS4-UI-STACKABLE-08"
LUA_POLICY_SHA = "68ea73480e0f909acc646cb9146278e9b4a8fce85fee1bcfb5850509ed8601db"
POLICY_MODULE = previous.POLICY_MODULE
MAIN, RELEASE_PROFILE, WEB_CONFIG = previous.MAIN, previous.RELEASE_PROFILE, previous.WEB_CONFIG
SOURCE_NAMES = frozenset({"scripts/custom_game/archive_v10_semantics.js",
                          "scripts/custom_game/archive_v10.js",
                          "scripts/custom_game/common/archive_tooltip.js"})
ALLOWLIST = COMPILED = frozenset("panorama/" + name[:-3] + ".vjs_c" for name in SOURCE_NAMES)

# Independently checked game/content/source DATA associations from the exact
# successful three-file compiler receipt. Callers cannot substitute hashes.
JS_PINS = {
    "scripts/custom_game/archive_v10_semantics.js": (
        "c51b440823448fd9789459671c746797b8e3a2b1b3f813c8e9909a14a8215133",
        "d7701a6cc34eb62c34d45069f03fcdd9841fd6565cc7cc85af4719fd3e48e456", 12897),
    "scripts/custom_game/archive_v10.js": (
        "236b91cbf71368d32874da09eb64a04c72ca5cc4a9a4334ef250c0c9769cc714",
        "7a28103d8f7c219adc865e43bfa50bf10dca1f2b36b7106ceeea12c12473ed82", 37512),
    "scripts/custom_game/common/archive_tooltip.js": (
        "3fd83f07acae05fba275535e305077e6b307540954357d5ff9cfb1d1e9d07244",
        "2f0830ce317c9dfe639e5481a0077a4fe56e8a7c6d2a833d82c6eba96302af0f", 23953),
}
COMPILE_REPORT = ROOT / "output/ui_qa_20261025/compile/20261024T214452211Z/compile.json"
COMPILE_REPORT_SHA = "361ae02c4a9f9ab4a4a08d9c5c5e93010b251c7337b073edc117e80df710bb04"
DESTINATION = Path("D:/Survival_发布候选/20261025_ws4_ui_stackable_v08")
TRUSTED_DESTINATION = DESTINATION.with_name(DESTINATION.name + "_trusted_source")
PACKAGE_OUTPUT = Path("D:/Survival_工坊输出/20261025_ws4_ui_stackable_v08")

def require_review_pins():
    web.need(set(JS_PINS) == SOURCE_NAMES and len(JS_PINS) == 3,
             "Stackable UI pins must retain the exact three-source allowlist")
    web.need(isinstance(COMPILE_REPORT_SHA, str) and re.fullmatch(r"[0-9a-f]{64}", COMPILE_REPORT_SHA),
             "Stackable UI compile review pins are not finalized")
    for row in JS_PINS.values():
        web.need(isinstance(row, tuple) and len(row) == 3
                 and all(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) for value in row[:2])
                 and type(row[2]) is int and 28 <= row[2] <= 4 * 1024 * 1024,
                 "Stackable UI compile review pins are not finalized")


def authenticate_base():
    pinned, _ = pack.handoff.trusted_policy(pack.handoff.POLICY)
    with web.trusted_root(BASE_TRUSTED):
        base, manifest, signature, _ = pack.authenticate(BASE)
    web.need(manifest["content_sha256"] == BASE_SHA and manifest["file_count"] == BASE_FILES,
             "Immutable v07 candidate identity mismatch")
    web.need(signature["release_sequence"] == BASE_SEQUENCE, "Unexpected v07 release sequence")
    web.need(signature["key_id"] == pinned["integrity"]["trusted_key_id"], "v07 checkout key pin differs")
    web.need(RELEASE_SEQUENCE > BASE_SEQUENCE
             and RELEASE_SEQUENCE >= pinned["integrity"]["minimum_release_sequence"],
             "v08 sequence is below the trusted release floor")
    pack.runtime.require_production(base)
    web.need(b"enabled = true" in pack.protect_data.source_path(base, WEB_CONFIG).read_bytes(),
             "Frozen web authorization must stay enabled")
    return base, manifest, signature


def protected_paths(manifest):
    policy = pack.handoff.load_json(ROOT / "tools/lua_protection_policy.json")
    web.need(web.sha(pack.runtime.canonical_bytes(policy)) == LUA_POLICY_SHA,
             "Reviewed Lua protection policy changed")
    web.protect_runtime_lua.check_policy(policy)
    rows = web.protect_runtime_lua.selected_files([row["path"] for row in manifest["files"]], policy)
    paths = [row["path"] for row in rows]
    web.need(len(paths) == len(set(paths)) == 180 and POLICY_MODULE in paths
             and not set(paths) & ALLOWLIST, "Frozen 180-module protection selection differs")
    return paths


def compiled_data(raw, relative):
    """Bound native v12 blocks and return exactly one nonoverlapping DATA."""
    web.need(relative in ALLOWLIST and 28 <= len(raw) <= 4 * 1024 * 1024,
             "Compiled stackable UI resource absent, unreviewed or oversized")
    size, version, _, offset, count = struct.unpack_from("<IHHII", raw)
    table = 8 + offset
    web.need(size == len(raw) and version == 12 and 1 <= count <= 64
             and 16 <= table <= len(raw) - count * 12, "Compiled stackable UI header invalid")
    blocks, data = [], []
    for index in range(count):
        entry = table + index * 12
        tag, displacement, length = struct.unpack_from("<4sII", raw, entry)
        start = entry + 4 + displacement
        web.need(all(32 <= c <= 126 for c in tag) and start >= table + count * 12
                 and start + length <= len(raw), "Compiled stackable UI block invalid")
        web.need(not any(start < end and begin < start + length for begin, end in blocks),
                 "Compiled stackable UI blocks overlap")
        blocks.append((start, start + length))
        if tag == b"DATA":
            data.append(raw[start:start + length])
    web.need(len(data) == 1, "Compiled stackable UI must contain exactly one DATA block")
    return data[0]


def capture_inputs(report_path, overlay=None):
    require_review_pins()
    report_path = pack.handoff.regular_path(report_path)
    receipt_raw = pack.protect_data.source_path(report_path.parent, report_path.name).read_bytes()
    web.need(web.sha(receipt_raw) == COMPILE_REPORT_SHA, "Reviewed stackable compile receipt changed")
    receipt = pack.handoff.decode_json(receipt_raw)
    web.need(receipt.get("ok") is True and receipt.get("check_only") is False
             and receipt.get("compiled_files") == 3
             and isinstance(receipt.get("scope"), list) and len(receipt["scope"]) == 3
             and set(receipt["scope"]) == SOURCE_NAMES,
             "Stackable UI compile receipt scope or successful build status differs")
    rows = receipt.get("results")
    web.need(isinstance(rows, list) and len(rows) == 3 and all(isinstance(row, dict) for row in rows)
             and {row.get("relative") for row in rows} == SOURCE_NAMES,
             "Stackable UI compile receipt results differ")
    rows = {row["relative"]: row for row in rows}
    runtime_root = ROOT
    if overlay is not None:
        runtime_root = pack.handoff.regular_path(overlay)
        web.need(runtime_root.is_dir(), "Stackable overlay must be a directory")
        actual = set()
        for path in runtime_root.rglob("*"):
            web.need(not pack.protect_data.linked(path), "Stackable overlay links are forbidden")
            if path.is_file():
                actual.add(path.relative_to(runtime_root).as_posix())
        web.need(actual == ALLOWLIST, "Stackable UI overlay must contain exactly the three reviewed resources")
    snapshots, patches = {report_path: receipt_raw}, {}
    for name, (source_sha, runtime_sha, byte_count) in JS_PINS.items():
        row = rows[name]
        web.need(row.get("source_sha256") == row.get("content_sha256") == source_sha
                 and row.get("runtime_sha256") == runtime_sha and row.get("runtime_bytes") == byte_count,
                 "Stackable UI compile receipt hash association differs: " + name)
        game_source = pack.protect_data.source_path(ROOT, "panorama/src/" + name)
        content_source = pack.protect_data.source_path(CONTENT, "panorama/" + name)
        source = game_source.read_bytes()
        web.need(web.sha(source) == source_sha and content_source.read_bytes() == source,
                 "Reviewed game/content stackable UI source differs: " + name)
        relative = "panorama/" + name[:-3] + ".vjs_c"
        runtime = pack.protect_data.source_path(runtime_root, relative)
        raw = runtime.read_bytes()
        web.need(len(raw) == byte_count and web.sha(raw) == runtime_sha,
                 "Reviewed compiled stackable UI resource differs: " + name)
        web.need(compiled_data(raw, relative) == source, "Compiled stackable UI DATA is not the exact reviewed JS source")
        snapshots.update({game_source: source, content_source: source, runtime: raw})
        patches[relative] = raw
    return snapshots, patches


def trust_inputs(base):
    snapshots = {}
    gates = (*pack.handoff.GATE_FILES, *pack.handoff.ENTRY_GATE_FILES, pack.handoff.ACCESS_FILE)
    for name in (*gates, *web.POLICY_FILES):
        path = pack.protect_data.source_path(BASE_TRUSTED, name)
        raw = path.read_bytes()
        if name in gates:
            web.need(pack.protect_data.source_path(base, name).read_bytes() == raw,
                     "Frozen gate trust snapshot differs from signed v07")
        snapshots[path] = raw
    for name in (*web.POLICY_FILES, "tools/lua_protection_policy.json"):
        path = pack.protect_data.source_path(ROOT, name)
        snapshots[path] = path.read_bytes()
    return snapshots


def require_review_unchanged(snapshots, head):
    for path, raw in snapshots.items():
        web.need(pack.protect_data.source_path(path.parent, path.name).read_bytes() == raw,
                 "Reviewed stackable UI input changed during build")
    web.need(web.git("rev-parse", "HEAD", root=ROOT).decode("ascii").strip() == head,
             "Reviewed HEAD changed during build")


def trusted_snapshot(destination):
    web.need(len(pack.handoff.GATE_FILES) == 7 and MAIN in pack.handoff.GATE_FILES
             and set(pack.handoff.ENTRY_GATE_FILES) == {
                 "scripts/vscripts/systems/workshop_entry.lua", "scripts/vscripts/addon_game_mode_client.lua"},
             "Reviewed frozen gate inventory differs")
    destination.mkdir(parents=True, exist_ok=False)
    for name in (*pack.handoff.GATE_FILES, *pack.handoff.ENTRY_GATE_FILES,
                 pack.handoff.ACCESS_FILE, *web.POLICY_FILES):
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(pack.protect_data.source_path(BASE_TRUSTED, name).read_bytes())


def audit_changes(baseline, candidate, patches, protected):
    before = {row["path"]: row for row in baseline["files"]}
    after = {row["path"]: row for row in candidate["files"]}
    web.need(before.keys() == after.keys(), "Stackable runtime additions/removals are forbidden")
    web.need(baseline["file_count"] == candidate["file_count"] == len(after) == BASE_FILES,
             "Stackable release must retain exactly 6630 runtime files")
    web.need(set(patches) == ALLOWLIST, "Stackable UI replacements must match the three-resource allowlist")
    changed = {name for name in before if before[name] != after[name]}
    web.need(changed == ALLOWLIST, "Only the three reviewed stackable UI resources may change")
    web.need(len(protected) == len(set(protected)) == 180 and POLICY_MODULE in protected
             and not set(protected) & ALLOWLIST and set(protected) <= before.keys(),
             "The protected 180-module set must remain intact")
    web.need(set(protected) == set(protected_paths(baseline)), "Protected inventory differs from the pinned policy")
    web.need(all(before[name] == after[name] for name in protected), "A protected runtime module changed")
    for name, raw in patches.items():
        web.need(after[name]["sha256"] == web.sha(raw) and after[name]["bytes"] == len(raw),
                 "Stackable overlay changed during staging")
    return [{"path": name, "before": before[name], "after": after[name]} for name in sorted(changed)]


def build(args):
    web.need(args.sequence == RELEASE_SEQUENCE, "UI stackable v08 requires the fixed 2026102503 sequence")
    require_review_pins()
    if args.build:
        web.need(args.destination is not None and args.trusted_source is not None
                 and args.destination.absolute() == DESTINATION.absolute()
                 and args.trusted_source.absolute() == TRUSTED_DESTINATION.absolute(),
                 "Stackable v08 requires its fixed new candidate/trusted directories")
        web.need(args.package_output is None or args.package_output.absolute() == PACKAGE_OUTPUT.absolute(),
                 "Stackable v08 package output differs from the fixed external directory")
    base, baseline, signature = authenticate_base()
    protected = protected_paths(baseline)
    head = web.git("rev-parse", "HEAD", root=ROOT).decode("ascii").strip()
    snapshots, patches = capture_inputs(args.compile_report, args.compiled_overlay)
    snapshots.update(trust_inputs(base))
    result = dict(ok=True, status="READ_ONLY_PLAN", revision=REVISION, base_content_sha256=BASE_SHA,
                  base_files=BASE_FILES, base_signature_sequence=signature["release_sequence"],
                  release_sequence=args.sequence, allowed_changes=sorted(ALLOWLIST), expected_files=BASE_FILES,
                  reviewed_head=head, compile_receipt_sha256=COMPILE_REPORT_SHA,
                  patches={name: web.sha(raw) for name, raw in patches.items()},
                  protected_modules_preserved=180, protected_modules_rebuilt=0,
                  game_content_js_sources_equal=True, compiled_DATA_equals_reviewed_source=True,
                  online_authentication_changed=False, online_cheats_allowed=False, four_account_only=True,
                  real_money_payments=False, alias_install_performed=False, workshop_upload_performed=False,
                  game_started=False)
    require_review_unchanged(snapshots, head)
    if not args.build:
        return result
    web.need(args.signing_key is not None, "--build requires --signing-key")
    destination, trusted, package_output, key = web.output_paths(args, base)
    destination.mkdir(parents=True, exist_ok=False)
    for row in baseline["files"]:
        target = destination / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(pack.protect_data.source_path(base, row["path"]), target)
    for name, raw in patches.items():
        pack.protect_data.source_path(destination, name).write_bytes(raw)
    manifest = pack.runtime.manifest(destination)
    changed = audit_changes(baseline, manifest, patches, protected)
    pack.runtime.require_production(destination)
    pack.handoff.require_single_map(destination)
    require_review_unchanged(snapshots, head)
    trusted_snapshot(trusted)
    pack.runtime.atomic_write_json(destination / pack.handoff.MANIFEST, manifest)
    pack.protect_data.sign_manifest(destination / pack.handoff.MANIFEST, key,
                                    destination / pack.handoff.SIGNATURE, args.sequence)
    with web.trusted_root(trusted):
        _, authenticated, signed, _ = pack.authenticate(destination)
        web.need(authenticated["content_sha256"] == manifest["content_sha256"], "Signed stackable identity mismatch")
        web.need(signed["key_id"] == signature["key_id"], "Signed stackable key differs from authenticated v07")
        packaged = None
        if package_output is not None:
            package_output.mkdir(parents=True, exist_ok=False)
            packaged = pack.package(destination, package_output, "3824360109", build=True)
    require_review_unchanged(snapshots, head)
    result.update(status="SIGNED_UI_STACKABLE_REQUIRES_NATIVE_TEST", content_sha256=manifest["content_sha256"],
                  files=manifest["file_count"], changed=changed, signature_valid=signed["signature_valid"],
                  all_other_runtime_bytes_preserved=True, plaintext_substitution=False, private_key_copied=False,
                  destination=str(destination), trusted_source=str(trusted), packaged=packaged,
                  native_dota_smoke="NOT_RUN")
    pack.runtime.atomic_write_json(destination / "_ui_stackable_provenance.json", result)
    return result


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--build", action="store_true")
    result.add_argument("--destination", type=Path)
    result.add_argument("--trusted-source", type=Path)
    result.add_argument("--signing-key", type=Path)
    result.add_argument("--compiled-overlay", type=Path)
    result.add_argument("--compile-report", type=Path, default=COMPILE_REPORT)
    result.add_argument("--sequence", type=int, default=RELEASE_SEQUENCE)
    result.add_argument("--package-output", type=Path)
    return result


def main():
    try:
        result = build(parser().parse_args())
    except (OSError, ValueError, KeyError, TypeError, struct.error, subprocess.SubprocessError) as error:
        print(json.dumps(dict(ok=False, error="stackable_candidate_build_failed", detail=str(error)[:500]),
                         ensure_ascii=True))
        return 2
    print(json.dumps(result, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
