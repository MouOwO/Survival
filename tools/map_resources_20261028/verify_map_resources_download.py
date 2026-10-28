"""Verify only the official native-cloud MAP2802 2802 download; no default Steam call.

Reuse the frozen 2705 callback/query/VPK protocol in a private module instance.
This release has independent fixed identities and additional completed-package
pins. Missing pins refuse before release reads or SDK initialization. The old
verifier and its release constants are never changed.
"""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
RUNTIME_VALIDATOR_FILE = ROOT / "tools/build_runtime_release.py"
RUNTIME_VALIDATOR_LF_SHA = "2b321bf45df70463e84684d982d3a83189b9b3a5f7565b972bb14383de363e81"
if hashlib.sha256(RUNTIME_VALIDATOR_FILE.read_bytes().replace(b"\r\n", b"\n")).hexdigest() != RUNTIME_VALIDATOR_LF_SHA:
    raise ValueError("Reviewed production profile parser changed")
PROTOCOL_FILE = ROOT / "tools/arcade_cleanup_20261027/verify_download.py"
PROTOCOL_LF_SHA = "1f7afed91128c8601ccd9848b092300d0869067853422fe87cc5c5e511eb237f"
PUBLISHER_SHA = "6131f0358c328e8574b44ccb07c589ef68e1544e197c2555569fda7ed0f81f40"
if hashlib.sha256(PROTOCOL_FILE.read_bytes().replace(b"\r\n", b"\n")).hexdigest() != PROTOCOL_LF_SHA:
    raise ValueError("Reviewed official-download protocol changed")
spec = importlib.util.spec_from_file_location("private_map2802_download_protocol", PROTOCOL_FILE)
protocol = importlib.util.module_from_spec(spec)
spec.loader.exec_module(protocol)
callbacks, api, need = protocol.callbacks, protocol.api, protocol.need

ITEM, SEQUENCE, FILE_COUNT = "3824360109", 2026102802, 6658
CONTENT = "310aad0a33116f29304d9ea7251524b4c1721bd5fb2b7952610d63cca2ac09d5"
CANDIDATE = Path("D:/Survival_发布候选/20261028_ws4_map_resources_v01_view")
TRUSTED = Path("D:/Survival_发布候选/20261028_ws4_map_resources_v01_overlay_trusted_source")
VPK = Path("D:/Survival_工坊输出/20261028_ws4_map_resources_v01/3824360109.vpk")
REPORT = ROOT / "output/map_resources_20261028/package.json"
STATE = ROOT / "output/four_accounts_20261022/steam_upload_state.json"
OUTPUT = ROOT / "output/map_resources_20261028/download_evidence"
MINIMUM_REMOTE_UPDATED = 1793146417  # Actual verified native2801 publication, never a predicted timestamp.

# Fill only from the completed real 2802 package, before enabling --download.
# No CLI option can provide a replacement hash, release identity or manifest.
REPORT_SHA = "4b701bce2b41d30ffe4bc5d3628dd44180778e52d70085b58ea7bde801c6a368"
INDEX_SHA = "b3dbe2351798561cd8d585449a7e304822d62f0706689527285c7f41658359f8"
TOTAL_BYTES = 3767361725
TRUST_NAMES = (*api.pack.handoff.GATE_FILES, *api.pack.handoff.ENTRY_GATE_FILES,
    api.pack.handoff.ACCESS_FILE, "tools/release_security/protection_policy.json",
    "tools/release_security/trusted_public_key.pem", *api.pack.handoff.NATIVE_CLOUD_ENTRY_GATE_FILES[:2])
LAYOUT_SOURCE_REL = "panorama/src/scripts/custom_game/production_progress.js"
LAYOUT_SOURCE_SHA = "136ce07fcebc36c7c27ffc428ab05c0d7f63837902f5c7dfdb885b553810cc27"
LAYOUT_TARGET = "panorama/scripts/custom_game/production_progress.vjs_c"
LAYOUT_COMPILED_SHA = "36dd249135d8c650ea0055023c33e4df2cc7b068a77e7521b32ba82cbac5b4ce"
COMPILE_LOG_SHA = "be9a1899a5f39ada3bef977e5d53a77f0da794efa8464f7f083b6947878450c4"
QR_SOURCE_REL = "panorama/src/scripts/custom_game/payment_test.js"
QR_SOURCE_SHA = "2ee90ef3ca2454aa7c5e37af1473d17cc776e5117b99ec69ea764cf1906706dd"
QR_TARGET = "panorama/scripts/custom_game/payment_test.vjs_c"
QR_COMPILED_SHA = "8cca589085ff74459f17cee9cf620a450364eb22b4395b0458a0db4cf72ed566"
MAP_TARGET = "maps/template_map.vpk"
MAP_SOURCE_SHA = "4e62350c1bf08e663f5217885f26652918c2e09296a829f29a987ba8a14dccdc"
MAP_SOURCE_CRC = 3557144492
MAP_CRC_ENTRIES = 307
MAP_COMPILED_SHA = "f868f295a01b78f63dbeb9fe9edfc6a7591b3889ace84f0892f595ac46f22186"
MAP_COMPILED_BYTES = 65142294
MAP_VERIFICATION = ROOT / "output/map_resources_20261028/package_verification.json"
MAP_VERIFICATION_SHA = "ddcd2dd519777e56e7fca1d5ee8849f58d8939bbe0c795aaa36e5f5636ba777f"
ENTRY_TARGET = "maps/ws4_entry.vpk"
ENTRY_SHA = "abce9c7f6a1159303c799ec9a8b40afa7f724e7bf4c52509038e490afa67fecb"

