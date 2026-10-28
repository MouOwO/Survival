"""Draft reviewed map-resource replacement over the verified native 2801 release.

No Steam, compiler, game or network calls. Default only reads existing inputs.
Reviewed compile pins are fixed below; --build additionally requires a reviewed
archive plan, external key and entirely new external artifact directories.
Unchanged hard links are never opened for writing or given new attributes.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
PRIMITIVES = ROOT / "tools/arcade_cleanup_20261027/incremental_vpk.py"
PRIMITIVES_SHA = "a90312c526dac539eb3e83bf7a3fe17615ac5550f1bb9dd6e659c58f2af349e7"
PUBLISHER_SHA = "6131f0358c328e8574b44ccb07c589ef68e1544e197c2555569fda7ed0f81f40"
PARSER_SHA = "2b321bf45df70463e84684d982d3a83189b9b3a5f7565b972bb14383de363e81"
if hashlib.sha256(PRIMITIVES.read_bytes().replace(b"\r\n", b"\n")).hexdigest() != PRIMITIVES_SHA:
    raise ValueError("Frozen incremental VPK primitives changed")
spec = importlib.util.spec_from_file_location("map2802_incremental_primitives", PRIMITIVES)
incremental = importlib.util.module_from_spec(spec)
spec.loader.exec_module(incremental)
pack, need = incremental.pack, incremental.need
import protect_runtime_lua as protection

ITEM, SEQUENCE, REVISION = "3824360109", 2026102802, "WS4-MAP-RESOURCES-01"
BASE_SEQUENCE, BASE_COUNT, PROTECTED_COUNT = 2026102801, 6658, 180
BASE_CONTENT = "f20c64b00da4e9d9f1a93bd7fca23163aa3f8b203e9ae354de5f60d9a8c75503"
BASE = Path("D:/Survival_发布候选/20261028_ws4_native_layout_v01_view")
BASE_TRUSTED = Path("D:/Survival_发布候选/20261028_ws4_native_layout_v01_overlay_trusted_source")
BASE_VPK = Path("D:/Survival_工坊输出/20261028_ws4_native_layout_v01/3824360109.vpk")
BASE_REPORT = ROOT / "output/ui_layout_20261028/package.json"
BASE_REPORT_SHA = "fdd18e31dea56098a4ffe949591b3aeb2e5a3905764e6b257f42a11e5a0443ee"
BASE_DOWNLOAD = ROOT / "output/ui_layout_20261028/download_evidence/20261028T001512Z_2dd45dc3a84a4fae8b225ae313ddf333/verification.json"
BASE_DOWNLOAD_SHA = "09ff2163ea73e75fec9437addfe3f0cefaf668d97723a1d7d50a533b737b6d6c"
BASE_STEAM_MANIFEST = "6288215904920783611"
OVERLAY = Path("D:/Survival_发布候选/20261028_ws4_map_resources_v01_overlay")
TRUSTED = OVERLAY.with_name(OVERLAY.name + "_trusted_source")
VIEW = Path("D:/Survival_发布候选/20261028_ws4_map_resources_v01_view")
OUTPUT = Path("D:/Survival_工坊输出/20261028_ws4_map_resources_v01")
MAP_TARGET = "maps/template_map.vpk"
MAP_SOURCE = ROOT.parents[2] / "content/dota_addons/Survival/maps/template_map.vmap"
COMPILE_LOG = ROOT / "output/map_resources_20261028/compile.log"
MAP_VERIFICATION = ROOT / "output/map_resources_20261028/package_verification.json"

# Actual Valve compile of 2026-10-28; these identities cannot be supplied via CLI.
# Each runtime pin is exactly {bytes, md5, sha256}; no deletions are permitted.
TARGET_PINS = {MAP_TARGET: {
    "bytes": 65142294,
    "md5": "0b90294d0a36aca75e9c86231255bad5",
    "sha256": "f868f295a01b78f63dbeb9fe9edfc6a7591b3889ace84f0892f595ac46f22186",
}}
MAP_SOURCE_PIN = {
    "bytes": 72574022,
    "md5": "f1b7e3f8ef7fe711eab20a614886f8f2",
    "sha256": "4e62350c1bf08e663f5217885f26652918c2e09296a829f29a987ba8a14dccdc",
}
COMPILE_LOG_SHA = "be9a1899a5f39ada3bef977e5d53a77f0da794efa8464f7f083b6947878450c4"
MAP_VERIFICATION_SHA = "ddcd2dd519777e56e7fca1d5ee8849f58d8939bbe0c795aaa36e5f5636ba777f"
MAP_SOURCE_CRC, MAP_CRC_ENTRIES = 3557144492, 307
EXPECTED_REBUILT_ARCHIVES = (0,)

POLICY_NAMES = ("tools/release_security/protection_policy.json", "tools/release_security/trusted_public_key.pem")
PUBLIC_PINS = {
    POLICY_NAMES[0]: "8e8c2e50a6a983dda7336a083377bbf55de8625f89f5633977c8d7901b53da96",
    POLICY_NAMES[1]: "1717c28cb7476e5eb5326b780589c880e86d42cc026b6d4728d95ac95e8873bf",
    "tools/lua_protection_policy.json": "bc03e38f2e0b9165299df5777dbb561a593d5d4e2f45eaef5e51c48f8856958a",
}
GATE_NAMES = (*pack.handoff.GATE_FILES, *pack.handoff.ENTRY_GATE_FILES, pack.handoff.ACCESS_FILE,
              *POLICY_NAMES, *pack.handoff.NATIVE_CLOUD_ENTRY_GATE_FILES[:2])
REVIEW_PINS = {
    "panorama/src/scripts/custom_game/payment_test.js": "2ee90ef3ca2454aa7c5e37af1473d17cc776e5117b99ec69ea764cf1906706dd",
    "panorama/src/scripts/custom_game/production_progress.js": "136ce07fcebc36c7c27ffc428ab05c0d7f63837902f5c7dfdb885b553810cc27",
}
PRESERVED_RUNTIME_PINS = {
    "panorama/scripts/custom_game/payment_test.vjs_c": "8cca589085ff74459f17cee9cf620a450364eb22b4395b0458a0db4cf72ed566",
    "panorama/scripts/custom_game/production_progress.vjs_c": "36dd249135d8c650ea0055023c33e4df2cc7b068a77e7521b32ba82cbac5b4ce",
    "maps/ws4_entry.vpk": "abce9c7f6a1159303c799ec9a8b40afa7f724e7bf4c52509038e490afa67fecb",
}


def capture(path, snapshots, *, sha=None, normalized=False, maximum=pack.MAX_MANIFEST):
    path = pack.handoff.regular_path(path)
    raw = pack.read_metadata(path, maximum)
    digest = hashlib.sha256(raw.replace(b"\r\n", b"\n") if normalized else raw).hexdigest()
    need(sha is None or digest == sha, "Reviewed MAP2802 metadata hash differs: " + path.name)
    snapshots[path] = raw
    return raw


def unchanged(snapshots, payloads):
    for path, raw in snapshots.items():
        need(pack.read_metadata(pack.handoff.regular_path(path), len(raw)) == raw,
             "MAP2802 metadata changed: " + path.name)
    for path, (stat, pin) in payloads.items():
        need(incremental.snapshot(path) == stat and pack.runtime.checksums(path) == pin
             and incremental.snapshot(path) == stat, "MAP2802 payload changed: " + path.name)


def capture_payload(path, pin, payloads):
    """Stream map binaries; old metadata capture has a deliberate 16 MiB cap."""
    path = pack.handoff.regular_path(path)
    need(set(pin) == {"bytes", "md5", "sha256"} and type(pin["bytes"]) is int and pin["bytes"] > 0
         and all(isinstance(pin[k], str) and len(pin[k]) == size
                 and all(c in "0123456789abcdef" for c in pin[k]) for k, size in (("md5", 32), ("sha256", 64))),
         "MAP2802 reviewed binary pin is incomplete")
    stat = incremental.snapshot(path)
    need(pack.runtime.checksums(path) == pin and incremental.snapshot(path) == stat,
         "MAP2802 compiled/source pin differs: " + path.name)
    payloads[path] = (stat, dict(pin))
    return path


def allowed_target(name):
    if not pack.runtime.safe_relative(name):
        return False
    if name == MAP_TARGET:
        return True
    # The explicit, reviewed TARGET_PINS inventory authorizes exact dependencies.
    # Code, Panorama, entry maps and other map bundles cannot enter this scope.
    return name.startswith(("materials/", "models/", "particles/", "maps/template_map/")) and name.endswith(
        (".vmat_c", ".vtex_c", ".vmdl_c", ".vmesh_c", ".vphys_c", ".vanim_c", ".vpcf_c"))


def verify_compile_log(raw):
    need(all(needle in raw for needle in (
        b"template_map.vmap", b"template_map.vpk", b"Map build finished.",
        b"OK: 302 compiled, 0 failed, 1 skipped")), "MAP2802 successful actual Valve map compile log required")


def verify_map_proof(raw):
    proof = pack.handoff.decode_json(raw)
    source, package, match, compiled = [proof.get(name, {}) for name in ("source", "package", "source_match", "compiled_map")]
    need(all(isinstance(value, dict) for value in (source, package, match, compiled)),
         "MAP2802 map proof sections must be objects")
    need(proof.get("status") == "PASS" and proof.get("compiled_verified") is True
         and source.get("bytes") == MAP_SOURCE_PIN["bytes"] and source.get("sha256") == MAP_SOURCE_PIN["sha256"]
         and source.get("raw_crc32") == MAP_SOURCE_CRC and source.get("converted") is False
         and package.get("bytes") == TARGET_PINS[MAP_TARGET]["bytes"]
         and package.get("sha256") == TARGET_PINS[MAP_TARGET]["sha256"] and package.get("version") == 2
         and package.get("crc_entries") == MAP_CRC_ENTRIES
         and match.get("source_name") == "maps/template_map.vmap"
         and str(match.get("compiled_search_path", "")).lower() == "dota_addons/survival"
         and match.get("matches") is True
         and match.get("raw_source_crc32") == match.get("compiled_source_crc32") == MAP_SOURCE_CRC
         and compiled.get("path") == "maps/template_map.vmap_c" and compiled.get("dependency_block") == "RED2"
         and type(compiled.get("bytes")) is int and compiled["bytes"] > 0
         and isinstance(compiled.get("sha256"), str) and len(compiled["sha256"]) == 64
         and all(c in "0123456789abcdef" for c in compiled["sha256"]),
         "MAP2802 map package/source-CRC proof differs from reviewed compile")
    entries = package.get("entries")
    need(isinstance(entries, list) and len(entries) == MAP_CRC_ENTRIES
         and all(isinstance(entry, dict) for entry in entries)
         and len({entry.get("path") for entry in entries}) == MAP_CRC_ENTRIES
         and all(entry.get("crc_matches") is True
                 and type(entry.get("expected_crc32")) is int and 0 <= entry["expected_crc32"] < 2**32
                 and type(entry.get("actual_crc32")) is int
                 and entry["expected_crc32"] == entry.get("actual_crc32") for entry in entries),
         "MAP2802 map package entry CRC proof differs")
    embedded = [entry for entry in entries if entry.get("path") == compiled["path"]]
    need(len(embedded) == 1 and embedded[0].get("sha256") == compiled.get("sha256")
         and embedded[0].get("bytes") == compiled.get("bytes"), "MAP2802 compiled VMAP identity differs inside map proof")
    return proof


def project(before, pins, policy):
    need(pins and MAP_TARGET in pins and all(allowed_target(name) for name in pins),
         "MAP2802 requires an exact reviewed map/dependency inventory")
    after = copy.deepcopy(before)
    old = {row["path"]: row for row in before["files"]}
    rows = copy.deepcopy(old)
    for name, pin in pins.items():
        need(set(pin) == {"bytes", "md5", "sha256"}, "MAP2802 replacement pin shape differs")
        rows[name] = dict(path=name, **pin)
    after["files"] = [rows[name] for name in sorted(rows)]
    after["file_count"] = len(rows)
    after["bytes"] = sum(row["bytes"] for row in rows.values())
    after["content_sha256"] = hashlib.sha256(pack.runtime.manifest_payload(after)).hexdigest()
    pack.runtime.validate_manifest(after)
    changed = {name for name in rows if old.get(name) != rows[name]}
    need(changed == set(pins) and old.keys() <= rows.keys(), "MAP2802 includes unchanged targets or removes runtime files")
    protection.check_policy(policy)
    chosen = [{row["path"] for row in protection.selected_files(list(value), policy)} for value in (old, rows)]
    need(chosen[0] == chosen[1] and len(chosen[0]) == PROTECTED_COUNT
         and all(old[name] == rows[name] for name in chosen[0]), "MAP2802 protected 180 modules differ")
    for name, digest in PRESERVED_RUNTIME_PINS.items():
        need(old.get(name, {}).get("sha256") == digest and rows[name] == old[name],
             "MAP2802 entry/QR/layout resource differs: " + name)
    return after


def rotation_plan(entries, before, after, changed):
    """Keep old placements; move only reviewed replacements when a volume grows.

    Existing archive count stays fixed. Prefer the last volume's free space.
    No unchanged asset is silently rotated, and overflow fails before any write.
    """
    old = {row["path"]: row for row in before["files"]}
    rows = {row["path"]: row for row in after["files"]}
    previous = {row["path"]: row["archive"] for row in entries}
    indices = sorted(set(previous.values()))
    need(indices and indices == list(range(len(indices))) and previous.keys() == old.keys(),
         "MAP2802 base archive assignments differ")
    need(old.keys() <= rows.keys() and changed == {name for name in rows if old.get(name) != rows[name]},
         "MAP2802 reviewed changed path set differs")
    assignments = {name: previous.get(name, indices[-1]) for name in rows}
    sizes = [sum(row["bytes"] for name, row in rows.items() if assignments[name] == index) for index in indices]
    moves = []
    for index in indices:
        if sizes[index] <= pack.ARCHIVE_BYTES:
            continue
        candidates = sorted((name for name in changed if assignments[name] == index),
                            key=lambda name: (-rows[name]["bytes"], name))
        for name in candidates:
            amount = rows[name]["bytes"]
            target = next((dest for dest in reversed(indices) if dest != index
                           and sizes[dest] + amount <= pack.ARCHIVE_BYTES), None)
            if target is None:
                continue
            assignments[name] = target
            sizes[index] -= amount
            sizes[target] += amount
            moves.append(dict(path=name, old_archive=index, new_archive=target, bytes=amount))
            if sizes[index] <= pack.ARCHIVE_BYTES:
                break
        need(sizes[index] <= pack.ARCHIVE_BYTES,
             "MAP2802 existing archives cannot fit reviewed replacements; separate reviewed repack required")
    tree, ordered, _ = pack.make_tree(after["files"])
    groups = [[item for item in ordered if assignments[item["row"]["path"]] == index] for index in indices]
    need(all(groups), "MAP2802 cannot remove an entire existing archive")
    rewritten = set()
    for index, group in enumerate(groups):
        old_paths = {name for name, value in previous.items() if value == index}
        new_paths = {item["row"]["path"] for item in group}
        if old_paths != new_paths or any(old.get(name) != rows[name] for name in new_paths):
            rewritten.add(index)
    return tree, groups, rewritten, moves


def paths(key, build):
    base, trusted_base, vpk = [incremental.external(path) for path in (BASE, BASE_TRUSTED, BASE_VPK)]
    destinations = [incremental.external(path, exists=False) for path in (OVERLAY, TRUSTED, VIEW, OUTPUT)]
    incremental.disjoint([base, trusted_base, vpk.parent, *destinations])
    need(all(not path.exists() for path in destinations), "MAP2802 requires entirely new output directories")
    need(incremental.ancestor(VIEW).stat().st_dev == base.stat().st_dev
         and incremental.ancestor(OUTPUT).stat().st_dev == vpk.stat().st_dev,
         "MAP2802 hard-link reuse requires the base volume")
    if not build:
        need(key is None, "MAP2802 private key is accepted only with --build")
        return None
    need(TARGET_PINS and MAP_SOURCE_PIN and COMPILE_LOG_SHA and MAP_VERIFICATION_SHA
         and EXPECTED_REBUILT_ARCHIVES is not None,
         "MAP2802 build remains closed until compile pins and archive plan are reviewed")
    need(key is not None, "MAP2802 --build requires an external --key")
    key = pack.handoff.regular_path(pack.protect_data.external(key, source=base))
    need(key.is_file(), "MAP2802 signing key must be a regular external file")
    for destination in destinations:
        need(not pack.runtime.within(key, destination) and not pack.runtime.within(destination, key.parent),
             "MAP2802 outputs overlap the private key directory")
    return key


def run(*, build=False, key=None):
    need(SEQUENCE == 2026102802 and BASE_SEQUENCE == 2026102801,
         "MAP2802 fixed new/base release sequences differ")
    key = paths(key, build)
    snapshots, payloads = {}, {}
    for path, pin, normalized in ((PRIMITIVES, PRIMITIVES_SHA, True),
                                  (Path(pack.handoff.__file__), PUBLISHER_SHA, False),
                                  (ROOT / "tools/build_runtime_release.py", PARSER_SHA, True)):
        capture(path, snapshots, sha=pin, normalized=normalized)
    capture(Path(__file__), snapshots)
    for name, pin in PUBLIC_PINS.items():
        capture(ROOT / name, snapshots, sha=pin)
    names = set(GATE_NAMES) | REVIEW_PINS.keys()
    need(len(GATE_NAMES) == len(set(GATE_NAMES)) == 14 and incremental.all_files(BASE_TRUSTED) == names,
         "MAP2802 base trusted-source inventory differs")
    review = {name: capture(BASE_TRUSTED / name, snapshots, sha=REVIEW_PINS.get(name)) for name in names}
    need(all(review[name] == snapshots[ROOT / name] for name in POLICY_NAMES), "MAP2802 public trust differs")
    with incremental.trusted_source(BASE_TRUSTED):
        _, before, signed, base_metadata = pack.authenticate(BASE)
    need(before["content_sha256"] == BASE_CONTENT and before["file_count"] == BASE_COUNT
         and signed["release_sequence"] == BASE_SEQUENCE, "MAP2802 base signed 2801 identity differs")
    report = pack.handoff.decode_json(capture(BASE_REPORT, snapshots, sha=BASE_REPORT_SHA))
    need(report.get("content_sha256") == BASE_CONTENT and report.get("release_sequence") == BASE_SEQUENCE
         and report.get("signature_valid") is True and report.get("dry_run") is False
         and report.get("full_runtime_validator_passed") is True and report.get("full_view_canonical_guard") == "PASS"
         and report.get("protected_modules_preserved") == PROTECTED_COUNT,
         "MAP2802 actual verified 2801 package report required")
    downloaded = pack.handoff.decode_json(capture(BASE_DOWNLOAD, snapshots, sha=BASE_DOWNLOAD_SHA))
    need(downloaded.get("status") == "OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED"
         and downloaded.get("release_sequence") == BASE_SEQUENCE and downloaded.get("content_sha256") == BASE_CONTENT
         and downloaded.get("steam_manifest") == BASE_STEAM_MANIFEST and type(downloaded["steam_manifest"]) is str
         and downloaded.get("signed_resources_verified") == BASE_COUNT
         and downloaded.get("protected_modules_verified") == PROTECTED_COUNT,
         "MAP2802 actual fresh 2801 official download receipt required")
    inventory = pack.package_inventory(BASE_VPK)
    need(inventory == report.get("package_files") and len(inventory) == 5
         and report.get("vpk_sha256") == inventory[0]["sha256"], "MAP2802 base five-VPK bytes differ")
    pack.verify_vpk(BASE_VPK, before)
    frozen_archives = {path: incremental.snapshot(path) for path in pack.package_paths(BASE_VPK)}
    entries = incremental.read_entries(BASE_VPK)
    if not TARGET_PINS:
        need(not build, "MAP2802 missing compile pins")
        unchanged(snapshots, payloads)
        return dict(status="DRAFT_PENDING_REVIEWED_MAP_COMPILE_PINS", dry_run=True,
                    base_release_sequence=BASE_SEQUENCE, base_content_sha256=BASE_CONTENT,
                    proposed_release_sequence=SEQUENCE, files=BASE_COUNT,
                    archive_headroom_bytes={str(i): pack.ARCHIVE_BYTES - row["bytes"] for i, row in enumerate(inventory[1:])},
                    target_pins_reviewed=False, ready_for_upload=False, workshop_upload_performed=False)
    need(MAP_SOURCE_PIN is not None and COMPILE_LOG_SHA is not None, "MAP2802 source/compile evidence pins missing")
    capture_payload(MAP_SOURCE, MAP_SOURCE_PIN, payloads)
    verify_compile_log(capture(COMPILE_LOG, snapshots, sha=COMPILE_LOG_SHA, maximum=1024 * 1024))
    verify_map_proof(capture(MAP_VERIFICATION, snapshots, sha=MAP_VERIFICATION_SHA, maximum=1024 * 1024))
    replacements = {name: capture_payload(pack.protect_data.source_path(ROOT, name), pin, payloads)
                    for name, pin in TARGET_PINS.items()}
    after = project(before, TARGET_PINS, pack.handoff.decode_json(snapshots[ROOT / "tools/lua_protection_policy.json"]))
    tree, groups, rewritten, moves = rotation_plan(entries, before, after, set(TARGET_PINS))
    if build:
        need(sorted(rewritten) == list(EXPECTED_REBUILT_ARCHIVES), "MAP2802 actual archive plan differs from reviewed indices")
    sizes = [sum(item["row"]["bytes"] for item in group) for group in groups]
    stage_bytes = sum(pin["bytes"] for pin in TARGET_PINS.values()) * 2 + sum(map(len, review.values())) + sum(incremental.METADATA.values()) * 2
    disk = incremental.capacity(VIEW, OUTPUT, stage_bytes, sum(sizes[i] for i in rewritten), pack.HEADER.size + len(tree) + 48, 0)
    unchanged(snapshots, payloads)
    result = dict(schema=1, status="READ_ONLY_MAP2802_PLAN", revision=REVISION, dry_run=not build,
        release_sequence=SEQUENCE, content_sha256=after["content_sha256"], files=after["file_count"],
        base_release_sequence=BASE_SEQUENCE, base_content_sha256=BASE_CONTENT,
        base_package_report_sha256=BASE_REPORT_SHA, base_official_download_sha256=BASE_DOWNLOAD_SHA,
        overlay=str(OVERLAY), trusted_source=str(TRUSTED), candidate=str(VIEW), output=str(OUTPUT / (ITEM + ".vpk")),
        changed_runtime_paths=sorted(TARGET_PINS), deleted_runtime_paths=[], added_runtime_paths=sorted(set(TARGET_PINS) - {r["path"] for r in before["files"]}),
        protected_modules_preserved=PROTECTED_COUNT, protected_modules_rebuilt=0, trusted_gate_files=14, trusted_review_files=16,
        qr_fix_preserved=True, layout_fix_preserved=True, authentication_payment_gameplay_code_preserved=True,
        source_sha256=MAP_SOURCE_PIN["sha256"], source_crc32=MAP_SOURCE_CRC,
        compile_log_sha256=COMPILE_LOG_SHA, map_package_verification_sha256=MAP_VERIFICATION_SHA,
        map_package_crc_entries_verified=MAP_CRC_ENTRIES, map_compiled_source_crc_verified=True,
        payload_changed=False, full_input_hash_verification=True, rebuilt_archives=sorted(rewritten),
        reused_archives=sorted(set(range(len(groups))) - rewritten), archive_migrations=moves, archive_reuse="hardlink",
        payload_bytes=after["bytes"], container_bytes=after["bytes"] + pack.HEADER.size + len(tree) + 48,
        max_archive_bytes=pack.ARCHIVE_BYTES, physical_rebuilt_bytes=sum(sizes[i] for i in rewritten), disk_preflight=disk,
        separate_official_download_budget_bytes=after["bytes"] + pack.HEADER.size + len(tree) + 48 + 1024**3,
        full_view_canonical_guard="NOT_RUN_requires_build", workshop_upload_performed=False,
        native_dota_read_test="NOT_RUN", ready_for_upload=False)
    if not build:
        return result
    OVERLAY.mkdir(parents=True, exist_ok=False)
    TRUSTED.mkdir(parents=True, exist_ok=False)
    for name, path in replacements.items():
        incremental.copy_new(path, OVERLAY / name, dict(path=name, **TARGET_PINS[name]))
    for name, raw in review.items():
        incremental.write_new(TRUSTED / name, raw)
    incremental.write_new(OVERLAY / pack.handoff.MANIFEST, pack.runtime.canonical_bytes(after) + b"\n")
    unchanged(snapshots, payloads)
    pack.protect_data.sign_manifest(OVERLAY / pack.handoff.MANIFEST, key, OVERLAY / pack.handoff.SIGNATURE, SEQUENCE)
    policy, public = pack.handoff.trusted_policy(pack.handoff.POLICY)
    actual, document, metadata = incremental.metadata(OVERLAY)
    signature = pack.verify_signed_snapshot(actual, document, public,
        policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
    need(actual == after and signature["release_sequence"] == SEQUENCE, "MAP2802 signed overlay identity differs")
    sources, changed = incremental.validate_merged(BASE, OVERLAY, before, after, TRUSTED)
    need(changed == set(TARGET_PINS) and incremental.all_files(TRUSTED) == names, "MAP2802 staged scope differs")
    incremental.materialize(VIEW, sources, changed, after, metadata)
    with incremental.trusted_source(TRUSTED):
        _, verified, verified_signature, view_metadata = pack.authenticate(VIEW)
    need(verified == after and verified_signature == signature, "MAP2802 complete view identity differs")
    unchanged(snapshots, payloads)
    verification, package_files = incremental.build_volumes(VIEW, OUTPUT, BASE_VPK, tree, groups, rewritten, after, "hardlink")
    unchanged(snapshots, payloads)
    for folder, frozen in ((BASE, base_metadata), (OVERLAY, metadata), (VIEW, view_metadata)):
        pack.inventory_unchanged(folder, frozen)
    need(all(incremental.snapshot(path) == stat for path, stat in frozen_archives.items())
         and pack.package_inventory(BASE_VPK) == inventory and pack.runtime.verify(BASE, before)["ok"],
         "MAP2802 immutable base changed")
    result.update(status="BUILT_SIGNED_MAP2802_REQUIRES_NATIVE_MAP_TEST", dry_run=False, signature_valid=True,
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
        print(__import__("json").dumps({"status": "BLOCKED", "error": str(error)}, ensure_ascii=False))
        return 1
    print(__import__("json").dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
