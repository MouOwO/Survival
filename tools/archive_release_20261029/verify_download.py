"""Pinned full-release download verification; default operation is read-only.

Reuse the unchanged 2705 official SDK callback/query/install protocol in a
private module. This release rebuilds its entire selected Lua set, so local
evidence binds the new completed build rather than a historical 180-module
preservation claim. Only the root operator executes --download.
"""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
PROTOCOL_FILE = ROOT / "tools/arcade_cleanup_20261027/verify_download.py"
PROTOCOL_LF_SHA = "1f7afed91128c8601ccd9848b092300d0869067853422fe87cc5c5e511eb237f"
VALIDATOR_FILE = ROOT / "tools/build_runtime_release.py"
VALIDATOR_LF_SHA = "2b321bf45df70463e84684d982d3a83189b9b3a5f7565b972bb14383de363e81"
PUBLISHER_FILE = ROOT / "tools/publish_test_release.py"
PUBLISHER_SHA = "6131f0358c328e8574b44ccb07c589ef68e1544e197c2555569fda7ed0f81f40"
if hashlib.sha256(PROTOCOL_FILE.read_bytes().replace(b"\r\n", b"\n")).hexdigest() != PROTOCOL_LF_SHA:
    raise ValueError("Frozen official-download protocol changed")
spec = importlib.util.spec_from_file_location("private_archive2901_download_protocol", PROTOCOL_FILE)
protocol = importlib.util.module_from_spec(spec)
spec.loader.exec_module(protocol)
callbacks, api, need = protocol.callbacks, protocol.api, protocol.need

ITEM, SEQUENCE = "3824360109", 2026102901
CANDIDATE = Path("D:/Survival_发布候选/20261029_ws4_archive_all_v01_view")
TRUSTED = Path("D:/Survival_发布候选/20261029_ws4_archive_all_v01_trusted_source")
PROTECTED = Path("D:/Survival_发布候选/20261029_ws4_archive_all_v01_lua")
VPK = Path("D:/Survival_工坊输出/20261029_ws4_archive_all_v01/3824360109.vpk")
REPORT = ROOT / "output/release_archive_20261029/workshop_build/package.json"
STATE = ROOT / "output/four_accounts_20261022/steam_upload_state.json"
OUTPUT = ROOT / "output/release_archive_20261029/download_evidence"
MINIMUM_REMOTE_UPDATED = 1793195047  # Actual 2805 receipt post_query.time_updated.
TRUST_NAMES = (
    "tools/release_security/protection_policy.json", "tools/release_security/trusted_public_key.pem",
    "scripts/vscripts/addon_game_mode.lua", "scripts/vscripts/addon_game_mode_client.lua",
    "scripts/vscripts/config/test_access.lua", "scripts/vscripts/core/event_bus.lua",
    "scripts/vscripts/core/test_access_policy.lua", "scripts/vscripts/systems/multiplayer_player_service.lua",
    "scripts/vscripts/systems/native_cloud_handoff.lua", "scripts/vscripts/systems/native_cloud_roster.lua",
    "scripts/vscripts/systems/player_profile_service.lua", "scripts/vscripts/systems/startup_loading_service.lua",
    "scripts/vscripts/systems/workshop_entry.lua", "scripts/vscripts/ui/ui_request_router.lua",
    "panorama/src/scripts/custom_game/payment_test.js", "panorama/src/scripts/custom_game/production_progress.js",
)