for name in ("ITEM", "SEQUENCE", "FILE_COUNT", "CONTENT", "CANDIDATE", "TRUSTED", "VPK", "REPORT", "STATE", "OUTPUT", "MINIMUM_REMOTE_UPDATED"):
    setattr(protocol, name, globals()[name])
_verified_local_inputs = protocol.local_inputs


def require_package_pins():
    need(all(protocol.sha_pin(value) for value in (
             CONTENT, REPORT_SHA, INDEX_SHA, MAP_COMPILED_SHA, COMPILE_LOG_SHA, MAP_VERIFICATION_SHA))
         and type(TOTAL_BYTES) is int and TOTAL_BYTES > 0
         and type(MAP_COMPILED_BYTES) is int and MAP_COMPILED_BYTES > 0,
         "map_resources_completed_package_pins_not_yet_finalized")


def verify_completed_report(inputs):
    report = inputs["report"]
    need(inputs["report_sha256"] == REPORT_SHA and report.get("vpk_sha256") == INDEX_SHA
         and inputs["total"] == TOTAL_BYTES, "map_resources_completed_package_pin_mismatch")
    need(report.get("status") == "BUILT_SIGNED_MAP2802_REQUIRES_NATIVE_MAP_TEST"
         and report.get("full_view_canonical_guard") == "PASS"
         and report.get("canonical_single_map") is True and report.get("canonical_reviewed_gate") is True
         and report.get("immutable_base_unchanged") is True
         and report.get("qr_fix_preserved") is True and report.get("layout_fix_preserved") is True
         and report.get("authentication_payment_gameplay_code_preserved") is True
         and report.get("base_release_sequence") == 2026102801
         and report.get("base_content_sha256") == "f20c64b00da4e9d9f1a93bd7fca23163aa3f8b203e9ae354de5f60d9a8c75503"
         and report.get("changed_runtime_paths") == [MAP_TARGET]
         and report.get("deleted_runtime_paths") == [] and report.get("added_runtime_paths") == []
         and report.get("source_sha256") == MAP_SOURCE_SHA and report.get("compile_log_sha256") == COMPILE_LOG_SHA
         and report.get("source_crc32") == MAP_SOURCE_CRC
         and report.get("map_package_verification_sha256") == MAP_VERIFICATION_SHA
         and type(report.get("map_package_crc_entries_verified")) is int
         and report["map_package_crc_entries_verified"] == MAP_CRC_ENTRIES
         and report.get("map_compiled_source_crc_verified") is True
         and report.get("trusted_gate_files") == 14 and report.get("trusted_review_files") == 16
         and report.get("protected_modules_preserved") == 180 and report.get("protected_modules_rebuilt") == 0,
         "map_resources_complete_view_canonical_and_protection_verification_required")
    rows = {row["path"]: row for row in inputs["manifest"]["files"]}
    need(rows.get(MAP_TARGET, {}).get("sha256") == MAP_COMPILED_SHA
         and rows.get(MAP_TARGET, {}).get("bytes") == MAP_COMPILED_BYTES
         and rows.get(ENTRY_TARGET, {}).get("sha256") == ENTRY_SHA
         and "maps/template_map.vmap" not in rows, "map_resources_signed_map_entry_or_source_scope_changed")


