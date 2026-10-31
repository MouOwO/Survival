"""Prepare a thin 3101 release over verified3004; publication is separate.

Default: read-only plan. --prepare writes an unsigned, explicitly incomplete
external overlay. --build additionally requires a reviewed plan, confirmed
wall-fix approval and an existing external signing key. Never edits the base,
development runtime, canonical journal, account gate or live backend.
"""
from __future__ import annotations

from contextlib import contextmanager
from functools import lru_cache
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
sys.path.insert(0, str(ROOT / "tools"))
spec = importlib.util.spec_from_file_location("wall3101_previous", ROOT / "tools/monster_portrait_release_20261030/build_release.py")
previous = importlib.util.module_from_spec(spec)
spec.loader.exec_module(previous)
inc, pack, need = previous.inc, previous.pack, previous.need

ITEM, SEQUENCE, REVISION = "3824360109", 2026103101, "WS4-WALL-ATTACK-PERF-01"
BASE_SEQUENCE = 2026103004
BASE_CONTENT = "5cdb3ad487e7f70ad22ba37658a4a10c14d56ad96ed566a223b787d058f87913"
BASE_REPORT_SHA = "41727267f775e7fb9cd42826c9361b503322bc7f55042b62e6d351b73dcd260f"
BASE_DOWNLOAD_SHA = "762d84ae2092f0688a2d220fab4ad32145b1432bb79c75463233e07e9f75899c"
BASE = Path("D:/Survival_发布候选/20261030_ws4_unit_portraits_v05_view")
BASE_TRUSTED = Path("D:/Survival_发布候选/20261030_ws4_unit_portraits_v05_trusted_source")
BASE_VPK = Path("D:/Survival_工坊输出/20261030_ws4_unit_portraits_v05/3824360109.vpk")
BASE_REPORT = ROOT / "output/portrait_followup_publish_20261030/package_v05.json"
BASE_RECORD = ROOT / "publishing/workshop/unit_portraits_20261030_v05.json"
BASE_LISTING = ROOT / "output/portrait_followup_publish_20261030/listing.json"
JOURNAL = ROOT / "output/four_accounts_20261022/steam_upload_state.json"
PREFIX = "20261031_ws4_wall_perf_v01"
PENDING = Path("D:/Survival_发布候选") / (PREFIX + "_pending_wall_fix")
OVERLAY = Path("D:/Survival_发布候选") / (PREFIX + "_overlay")
TRUSTED = Path("D:/Survival_发布候选") / (PREFIX + "_trusted_source")
VIEW = Path("D:/Survival_发布候选") / (PREFIX + "_view")
OUTPUT = Path("D:/Survival_工坊输出") / PREFIX
REPORT = ROOT / "output/wall_attack_release_20261031"
CATALOG_WORK = Path("D:/Survival_发布候选") / (PREFIX + "_catalog_work")
CATALOG_REPORT = CATALOG_WORK / "catalog_protection_report.json"
CATALOG = "scripts/vscripts/config/generated/asset_catalog.lua"
CATALOG_BASE_SHA = "0c5746d05ec81dbe8cb49dd1145ec5d885acfa258f3a3ea24cc27f4c5554c36f"
CATALOG_TARGET_SHA = "f599a199d245fdf7c0b4b0f72f8d21142c447a2c453273cee44df9a4c3821539"
CATALOG_OUTPUT_SHA = "656b2aaf9aca65b85eac356b812155372eb9f5d8ca186e0eb078441dda507772"
BUNDLE = "scripts/vscripts/config/generated/archive_http_bundle.lua"
EXPECTED_BUNDLE = "d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488"
PORTRAIT_REVISION = "deadad5a3"
UI_REVISION = "753de9888"
NEW_SCENE = "maps/portraits/monster_1bc348e8932e1cfc065b_v1.vpk"
UI_NAMES = (
    "panorama/scripts/custom_game/combat_stats.vjs_c",
    "panorama/scripts/custom_game/daily_remaining_5d5c1152eb.vjs_c",
    "panorama/scripts/custom_game/monster_portrait_renderer.vjs_c",
    "panorama/scripts/custom_game/topnav_remaining_5d5c1152eb.vjs_c",
    "panorama/styles/custom_game/handoff_v1.vcss_c",
    "scripts/vscripts/core/performance_clock.lua",
    "scripts/vscripts/systems/grid_placement_system.lua",
    "scripts/vscripts/ui/grid_placement_router.lua",
)
SCENE_JS = "panorama/scripts/custom_game/monster_portrait_scenes.vjs_c"
PENDING_MARKER = "_PENDING_WALL_FIX_DO_NOT_PUBLISH.json"
AUXILIARY_INPUTS = (
    "tools/wall_attack_release_20261031/build_release.py",
    "tools/wall_attack_release_20261031/protected_catalog.py",
    "tools/wall_attack_release_20261031/publish.py",
    "tools/wall_attack_release_20261031/verify_download.py",
    "tools/steam_workshop_upload.py", "tools/stream_workshop_vpk.py",
    "tools/publish_test_release.py", "tools/build_runtime_release.py",
    "tools/protect_runtime_lua.py", "tools/arcade_cleanup_20261027/incremental_vpk.py",
    "tools/arcade_cleanup_20261027/verify_download.py", "tools/map_resources_20261028/build_map_resources.py",
    "tools/lua_protection_policy.json", "tools/release_security/protection_policy.json",
    "tools/release_security/trusted_public_key.pem",
)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def load(path):
    return pack.handoff.load_json(path)


