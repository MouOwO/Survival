"""Build a new, scoped 3102 candidate over verified 3101; never deploy/upload.

Default is a read-only plan. --build needs that exact plan and an existing
external key. Backend redemption admission and native startup remain separate.
"""
from contextlib import contextmanager
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json
import re
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("shop3102_parent", ROOT / "tools/wall_attack_release_20261031/build_release.py")
parent = importlib.util.module_from_spec(spec); spec.loader.exec_module(parent)
inc, pack, need = parent.inc, parent.pack, parent.need
BASE_REPORT = ROOT / "output/wall_attack_release_20261031/package.json"
BASE_REPORT_SHA = "66af15ec97586cd28c6314bd420085e55f52b2c4c6df5a6e7eca054e359fab22"
BASE_RECORD = ROOT / "publishing/workshop/wall_attack_perf_20261031_v01.json"
BASE_CONTENT = "b99f3ac128c6433012f419fba87b6b7b59ca2aab8c2c98339f50f24c788b3263"
BASE = Path("D:/Survival_发布候选/20261031_ws4_wall_perf_v01_view")
BASE_TRUSTED = Path("D:/Survival_发布候选/20261031_ws4_wall_perf_v01_trusted_source")
BASE_VPK = Path("D:/Survival_工坊输出/20261031_ws4_wall_perf_v01/3824360109.vpk")
ITEM, SEQUENCE, REVISION = "3824360109", 2026103102, "WS4-SHOP-BENEFITS-REDEMPTION-01"
PREFIX = "20261031_ws4_shop_recovery_v01"
OVERLAY = Path("D:/Survival_发布候选") / (PREFIX + "_overlay")
VIEW = Path("D:/Survival_发布候选") / (PREFIX + "_view")
TRUSTED = Path("D:/Survival_发布候选") / (PREFIX + "_trusted_source")
OUTPUT = Path("D:/Survival_工坊输出") / PREFIX
UNSIGNED = Path("D:/Survival_发布候选") / (PREFIX + "_unsigned_review")
REPORT = ROOT / "output/shop_recovery_20261031"
MODE = "scripts/vscripts/config/mode_release_config.lua"
PAYLOADS = (MODE, "scripts/vscripts/systems/commerce_service.lua",
    "panorama/scripts/custom_game/black_lion_market.vjs_c",
    "panorama/layout/custom_game/redemption_code.vxml_c",
    "panorama/styles/custom_game/redemption_code.vcss_c",
    "scripts/vscripts/debug/mode_unlock_test.lua")


def sha(raw): return hashlib.sha256(raw).hexdigest()
def load(path): return json.loads(path.read_bytes())
def checks(raw): return {"bytes": len(raw), "md5": hashlib.md5(raw).hexdigest(), "sha256": sha(raw)}


def baseline(full=False):
    report, manifest, signature = parent.validated_package(BASE_REPORT_SHA, full=full)
    record = load(BASE_RECORD)
    need(record["status"] == "UPLOADED_AND_OFFICIAL_DOWNLOAD_FULLY_VERIFIED"
         and record["release_sequence"] == 2026103101 and record["content_sha256"] == BASE_CONTENT
         and record["package_files"] == report["package_files"], "Verified 3101 publication required")
    need(manifest["content_sha256"] == BASE_CONTENT and signature["release_sequence"] == 2026103101,
         "Parent signed identity differs")
    state = load(parent.JOURNAL)
    need(state.get("uploaded") is True and state.get("workshop_id") == ITEM
         and state.get("release_sequence") == 2026103101 and state.get("content_sha256") == BASE_CONTENT,
         "Canonical publication is not the verified 3101 parent")
    return report, manifest


def payloads(revision):
    revision = parent.revision(revision)
    values = {name: parent.blob(revision, name) for name in PAYLOADS}
    need(re.search(rb"(?m)^M\.all_difficulties_unlocked\s*=\s*false\s*$", values[MODE]) is not None,
         "Online package must not latch read-only acceptance")
    need(b"redemption_redeem" in values[PAYLOADS[1]] and b"action~='redeem'" in values[PAYLOADS[1]],
         "Server redemption dispatcher missing")
    need(b"BlackLionMarketRedeem" in values[PAYLOADS[2]] and all(values[name] for name in PAYLOADS),
         "Compiled redemption UI is incomplete")
    return revision, values


