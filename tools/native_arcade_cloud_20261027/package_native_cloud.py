"""Package only the reviewed native-cloud 2708 release; default is read-only.

The signed thin overlay is combined with immutable SHOP02. A new complete
hard-link view must pass the shared publisher guards before any VPK is written.
Only changed archives are rebuilt. This tool has no signing, upload, install,
Steam SDK, game launch, or arbitrary input-path/sequence option.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
RUNTIME_VALIDATOR_FILE = ROOT / "tools/build_runtime_release.py"
RUNTIME_VALIDATOR_LF_SHA = "2b321bf45df70463e84684d982d3a83189b9b3a5f7565b972bb14383de363e81"
if hashlib.sha256(RUNTIME_VALIDATOR_FILE.read_bytes().replace(b"\r\n", b"\n")).hexdigest() != RUNTIME_VALIDATOR_LF_SHA:
    raise ValueError("Reviewed production profile parser changed")
PRIMITIVES = ROOT / "tools/arcade_cleanup_20261027/incremental_vpk.py"
PRIMITIVES_LF_SHA = "a90312c526dac539eb3e83bf7a3fe17615ac5550f1bb9dd6e659c58f2af349e7"
PUBLISHER_SHA = "6131f0358c328e8574b44ccb07c589ef68e1544e197c2555569fda7ed0f81f40"
if hashlib.sha256(PRIMITIVES.read_bytes().replace(b"\r\n", b"\n")).hexdigest() != PRIMITIVES_LF_SHA:
    raise ValueError("Reviewed incremental VPK primitives changed")
spec = importlib.util.spec_from_file_location("native_cloud_incremental_primitives", PRIMITIVES)
incremental = importlib.util.module_from_spec(spec)
spec.loader.exec_module(incremental)
pack, need = incremental.pack, incremental.need
import protect_runtime_lua as lua_protection

ITEM = "3824360109"
BASE, BASE_TRUSTED, BASE_VPK = incremental.BASE, incremental.BASE_TRUSTED, incremental.BASE_VPK
BASE_CONTENT, BASE_SEQUENCE, BASE_COUNT = incremental.BASE_CONTENT, 2026102604, 6637
BASE_PACKAGE = incremental.BASE_PACKAGE
OVERLAY = Path("D:/Survival_发布候选/20261027_ws4_native_cloud_v02_overlay")
TRUSTED = OVERLAY.with_name(OVERLAY.name + "_trusted_source")
VIEW = Path("D:/Survival_发布候选/20261027_ws4_native_cloud_v02_view")
OUTPUT = Path("D:/Survival_工坊输出/20261027_ws4_native_cloud_v02")
SEQUENCE, COUNT = 2026102708, 6658
CONTENT = "55d9e63ea1c95bed2456c739c0cf0e3148030e91a43f3a0d72aeaf64ab540e26"
REPORT = ROOT / "output/native_arcade_cloud_20261027/native_cloud_v02_plan.json"
REPORT_SHA = "a35df91512ffff21c66bb96a07f299b79a50edbee95e531bff02ab13b164e286"
PROTECTION_POLICY = ROOT / "tools/lua_protection_policy.json"
PROTECTION_SHA = "bc03e38f2e0b9165299df5777dbb561a593d5d4e2f45eaef5e51c48f8856958a"
REMOVED = {"panorama/styles/custom_game/commerce_wallet.vcss_c"}
ADDED_COUNT, UPDATED_COUNT, PROTECTED_COUNT = 22, 48, 180
POLICY_NAMES = ("tools/release_security/protection_policy.json", "tools/release_security/trusted_public_key.pem")
TRUST_NAMES = (*pack.handoff.GATE_FILES, *pack.handoff.ENTRY_GATE_FILES, pack.handoff.ACCESS_FILE,
               *POLICY_NAMES, *pack.handoff.NATIVE_CLOUD_ENTRY_GATE_FILES[:2])


def read_snapshot(path, maximum, snapshots):
    path = pack.handoff.regular_path(path)
    need(path.is_file(), "Missing reviewed input: " + path.name)
    raw = pack.read_metadata(path, maximum)
    snapshots[path] = raw
    return raw


def unchanged(snapshots):
    for path, expected in snapshots.items():
        need(pack.read_metadata(pack.handoff.regular_path(path), len(expected)) == expected,
             "Reviewed input changed while packaging: " + path.name)


def reviewed_report(snapshots):
    raw = read_snapshot(REPORT, pack.MAX_MANIFEST, snapshots)
    need(hashlib.sha256(raw).hexdigest() == REPORT_SHA, "Final native-cloud plan receipt differs")
    report = pack.handoff.decode_json(raw)
    exact = dict(ok=True, status="READ_ONLY_PLAN", revision="WS4-NATIVE-CLOUD-02", release_sequence=SEQUENCE,
        base_content_sha256=BASE_CONTENT, base_files=BASE_COUNT, projected_content_sha256=CONTENT,
        expected_files=COUNT, destination=str(OVERLAY), trusted_source=str(TRUSTED), view=str(VIEW), package=str(OUTPUT),
        protected_modules_preserved=PROTECTED_COUNT, protected_modules_rebuilt=0, four_accounts_preserved=True,
        production_preserved=True, online_cheats_allowed=False, web_auth=True, session_only=False,
        cash_code_enabled=True, connection_helper=False, full_view_canonical_required=True,
        native_cloud_roster_required=True, development_release_profile_modified=False,
        default_map="ws4_entry", entry_capacity=4, gameplay_map="template_map", gameplay_capacity=4,
        native_entry_handoff_acceptance="NOT_RUN", multiplayer_cloud_auth_acceptance="NOT_RUN",
        this_candidate_payment_acceptance="NOT_RUN", workshop_upload_performed=False,
        alias_installed=False, game_started=False, real_order_created=False, private_key_copied=False)
    need(all(type(report.get(key)) is type(value) and report[key] == value for key, value in exact.items()),
         "Final native-cloud plan identity, gates or acceptance state differs")
    return report


def verify_trust(snapshots):
    need(len(TRUST_NAMES) == len(set(TRUST_NAMES)) == 14, "Native-cloud review-source scope differs")
    need(incremental.all_files(TRUSTED) == set(TRUST_NAMES), "Review source contains missing or foreign files")
    for relative in TRUST_NAMES:
        raw = read_snapshot(pack.protect_data.source_path(TRUSTED, relative), pack.MAX_MANIFEST, snapshots)
        if relative in POLICY_NAMES:
            expected = read_snapshot(ROOT / relative, pack.MAX_MANIFEST, snapshots)
            need(raw == expected, "Native-cloud trusted policy/public key differs from checkout")
    raw = read_snapshot(Path(pack.handoff.__file__), pack.MAX_MANIFEST, snapshots)
    need(hashlib.sha256(raw).hexdigest() == PUBLISHER_SHA, "Canonical native-cloud publisher guard changed")
    raw = read_snapshot(PRIMITIVES, pack.MAX_MANIFEST, snapshots)
    need(hashlib.sha256(raw.replace(b"\r\n", b"\n")).hexdigest() == PRIMITIVES_LF_SHA,
         "Reviewed incremental VPK primitives changed after import")
    raw=read_snapshot(RUNTIME_VALIDATOR_FILE,pack.MAX_MANIFEST,snapshots)
    need(hashlib.sha256(raw.replace(b"\r\n",b"\n")).hexdigest()==RUNTIME_VALIDATOR_LF_SHA,
         "Reviewed production profile parser changed after import")


def verify_scope(report, old, new):
    before, after = ({row["path"]: row for row in manifest["files"]} for manifest in (old, new))
    changed = {name for name in after if before.get(name) != after[name]}
    added, removed = set(after) - before.keys(), set(before) - after.keys()
    actual = [dict(path=name, before=before.get(name), after=after.get(name))
              for name in sorted(changed | removed)]
    need(len(changed) == UPDATED_COUNT and len(added) == ADDED_COUNT and removed == REMOVED,
         "Signed native-cloud complete change scope differs")
    need(report.get("changed") == actual and report.get("allowed_additions") == sorted(added)
         and report.get("allowed_removals") == sorted(removed), "Signed inventory differs from final reviewed plan")
    need(report.get("patch_sha256") == {name: after[name]["sha256"] for name in sorted(changed)},
         "Signed overlay bytes differ from reviewed patch pins")
    return changed, removed


def verify_protected(old, new, snapshots):
    raw = read_snapshot(PROTECTION_POLICY, pack.MAX_MANIFEST, snapshots)
    need(hashlib.sha256(raw).hexdigest() == PROTECTION_SHA, "Lua protection policy changed")
    policy = pack.handoff.decode_json(raw)
    lua_protection.check_policy(policy)
    before, after = ({row["path"]: row for row in manifest["files"]} for manifest in (old, new))
    selected = [{row["path"] for row in lua_protection.selected_files(list(rows), policy)} for rows in (before, after)]
    need(selected[0] == selected[1] and len(selected[0]) == PROTECTED_COUNT
         and all(before[name] == after[name] for name in selected[0]),
         "Protected 180-module inventory or original runtime bytes changed")
    return len(selected[0])


def run(*, build=False, reuse="hardlink"):
    need(reuse in ("hardlink", "copy"), "Invalid archive reuse mode")
    # No caller-supplied sequence/path and no mutation of the frozen 05/06 run().
    need(SEQUENCE == 2026102708, "Only the reviewed native-cloud sequence is supported")
    overlay, view, output = (incremental.external(OVERLAY), incremental.external(VIEW, exists=False),
                             incremental.external(OUTPUT, exists=False))
    base, base_vpk = incremental.external(BASE), incremental.external(BASE_VPK)
    trusted = pack.handoff.regular_path(TRUSTED)
    incremental.disjoint([base, overlay, trusted, view, output, base_vpk.parent, BASE_TRUSTED])
    need(not view.exists(), "Candidate view must be a new directory")
    need(not output.exists() or output.is_dir() and not list(output.iterdir()), "VPK output directory must be empty")
    need(incremental.ancestor(view).stat().st_dev == base.stat().st_dev,
         "Candidate view must share the immutable base volume")
    if reuse == "hardlink":
        need(incremental.ancestor(output).stat().st_dev == base_vpk.stat().st_dev,
             "Hard-linked archive reuse requires the base VPK volume")
    snapshots = {}
    report = reviewed_report(snapshots)
    verify_trust(snapshots)
    policy, public = pack.handoff.trusted_policy(pack.handoff.POLICY)
    with incremental.trusted_source(BASE_TRUSTED):
        _, old, old_signature, base_metadata = pack.authenticate(base)
    need(old["content_sha256"] == BASE_CONTENT and old["file_count"] == BASE_COUNT
         and old_signature["release_sequence"] == BASE_SEQUENCE
         and old_signature["key_id"] == policy["integrity"]["trusted_key_id"], "Immutable SHOP02 identity differs")
    need(pack.package_inventory(base_vpk) == BASE_PACKAGE, "Immutable SHOP02 VPK inventory differs")
    pack.verify_vpk(base_vpk, old)
    base_packages = {path: incremental.snapshot(path) for path in pack.package_paths(base_vpk)}
    new, document, signed_metadata = incremental.metadata(overlay)
    signature = pack.verify_signed_snapshot(new, document, public, policy["integrity"]["minimum_release_sequence"],
                                            policy["integrity"]["trusted_key_id"])
    need(signature["release_sequence"] == SEQUENCE and new["content_sha256"] == CONTENT
         and new["file_count"] == COUNT, "Signed native-cloud sequence/content/count differs")
    changed, removed = verify_scope(report, old, new)
    protected = verify_protected(old, new, snapshots)
    sources, merged_changes = incremental.validate_merged(base, overlay, old, new, trusted)
    need(merged_changes == changed, "Merged overlay change set differs")
    for relative in pack.handoff.NATIVE_CLOUD_ENTRY_GATE_FILES:
        need(pack.runtime.digest(sources[relative]) == pack.runtime.digest(trusted / relative),
             "Merged native-cloud entry differs from reviewed source: " + relative)
    tree, groups, rewritten = incremental.rotation_plan(incremental.read_entries(base_vpk), old, new)
    sizes = [sum(item["row"]["bytes"] for item in group) for group in groups]
    spaces = incremental.capacity(view, output, sum(row["bytes"] for row in new["files"] if row["path"] in changed),
        sum(sizes[index] for index in rewritten), pack.HEADER.size + len(tree) + 48,
        sum(sizes[index] for index in range(len(groups)) if index not in rewritten) if reuse == "copy" else 0)
    unchanged(snapshots)
    pack.inventory_unchanged(base, base_metadata)
    pack.inventory_unchanged(overlay, signed_metadata)
    need(all(incremental.snapshot(path) == value for path, value in base_packages.items()), "Base VPK changed during plan")
    result = dict(schema=1, ok=True, status="VERIFIED_NATIVE_CLOUD_PACKAGE_PLAN", dry_run=not build,
        candidate=str(view), overlay=str(overlay), trusted_source=str(trusted), output=str(output / (ITEM + ".vpk")),
        base_content_sha256=BASE_CONTENT, content_sha256=CONTENT, release_sequence=SEQUENCE, files=COUNT,
        final_plan_sha256=REPORT_SHA, trusted_key_id=signature["key_id"], signature_valid=True,
        full_input_hash_verification=True, protected_modules_preserved=protected, protected_modules_rebuilt=0,
        full_view_canonical_guard="NOT_RUN_requires_build_materialization", layout="external_archives",
        native_cloud_roster_required=True,
        payload_bytes=new["bytes"], container_bytes=new["bytes"] + pack.HEADER.size + len(tree) + 48,
        max_archive_bytes=pack.ARCHIVE_BYTES, changed_runtime_paths=sorted(changed), deleted_runtime_paths=sorted(removed),
        rebuilt_archives=sorted(rewritten), reused_archives=sorted(set(range(len(groups))) - rewritten),
        archive_reuse=reuse, physical_rebuilt_bytes=sum(sizes[index] for index in rewritten), disk_preflight=spaces,
        payload_changed=False, workshop_upload_performed=False, native_dota_read_test="NOT_RUN", native_over_2gib_read_test="NOT_RUN",
        multiplayer_cloud_auth_acceptance="NOT_RUN", this_candidate_payment_acceptance="NOT_RUN", ready_for_upload=False)
    if not build:
        return result
    owned_view = False
    try:
        unchanged(snapshots)
        incremental.materialize(view, sources, changed, new, signed_metadata)
        owned_view = True
        # This is the actual shared canonical entry4 + reviewed gate + complete
        # signed/fullhash check, not a partial thin-filesystem approximation.
        with incremental.trusted_source(trusted):
            _, verified, verified_signature, view_metadata = pack.authenticate(view)
        need(verified == new and verified_signature == signature, "Complete native-cloud view identity differs")
        unchanged(snapshots)
        verification, inventory = incremental.build_volumes(view, output, base_vpk, tree, groups, rewritten, new, reuse)
        unchanged(snapshots)
        pack.inventory_unchanged(base, base_metadata)
        pack.inventory_unchanged(overlay, signed_metadata)
        pack.inventory_unchanged(view, view_metadata)
        need(all(incremental.snapshot(path) == value for path, value in base_packages.items()), "Base VPK changed during build")
        need(pack.package_inventory(base_vpk) == BASE_PACKAGE and pack.runtime.verify(base, old)["ok"],
             "Immutable SHOP02 changed during native-cloud build")
        result.update(status="BUILT_AND_VERIFIED_NATIVE_CLOUD_REQUIRES_NATIVE_TEST", dry_run=False,
            full_view_canonical_guard="PASS", canonical_single_map=True, canonical_reviewed_gate=True,
            full_runtime_validator_passed=True, immutable_base_unchanged=True, verification=verification,
            package_files=inventory, vpk_sha256=inventory[0]["sha256"])
        return result
    except BaseException:
        if owned_view and not (output / (ITEM + ".vpk")).exists():
            incremental.remove_owned_tree(view)
        raise


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--build", action="store_true")
    result.add_argument("--reuse", choices=("hardlink", "copy"), default="hardlink")
    return result


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        result = run(build=args.build, reuse=args.reuse)
    except Exception as error:
        print(json.dumps(dict(ok=False, status="BLOCKED_DO_NOT_UPLOAD", error=str(error),
                              workshop_upload_performed=False), ensure_ascii=True))
        return 1
    print(json.dumps(result, ensure_ascii=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