# Finalize exclusively from the REAL completed 2901 build. Missing values reject
# before opening a release file, touching a journal, or initializing Steam.
# No CLI replacement hashes, fake success fields or historical counts exist.
PINS = {'report_sha256': '39a6877ce20132efcf96cdfb3f435ab6f759d5ba6ab5bd2258fefe2fd0501cd7',
 'content_sha256': '7eee7d5b975573da3e26b2f8fcf079cbc346e33e4a06dc7f7c1c7280691e46ba',
 'index_sha256': 'ccfcc45828f8ce758f43cb4749dd90edf33ed8659a1cdc259bfdc9f762786109',
 'file_count': 6695,
 'selected_count': 184,
 'container_bytes': 3777996435,
 'protection_report_sha256': '11c90e1acf49a38d6a5b6a96a83e4b2e4dc76edf3d3aaa542a17dbfda3d439c9',
 'production_manifest_sha256': '3a091dac75b92ef89622b019aab851d0eab54153af8f29b8da78a500be68e684',
 'assembly_sha256': 'ba0076283d86c57262b04d952e8b3268ba9e6f422c97602d69b43ac77a65ca3d',
 'reviewed_plan_sha256': 'ccbfc7339274ede73f274fa93ef63f865731d2d4089c8ec00c58425464f73657',
 'plan_sha256': '92fd6092a11fd17cf1b22bf3362ace00b33797d192dd75ebcfe5d406d3d6d22a',
 'metadata_sha256': {'_release_manifest.json': 'efd0d621472a32677c2c399e0d3cd1d08e40296e1acf08ac18c219f0672ba3d1',
                     '_release_signature.json': 'd23be643fddaced3d43816f45034fc5260b7ce70492a5f628bdce06f791f6750'},
 'review_sources': {'panorama/src/scripts/custom_game/payment_test.js': '2ee90ef3ca2454aa7c5e37af1473d17cc776e5117b99ec69ea764cf1906706dd',
                    'panorama/src/scripts/custom_game/production_progress.js': '136ce07fcebc36c7c27ffc428ab05c0d7f63837902f5c7dfdb885b553810cc27',
                    'scripts/vscripts/addon_game_mode.lua': '7e5f08fd16301370366d024c7ed1e1416dbc32736bef637628cda0be77ccee94',
                    'scripts/vscripts/addon_game_mode_client.lua': 'f4e069479bfceb852e817f9e794b761203a4e442a5a52b406632532d9c9d4576',
                    'scripts/vscripts/config/test_access.lua': 'd1be1229149a8191c847a9ff964a6a8342dae38782971135a5b741651807b220',
                    'scripts/vscripts/core/event_bus.lua': '316d424fc50cd86e639eb29c83cda3bcc4cc688fb10ac4954a86cbfd916d8cf9',
                    'scripts/vscripts/core/test_access_policy.lua': 'b58ca800a3186ad9757fb740931e6eeb7557b28f3b63a00b53ded8c394b6ad5e',
                    'scripts/vscripts/systems/multiplayer_player_service.lua': '55aef4d45f1a2ad12fce95437547230f398455424c5244c9ae67f386deec0f29',
                    'scripts/vscripts/systems/native_cloud_handoff.lua': '74525fecec2367d9af5a49073e357b6024eb20a8e6dd44be96123c2e9f64ebf1',
                    'scripts/vscripts/systems/native_cloud_roster.lua': 'cc3f4a5f753749d8ee184a8862adc50061e00282ac9a7b2aed352b894adeb0e7',
                    'scripts/vscripts/systems/player_profile_service.lua': '9a84e7378635a33966126304d75f55edd0b5b21ce4bff5dc8a52a5d0c41e750a',
                    'scripts/vscripts/systems/startup_loading_service.lua': '95070e73ba064820ef98b6255c1f51e223549af75a6152b34e038888f353d658',
                    'scripts/vscripts/systems/workshop_entry.lua': '1afaa3f740a2b3c5c53c8f802ec244f3b20e277f13f20157175088edaecc4fcc',
                    'scripts/vscripts/ui/ui_request_router.lua': '429ed8269ca1996de51fb057e6d93bfe50dee6c58a55227555c873eb2dcd9a07',
                    'tools/release_security/protection_policy.json': '8e8c2e50a6a983dda7336a083377bbf55de8625f89f5633977c8d7901b53da96',
                    'tools/release_security/trusted_public_key.pem': '1717c28cb7476e5eb5326b780589c880e86d42cc026b6d4728d95ac95e8873bf'}}