def plan(revision):
    base_report, old = baseline()
    revision, values = payloads(revision)
    after, changed = parent.projected(old, values)
    need(set(changed) == set(PAYLOADS), "Unexpected six-file scope")
    policy = load(ROOT / "tools/lua_protection_policy.json")
    selected = {row["path"] for row in parent.previous.base.protection.selected_files(
        [row["path"] for row in after["files"]], policy)}
    need(len(selected) == 184 and not selected.intersection(changed), "Protected modules must remain exact")
    expected_review = base_report["trusted_review_pins"]
    extra = inc.all_files(BASE_TRUSTED) - set(expected_review)
    handoff = {"output/release_test_handoff/svt_m3101/" + name for name in
               ("_release_manifest.json", "_release_signature.json", "handoff.json")}
    need(extra <= handoff, "Unknown files in parent trusted source")
    review = {name: checks((BASE_TRUSTED / name).read_bytes()) for name in sorted(expected_review)}
    need(review == expected_review, "Parent admission review bytes changed")
    need(len(review) == 16 and not set(review).intersection(changed), "Admission review sources must remain exact")
    tree, groups, rewritten, moves = parent.previous.base.parent.rotation_plan(
        inc.read_entries(BASE_VPK), old, after, set(changed))
    sizes = [sum(item["row"]["bytes"] for item in group) for group in groups]
    disk = inc.capacity(VIEW, OUTPUT, 2 * sum(map(len, changed.values())) + 2**22,
        sum(sizes[index] for index in rewritten), pack.HEADER.size + len(tree) + 48, 0)
    pins = {name: checks((ROOT / name).read_bytes()) for name in
        ("tools/shop_recovery_20261031/build_release.py", *parent.AUXILIARY_INPUTS)}
    result = dict(schema=1, status="READY_FOR_SCOPED_SIGNED_BUILD", workshop_id=ITEM,
        release_sequence=SEQUENCE, revision=REVISION, source_revision=revision,
        baseline_release_sequence=2026103101, baseline_content_sha256=BASE_CONTENT,
        baseline_report_sha256=BASE_REPORT_SHA, canonical_journal_sha256=pack.runtime.digest(parent.JOURNAL),
        target_pins={name: checks(raw) for name, raw in sorted(changed.items())},
        changed_runtime_paths=sorted(changed), removed_runtime_paths=[], files=after["file_count"],
        content_sha256=after["content_sha256"], protected_modules_preserved=184,
        trusted_review_pins=review, auxiliary_input_pins=pins, rebuilt_archives=sorted(rewritten),
        archive_migrations=moves, disk_preflight=disk, candidate=str(VIEW), trusted_source=str(TRUSTED),
        output=str(OUTPUT / (ITEM + ".vpk")), baseline_package_files=base_report["package_files"],
        container_bytes=after["bytes"] + pack.HEADER.size + len(tree) + 48,
        all_difficulties_unlocked=False, offline_isolation_preserved=True,
        account_gates_payment_policy_preserved=True, archive_bundle_hash=parent.EXPECTED_BUNDLE,
        ready_for_upload=False, redemption_backend_acceptance="REQUIRED_NOT_PROVIDED",
        server_changed=False, workshop_upload_performed=False, native_test="NOT_RUN", dry_run=True)
    return result, old, after, changed, tree, groups


