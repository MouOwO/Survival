"""Read-only plan, or explicitly sign, six native-shop UI replacements.

Copy only the authenticated SHOP01v3 signed runtime inventory, replacing the
six reviewed compiled UI resources. Preserve the 173-offer catalog, all Lua,
maps, protected modules and production multiplayer/account/payment policies.
No key is read and no directory is created unless --build is supplied. This
tool never runs Dota, installs, uploads or calls account/payment services.
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
import build_arcade_two_player_candidate as frozen
import build_public_shop_catalog as public_shop

web, pack = frozen.web, frozen.pack
ROOT, CONTENT = frozen.ROOT, frozen.CONTENT
BASE = Path("D:/Survival_发布候选/20261026_ws4_shop_v03")
BASE_TRUSTED = BASE.with_name(BASE.name + "_trusted_source")
BASE_SHA = "cf15590f4c0a93977a70a2357c3c94f5685040a1dbeea44d1cd4e6b00503b109"
BASE_FILES, BASE_SEQUENCE = 6637, 2026102603
REVISION, RELEASE_SEQUENCE = "WS4-SHOP-02", 2026102604
DESTINATION = Path("D:/Survival_发布候选/20261026_ws4_native_shop_v04")
TRUSTED_DESTINATION = DESTINATION.with_name(DESTINATION.name + "_trusted_source")
PACKAGE_OUTPUT = Path("D:/Survival_工坊输出/20261026_ws4_native_shop_v04")
COMPILE_REPORT = ROOT / "output/native_shop_qr_20261026/compile.json"
COMPILE_REPORT_SHA = "b8a62765467df303fb2a0ee84665fa78dc7ca418d34bf8dc1e58aa37649e32ce"
COMPILE_LOG_DIRECTORY = ROOT / "output/native_shop_qr_20261026/compile_678a8e5974bc4b4391d0d3488d1cff78"
CATALOG_SHA = "0c227adb8b1d919c33b10b5a3eeed7f53828eb41099f117542f7874d41ce18b9"
# source-relative name: (source SHA256, compiled-relative name, SHA256, bytes)
PINS = {
    'scripts/custom_game/commerce_remaining_5d5c1152eb.js': (
        '223d4a59a0caa4d4cebed59cffba5b34777f11b6b6dbbc3e905f818c781ba12f', 'panorama/scripts/custom_game/commerce_remaining_5d5c1152eb.vjs_c',
        '1d673048e120a423debd7e014a8f82399f1012f8aed53cd85be40c6521b61052', 32452),
    'scripts/custom_game/black_lion_market.js': (
        '269067f18bf48eea65f026d0a0da8acbb34a4728e93ec38ce33a64ab5d7e38b2', 'panorama/scripts/custom_game/black_lion_market.vjs_c',
        'e77971a40a59e0fb0afc7cec1452e92734885fbba4a53cbc13a3c7b3290ec614', 19279),
    'scripts/custom_game/common/commerce_components.js': (
        '1125db75245952d815d2dedfd7d59630820a0ac0507da74eabb8c435d3838815', 'panorama/scripts/custom_game/common/commerce_components.vjs_c',
        '748b98200909c87a13225f3ad8b19f8e155285c77ca1413e6d9861032bd40295', 24479),
    'scripts/custom_game/arcade_multiplayer_test.js': (
        '0faa39a383add10c32a37cc4bfcdae8218b0015d79ef7980ded9593953b8f5a5', 'panorama/scripts/custom_game/arcade_multiplayer_test.vjs_c',
        '362b007d4fbb762462e044c25a6ed81fb542e93072e156af6b3c1953e23387c4', 15461),
    'styles/custom_game/arcade_multiplayer_test.css': (
        '3c272fa2387a1cf0b442704aaaa8ce9620857a22f852824b9b542029288edebc', 'panorama/styles/custom_game/arcade_multiplayer_test.vcss_c',
        '1b8d549d454f18671385d06bd324298935f9d769875227005f5474054d4d9ff5', 3712),
    'layout/custom_game/arcade_multiplayer_test.xml': (
        'a2053fb8b9c3d3d7f9e3b6427f55ae26e29776c2829422e2fae660741ccf0024', 'panorama/layout/custom_game/arcade_multiplayer_test.vxml_c',
        '34bc11a33facd92696f7aa00a131e5cb7ec588097de42933ce9c8c6bd2ece6cd', 2098),
}
CATALOG_SOURCE = "scripts/custom_game/arcade_shop_catalog.js"
CATALOG_PIN = (
    "331380f1400cffbc149b348e009697ec65e0dd8ef691ca57b5cd3f42335e2b62",
    "panorama/scripts/custom_game/arcade_shop_catalog.vjs_c",
    "2e026442d43c9a8c8d02e1f0d008afea5f2a2934834202bd02cba4c1bd60caa4", 164454)
ADDED = frozenset()
MODIFIED = frozenset((
    "panorama/scripts/custom_game/commerce_remaining_5d5c1152eb.vjs_c",
    "panorama/scripts/custom_game/black_lion_market.vjs_c",
    "panorama/scripts/custom_game/common/commerce_components.vjs_c",
    "panorama/scripts/custom_game/arcade_multiplayer_test.vjs_c",
    "panorama/styles/custom_game/arcade_multiplayer_test.vcss_c",
    "panorama/layout/custom_game/arcade_multiplayer_test.vxml_c"))
ALLOWLIST, EXPECTED_FILES = MODIFIED, BASE_FILES
LUA_POLICY_SHA, POLICY_MODULE = frozen.LUA_POLICY_SHA, frozen.POLICY_MODULE
SPACE_RESERVE = 256 * 1024 * 1024


def require_review_pins():
    values = [BASE_SHA, COMPILE_REPORT_SHA, CATALOG_SHA]
    web.need(set(row[1] for row in PINS.values()) == ALLOWLIST and len(PINS) == 6,
             "SHOP02 review scope must contain exactly six UI resources")
    for source, row in (*PINS.items(), (CATALOG_SOURCE, CATALOG_PIN)):
        web.need(isinstance(source, str) and source.startswith(("scripts/", "styles/", "layout/"))
                 and isinstance(row, tuple) and len(row) == 4
                 and type(row[3]) is int and 28 <= row[3] <= 4 * 1024 * 1024,
                 "SHOP02 source/compiled review pins are not finalized")
        values.extend((row[0], row[2]))
    web.need(all(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) for value in values),
             "SHOP02 source/compiled review pins are not finalized")


def read_input(path, snapshots):
    path = pack.protect_data.source_path(path.parent, path.name)
    raw = path.read_bytes()
    snapshots[path] = raw
    return raw


def authenticate_base():
    pinned, _ = pack.handoff.trusted_policy(pack.handoff.POLICY)
    with web.trusted_root(BASE_TRUSTED):
        base, manifest, signature, metadata = pack.authenticate(BASE)
    web.need(manifest["content_sha256"] == BASE_SHA and manifest["file_count"] == BASE_FILES
             and signature["release_sequence"] == BASE_SEQUENCE
             and signature["key_id"] == pinned["integrity"]["trusted_key_id"],
             "Immutable signed SHOP01v3 identity differs")
    web.need(RELEASE_SEQUENCE > BASE_SEQUENCE and RELEASE_SEQUENCE >= pinned["integrity"]["minimum_release_sequence"],
             "SHOP02 sequence is below the trusted release floor")
    pack.runtime.require_production(base)
    pack.handoff.configured_ids(base)
    return base, manifest, signature, metadata


def protected_paths(manifest):
    paths = frozen.protected_paths(manifest)
    web.need(len(paths) == len(set(paths)) == 180 and not set(paths) & ALLOWLIST,
             "SHOP02 protected 180-module inventory differs")
    return paths


def capture_inputs():
    snapshots, patches = {}, {}
    raw = read_input(COMPILE_REPORT, snapshots)
    web.need(web.sha(raw) == COMPILE_REPORT_SHA, "Reviewed SHOP02 compile receipt changed")
    receipt = pack.handoff.decode_json(raw)
    rows = receipt.get("records")
    web.need(receipt.get("ok") is True and receipt.get("kind") == "WS4_SHOP_NATIVE_COMPILE"
             and receipt.get("original_102_bytes_preserved") is True
             and isinstance(rows, list) and len(rows) == 6 and all(isinstance(row, dict) for row in rows),
             "SHOP02 compile receipt status or six-resource scope differs")
    indexed = {row.get("source"): row for row in rows}
    web.need(len(indexed) == 6 and set(indexed) == {"panorama/src/" + name for name in PINS},
             "SHOP02 compile receipt contains duplicate or unknown sources")
    for source, (source_sha, compiled, compiled_sha, size) in PINS.items():
        row = indexed["panorama/src/" + source]
        log = COMPILE_LOG_DIRECTORY / (Path(source).name + ".log")
        web.need(row.get("source_sha256") == source_sha and row.get("compiled") == compiled
                 and row.get("compiled_sha256") == compiled_sha and row.get("compiled_bytes") == size
                 and Path(row.get("log", "")) == log, "SHOP02 compile source/runtime association differs")
        game = read_input(ROOT / "panorama/src" / source, snapshots)
        content = read_input(CONTENT / "panorama" / source, snapshots)
        web.need(game == content and web.sha(game) == source_sha, "Reviewed SHOP02 game/content source differs")
        runtime = read_input(ROOT / compiled, snapshots)
        web.need(len(runtime) == size and web.sha(runtime) == compiled_sha, "Reviewed SHOP02 compiled resource differs")
        data = frozen.compiled_data(runtime)
        if source.endswith(".js"):
            web.need(data == game, "SHOP02 compiled JS DATA differs from reviewed source")
        log_raw = read_input(log, snapshots)
        web.need(log_raw.count(b"1 compiled, 0 failed, 0 skipped") == 1,
                 "SHOP02 native compile success log differs")
        patches[compiled] = runtime
    # The catalog was compiled in SHOP01v3; it is an immutable verified input,
    # never an overlay resource and never falsely included in this compile receipt.
    source_sha, compiled_name, compiled_sha, size = CATALOG_PIN
    catalog_source = read_input(ROOT / "panorama/src" / CATALOG_SOURCE, snapshots)
    catalog_content = read_input(CONTENT / "panorama" / CATALOG_SOURCE, snapshots)
    catalog_runtime = read_input(ROOT / compiled_name, snapshots)
    web.need(catalog_source == catalog_content and web.sha(catalog_source) == source_sha
             and len(catalog_runtime) == size and web.sha(catalog_runtime) == compiled_sha
             and frozen.compiled_data(catalog_runtime) == catalog_source,
             "SHOP02 immutable catalog source/runtime differs")
    data = public_shop.catalog()
    web.need(data["catalog_sha256"] == CATALOG_SHA and data["checkout_enabled"] is False
             and len(data["products"]) == 173
             and public_shop.javascript(data, "panorama") == snapshots[ROOT / "panorama/src" / CATALOG_SOURCE],
             "SHOP02 formal catalog differs from the reviewed generated resource")
    # Capture compiler code and every input CSV as review inputs too. They are
    # never copied to the runtime and must remain unchanged through signing.
    compiled = public_shop.build(ROOT)
    for name in compiled["reference_hashes"]:
        read_input(ROOT / "data/csv" / name, snapshots)
    for category, names in (("商城支付系统", compiled["tables"]), ("商城兑换系统", compiled["commerce_tables"])):
        for name in names:
            path = ROOT / "data/csv" / category / (name + ".csv")
            if path.is_file():
                read_input(path, snapshots)
    for name in ("tools/workshop_test/build_public_shop_catalog.py", "server/payment_backend/csv_catalog.py",
                 "server/payment_backend/commerce_bundles.py", "server/payment_backend/ucoin_catalog.py"):
        read_input(ROOT / name, snapshots)
    web.need(set(patches) == ALLOWLIST, "SHOP02 overlay scope differs")
    return snapshots, patches


def trust_names():
    return frozen.trust_names()


def trust_inputs(base):
    snapshots = {}
    for name in trust_names():
        raw = read_input(BASE_TRUSTED / name, snapshots)
        if name not in web.POLICY_FILES:
            web.need(read_input(base / name, snapshots) == raw, "Frozen SHOP01v3 trusted gate differs from signed runtime")
    for name in (*web.POLICY_FILES, "tools/lua_protection_policy.json"):
        read_input(ROOT / name, snapshots)
    return snapshots


def require_review_unchanged(snapshots, head):
    for path, raw in snapshots.items():
        web.need(pack.protect_data.source_path(path.parent, path.name).read_bytes() == raw,
                 "Reviewed SHOP02 input changed during build")
    web.need(web.git("rev-parse", "HEAD", root=ROOT).decode("ascii").strip() == head,
             "Reviewed HEAD changed during SHOP02 build")


def projected_manifest(baseline, patches):
    pack.runtime.validate_manifest(baseline)
    web.need(set(patches) == ALLOWLIST, "SHOP02 projection overlay scope differs")
    rows = {row["path"]: dict(row) for row in baseline["files"]}
    web.need(ALLOWLIST <= rows.keys(), "SHOP02 cannot add resources absent from the frozen inventory")
    for name, raw in patches.items():
        rows[name] = dict(path=name, bytes=len(raw), sha256=web.sha(raw),
                          md5=hashlib.md5(raw, usedforsecurity=False).hexdigest())
    result = {name: baseline[name] for name in ("schema", "kind", "hash_algorithms")}
    result.update(files=[rows[name] for name in sorted(rows)], file_count=len(rows),
                  bytes=sum(row["bytes"] for row in rows.values()))
    result["content_sha256"] = web.sha(pack.runtime.manifest_payload(result))
    return result


def audit_changes(baseline, candidate, patches, protected):
    pack.runtime.validate_manifest(baseline)
    pack.runtime.validate_manifest(candidate)
    before, after = ({row["path"]: row for row in document["files"]} for document in (baseline, candidate))
    web.need(not before.keys() - after.keys() and after.keys() - before.keys() == ADDED,
             "SHOP02 runtime additions/removals differ from the exact allowlist")
    web.need(baseline["file_count"] == len(before) == BASE_FILES
             and candidate["file_count"] == len(after) == EXPECTED_FILES,
             "SHOP02 must preserve exactly 6637 existing files")
    web.need(set(patches) == ALLOWLIST
             and {name for name in before.keys() & after.keys() if before[name] != after[name]} == MODIFIED,
             "SHOP02 runtime modifications differ from the exact six-resource allowlist")
    web.need(len(protected) == len(set(protected)) == 180 and set(protected) == set(protected_paths(baseline))
             and not set(protected) & ALLOWLIST and all(before[name] == after[name] for name in protected),
             "SHOP02 protected 180-module bytes changed")
    for name, raw in patches.items():
        pin = next(row for row in PINS.values() if row[1] == name)
        web.need(after[name]["sha256"] == web.sha(raw) == pin[2] and after[name]["bytes"] == len(raw) == pin[3],
                 "SHOP02 reviewed patch bytes changed during staging")
    return [dict(path=name, before=before.get(name), after=after[name]) for name in sorted(ALLOWLIST)]


def stage_runtime(base, destination, baseline, patches):
    pack.runtime.validate_manifest(baseline)
    web.need(set(patches) == ALLOWLIST, "SHOP02 staging overlay scope differs")
    destination.mkdir(parents=True, exist_ok=False)
    for row in baseline["files"]:
        target = destination / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(pack.protect_data.source_path(base, row["path"]), target)
    for name, raw in patches.items():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)


def trusted_snapshot(destination):
    destination.mkdir(parents=True, exist_ok=False)
    for name in trust_names():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        pack.protect_data.write_new(target, pack.protect_data.source_path(BASE_TRUSTED, name).read_bytes())


def require_projection(manifest, projected):
    """Compare every signed field while retaining runtime-local diagnostics."""
    pack.runtime.validate_manifest(manifest)
    pack.runtime.validate_manifest(projected)
    web.need(pack.runtime.manifest_payload(manifest) == pack.runtime.manifest_payload(projected)
             and manifest["content_sha256"] == projected["content_sha256"],
             "Staged SHOP02 differs from the read-only projection")


def require_space(destination, projected, package_output):
    # The fixed output directories are on the same volume. Reserve a complete
    # additional payload if packaging is requested; staging uses no hardlinks.
    copies = 1 + (1 if package_output is not None else 0)
    required = projected["bytes"] * copies + SPACE_RESERVE
    parent = destination.parent
    web.need(parent.is_dir() and shutil.disk_usage(parent).free >= required,
             "Insufficient free space for SHOP02 staging/optional package and reserve")


def build(args):
    web.need(args.sequence == RELEASE_SEQUENCE, "SHOP02 requires fixed sequence 2026102604")
    require_review_pins()
    if args.build:
        web.need(args.destination == DESTINATION and args.trusted_source == TRUSTED_DESTINATION,
                 "SHOP02 requires its fixed new candidate/trusted directories")
        web.need(args.package_output is None or args.package_output == PACKAGE_OUTPUT,
                 "SHOP02 package output differs from fixed directory")
        web.need(args.signing_key is not None, "--build requires an external --signing-key")
    base, baseline, signature, metadata = authenticate_base()
    protected = protected_paths(baseline)
    head = web.git("rev-parse", "HEAD", root=ROOT).decode("ascii").strip()
    snapshots, patches = capture_inputs()
    snapshots.update(trust_inputs(base))
    projected = projected_manifest(baseline, patches)
    changes = audit_changes(baseline, projected, patches, protected)
    result = dict(ok=True, status="READ_ONLY_PLAN", revision=REVISION, release_sequence=RELEASE_SEQUENCE,
                  base_content_sha256=BASE_SHA, base_files=BASE_FILES, base_signature_sequence=BASE_SEQUENCE,
                  expected_files=EXPECTED_FILES, projected_content_sha256=projected["content_sha256"],
                  reviewed_head=head, compile_receipt_sha256=COMPILE_REPORT_SHA, catalog_sha256=CATALOG_SHA,
                  allowed_changes=sorted(MODIFIED), allowed_additions=sorted(ADDED), allowed_removals=[], changed=changes,
                  patches={name: web.sha(raw) for name, raw in patches.items()},
                  protected_modules_preserved=180, protected_modules_rebuilt=0,
                  all_other_base_files_preserved=True, lua_and_maps_unchanged=True, trusted_sources_unchanged=True,
                  full_catalog_offers=173, cash_offers=48, wallet_offers=125,
                  default_map="template_map", declared_max_players=4, session_only=True,
                  cloud_archive_enabled=False, real_money_payments=False, four_account_only=True,
                  online_cheats_allowed=False, private_key_copied=False, workshop_upload_performed=False,
                  alias_install_performed=False, game_started=False, native_shop_acceptance="NOT_RUN",
                  resumed_unsigned_stage=False)
    require_review_unchanged(snapshots, head)
    if not args.build:
        return result
    destination, trusted, package_output, key = web.output_paths(args, base)
    require_space(destination, projected, package_output)
    stage_runtime(base, destination, baseline, patches)
    manifest = pack.runtime.manifest(destination)
    changes = audit_changes(baseline, manifest, patches, protected)
    require_projection(manifest, projected)
    pack.runtime.require_production(destination)
    pack.handoff.require_single_map(destination)
    web.need(pack.handoff.configured_ids(destination) == pack.handoff.configured_ids(base),
             "Frozen four-account list changed")
    frozen.previous.require_base_unchanged(base, baseline, metadata)
    require_review_unchanged(snapshots, head)
    trusted_snapshot(trusted)
    pack.protect_data.write_new(destination / pack.handoff.MANIFEST, pack.runtime.canonical_bytes(manifest) + b"\n")
    pack.protect_data.sign_manifest(destination / pack.handoff.MANIFEST, key,
                                    destination / pack.handoff.SIGNATURE, RELEASE_SEQUENCE)
    with web.trusted_root(trusted):
        _, authenticated, signed, _ = pack.authenticate(destination)
        web.need(authenticated == manifest and signed["key_id"] == signature["key_id"]
                 and signed["release_sequence"] == RELEASE_SEQUENCE and signed["signature_valid"] is True,
                 "Signed SHOP02 identity/key/sequence differs")
        packaged = None
        if package_output is not None:
            package_output.mkdir(parents=True, exist_ok=False)
            packaged = pack.package(destination, package_output, "3824360109", build=True)
    frozen.previous.require_base_unchanged(base, baseline, metadata)
    require_review_unchanged(snapshots, head)
    result.update(status="SIGNED_SHOP02_REQUIRES_NATIVE_TEST", content_sha256=manifest["content_sha256"],
                  changed=changes, signature_valid=True, destination=str(destination),
                  trusted_source=str(trusted), packaged=packaged)
    pack.protect_data.write_new(destination / "_arcade_shop_provenance.json", pack.runtime.canonical_bytes(result) + b"\n")
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
    except (OSError, ValueError, KeyError, TypeError, struct.error, subprocess.SubprocessError) as error:
        print(json.dumps(dict(ok=False, error="native_shop_candidate_build_failed", detail=str(error)[:300])))
        return 2
    print(json.dumps(result, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