def require_package_pins():
    need(isinstance(PINS, dict), "archive_completed_build_pins_not_yet_finalized")
    hashes = ("report_sha256", "content_sha256", "index_sha256", "protection_report_sha256",
              "production_manifest_sha256", "assembly_sha256", "reviewed_plan_sha256", "plan_sha256")
    need(all(protocol.sha_pin(PINS.get(k)) for k in hashes)
         and all(type(PINS.get(k)) is int and PINS[k] > 0 for k in ("file_count", "selected_count", "container_bytes"))
         and PINS["selected_count"] <= PINS["file_count"]
         and isinstance(PINS.get("metadata_sha256"), dict)
         and set(PINS["metadata_sha256"]) == {api.pack.handoff.MANIFEST, api.pack.handoff.SIGNATURE}
         and all(protocol.sha_pin(v) for v in PINS["metadata_sha256"].values())
         and isinstance(PINS.get("review_sources"), dict) and set(PINS["review_sources"]) == set(TRUST_NAMES)
         and all(protocol.sha_pin(v) for v in PINS["review_sources"].values()),
         "archive_completed_build_pins_invalid")


def protected_inventory(manifest, policy):
    protocol.protect_runtime_lua.check_policy(policy)
    selected = protocol.protect_runtime_lua.selected_files([r["path"] for r in manifest["files"]], policy)
    paths = [r["path"] for r in selected]
    need(len(paths) == len(set(paths)) == PINS["selected_count"], "archive_selected_module_inventory_mismatch")
    need(api.pack.runtime.CRITICAL <= {r["path"] for r in manifest["files"]}, "archive_missing_critical_signed_resources")
    return selected


def verify_completed_report(report, manifest, signature):
    rows = report.get("package_files")
    need(report.get("status") == "BUILT_AND_VERIFIED_FOR_NATIVE_TEST_ONLY"
         and report.get("content_sha256") == signature.get("content_sha256") == PINS["content_sha256"]
         and report.get("release_sequence") == signature.get("release_sequence") == SEQUENCE
         and type(report.get("files")) is int and report["files"] == manifest["file_count"] == PINS["file_count"]
         and report.get("protected_modules_rebuilt") == PINS["selected_count"]
         and type(report.get("protected_modules_rebuilt")) is int
         and report.get("protected_modules_preserved") == 0
         and type(report.get("protected_modules_preserved")) is int
         and report.get("full_source_plan_sha256") == PINS["plan_sha256"]
         and report.get("signature_valid") is True and report.get("dry_run") is False
         and report.get("payload_changed") is False and report.get("workshop_upload_performed") is False
         and report.get("full_input_hash_verification") is True and report.get("full_runtime_validator_passed") is True
         and report.get("candidate") == str(CANDIDATE) and report.get("trusted_source") == str(TRUSTED)
         and report.get("output") == str(VPK)
         and isinstance(rows, list) and len(rows) == 5
         and [r.get("name") for r in rows] == protocol.EXPECTED_NAMES
         and all(type(r.get("bytes")) is int and r["bytes"] > 0 and protocol.sha_pin(r.get("sha256")) for r in rows)
         and report.get("vpk_sha256") == rows[0]["sha256"] == PINS["index_sha256"],
         "archive_completed_package_report_required")
    checks = report.get("verification", {})
    need(type(checks.get("files")) is int and checks["files"] == PINS["file_count"]
         and type(checks.get("archive_count")) is int and checks["archive_count"] == 4
         and all(checks.get(k) is True for k in callbacks.CHECKS), "archive_incomplete_four_archive_verification")
    total = sum(r["bytes"] for r in rows)
    need(total == report.get("container_bytes") == PINS["container_bytes"]
         and manifest["bytes"] == report.get("payload_bytes"), "archive_package_totals_mismatch")
    return total


def pinned_snapshot(path, expected, snapshots, maximum=None):
    raw = protocol.read_snapshot(path, maximum or api.pack.MAX_MANIFEST, snapshots)
    need(hashlib.sha256(raw).hexdigest() == expected, "archive_completed_input_pin_mismatch:" + path.name)
    return raw


