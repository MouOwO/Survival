"""Native-cloud 2709: one compiled checkout replacement over verified 2708.

Default is a complete read-only plan and never reads a private key. --build
requires an external key and creates new v03 thin/review/full-view/VPK outputs.
No map/Lua/protected module is rebuilt; no game, payment or Steam SDK is called.
The fixed compile pins determine the projection without a self-referential
plan/report hash. Existing 2708 tools, signed resources and archives stay intact.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
PRIMITIVES = ROOT / "tools/arcade_cleanup_20261027/incremental_vpk.py"
PRIMITIVES_SHA = "a90312c526dac539eb3e83bf7a3fe17615ac5550f1bb9dd6e659c58f2af349e7"
PUBLISHER_SHA = "6131f0358c328e8574b44ccb07c589ef68e1544e197c2555569fda7ed0f81f40"
PARSER_SHA = "2b321bf45df70463e84684d982d3a83189b9b3a5f7565b972bb14383de363e81"
if hashlib.sha256(PRIMITIVES.read_bytes().replace(b"\r\n", b"\n")).hexdigest() != PRIMITIVES_SHA:
    raise ValueError("Frozen incremental VPK primitives changed")
spec = importlib.util.spec_from_file_location("qr09_incremental_primitives", PRIMITIVES)
incremental = importlib.util.module_from_spec(spec)
spec.loader.exec_module(incremental)
pack, need = incremental.pack, incremental.need
import protect_runtime_lua as protection

REVISION, SEQUENCE, COUNT, PROTECTED_COUNT, ARCHIVE_COUNT = "WS4-NATIVE-CLOUD-03", 2026102709, 6658, 180, 4
REBUILT_ARCHIVE = 0
ITEM = "3824360109"
BASE = Path("D:/Survival_发布候选/20261027_ws4_native_cloud_v02_view")
BASE_TRUSTED = Path("D:/Survival_发布候选/20261027_ws4_native_cloud_v02_overlay_trusted_source")
BASE_VPK = Path("D:/Survival_工坊输出/20261027_ws4_native_cloud_v02/3824360109.vpk")
BASE_SEQUENCE = 2026102708
BASE_CONTENT = "55d9e63ea1c95bed2456c739c0cf0e3148030e91a43f3a0d72aeaf64ab540e26"
BASE_REPORT = ROOT / "output/native_arcade_cloud_20261027/native_cloud_v02_package.json"
BASE_REPORT_SHA = "0eada1ac04619d99330595b878139757802627d0aff948bd460dccf05a5f6ba4"
BASE_DOWNLOAD = ROOT / "output/native_arcade_cloud_20261027/download_evidence_v02/20261027T131226Z_47475f709b284ebfa099237868d7e53a/verification.json"
BASE_DOWNLOAD_SHA = "95f12a1275a146eee563d3d50396df8425ca1f35e1c1b3ad166ef84a81950d13"
BASE_STEAM_MANIFEST = "976725920376391555"
TARGET = "panorama/scripts/custom_game/payment_test.vjs_c"
BEFORE_SHA = "297223b0e062db7c6014b0017932a665e996fd43cf0bdea4b94a0e84c7b22b6c"
AFTER_SHA, AFTER_BYTES = "8cca589085ff74459f17cee9cf620a450364eb22b4395b0458a0db4cf72ed566", 55854
SOURCE_REL = "panorama/src/scripts/custom_game/payment_test.js"
SOURCE = ROOT / SOURCE_REL
MIRROR = ROOT.parents[2] / "content/dota_addons/Survival/panorama/scripts/custom_game/payment_test.js"
SOURCE_SHA = "2ee90ef3ca2454aa7c5e37af1473d17cc776e5117b99ec69ea764cf1906706dd"
COMPILED = ROOT / TARGET
COMPILE_LOG = ROOT / "output/native_arcade_cloud_20261027/qr_fix_compile.log"
COMPILE_LOG_SHA = "a14cdf39205d82e6b7d6ce52dd2b3947c546846a4b2b1b67a035a92d383d6877"
OVERLAY = Path("D:/Survival_发布候选/20261027_ws4_native_cloud_v03_overlay")
TRUSTED = OVERLAY.with_name(OVERLAY.name + "_trusted_source")
VIEW = Path("D:/Survival_发布候选/20261027_ws4_native_cloud_v03_view")
OUTPUT = Path("D:/Survival_工坊输出/20261027_ws4_native_cloud_v03")
POLICY_NAMES = ("tools/release_security/protection_policy.json", "tools/release_security/trusted_public_key.pem")
PUBLIC_PINS = {
    POLICY_NAMES[0]: "8e8c2e50a6a983dda7336a083377bbf55de8625f89f5633977c8d7901b53da96",
    POLICY_NAMES[1]: "1717c28cb7476e5eb5326b780589c880e86d42cc026b6d4728d95ac95e8873bf",
    "tools/lua_protection_policy.json": "bc03e38f2e0b9165299df5777dbb561a593d5d4e2f45eaef5e51c48f8856958a",
}
TRUST_NAMES = (*pack.handoff.GATE_FILES, *pack.handoff.ENTRY_GATE_FILES, pack.handoff.ACCESS_FILE,
               *POLICY_NAMES, *pack.handoff.NATIVE_CLOUD_ENTRY_GATE_FILES[:2])


def capture(path, snapshots, *, sha=None, normalized=False, maximum=pack.MAX_MANIFEST):
    path = pack.handoff.regular_path(path)
    raw = pack.read_metadata(path, maximum)
    if sha is not None:
        need(hashlib.sha256(raw.replace(b"\r\n", b"\n") if normalized else raw).hexdigest() == sha,
             "Reviewed QR09 input hash differs: " + path.name)
    snapshots[path] = raw
    return raw


def unchanged(snapshots):
    for path, raw in snapshots.items():
        need(pack.read_metadata(pack.handoff.regular_path(path), len(raw)) == raw, "QR09 input changed: " + path.name)


def compiled_data(raw):
    """Read the reviewed JS DATA block using the existing strict v12 format."""
    need(28 <= len(raw) <= 4 * 1024 * 1024, "QR09 compiled resource absent or oversized")
    size, version, _, offset, count = struct.unpack_from("<IHHII", raw)
    table = 8 + offset
    need(size == len(raw) and version == 12 and 1 <= count <= 64
         and 16 <= table <= len(raw) - 12 * count, "QR09 compiled header invalid")
    ranges, data = [], []
    for index in range(count):
        entry = table + index * 12
        tag, displacement, length = struct.unpack_from("<4sII", raw, entry)
        start = entry + 4 + displacement
        need(all(32 <= value <= 126 for value in tag) and start >= table + count * 12
             and start + length <= len(raw)
             and not any(start < end and begin < start + length for begin, end in ranges),
             "QR09 compiled block invalid or overlapping")
        ranges.append((start, start + length))
        if tag == b"DATA":
            data.append(raw[start:start + length])
    need(len(data) == 1, "QR09 compiled resource must contain one DATA block")
    return data[0]


def verify_protected(before, after, policy):
    protection.check_policy(policy)
    rows = [{row["path"]:row for row in manifest["files"]} for manifest in (before, after)]
    chosen = [{row["path"] for row in protection.selected_files(list(values), policy)} for values in rows]
    need(chosen[0] == chosen[1] and len(chosen[0]) == PROTECTED_COUNT and TARGET not in chosen[0]
         and all(rows[0][name] == rows[1][name] for name in chosen[0]), "QR09 protected 180 modules differ")


def projection(before, compiled, lua_policy):
    after = copy.deepcopy(before)
    old = {row["path"]:row for row in before["files"]}
    need(before["file_count"] == COUNT and TARGET in old and old[TARGET]["sha256"] == BEFORE_SHA,
         "QR09 base checkout resource or count differs")
    row = dict(path=TARGET, bytes=len(compiled), sha256=hashlib.sha256(compiled).hexdigest(),
               md5=hashlib.md5(compiled, usedforsecurity=False).hexdigest())
    need(row["sha256"] == AFTER_SHA and row["bytes"] == AFTER_BYTES, "QR09 replacement compile differs")
    after["files"] = [row if current["path"] == TARGET else current for current in after["files"]]
    after["bytes"] = before["bytes"] - old[TARGET]["bytes"] + row["bytes"]
    after["content_sha256"] = hashlib.sha256(pack.runtime.manifest_payload(after)).hexdigest()
    pack.runtime.validate_manifest(after)
    current = {value["path"]:value for value in after["files"]}
    need(current.keys() == old.keys() and [name for name in current if current[name] != old[name]] == [TARGET],
         "QR09 exceeds the one compiled resource scope")
    verify_protected(before, after, lua_policy)
    return after


def paths(key, build):
    base, trusted_base, vpk = [incremental.external(path) for path in (BASE, BASE_TRUSTED, BASE_VPK)]
    destinations = [incremental.external(path, exists=False) for path in (OVERLAY, TRUSTED, VIEW, OUTPUT)]
    incremental.disjoint([base, trusted_base, vpk.parent, *destinations])
    need(all(not path.exists() for path in destinations), "QR09 requires entirely new v03 output directories")
    need(incremental.ancestor(VIEW).stat().st_dev == base.stat().st_dev
         and incremental.ancestor(OUTPUT).stat().st_dev == vpk.stat().st_dev,
         "QR09 read-only hardlink reuse requires the existing base volumes")
    if not build:
        need(key is None, "QR09 private key is accepted only with --build")
        return None
    need(key is not None, "QR09 --build requires an external --key")
    key = pack.protect_data.external(key, source=base)
    key = pack.handoff.regular_path(key)
    need(key.is_file(), "QR09 requires a regular external signing key")
    for destination in destinations:
        need(not pack.runtime.within(key, destination) and not pack.runtime.within(destination, key.parent),
             "QR09 output overlaps the private key directory")
    return key


def run(*, build=False, key=None):
    key = paths(key, build)
    need(SEQUENCE == 2026102709 and BASE_SEQUENCE == 2026102708, "QR09 fixed release sequence differs")
    snapshots = {}
    for file, pin, normalized in ((PRIMITIVES, PRIMITIVES_SHA, True), (Path(pack.handoff.__file__), PUBLISHER_SHA, False),
                                  (ROOT / "tools/build_runtime_release.py", PARSER_SHA, True)):
        capture(file, snapshots, sha=pin, normalized=normalized)
    capture(Path(__file__), snapshots)
    for relative, pin in PUBLIC_PINS.items():
        capture(ROOT / relative, snapshots, sha=pin)
    need(len(TRUST_NAMES) == len(set(TRUST_NAMES)) == 14
         and incremental.all_files(BASE_TRUSTED) == set(TRUST_NAMES), "QR09 base review-source inventory differs")
    review = {name:capture(BASE_TRUSTED / name, snapshots) for name in TRUST_NAMES}
    need(all(review[name] == snapshots[ROOT / name] for name in POLICY_NAMES), "QR09 base public trust differs")
    with incremental.trusted_source(BASE_TRUSTED):
        _, before, signed, base_metadata = pack.authenticate(BASE)
    need(before["content_sha256"] == BASE_CONTENT and before["file_count"] == COUNT
         and signed["release_sequence"] == BASE_SEQUENCE, "QR09 immutable signed native08 identity differs")
    report = pack.handoff.decode_json(capture(BASE_REPORT, snapshots, sha=BASE_REPORT_SHA))
    inventory = report.get("package_files")
    need(report.get("content_sha256") == BASE_CONTENT and report.get("release_sequence") == BASE_SEQUENCE
         and report.get("files") == COUNT and report.get("signature_valid") is True and report.get("dry_run") is False
         and report.get("full_runtime_validator_passed") is True and report.get("full_view_canonical_guard") == "PASS"
         and report.get("protected_modules_preserved") == PROTECTED_COUNT
         and isinstance(inventory, list) and len(inventory) == ARCHIVE_COUNT + 1,
         "QR09 verified native08 package report required")
    downloaded = pack.handoff.decode_json(capture(BASE_DOWNLOAD, snapshots, sha=BASE_DOWNLOAD_SHA))
    need(downloaded.get("status") == "OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED"
         and downloaded.get("release_sequence") == BASE_SEQUENCE and downloaded.get("content_sha256") == BASE_CONTENT
         and downloaded.get("steam_manifest") == BASE_STEAM_MANIFEST and type(downloaded["steam_manifest"]) is str
         and downloaded.get("signed_resources_verified") == COUNT
         and downloaded.get("protected_modules_verified") == PROTECTED_COUNT,
         "QR09 actual native08 official download receipt required")
    need(pack.package_inventory(BASE_VPK) == inventory and report.get("vpk_sha256") == inventory[0]["sha256"],
         "QR09 immutable native08 five-VPK bytes differ")
    pack.verify_vpk(BASE_VPK, before)
    package_snapshots = {path:incremental.snapshot(path) for path in pack.package_paths(BASE_VPK)}
    compiled = capture(COMPILED, snapshots, sha=AFTER_SHA)
    source = capture(SOURCE, snapshots, sha=SOURCE_SHA)
    need(capture(MIRROR, snapshots, sha=SOURCE_SHA) == source, "QR09 game/content checkout source differs")
    need(compiled_data(compiled) == source, "QR09 compiled JS DATA differs from reviewed source")
    log = capture(COMPILE_LOG, snapshots, sha=COMPILE_LOG_SHA, maximum=1024 * 1024)
    need(b"payment_test.js" in log and b"OK: 1 compiled, 0 failed, 0 skipped" in log,
         "QR09 successful single-source Valve compile log required")
    after = projection(before, compiled, pack.handoff.decode_json(snapshots[ROOT / "tools/lua_protection_policy.json"]))
    tree, groups, rewritten = incremental.rotation_plan(incremental.read_entries(BASE_VPK), before, after)
    need(len(groups) == ARCHIVE_COUNT and rewritten == {REBUILT_ARCHIVE}, "QR09 changed archive differs from reviewed native08 assignment")
    sizes = [sum(item["row"]["bytes"] for item in group) for group in groups]
    stage_bytes = len(compiled) * 2 + len(source) + sum(map(len, review.values())) + sum(incremental.METADATA.values()) * 2
    disk = incremental.capacity(VIEW, OUTPUT, stage_bytes, sizes[REBUILT_ARCHIVE], pack.HEADER.size + len(tree) + 48, 0)
    unchanged(snapshots); pack.inventory_unchanged(BASE, base_metadata)
    need(all(incremental.snapshot(path) == value for path, value in package_snapshots.items()), "QR09 base VPK changed during plan")
    # The checkout resource differs from 2708. Legacy publisher payload_changed
    # describes mutation DURING this packaging run, whose inputs remain frozen.
    result = dict(schema=1, status="READ_ONLY_QR09_PLAN", revision=REVISION, dry_run=not build,
        release_sequence=SEQUENCE, content_sha256=after["content_sha256"], files=COUNT,
        base_release_sequence=BASE_SEQUENCE, base_content_sha256=BASE_CONTENT,
        base_package_report_sha256=BASE_REPORT_SHA, base_official_download_sha256=BASE_DOWNLOAD_SHA,
        overlay=str(OVERLAY), trusted_source=str(TRUSTED), candidate=str(VIEW), output=str(OUTPUT / (ITEM + ".vpk")),
        changed_runtime_paths=[TARGET], deleted_runtime_paths=[], added_runtime_paths=[],
        source_sha256=SOURCE_SHA, compiled_sha256=AFTER_SHA, compile_log_sha256=COMPILE_LOG_SHA,
        trusted_gate_files=14, trusted_review_files=15, protected_modules_preserved=PROTECTED_COUNT, protected_modules_rebuilt=0,
        lua_maps_entry_auth_preserved=True, payload_changed=False, full_input_hash_verification=True,
        rebuilt_archives=[REBUILT_ARCHIVE], reused_archives=[i for i in range(ARCHIVE_COUNT) if i != REBUILT_ARCHIVE], archive_reuse="hardlink",
        payload_bytes=after["bytes"], container_bytes=after["bytes"] + pack.HEADER.size + len(tree) + 48,
        max_archive_bytes=pack.ARCHIVE_BYTES, disk_preflight=disk, physical_rebuilt_bytes=sizes[REBUILT_ARCHIVE],
        full_view_canonical_guard="NOT_RUN_requires_build", workshop_upload_performed=False,
        native_dota_read_test="NOT_RUN", native_guest_qr_scan_test="NOT_RUN", ready_for_upload=False)
    if not build:
        return result
    unchanged(snapshots)
    OVERLAY.mkdir(parents=True, exist_ok=False); TRUSTED.mkdir(parents=True, exist_ok=False)
    incremental.write_new(OVERLAY / TARGET, compiled)
    for name, raw in {**review, SOURCE_REL:source}.items():
        incremental.write_new(TRUSTED / name, raw)
    incremental.write_new(OVERLAY / pack.handoff.MANIFEST, pack.runtime.canonical_bytes(after) + b"\n")
    pack.protect_data.sign_manifest(OVERLAY / pack.handoff.MANIFEST, key, OVERLAY / pack.handoff.SIGNATURE, SEQUENCE)
    policy, public = pack.handoff.trusted_policy(pack.handoff.POLICY)
    actual, document, metadata = incremental.metadata(OVERLAY)
    signature = pack.verify_signed_snapshot(actual, document, public,
        policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
    need(actual == after and signature["release_sequence"] == SEQUENCE, "QR09 signed overlay identity differs")
    sources, changed = incremental.validate_merged(BASE, OVERLAY, before, after, TRUSTED)
    need(changed == {TARGET} and incremental.all_files(TRUSTED) == set(TRUST_NAMES) | {SOURCE_REL},
         "QR09 staged runtime/review scope differs")
    incremental.materialize(VIEW, sources, changed, after, metadata)
    with incremental.trusted_source(TRUSTED):
        _, verified, verified_signature, view_metadata = pack.authenticate(VIEW)
    need(verified == after and verified_signature == signature, "QR09 complete-view identity differs")
    unchanged(snapshots)
    verification, package_files = incremental.build_volumes(VIEW, OUTPUT, BASE_VPK, tree, groups, rewritten, after, "hardlink")
    unchanged(snapshots)
    for root, frozen in ((BASE, base_metadata), (OVERLAY, metadata), (VIEW, view_metadata)):
        pack.inventory_unchanged(root, frozen)
    need(all(incremental.snapshot(path) == value for path, value in package_snapshots.items())
         and pack.package_inventory(BASE_VPK) == inventory and pack.runtime.verify(BASE, before)["ok"],
         "QR09 immutable native08 changed during build")
    result.update(status="BUILT_SIGNED_QR09_REQUIRES_NATIVE_GUEST_SCAN", dry_run=False, signature_valid=True,
        trusted_key_id=signature["key_id"], full_view_canonical_guard="PASS", canonical_single_map=True,
        canonical_reviewed_gate=True, full_runtime_validator_passed=True, immutable_base_unchanged=True,
        package_files=package_files, vpk_sha256=package_files[0]["sha256"], verification=verification)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--key", type=Path)
    args = parser.parse_args(argv)
    try:
        result = run(build=args.build, key=args.key)
    except Exception as error:
        print(__import__("json").dumps(dict(ok=False, status="QR09_BLOCKED_DO_NOT_UPLOAD", error=str(error),
              workshop_upload_performed=False), ensure_ascii=True)); return 1
    print(__import__("json").dumps(result, ensure_ascii=True, indent=2)); return 0


if __name__ == "__main__":
    raise SystemExit(main())
