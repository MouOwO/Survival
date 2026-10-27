"""Plan, or explicitly sign, the two fixed thin WS4 refresh overlays.

Every unchanged runtime byte comes from signed SHOP02. No full candidate copy,
hardlink, VPK, installation, upload, network request or credential is created.
Default operation reads no private key and creates no output directory.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/arcade_payment_link_20261027"))
import build_helper_candidate as helper

web, pack, frozen = helper.web, helper.pack, helper.frozen
CONTENT = helper.CONTENT
BASE, BASE_TRUSTED = helper.BASE, helper.BASE_TRUSTED
BASE_SHA, BASE_SEQUENCE, BASE_FILES = helper.BASE_SHA, helper.BASE_SEQUENCE, helper.BASE_FILES
HELPER = helper.DESTINATION
HELPER_TRUSTED = helper.TRUSTED_DESTINATION
HELPER_SHA = "b854dc178d76dce6231350b7bdf833178a1d2460da3a63e00f0140e5045fdf4d"
MAIN, POLICY = helper.MAIN, helper.CASH_POLICY
SERVICE = "scripts/vscripts/systems/native_setup_auto_start.lua"
ENVIRONMENT = "scripts/vscripts/systems/valley_environment_service.lua"
MAIN_OUTPUT_SHA = "15c273c95e778bd1dd803583846458f472de34daece1baed41be11d31bce0e40"
POLICY_SHA = "6da29c9e100c9bb7c591d7a44b7a333dacad2a7895b98fdf4d1c1415e8afe1c2"
SERVICE_SHA = "f47fb858b108d88460273112f61559b55784826f882b4ad248cd4399018a1c22"
ENVIRONMENT_SHA = "2c242f2348e3394910bc4e7a6ad56ca694b6fbbe3cbd012b613fcda00e1361e9"
COMPILE_REPORT = ROOT / "output/arcade_cleanup_20261027/compile_v02.json"
# Original eleven native records plus the officially recompiled wallet only.
COMPILE_REPORT_SHA = "bf0f525a44cc271e42b9660e66515fbe7f73617f936cf1ec15d0d4ed33978774"
COMPILE_LOG_DIRECTORY = ROOT / "output/arcade_cleanup_20261027/compile_b168fff8400a4956bf8eec7be7a08ce1"
COMPILE_LOG_OVERRIDES = {
    "scripts/custom_game/commerce_wallet.js": ROOT / "output/arcade_cleanup_20261027/compile_wallet_v02/commerce_wallet.js.log",
}
SOURCES = frozenset((
    "scripts/custom_game/commerce_wallet.js", "scripts/custom_game/common/purple_shell.js",
    "scripts/custom_game/topnav_remaining_5d5c1152eb.js", "styles/custom_game/commerce_result.css",
    "styles/custom_game/menus_v10_commerce.css", "layout/custom_game/payment_test.xml",
    "scripts/custom_game/native_team_setup.js", "layout/custom_game/native_team_setup.xml",
    "scripts/custom_game/startup_loading.js", "styles/custom_game/startup_loading.css",
    "layout/custom_game/startup_team_setup_loading.xml", "layout/custom_game/arcade_multiplayer_test.xml",
))
COMPILE_SKIPPED = {"styles/custom_game/menus_v10_commerce.css": 2,
                   "styles/custom_game/startup_loading.css": 1,
                   "layout/custom_game/startup_team_setup_loading.xml": 4}
ART = ROOT / "art/effects/rich_portal"
ART_MANIFEST_SHA = "5be5d8737856ea3b0bc0d0e88b8fb5a8f7e01c15c4b4b1dcd744b08bd26d744a"
# Existing native-compiled graph, already reviewed; never regenerate particles.
PARTICLES = {
    "ambient": ("8863afd6177c69bf2770d9239b4c92496d44fd18560cd4e15656ab975c20fc96", 2099),
    "ambient_galaxy": ("d197b52f1915796b039a2b7f4c145835aebd59cf809201864c55ac741db2eb5c", 4169),
    "ambient_light": ("23771652b72bb371b1e16b476983e34891a804fc51c30ea4ed41ca91a379bf1e", 4058),
    "ambient_pointer": ("85cd4cae24f7331884b9e3349509db170e592477010bb0e453d16f07cbd056d2", 4605),
    "ambient_pointer_core": ("b8766b07da65d489510018e1ba5fd998079d1c87754593f0dac94927864957a2", 4152),
    "ambient_pointer_energy": ("a812a9fbcca8e9d1948c21fa49247db0f8aa5456b1e54ad32b7e0a494b39b2ad", 4108),
    "ambient_pointer_line": ("e886f1eec9ce1367014b12586f44ea64997416e2ab65aa6db1dc84ff82df868b", 3663),
    "ambient_pointer_stars": ("4c868cc28e50c676a05f23a84ceb4e7ca35dddfb8d87a3c82a28d05dd8ada3ea", 4710),
    "ambient_shadow": ("b8a918abb66134a3e24f0e343fca6e8968bb00f6f63adbaf8748a444ccc12fd7", 3632),
    "ambient_void": ("95eaed4bd4a94291cccae1da32925c4202c083828c2c6f52bb7e72107d3e9837", 3675),
    "ambient_void_edge": ("3f903e99705e76856cefea7b59d9b1080a6e970e39d14ca4b4e0b4677a3eb5e4", 4434),
    "ambient_void_edge_glow": ("4206819a705484dc119603a69fb95963b04b0d74d45408dba80e14581dcb3c4e", 4027),
    "ambient_void_edge_glow_animated": ("b5521399a7fa10cabf2d35d26459af60529af388191c58d3cf320469741b52c0", 3966),
    "ambient_void_edge_spikes": ("9a508ea7a9bc3ab3ee9a2bd2253d18c7ff1ab23d39f38e020de4227d2aff6f8a", 3596),
    "ambient_void_twirl": ("957ba2c363a334584d3c8fa90c3306c48a760dd869af3134f360f16f0c65ff47", 4265),
}
PARTICLE_DIRECTORY = "particles/survival_environment/rich_portal/"
PARTICLE_PATHS = frozenset(PARTICLE_DIRECTORY + name + ".vpcf_c" for name in PARTICLES)
REMOVE = frozenset(("panorama/styles/custom_game/commerce_wallet.vcss_c",))
RESULT_CSS = "panorama/styles/custom_game/commerce_result.vcss_c"
ADDED = helper.ADDED | {SERVICE, RESULT_CSS} | PARTICLE_PATHS
EXPECTED_FILES = BASE_FILES + len(ADDED) - len(REMOVE)
VARIANTS = {
    "native": dict(sequence=2026102705, revision="WS4-REFRESH-NATIVE-02", web=False, session=True, cash=False, connection_helper=False,
                   destination=Path("D:/Survival_发布候选/20261027_ws4_refresh_native_v02_overlay")),
    "helper": dict(sequence=2026102706, revision="WS4-REFRESH-HELPER-04", web=True, session=False, cash=True, connection_helper=True,
                   destination=Path("D:/Survival_发布候选/20261027_ws4_refresh_helper_v04_overlay")),
}
METADATA = frozenset((pack.handoff.MANIFEST, pack.handoff.SIGNATURE))


def compiled_name(source):
    extensions = {".js": ".vjs_c", ".css": ".vcss_c", ".xml": ".vxml_c"}
    return "panorama/" + str(Path(source).with_suffix(extensions[Path(source).suffix])).replace("\\", "/")


UI = frozenset(compiled_name(name) for name in SOURCES)
ALLOWLIST = helper.ALLOWLIST | UI | {MAIN, SERVICE, ENVIRONMENT} | PARTICLE_PATHS
MODIFIED = ALLOWLIST - ADDED
read_input, need = helper.read_input, web.need


def row_bytes(raw):
    return dict(bytes=len(raw), sha256=web.sha(raw), md5=hashlib.md5(raw, usedforsecurity=False).hexdigest())


def reviewed_pins():
    helper.require_review_pins()
    need(len(SOURCES) == len(UI) == 12 and len(PARTICLES) == 15 and len(ADDED) == 19
         and EXPECTED_FILES == 6655 and len(ALLOWLIST) == 41 and not REMOVE & ALLOWLIST,
         "Refresh exact reviewed scope differs")


def frozen_main(raw):
    need(web.sha(raw) == helper.FROZEN_CODE_PINS[MAIN], "Frozen MAIN preimage differs")
    newline = b"\r\n" if b"\r\n" in raw else b"\n"
    anchor = (b'            print("[MULTIPLAYER_SESSION] admission_finished authentication_and_assets_ready=true")\n'
              b"        end,\n    })\n    logger.info(").replace(b"\n", newline)
    replacement = anchor.replace(b"    logger.info(", b'    require("systems/native_setup_auto_start").init()' + newline + b"    logger.info(")
    result = helper.replace_once(raw, anchor, replacement)
    need(web.sha(result) == MAIN_OUTPUT_SHA, "MAIN change exceeds the exact automatic-setup insertion")
    return result


def authenticate_inputs():
    policy, _ = pack.handoff.trusted_policy(pack.handoff.POLICY)
    with web.trusted_root(BASE_TRUSTED): base, before, signed, metadata = pack.authenticate(BASE)
    with web.trusted_root(HELPER_TRUSTED): payment, payment_manifest, payment_signed, payment_metadata = pack.authenticate(HELPER)
    need(before["content_sha256"] == BASE_SHA and before["file_count"] == BASE_FILES
         and signed["release_sequence"] == BASE_SEQUENCE and payment_manifest["content_sha256"] == HELPER_SHA
         and payment_manifest["file_count"] == helper.EXPECTED_FILES and payment_signed["release_sequence"] == 2026102701
         and signed["key_id"] == payment_signed["key_id"] == policy["integrity"]["trusted_key_id"],
         "Fixed signed SHOP02/HELPER01 identities differ")
    need(all(value["sequence"] >= policy["integrity"]["minimum_release_sequence"] for value in VARIANTS.values()),
         "Refresh sequence is below the current trusted floor")
    pack.runtime.require_production(base)
    need(pack.handoff.configured_ids(base) == pack.handoff.configured_ids(payment), "Helper four-account roster differs")
    return base, before, signed, metadata, payment, payment_manifest, payment_metadata


def capture_payment(base, before, payment, payment_manifest, protected, snapshots):
    patches = {name: read_input(payment / name, snapshots) for name in helper.ALLOWLIST}
    helper.audit_changes(before, payment_manifest, patches, protected)
    expected = {row[1]: row[2] for row in helper.PINS.values()}
    expected.update({POLICY: helper.LUA_PINS[POLICY], helper.PAYMENT: helper.LUA_PINS[helper.PAYMENT],
                     helper.WEB_AUTH: helper.WEB_AUTH_OUTPUT_SHA, helper.CASH_CONFIG: "16a07a6ff22578f1aa20cdfe73811a7aeb453348e4776c962770c101c5790e79",
                     helper.WEB_CONFIG: "0c9b391bcdaaf8a99ace305f1f062c3a6e9902c1c8d6b18eaa1ccf7ab3d18729",
                     helper.SESSION_CONFIG: "68781cf8bfc5d0f599dd2dd6fa048d9205be2aa14c6b305d0f22a9356ef6572b"})
    need(set(expected) == helper.ALLOWLIST and all(web.sha(patches[name]) == value for name, value in expected.items()),
         "Signed HELPER01 twelve payment rows differ")
    need(patches[helper.WEB_CONFIG] == helper.replace_once(read_input(base / helper.WEB_CONFIG, snapshots), b"enabled = false", b"enabled = true")
         and patches[helper.SESSION_CONFIG] == helper.replace_once(read_input(base / helper.SESSION_CONFIG, snapshots), b"enabled = true", b"enabled = false"),
         "Signed helper configuration exceeds the two exact flags")
    return patches


def capture_ui(snapshots):
    need(isinstance(COMPILE_REPORT_SHA, str) and re.fullmatch(r"[0-9a-f]{64}", COMPILE_REPORT_SHA),
         "Replacement wallet compile receipt has not been reviewed")
    need(set(COMPILE_LOG_OVERRIDES) <= {"scripts/custom_game/commerce_wallet.js"},
         "Only the replacement wallet may use a newly reviewed compile log")
    receipt_raw = read_input(COMPILE_REPORT, snapshots)
    need(web.sha(receipt_raw) == COMPILE_REPORT_SHA, "Reviewed cleanup compile receipt changed")
    receipt = pack.handoff.decode_json(receipt_raw); rows = receipt.get("records")
    need(receipt.get("ok") is True and receipt.get("kind") == "WS4_ARCADE_CLEANUP_COMPILE"
         and receipt.get("original_102_bytes_preserved") is True and isinstance(rows, list) and len(rows) == 12
         and all(isinstance(row, dict) for row in rows), "Cleanup compile receipt contract differs")
    indexed = {row.get("source"): row for row in rows}
    need(len(indexed) == 12 and set(indexed) == {"panorama/src/" + name for name in SOURCES},
         "Cleanup compile sources contain duplicates or foreign UI")
    patches = {}
    for source in sorted(SOURCES):
        row = indexed["panorama/src/" + source]; compiled = compiled_name(source)
        log = COMPILE_LOG_OVERRIDES.get(source, COMPILE_LOG_DIRECTORY / (Path(source).name + ".log"))
        need(row.get("content") == "panorama/" + source and row.get("compiled") == compiled
             and Path(row.get("log", "")) == log, "Cleanup compile source/output association differs")
        game = read_input(ROOT / "panorama/src" / source, snapshots)
        content = read_input(CONTENT / "panorama" / source, snapshots)
        runtime = read_input(ROOT / compiled, snapshots)
        need(game == content and web.sha(game) == row.get("source_sha256")
             and web.sha(runtime) == row.get("compiled_sha256") and len(runtime) == row.get("compiled_bytes"),
             "Cleanup exact source mirror or native compiled hash differs")
        data = frozen.compiled_data(runtime)
        need(data and (not source.endswith(".js") or data == game), "Cleanup native DATA differs from JavaScript source")
        summary = ("1 compiled, 0 failed, %d skipped" % COMPILE_SKIPPED.get(source, 0)).encode("ascii")
        need(read_input(log, snapshots).count(summary) == 1, "Cleanup native compilation summary differs: " + source)
        patches[compiled] = runtime
    return patches


def capture_particles(snapshots):
    raw = read_input(ART / "manifest.json", snapshots)
    need(web.sha(raw) == ART_MANIFEST_SHA, "Reviewed fifteen-particle graph changed")
    manifest = pack.handoff.decode_json(raw); rows = manifest.get("outputs")
    need(manifest.get("scale") == 3 and isinstance(rows, list) and len(rows) == 15
         and all(isinstance(row, dict) for row in rows), "Portal graph count/scale differs")
    indexed = {row.get("resource"): row for row in rows}
    need(len(indexed) == 15 and {name + "_c" for name in indexed} == PARTICLE_PATHS, "Portal graph inventory differs")
    patches = {}
    for name in sorted(indexed):
        row = indexed[name]; pin, size = PARTICLES[Path(name).stem]
        source = read_input(ART / "source" / name, snapshots)
        content = read_input(CONTENT / name, snapshots)
        runtime = read_input(ROOT / (name + "_c"), snapshots)
        need(web.sha(source) == row.get("source_sha256") and web.lf(source) == web.lf(content)
             and web.sha(runtime) == pin and len(runtime) == size and frozen.compiled_data(runtime),
             "Portal source/content/native DATA association differs")
        patches[name + "_c"] = runtime
    return patches


def trust_inputs(base, snapshots):
    trusted = {}
    for name in helper.previous.trust_names():
        trusted[name] = read_input(BASE_TRUSTED / name, snapshots)
        if name not in web.POLICY_FILES:
            need(trusted[name] == read_input(base / name, snapshots), "Frozen base gate/trust bytes differ")
    for name in web.POLICY_FILES:
        need(read_input(ROOT / name, snapshots) == trusted[name], "Current trust key/policy differs from reviewed base")
    need(len(trusted) == 12, "Refresh trusted-source inventory differs")
    return trusted


def capture_common(base, before, payment, payment_manifest, protected):
    snapshots = {}
    patches = capture_payment(base, before, payment, payment_manifest, protected, snapshots)
    patches.update(capture_ui(snapshots)); patches.update(capture_particles(snapshots))
    patches[MAIN] = frozen_main(read_input(base / MAIN, snapshots))
    for name, expected in ((POLICY, POLICY_SHA), (SERVICE, SERVICE_SHA), (ENVIRONMENT, ENVIRONMENT_SHA)):
        raw = read_input(ROOT / name, snapshots)
        # Only the reviewed policy is LF-canonical, as in signed helper patch02.
        if name == POLICY: raw = web.lf(raw)
        need(web.sha(raw) == expected, "Reviewed cleanup Lua changed: " + name)
        patches[name] = raw
    for name, expected in helper.FROZEN_CODE_PINS.items():
        need(web.sha(read_input(base / name, snapshots)) == expected, "Frozen main/profile/provider preimage differs")
    provider = read_input(base / helper.PROVIDER, snapshots)
    need(b"web_auth.resolve(body.account_id, session, send, on_error)" in provider, "Frozen provider lacks per-account PWA")
    need("scripts/vscripts/debug/offline_logic_test.lua" not in {row["path"] for row in before["files"]}
         and b'require("debug/' not in patches[POLICY] and b"require('debug/" not in patches[POLICY]
         and b'package.loaded["debug/offline_logic_test"]' in patches[POLICY],
         "Production policy must tolerate the absent offline debug module")
    trusted = trust_inputs(base, snapshots); trusted[MAIN] = patches[MAIN]
    for path in (Path(__file__), ROOT / "tools/lua_protection_policy.json", Path(helper.__file__)):
        read_input(path, snapshots)
    need(set(patches) == ALLOWLIST, "Refresh common overlay scope differs")
    return snapshots, patches, trusted


def variant_patches(common, variant):
    need(variant in VARIANTS and set(common) == ALLOWLIST, "Unknown refresh variant/scope")
    patches = dict(common)
    if variant == "native":
        patches[helper.WEB_CONFIG] = helper.replace_once(patches[helper.WEB_CONFIG], b"enabled = true", b"enabled = false")
        patches[helper.SESSION_CONFIG] = helper.replace_once(patches[helper.SESSION_CONFIG], b"enabled = false", b"enabled = true")
        patches[helper.CASH_CONFIG] = helper.replace_once(helper.replace_once(patches[helper.CASH_CONFIG], b"enabled = true", b"enabled = false"),
                                                       b"connection_helper = true", b"connection_helper = false")
    no_credentials(patches)
    return patches


def no_credentials(patches):
    for name, raw in patches.items():
        need(name in ALLOWLIST and pack.runtime.safe_relative(name), "Unsafe/foreign refresh path")
        need(not re.search(rb"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----|Bearer [A-Za-z0-9_.~-]{20,}", raw)
             and not re.search(rb"(?:access_token|api_token|merchant_secret)\s*=\s*[\"'][A-Za-z0-9_.~-]{20,}[\"']", raw),
             "Credential literal cannot enter a refresh runtime")


def project(before, patches):
    pack.runtime.validate_manifest(before)
    need(set(patches) == ALLOWLIST, "Refresh projection scope differs")
    old = {row["path"]: row for row in before["files"]}
    need(REMOVE | MODIFIED <= old.keys() and not ADDED & old.keys(), "Refresh baseline additions/removals differ")
    rows = {name: dict(row) for name, row in old.items() if name not in REMOVE}
    rows.update({name: dict(path=name, **row_bytes(raw)) for name, raw in patches.items()})
    new = {key: before[key] for key in ("schema", "kind", "hash_algorithms")}
    new.update(files=[rows[name] for name in sorted(rows)], file_count=len(rows), bytes=sum(row["bytes"] for row in rows.values()))
    new["content_sha256"] = web.sha(pack.runtime.manifest_payload(new))
    return new


def audit_changes(before, after, patches, protected):
    pack.runtime.validate_manifest(before); pack.runtime.validate_manifest(after)
    old, new = ({row["path"]: row for row in doc["files"]} for doc in (before, after))
    need(set(patches) == ALLOWLIST and before["file_count"] == BASE_FILES and after["file_count"] == EXPECTED_FILES
         and old.keys() - new.keys() == REMOVE and new.keys() - old.keys() == ADDED,
         "Refresh full file inventory differs")
    changed = {name for name in old.keys() & new.keys() if old[name] != new[name]}
    expected = {name for name, raw in patches.items() if name in old and old[name] != dict(path=name, **row_bytes(raw))}
    need(changed == expected and all(new[name] == dict(path=name, **row_bytes(raw)) for name, raw in patches.items()),
         "Refresh changes runtime outside exact reviewed bytes")
    need(len(protected) == len(set(protected)) == 180 and set(protected) == set(frozen.protected_paths(before))
         and not set(protected) & (ALLOWLIST | REMOVE) and all(old[name] == new[name] for name in protected),
         "Refresh protected 180 modules differ")
    need(pack.runtime.CRITICAL <= new.keys(), "Refresh removes a critical file")
    return [dict(path=name, before=old.get(name), after=new.get(name)) for name in sorted(changed | ADDED | REMOVE)]


def write_new(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(raw); stream.flush(); os.fsync(stream.fileno())


def stage_thin(destination, before, after, patches):
    need(not destination.exists(), "Thin overlay already exists")
    destination.mkdir(parents=True, exist_ok=False)
    old = {row["path"]: row for row in before["files"]}
    changed = {row["path"] for row in after["files"] if old.get(row["path"]) != row}
    for name in sorted(changed): write_new(destination / name, patches[name])
    return changed


def verify_merged(base, destination, before, after, trusted, sequence, key_id):
    old = {row["path"]: row for row in before["files"]}
    changed = {row["path"] for row in after["files"] if old.get(row["path"]) != row}
    actual = set()
    for current, folders, files in os.walk(destination, followlinks=False):
        for leaf in (*folders, *files): need(not pack.protect_data.linked(Path(current) / leaf), "Linked thin overlay forbidden")
        actual.update((Path(current) / leaf).relative_to(destination).as_posix() for leaf in files)
    need(actual == changed | METADATA, "Thin overlay must contain only runtime differences and signed metadata")
    manifest_raw = pack.read_metadata(pack.protect_data.source_path(destination, pack.handoff.MANIFEST), pack.MAX_MANIFEST)
    signature_raw = pack.read_metadata(pack.protect_data.source_path(destination, pack.handoff.SIGNATURE), pack.MAX_SIGNATURE)
    manifest = pack.handoff.decode_json(manifest_raw); document = pack.handoff.decode_json(signature_raw)
    need(manifest == after, "Thin signed full manifest differs from the projection")
    with web.trusted_root(trusted):
        policy, public = pack.handoff.trusted_policy(pack.handoff.POLICY)
        signed = pack.verify_signed_snapshot(manifest, document, public, policy["integrity"]["minimum_release_sequence"], key_id)
    need(signed["release_sequence"] == sequence, "Thin signature sequence differs")
    for row in after["files"]:
        source = pack.protect_data.source_path(destination if row["path"] in changed else base, row["path"])
        need(pack.runtime.checksums(source) == {name: row[name] for name in ("bytes", "sha256", "md5")}, "Merged runtime hash differs: " + row["path"])
    for name in helper.previous.trust_names():
        if name not in web.POLICY_FILES:
            source = pack.protect_data.source_path(destination if name in changed else base, name)
            need(source.read_bytes() == pack.protect_data.source_path(trusted, name).read_bytes(), "Merged gate differs from frozen review source")
    pack.inventory_unchanged(destination, {pack.handoff.MANIFEST:manifest_raw, pack.handoff.SIGNATURE:signature_raw})
    return signed


def build(args):
    spec = VARIANTS[args.variant]; destination = spec["destination"]
    trusted_destination = destination.with_name(destination.name + "_trusted_source")
    need(not args.build or args.signing_key is not None, "--build requires --key (an external signing key)")
    reviewed_pins()
    base, before, signed, base_metadata, payment, payment_manifest, payment_metadata = authenticate_inputs()
    protected = helper.protected_paths(before)
    head = web.git("rev-parse", "HEAD", root=ROOT).decode("ascii").strip()
    snapshots, common, trust = capture_common(base, before, payment, payment_manifest, protected)
    patches = variant_patches(common, args.variant); helper.check_lua(patches)
    after = project(before, patches); changes = audit_changes(before, after, patches, protected)
    result = dict(ok=True, status="READ_ONLY_PLAN", variant=args.variant, revision=spec["revision"], release_sequence=spec["sequence"],
                  base_content_sha256=BASE_SHA, base_sequence=BASE_SEQUENCE, base_files=BASE_FILES,
                  helper_source_content_sha256=HELPER_SHA, helper_twelve_payment_rows_verified=True,
                  projected_content_sha256=after["content_sha256"], expected_files=EXPECTED_FILES,
                  destination=str(destination), trusted_source=str(trusted_destination), reviewed_head=head,
                  compile_receipt_sha256=COMPILE_REPORT_SHA, changed=changes, allowed_additions=sorted(ADDED), allowed_removals=sorted(REMOVE),
                  protected_modules_preserved=180, protected_modules_rebuilt=0, all_other_base_files_preserved=True,
                  main_patch="one_init_call_only", frozen_profile_http_provider_preserved=True, production_preserved=True,
                  four_accounts_preserved=True, multiplayer_max_players=4, online_cheats_allowed=False,
                  web_auth=spec["web"], session_only=spec["session"], cash_code_enabled=spec["cash"], connection_helper=spec["connection_helper"],
                  unpublished_gameplay_changes_included=False, human_wave_architecture_backported=False,
                  external_full_candidate_created=False, private_key_copied=False, workshop_upload_performed=False,
                  vpk_packaged=False, alias_installed=False, game_started=False, real_order_created=False, native_acceptance="NOT_RUN")
    helper.require_unchanged(snapshots, head)
    pack.inventory_unchanged(base, base_metadata); pack.inventory_unchanged(payment, payment_metadata)
    if not args.build: return result
    options = argparse.Namespace(destination=destination, trusted_source=trusted_destination, package_output=None, signing_key=args.signing_key)
    destination, trusted_destination, _, key = web.output_paths(options, base)
    need(not pack.runtime.within(destination, HELPER) and not pack.runtime.within(trusted_destination, HELPER), "Refresh output overlaps HELPER01")
    physical_bytes = sum(len(patches[row["path"]]) for row in changes if row["after"] is not None) + sum(len(raw) for raw in trust.values())
    need(destination.parent.is_dir() and shutil.disk_usage(destination.parent).free >= physical_bytes + 32 * 1024 * 1024,
         "Insufficient space for thin overlay and reserve")
    changed = stage_thin(destination, before, after, patches)
    trusted_destination.mkdir(parents=True, exist_ok=False)
    for name, raw in trust.items(): write_new(trusted_destination / name, raw)
    write_new(destination / pack.handoff.MANIFEST, pack.runtime.canonical_bytes(after) + b"\n")
    helper.require_unchanged(snapshots, head)
    pack.protect_data.sign_manifest(destination / pack.handoff.MANIFEST, key, destination / pack.handoff.SIGNATURE, spec["sequence"])
    verified = verify_merged(base, destination, before, after, trusted_destination, spec["sequence"], signed["key_id"])
    need(pack.runtime.verify(base, before)["ok"], "Immutable SHOP02 changed during thin build")
    helper.require_unchanged(snapshots, head)
    pack.inventory_unchanged(base, base_metadata); pack.inventory_unchanged(payment, payment_metadata)
    result.update(status="SIGNED_THIN_OVERLAY_REQUIRES_NATIVE_TEST", content_sha256=after["content_sha256"],
                  signature=verified, thin_runtime_files=len(changed), full_merged_hash_verification=True)
    return result


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--variant", choices=tuple(VARIANTS), default="native")
    result.add_argument("--build", action="store_true")
    result.add_argument("--key", "--signing-key", dest="signing_key", type=Path)
    return result


def main(argv=None):
    try: result = build(parser().parse_args(argv))
    except Exception as error:
        print(json.dumps(dict(ok=False, status="BLOCKED_DO_NOT_SIGN_OR_UPLOAD", error=str(error)), ensure_ascii=True)); return 1
    print(json.dumps(result, ensure_ascii=True, indent=2)); return 0


if __name__ == "__main__": raise SystemExit(main())