def verify_protection_evidence(manifest, selected, snapshots):
    directory = REPORT.parent
    source = api.pack.handoff.decode_json(pinned_snapshot(directory / "production_manifest.json", PINS["production_manifest_sha256"], snapshots))
    api.pack.runtime.validate_manifest(source)
    evidence = api.pack.handoff.decode_json(pinned_snapshot(PROTECTED / "_lua_protection_report.json", PINS["protection_report_sha256"], snapshots))
    assembled = api.pack.handoff.decode_json(pinned_snapshot(directory / "assembly.json", PINS["assembly_sha256"], snapshots))
    plan = api.pack.handoff.decode_json(pinned_snapshot(directory / "reviewed_plan.json", PINS["reviewed_plan_sha256"], snapshots))
    semantic = evidence.get("semantic_verification", {})
    need(evidence.get("status") == "PASS_REQUIRES_NATIVE_SMOKE" and evidence.get("syntax", {}).get("status") == "PASS"
         and evidence.get("selected_files") == PINS["selected_count"] and semantic.get("status") == "PASS"
         and semantic.get("all_generated_values_exact") is True
         and semantic.get("gameplay_rng_untouched_while_loading") is True
         and semantic.get("new_runtime_io_os_debug_dependency") is False
         and semantic.get("summary", {}).get("files") == PINS["selected_count"], "archive_full_reprotection_evidence_required")
    need(assembled.get("status") == "READY_FOR_NATIVE_SMOKE_ONLY" and assembled.get("full_file_verification") is True
         and assembled.get("runtime_files") == PINS["file_count"] and assembled.get("protected_lua_files") == PINS["selected_count"]
         and assembled.get("content_sha256") == PINS["content_sha256"] and assembled.get("release_sequence") == SEQUENCE,
         "archive_assembly_identity_mismatch")
    need(plan.get("plan_sha256") == PINS["plan_sha256"] and plan.get("release_sequence") == SEQUENCE
         and plan.get("runtime_files") == PINS["file_count"] and plan.get("protected_modules_rebuild") == PINS["selected_count"]
         and plan.get("protected_modules_preserve") == 0, "archive_reviewed_plan_identity_mismatch")
    files = evidence.get("files")
    need(isinstance(files, list) and [{"path": r.get("path"), "kind": r.get("kind")} for r in files] == selected,
         "archive_protected_evidence_inventory_mismatch")
    before, after = [{r["path"]: r for r in m["files"]} for m in (source, manifest)]
    need(before.keys() == after.keys(), "archive_protection_changed_runtime_inventory")
    for row in files:
        path = row["path"]
        need(row.get("before") == {k: before[path][k] for k in ("bytes", "md5", "sha256")}
             and row.get("after") == {k: after[path][k] for k in ("bytes", "md5", "sha256")}
             and row["before"]["sha256"] != row["after"]["sha256"], "archive_protected_source_or_signed_bytes_mismatch")