def checks(raw):
    return {"bytes": len(raw), "md5": hashlib.md5(raw).hexdigest(), "sha256": sha(raw)}


@lru_cache(maxsize=None)
def revision(value):
    return subprocess.check_output(["git", "rev-parse", "--verify", value + "^{commit}"], cwd=ROOT, text=True).strip()


@lru_cache(maxsize=None)
def blob(commit, relative):
    need(pack.runtime.safe_relative(relative), "Unsafe committed input path")
    raw = subprocess.check_output(["git", "cat-file", "blob", revision(commit) + ":" + relative], cwd=ROOT)
    if raw.startswith(b"version https://git-lfs.github.com/spec/v1\n"):
        match = re.fullmatch(rb"version https://git-lfs.github.com/spec/v1\noid sha256:([0-9a-f]{64})\nsize ([0-9]+)\n", raw)
        need(match is not None, "Malformed LFS pointer")
        resolved = pack.protect_data.source_path(ROOT, relative).read_bytes()
        need(sha(resolved) == match[1].decode() and len(resolved) == int(match[2]), "Installed LFS bytes differ from fixed revision")
        return resolved
    return raw


@lru_cache(maxsize=1)
def scene_inventory():
    old = json.loads(blob("fc75b575f", "art/portraits/monsters/manifest.json"))
    new = json.loads(blob(PORTRAIT_REVISION, "art/portraits/monsters/manifest.json"))
    need(len(old["assets"]) == len(new["assets"]) == 197 and old["unique_scenes"] == new["unique_scenes"] == 188,
         "Exact197 identities/188 active scenes required")
    changed = {key for key in old["assets"] if old["assets"][key] != new["assets"].get(key)}
    need(changed == {"hero_permanent_hero_blademaster"}, "Unrelated portrait catalog change")
    a, b = [copy.deepcopy(value["assets"]["hero_permanent_hero_blademaster"]) for value in (old, new)]
    a.pop("map"); b.pop("map")
    need(a == b and "maps/" + new["assets"]["hero_permanent_hero_blademaster"]["map"] + ".vpk" == NEW_SCENE,
         "Blademaster scene delta differs")
    names = lambda value: {"maps/" + row["map"] + ".vpk" for row in value["assets"].values()}
    old_names, new_names = names(old), names(new)
    need(len(old_names) == len(new_names) == 188 and new_names - old_names == {NEW_SCENE}, "Unexpected scene map scope")
    return old_names, new_names


@contextmanager
def scene_maps(include_new=True):
    old, new = scene_inventory()
    prior = pack.runtime.SCENE_MAPS
    try:
        pack.runtime.SCENE_MAPS = prior | old | (new if include_new else set())
        yield
    finally:
        pack.runtime.SCENE_MAPS = prior