def verify_map_compile_evidence(inputs):
    raw = protocol.read_snapshot(MAP_VERIFICATION, api.pack.MAX_MANIFEST, inputs["snapshots"])
    need(hashlib.sha256(raw).hexdigest() == MAP_VERIFICATION_SHA, "map_resources_map_crc_evidence_changed")
    proof = api.pack.handoff.decode_json(raw)
    source, package, match = [proof.get(key, {}) for key in ("source", "package", "source_match")]
    entries = package.get("entries")
    need(proof.get("status") == "PASS" and proof.get("compiled_verified") is True
         and source.get("sha256") == MAP_SOURCE_SHA and source.get("raw_crc32") == MAP_SOURCE_CRC
         and source.get("converted") is False
         and package.get("sha256") == MAP_COMPILED_SHA and package.get("bytes") == MAP_COMPILED_BYTES
         and package.get("version") == 2 and type(package.get("crc_entries")) is int
         and package["crc_entries"] == MAP_CRC_ENTRIES
         and isinstance(entries, list) and len(entries) == package["crc_entries"]
         and all(row.get("crc_matches") is True and type(row.get("expected_crc32")) is int
                 and type(row.get("actual_crc32")) is int
                 and 0 <= row["expected_crc32"] <= 0xffffffff
                 and row["expected_crc32"] == row["actual_crc32"] for row in entries)
         and match.get("source_name") == "maps/template_map.vmap" and match.get("matches") is True
         and match.get("raw_source_crc32") == match.get("compiled_source_crc32") == MAP_SOURCE_CRC
         and proof.get("compiled_map", {}).get("path") == "maps/template_map.vmap_c",
         "map_resources_actual_map_crc_and_source_match_evidence_required")


def verify_review_sources(inputs):
    need(len(TRUST_NAMES) == len(set(TRUST_NAMES)) == 14, "native_cloud_review_scope_changed")
    trusted = api.pack.handoff.regular_path(TRUSTED)
    need(protocol.incremental.all_files(trusted) == set(TRUST_NAMES) | {QR_SOURCE_REL, LAYOUT_SOURCE_REL}, "native_cloud_review_directory_inventory_changed")
    rows = {row["path"]: row for row in inputs["manifest"]["files"]}
    snapshots = inputs["snapshots"]
    for relative in TRUST_NAMES:
        raw = protocol.read_snapshot(api.pack.protect_data.source_path(trusted, relative), api.pack.MAX_MANIFEST, snapshots)
        if relative.startswith("scripts/"):
            need(relative in rows and hashlib.sha256(raw).hexdigest() == rows[relative]["sha256"],
                 "native_cloud_review_source_differs_from_signed_runtime")
    qr_source = protocol.read_snapshot(api.pack.protect_data.source_path(trusted, QR_SOURCE_REL), api.pack.MAX_MANIFEST, snapshots)
    need(hashlib.sha256(qr_source).hexdigest() == QR_SOURCE_SHA and QR_SOURCE_REL not in rows
         and rows.get(QR_TARGET, {}).get("sha256") == QR_COMPILED_SHA, "map2802_previous_qr_fix_changed")
    need(LAYOUT_SOURCE_REL not in rows and rows.get(LAYOUT_TARGET, {}).get("sha256") == LAYOUT_COMPILED_SHA,
         "map2802_compiled_checkout_identity_or_source_exclusion_changed")
    source = protocol.read_snapshot(api.pack.protect_data.source_path(trusted, LAYOUT_SOURCE_REL), api.pack.MAX_MANIFEST, snapshots)
    need(hashlib.sha256(source).hexdigest() == LAYOUT_SOURCE_SHA, "map2802_reviewed_checkout_source_changed")
    publisher = protocol.read_snapshot(Path(api.pack.handoff.__file__), api.pack.MAX_MANIFEST, snapshots)
    need(hashlib.sha256(publisher).hexdigest() == PUBLISHER_SHA, "native_cloud_canonical_publisher_changed")
    frozen = protocol.read_snapshot(PROTOCOL_FILE, api.pack.MAX_MANIFEST, snapshots)
    need(hashlib.sha256(frozen.replace(b"\r\n", b"\n")).hexdigest() == PROTOCOL_LF_SHA,
         "native_cloud_download_protocol_changed_after_import")
    validator=protocol.read_snapshot(RUNTIME_VALIDATOR_FILE,api.pack.MAX_MANIFEST,snapshots)
    need(hashlib.sha256(validator.replace(b"\r\n",b"\n")).hexdigest()==RUNTIME_VALIDATOR_LF_SHA,
         "native_cloud_production_profile_parser_changed_after_import")


def local_inputs(require_success=False, *, full=False):
    require_package_pins()
    inputs = _verified_local_inputs(require_success, full=full)
    verify_completed_report(inputs)
    verify_review_sources(inputs)
    verify_map_compile_evidence(inputs)
    # The protocol considers only top-level manifest fields when this exact
    # 2802 upload journal matches owner/item/signed bytes and five-file inventory.
    # It never imports manifests from release_history or previous_release.
    protocol.unchanged(inputs["snapshots"])
    return inputs


protocol.local_inputs = local_inputs


def main(argv=None):
    return protocol.main(argv)


if __name__ == "__main__":
    raise SystemExit(main())