def local_inputs(require_success=False, *, full=False):
    require_package_pins()
    bind_protocol()
    snapshots = {}
    report_raw = pinned_snapshot(REPORT, PINS["report_sha256"], snapshots)
    report = api.pack.handoff.decode_json(report_raw)
    for relative, pin in protocol.PUBLIC_PINS.items():
        raw = pinned_snapshot(ROOT / relative, pin, snapshots, 1024 * 1024)
        if relative != "tools/lua_protection_policy.json":
            need(protocol.read_snapshot(TRUSTED / relative, 1024 * 1024, snapshots) == raw,
                 "archive_frozen_public_trust_differs")
    for name, pin in PINS["metadata_sha256"].items():
        pinned_snapshot(CANDIDATE / name, pin, snapshots)
    manifest = api.pack.handoff.decode_json(snapshots[CANDIDATE / api.pack.handoff.MANIFEST])
    document = api.pack.handoff.decode_json(snapshots[CANDIDATE / api.pack.handoff.SIGNATURE])
    api.pack.runtime.validate_manifest(manifest)
    policy, public = api.pack.handoff.trusted_policy(api.pack.handoff.POLICY)
    signature = api.pack.verify_signed_snapshot(manifest, document, public,
        policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
    total = verify_completed_report(report, manifest, signature)
    lua_policy = api.pack.handoff.decode_json(snapshots[ROOT / "tools/lua_protection_policy.json"])
    selected = protected_inventory(manifest, lua_policy)
    verify_protection_evidence(manifest, selected, snapshots)
    need(protocol.incremental.all_files(TRUSTED) == set(TRUST_NAMES), "archive_review_source_inventory_mismatch")
    entries = {r["path"]: r for r in manifest["files"]}
    for relative, pin in PINS["review_sources"].items():
        raw = pinned_snapshot(TRUSTED / relative, pin, snapshots)
        if relative.startswith("scripts/"):
            need(relative in entries and hashlib.sha256(raw).hexdigest() == entries[relative]["sha256"],
                 "archive_review_source_differs_from_signed_runtime")
    frozen = protocol.read_snapshot(PROTOCOL_FILE, api.pack.MAX_MANIFEST, snapshots)
    need(hashlib.sha256(frozen.replace(b"\r\n", b"\n")).hexdigest() == PROTOCOL_LF_SHA, "archive_official_protocol_changed_after_import")
    validator = protocol.read_snapshot(VALIDATOR_FILE, api.pack.MAX_MANIFEST, snapshots)
    need(hashlib.sha256(validator.replace(b"\r\n", b"\n")).hexdigest() == VALIDATOR_LF_SHA,
         "archive_production_profile_parser_changed")
    publisher = protocol.read_snapshot(PUBLISHER_FILE, api.pack.MAX_MANIFEST, snapshots)
    need(hashlib.sha256(publisher).hexdigest() == PUBLISHER_SHA, "archive_canonical_publisher_changed")
    state_raw = protocol.read_snapshot(STATE, api.pack.MAX_MANIFEST, snapshots)
    state = api.pack.handoff.decode_json(state_raw)
    rows = report["package_files"]
    success = (state.get("uploaded") is True and state.get("owner") == api.OWNER and state.get("app_id") == api.APP
        and state.get("workshop_id") == ITEM and state.get("visibility_requested") == 3
        and state.get("release_sequence") == SEQUENCE and state.get("content_sha256") == PINS["content_sha256"]
        and state.get("vpk_sha256") == PINS["index_sha256"] and state.get("vpk_bytes") == rows[0]["bytes"]
        and state.get("package_files") == rows and state.get("legal_agreement_required") is False)
    if require_success:
        need(success, "archive_successful_same_release_original_item_upload_required")
    expected_manifest = protocol.journal_manifest(state) if success else None
    if full:
        with protocol.incremental.trusted_source(TRUSTED):
            _, verified, actual_signature, _ = api.pack.authenticate(CANDIDATE)
        need(verified == manifest and actual_signature == signature, "archive_full_candidate_identity_mismatch")
        need(api.pack.package_inventory(VPK) == rows, "archive_local_vpk_bytes_differ_from_report")
        api.pack.verify_vpk(VPK, manifest)
    protocol.unchanged(snapshots)
    return dict(report=report, manifest=manifest, signature=signature, state=state, snapshots=snapshots,
                success=success, expected_manifest=expected_manifest, total=total,
                report_sha256=hashlib.sha256(report_raw).hexdigest(), state_sha256=hashlib.sha256(state_raw).hexdigest(),
                protected_modules=len(selected))


_official_download_once = protocol.download_once


def download_once(inputs):
    result = _official_download_once(inputs)
    # The frozen function's evidence receipt already uses inputs' real count.
    # Correct only its historical summary literal; no SDK/verification change.
    result["protected_modules_verified"] = inputs["protected_modules"]
    return result


def bind_protocol():
    values = dict(ITEM=ITEM, SEQUENCE=SEQUENCE, FILE_COUNT=PINS.get("file_count") if isinstance(PINS, dict) else None,
        CONTENT=PINS.get("content_sha256") if isinstance(PINS, dict) else None, CANDIDATE=CANDIDATE, TRUSTED=TRUSTED,
        VPK=VPK, REPORT=REPORT, STATE=STATE, OUTPUT=OUTPUT, MINIMUM_REMOTE_UPDATED=MINIMUM_REMOTE_UPDATED,
        local_inputs=local_inputs, download_once=download_once)
    for name, value in values.items():
        setattr(protocol, name, value)


def main(argv=None):
    bind_protocol()
    return protocol.main(argv)


if __name__ == "__main__":
    raise SystemExit(main())