def baseline(full=False, require_current_journal=True):
    need(pack.runtime.digest(BASE_REPORT) == BASE_REPORT_SHA, "Immutable3004 package report changed")
    record = load(BASE_RECORD)
    need(record["release_sequence"] == BASE_SEQUENCE and record["content_sha256"] == BASE_CONTENT
         and record["status"] == "UPLOADED_AND_OFFICIAL_DOWNLOAD_FULLY_VERIFIED", "Verified3004 record required")
    receipt = ROOT / record["download_receipt"]
    need(pack.runtime.digest(receipt) == BASE_DOWNLOAD_SHA, "3004 official download receipt changed")
    old, document, _ = inc.metadata(BASE)
    with inc.trusted_source(BASE_TRUSTED), scene_maps(False):
        policy, public = pack.handoff.trusted_policy()
        signature = pack.verify_signed_snapshot(old, document, public,
            policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
        if full:
            _, checked, signed, _ = pack.authenticate(BASE)
            need(checked == old and signed == signature, "Full baseline authentication differs")
    need(signature["release_sequence"] == BASE_SEQUENCE and old["content_sha256"] == BASE_CONTENT
         and old["file_count"] == 6913, "Signed3004 identity differs")
    package = load(BASE_REPORT)
    need(package["package_files"] == record["package_files"] and len(package["package_files"]) == 5, "Base archive inventory differs")
    if full:
        need(pack.package_inventory(BASE_VPK) == package["package_files"], "Base VPK bytes changed")
        pack.verify_vpk(BASE_VPK, old)
    if require_current_journal:
        state = load(JOURNAL)
        need(state.get("uploaded") is True and state.get("workshop_id") == ITEM
             and state.get("release_sequence") == BASE_SEQUENCE and state.get("content_sha256") == BASE_CONTENT
             and state.get("visibility_requested") == 3, "Known successful3004 journal required; never clear pending")
        need(SEQUENCE > BASE_SEQUENCE and SEQUENCE > state["release_sequence"], "New sequence must increase")
    return old, package


def catalog_payload():
    report = load(CATALOG_REPORT)
    target = Path(report["output_path"])
    need(target.resolve() == (CATALOG_WORK / "protected" / CATALOG).resolve(), "Unexpected protected catalog output")
    need(report["status"] == "PASS_REQUIRES_NATIVE_SMOKE" and report["baseline_sha256"] == CATALOG_BASE_SHA
         and report["target_source_sha256"] == CATALOG_TARGET_SHA and report["source_hashes_unchanged"] is True
         and report["baseline_delta_verification"]["all_generated_values_exact"] is True
         and report["semantic_verification"]["all_generated_values_exact"] is True
         and report["semantic_verification"]["gameplay_rng_untouched_while_loading"] is True,
         "Catalog exact single-field/private-RNG protection proof required")
    raw = target.read_bytes()
    need(sha(raw) == report["output"]["sha256"] == CATALOG_OUTPUT_SHA
         and pack.runtime.digest(BASE / CATALOG) == CATALOG_BASE_SHA, "Protected catalog pin differs")
    return raw


def wall_inputs(approval):
    if approval is None:
        return {}, None
    value = load(approval)
    need(set(value) == {"source_revision", "paths", "reason", "fix_confirmed"}
         and value["fix_confirmed"] is True and isinstance(value["reason"], str) and value["reason"].strip(),
         "Explicit confirmed wall-fix approval required")
    paths = value["paths"]
    need(isinstance(paths, list) and 1 <= len(paths) <= 6 and len(set(paths)) == len(paths), "Nonempty narrow wall runtime path list required")
    for name in paths:
        need(re.fullmatch(r"scripts/vscripts/(?:systems|modifiers|ui)/[a-z0-9_/]+\.lua", name) is not None,
             "Wall approval cannot change config, authentication, payment, UI assets or arbitrary files")
        need(not re.search(r"(?:archive|commerce|payment|web_auth|native_cloud|http|profile|offline_logic|hosted_lobby)", name),
             "Wall approval includes protected business/admission authority")
        need(name not in UI_NAMES, "Wall approval cannot replace already-fixed performance inputs")
    commit = revision(value["source_revision"])
    return {name: blob(commit, name) for name in paths}, {**value, "source_revision": commit, "approval_path": str(approval.resolve()), "approval_sha256": pack.runtime.digest(approval)}


def payloads(approval=None):
    values = {name: blob(UI_REVISION, name) for name in UI_NAMES}
    values.update({name: blob(PORTRAIT_REVISION, name) for name in (NEW_SCENE, SCENE_JS)})
    values[CATALOG] = catalog_payload()
    extra, wall = wall_inputs(approval)
    values.update(extra)
    for name, raw in values.items():
        need(name == CATALOG or not name.startswith("scripts/vscripts/config/generated/"), "Only catalog protection may change")
        need(raw and not raw.startswith(b"version https://git-lfs.github.com/spec"), "Missing real runtime bytes")
    return values, wall


def projected(old, values):
    rows = {row["path"]: row for row in old["files"]}
    changed = {name: raw for name, raw in values.items() if name not in rows or checks(raw)["sha256"] != rows[name]["sha256"]}
    for name, raw in changed.items():
        rows[name] = {"path": name, **checks(raw)}
    result = copy.deepcopy(old)
    result.update(files=[rows[name] for name in sorted(rows)], file_count=len(rows), bytes=sum(row["bytes"] for row in rows.values()))
    result["content_sha256"] = sha(pack.runtime.manifest_payload(result))
    pack.runtime.validate_manifest(result)
    return result, changed


def make_plan(approval=None):
    old, base_package = baseline()
    values, wall = payloads(approval)
    after, changed = projected(old, values)
    if wall:
        need(set(wall["paths"]) <= set(changed), "Every approved wall path must actually differ from3004")
    policy = load(ROOT / "tools/lua_protection_policy.json")
    selected = {row["path"] for row in previous.base.protection.selected_files([row["path"] for row in after["files"]], policy)}
    need(len(selected) == 184 and selected.intersection(changed) == {CATALOG}, "Exactly183 preserved plus1 catalog protection required")
    review = {name: checks((BASE_TRUSTED / name).read_bytes()) for name in sorted(inc.all_files(BASE_TRUSTED))}
    need(len(review) == 16 and not set(review).intersection(changed), "Original16 gate/auth reviews must remain byte-identical")
    need(BUNDLE not in changed and EXPECTED_BUNDLE.encode() in blob("fc75b575f", BUNDLE), "d573 backend must remain unchanged")
    tree, groups, rewritten, moves = previous.base.parent.rotation_plan(inc.read_entries(BASE_VPK), old, after, set(changed))
    sizes = [sum(item["row"]["bytes"] for item in group) for group in groups]
    disk = inc.capacity(VIEW, OUTPUT, sum(map(len, changed.values())) * 2 + 2 ** 22,
                        sum(sizes[index] for index in rewritten), pack.HEADER.size + len(tree) + 48, 0)
    result = {"schema": 1, "status": "READY_FOR_REVIEWED_SIGNED_BUILD" if wall else "PENDING_WALL_FIX_DO_NOT_PUBLISH",
        "pending_wall_fix": wall is None, "ready_for_signed_build": wall is not None, "ready_for_upload": False,
        "workshop_id": ITEM, "release_sequence": SEQUENCE, "revision": REVISION,
        "baseline_release_sequence": BASE_SEQUENCE, "baseline_content_sha256": BASE_CONTENT,
        "baseline_report_sha256": BASE_REPORT_SHA, "baseline_download_sha256": BASE_DOWNLOAD_SHA,
        "canonical_journal_sha256": pack.runtime.digest(JOURNAL),
        "source_revisions": {"portrait": revision(PORTRAIT_REVISION), "performance_daily_query": revision(UI_REVISION)},
        "auxiliary_input_pins": {name: checks((ROOT / name).read_bytes()) for name in AUXILIARY_INPUTS},
        "wall_approval": wall, "target_pins": {name: checks(raw) for name, raw in sorted(changed.items())},
        "changed_runtime_paths": sorted(changed), "removed_runtime_paths": [], "files": after["file_count"],
        "content_sha256": after["content_sha256"], "preview_only_without_wall_fix": wall is None,
        "protected_modules_preserved": 183, "protected_modules_rebuilt": 1, "protected_rebuilt_paths": [CATALOG],
        "catalog_protection_report_sha256": pack.runtime.digest(CATALOG_REPORT), "trusted_review_pins": review,
        "account_gates_payment_backend_preserved": True, "archive_bundle_hash": EXPECTED_BUNDLE,
        "active_portrait_scenes": 188, "packaged_portrait_scenes": 189, "baseline_retired_scene_preserved_unused": True,
        "rebuilt_archives": sorted(rewritten), "archive_migrations": moves, "disk_preflight": disk,
        "candidate": str(VIEW), "trusted_source": str(TRUSTED), "pending_directory": str(PENDING),
        "output": str(OUTPUT / (ITEM + ".vpk")), "container_bytes": after["bytes"] + pack.HEADER.size + len(tree) + 48,
        "baseline_package_files": base_package["package_files"], "workshop_upload_performed": False,
        "server_changed": False, "native_test": "NOT_RUN"}
    return result, old, after, changed, tree, groups


def same_plan(a, b):
    def identity(value):
        result = copy.deepcopy(value)
        for item in result.get("disk_preflight", []):
            item.pop("free_bytes", None)
        return result
    return identity(a) == identity(b)


def prepare_pending(plan, values):
    need(plan["pending_wall_fix"] is True, "Pending preparation is not a signed build")
    inc.external(PENDING, exists=False)
    need(not PENDING.exists(), "Pending directory must be NEW; never overwrite")
    PENDING.mkdir(parents=True, exist_ok=False)
    for name, raw in values.items():
        inc.write_new(PENDING / name, raw)
    inc.write_new(PENDING / PENDING_MARKER, pack.runtime.canonical_bytes(plan) + b"\n")
    need(not (PENDING / pack.handoff.MANIFEST).exists() and not (PENDING / pack.handoff.SIGNATURE).exists(),
         "Pending overlay must never appear signed or publishable")


def build_signed(reviewed, key, approval):
    need(key is not None, "Existing external signing key required")
    actual, old, after, values, tree, groups = make_plan(approval)
    need(actual["ready_for_signed_build"] and not actual["pending_wall_fix"], "Wall fix still pending; refusing key use/sign/build")
    need(same_plan(load(reviewed), actual), "Reviewed plan changed")
    key = pack.handoff.regular_path(pack.protect_data.external(key, source=BASE))
    for target in (OVERLAY, TRUSTED, VIEW, OUTPUT):
        inc.external(target, exists=False)
        need(not target.exists(), "Every final artifact directory must be NEW")
        need(not pack.runtime.within(key, target) and not pack.runtime.within(target, key.parent), "Key/output overlap")
    inc.disjoint([BASE, BASE_TRUSTED, BASE_VPK.parent, OVERLAY, TRUSTED, VIEW, OUTPUT])
    baseline(full=True)
    before_inventory = pack.package_inventory(BASE_VPK)
    OVERLAY.mkdir(parents=True, exist_ok=False); TRUSTED.mkdir(parents=True, exist_ok=False)
    for name, raw in values.items(): inc.write_new(OVERLAY / name, raw)
    for name, pin in actual["trusted_review_pins"].items():
        raw = (BASE_TRUSTED / name).read_bytes(); need(checks(raw) == pin, "Trusted review drift")
        inc.write_new(TRUSTED / name, raw)
    inc.write_new(OVERLAY / pack.handoff.MANIFEST, pack.runtime.canonical_bytes(after) + b"\n")
    pack.protect_data.sign_manifest(OVERLAY / pack.handoff.MANIFEST, key, OVERLAY / pack.handoff.SIGNATURE, SEQUENCE)
    _, _, metadata = inc.metadata(OVERLAY)
    sources, changed = inc.validate_merged(BASE, OVERLAY, old, after, TRUSTED)
    need(changed == set(values), "Unexpected merged scope")
    inc.materialize(VIEW, sources, changed, after, metadata)
    with scene_maps(), inc.trusted_source(TRUSTED):
        _, checked, signature, _ = pack.authenticate(VIEW)
    need(checked == after and signature["release_sequence"] == SEQUENCE, "Final signed view differs")
    with scene_maps():
        verification, files = inc.build_volumes(VIEW, OUTPUT, BASE_VPK, tree, groups, set(actual["rebuilt_archives"]), after, "hardlink")
    need(pack.package_inventory(BASE_VPK) == before_inventory and pack.runtime.verify(BASE, old)["ok"], "Base changed during build")
    final, *_ = make_plan(approval)
    need(same_plan(actual, final), "Inputs/journal changed during build")
    actual.update(status="BUILT_SIGNED_3101_PENDING_NATIVE_WALL_ACCEPTANCE", dry_run=False, signature_valid=True,
        full_runtime_validator_passed=True, payload_changed=False, package_files=files, vpk_sha256=files[0]["sha256"],
        verification=verification, native_test="NOT_RUN", ready_for_upload=False)
    return actual


def validated_package(expected_report_sha256, full=False):
    """Validate frozen3101 even after its successful journal replaces3004."""
    report_path = REPORT / "package.json"
    need(re.fullmatch(r"[0-9a-f]{64}", expected_report_sha256 or "") is not None
         and pack.runtime.digest(report_path) == expected_report_sha256, "Explicit reviewed completed-report SHA256 required")
    report = load(report_path)
    need(report.get("pending_wall_fix") is False and report.get("release_sequence") == SEQUENCE
         and report.get("signature_valid") is True and report.get("full_runtime_validator_passed") is True
         and report.get("dry_run") is False and report.get("payload_changed") is False
         and report.get("workshop_upload_performed") is False, "Completed signed confirmed-wall package required")
    need(set(report["auxiliary_input_pins"]) == set(AUXILIARY_INPUTS)
         and all(checks((ROOT / name).read_bytes()) == report["auxiliary_input_pins"][name] for name in AUXILIARY_INPUTS),
         "Reviewed builder/publisher/protocol/policy inputs changed")
    old, _ = baseline(require_current_journal=False)
    approval = Path(report["wall_approval"]["approval_path"])
    values, wall = payloads(approval)
    need(wall == report["wall_approval"], "Wall approval drift")
    expected, changed = projected(old, values)
    need({name: checks(raw) for name, raw in sorted(changed.items())} == report["target_pins"]
         and sorted(changed) == report["changed_runtime_paths"], "Package scope differs from fixed committed inputs")
    manifest, document, _ = inc.metadata(VIEW)
    need(manifest == expected and manifest["content_sha256"] == report["content_sha256"]
         and manifest["file_count"] == report["files"], "Final manifest differs from thin3101 scope")
    with inc.trusted_source(TRUSTED), scene_maps():
        policy, public = pack.handoff.trusted_policy()
        signature = pack.verify_signed_snapshot(manifest, document, public,
            policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
        if full:
            _, checked, actual, _ = pack.authenticate(VIEW)
            need(checked == manifest and actual == signature, "Full3101 identity mismatch")
    need(signature["release_sequence"] == SEQUENCE, "Signed3101 sequence required")
    for name, pin in report["trusted_review_pins"].items():
        need(checks((TRUSTED / name).read_bytes()) == pin == checks((BASE_TRUSTED / name).read_bytes()), "Frozen16 gate reviews changed")
    if full:
        need(pack.package_inventory(OUTPUT / (ITEM + ".vpk")) == report["package_files"], "3101 VPK bytes differ")
        pack.verify_vpk(OUTPUT / (ITEM + ".vpk"), manifest)
    return report, manifest, signature


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--prepare", action="store_true")
    modes.add_argument("--build", action="store_true")
    parser.add_argument("--wall-approval", type=Path)
    parser.add_argument("--reviewed-plan", type=Path)
    parser.add_argument("--key", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    need(not args.report.exists(), "NEW report required")
    if args.build:
        need(args.reviewed_plan is not None, "Build requires exact reviewed plan")
        result = build_signed(args.reviewed_plan, args.key, args.wall_approval)
    else:
        need(args.key is None and args.reviewed_plan is None, "No private key/plan on read-only/pending mode")
        result, _, _, values, _, _ = make_plan(args.wall_approval)
        if args.prepare: prepare_pending(result, values)
    inc.write_new(args.report, json.dumps(result, ensure_ascii=False, indent=2).encode("utf8") + b"\n")
    print(json.dumps({name: result[name] for name in ("status", "pending_wall_fix", "release_sequence", "files", "changed_runtime_paths", "content_sha256", "ready_for_upload")}))
    return 0


if __name__ == "__main__":
    try: raise SystemExit(main())
    except Exception as error:
        print(json.dumps({"status": "BLOCKED_DO_NOT_UPLOAD", "error": str(error), "workshop_upload_performed": False}))
        raise SystemExit(1)