def build(reviewed, revision, key):
    actual, old, after, values, tree, groups = plan(revision)
    need(parent.same_plan(load(reviewed), actual), "Reviewed plan changed")
    need(key is not None, "Existing external signing key required")
    key = pack.handoff.regular_path(pack.protect_data.external(key, source=BASE))
    for target in (OVERLAY, TRUSTED, VIEW, OUTPUT):
        inc.external(target, exists=False); need(not target.exists(), "NEW artifact directories required")
        need(not pack.runtime.within(key, target) and not pack.runtime.within(target, key.parent), "Key/output overlap")
    inc.disjoint([BASE, BASE_TRUSTED, BASE_VPK.parent, OVERLAY, TRUSTED, VIEW, OUTPUT])
    baseline(full=True)
    OVERLAY.mkdir(parents=True, exist_ok=False); TRUSTED.mkdir(parents=True, exist_ok=False)
    for name, raw in values.items(): inc.write_new(OVERLAY / name, raw)
    for name, pin in actual["trusted_review_pins"].items():
        raw = (BASE_TRUSTED / name).read_bytes(); need(checks(raw) == pin, "Trusted source drift")
        inc.write_new(TRUSTED / name, raw)
    inc.write_new(OVERLAY / pack.handoff.MANIFEST, pack.runtime.canonical_bytes(after) + b"\n")
    pack.protect_data.sign_manifest(OVERLAY / pack.handoff.MANIFEST, key, OVERLAY / pack.handoff.SIGNATURE, SEQUENCE)
    _, _, metadata = inc.metadata(OVERLAY)
    sources, changed = inc.validate_merged(BASE, OVERLAY, old, after, TRUSTED)
    need(changed == set(values), "Merged scope differs")
    inc.materialize(VIEW, sources, changed, after, metadata)
    with parent.scene_maps(), inc.trusted_source(TRUSTED):
        _, verified, signature, _ = pack.authenticate(VIEW)
    need(verified == after and signature["release_sequence"] == SEQUENCE, "Candidate signature/identity differs")
    with parent.scene_maps():
        verification, files = inc.build_volumes(VIEW, OUTPUT, BASE_VPK, tree, groups,
            set(actual["rebuilt_archives"]), after, "hardlink")
    need(pack.package_inventory(BASE_VPK) == actual["baseline_package_files"]
         and pack.runtime.verify(BASE, old)["ok"], "Immutable parent changed")
    final, *_ = plan(revision); need(parent.same_plan(final, actual), "Inputs/publication changed during build")
    actual.update(status="BUILT_SIGNED_PENDING_NATIVE_AND_REDEMPTION_BACKEND", dry_run=False,
        signature_valid=True, full_runtime_validator_passed=True, package_files=files,
        vpk_sha256=files[0]["sha256"], verification=verification)
    return actual


def prepare_unsigned(revision):
    actual, _, after, values, _, _ = plan(revision)
    inc.external(UNSIGNED, exists=False)
    need(not UNSIGNED.exists(), "NEW unsigned review directory required")
    UNSIGNED.mkdir(parents=True, exist_ok=False)
    for name, raw in values.items(): inc.write_new(UNSIGNED / name, raw)
    inc.write_new(UNSIGNED / pack.handoff.MANIFEST, pack.runtime.canonical_bytes(after) + b"\n")
    marker = {"status": "UNSIGNED_DO_NOT_INSTALL_OR_UPLOAD", "content_sha256": actual["content_sha256"],
              "signing_key_read": False, "authorization_required": True}
    inc.write_new(UNSIGNED / "_UNSIGNED_DO_NOT_INSTALL_OR_UPLOAD.json", (json.dumps(marker) + "\n").encode())
    need(not (UNSIGNED / pack.handoff.SIGNATURE).exists(), "Unsigned preparation must not copy any signature")
    actual.update(status="UNSIGNED_REVIEW_READY_SIGNING_AUTHORIZATION_REQUIRED", unsigned_review=str(UNSIGNED),
                  signing_key_read=False)
    return actual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--report", type=Path, required=True)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--build", action="store_true")
    modes.add_argument("--prepare", action="store_true", help="Write only an unsigned review overlay; never read a key")
    parser.add_argument("--reviewed-plan", type=Path)
    parser.add_argument("--key", type=Path)
    args = parser.parse_args(); need(not args.report.exists(), "NEW report required")
    if args.build:
        need(args.reviewed_plan is not None, "Explicit reviewed plan required")
        result = build(args.reviewed_plan, args.source_revision, args.key)
    elif args.prepare: result = prepare_unsigned(args.source_revision)
    else: result, *_ = plan(args.source_revision)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    inc.write_new(args.report, (json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode("utf8"))
    print(json.dumps({key: result[key] for key in ("status", "release_sequence", "files", "content_sha256", "ready_for_upload")}))


if __name__ == "__main__": main()
