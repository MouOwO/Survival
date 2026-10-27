"""Verify only the official native-cloud 2708 download; no default Steam call.

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
spec = importlib.util.spec_from_file_location("private_native_cloud_download_protocol", PROTOCOL_FILE)
protocol = importlib.util.module_from_spec(spec)
spec.loader.exec_module(protocol)
callbacks, api, need = protocol.callbacks, protocol.api, protocol.need

ITEM, SEQUENCE, FILE_COUNT = "3824360109", 2026102708, 6658
CONTENT = "55d9e63ea1c95bed2456c739c0cf0e3148030e91a43f3a0d72aeaf64ab540e26"
CANDIDATE = Path("D:/Survival_发布候选/20261027_ws4_native_cloud_v02_view")
TRUSTED = Path("D:/Survival_发布候选/20261027_ws4_native_cloud_v02_overlay_trusted_source")
VPK = Path("D:/Survival_工坊输出/20261027_ws4_native_cloud_v02/3824360109.vpk")
REPORT = ROOT / "output/native_arcade_cloud_20261027/native_cloud_v02_package.json"
STATE = ROOT / "output/four_accounts_20261022/steam_upload_state.json"
OUTPUT = ROOT / "output/native_arcade_cloud_20261027/download_evidence_v02"
MINIMUM_REMOTE_UPDATED = 1793069949  # Actual verified native05 publication, not a predicted new timestamp.

# Fill only from the completed real 2708 package, before enabling --download.
# No CLI option can provide a replacement hash, release identity or manifest.
REPORT_SHA = "0eada1ac04619d99330595b878139757802627d0aff948bd460dccf05a5f6ba4"
INDEX_SHA = "a2d87c0daf0100af0fecce2b9056a20041ce84a38b53af62ae00f7a9bca31e91"
TOTAL_BYTES = 3767360950
TRUST_NAMES = (*api.pack.handoff.GATE_FILES, *api.pack.handoff.ENTRY_GATE_FILES,
    api.pack.handoff.ACCESS_FILE, "tools/release_security/protection_policy.json",
    "tools/release_security/trusted_public_key.pem", *api.pack.handoff.NATIVE_CLOUD_ENTRY_GATE_FILES[:2])

for name in ("ITEM", "SEQUENCE", "FILE_COUNT", "CONTENT", "CANDIDATE", "TRUSTED", "VPK", "REPORT", "STATE", "OUTPUT", "MINIMUM_REMOTE_UPDATED"):
    setattr(protocol, name, globals()[name])
_verified_local_inputs = protocol.local_inputs


def require_package_pins():
    need(protocol.sha_pin(REPORT_SHA) and protocol.sha_pin(INDEX_SHA)
         and type(TOTAL_BYTES) is int and TOTAL_BYTES > 0,
         "native_cloud_completed_package_pins_not_yet_finalized")


def verify_completed_report(inputs):
    report = inputs["report"]
    need(inputs["report_sha256"] == REPORT_SHA and report.get("vpk_sha256") == INDEX_SHA
         and inputs["total"] == TOTAL_BYTES,
         "native_cloud_completed_package_pin_mismatch")
    need(report.get("status") == "BUILT_AND_VERIFIED_NATIVE_CLOUD_REQUIRES_NATIVE_TEST"
         and report.get("full_view_canonical_guard") == "PASS"
         and report.get("canonical_single_map") is True and report.get("canonical_reviewed_gate") is True
         and report.get("immutable_base_unchanged") is True
         and report.get("native_cloud_roster_required") is True
         and report.get("protected_modules_preserved") == 180 and report.get("protected_modules_rebuilt") == 0,
         "native_cloud_complete_view_canonical_and_protection_verification_required")


def verify_review_sources(inputs):
    need(len(TRUST_NAMES) == len(set(TRUST_NAMES)) == 14, "native_cloud_review_scope_changed")
    trusted = api.pack.handoff.regular_path(TRUSTED)
    need(protocol.incremental.all_files(trusted) == set(TRUST_NAMES), "native_cloud_review_directory_inventory_changed")
    rows = {row["path"]: row for row in inputs["manifest"]["files"]}
    snapshots = inputs["snapshots"]
    for relative in TRUST_NAMES:
        raw = protocol.read_snapshot(api.pack.protect_data.source_path(trusted, relative), api.pack.MAX_MANIFEST, snapshots)
        if relative.startswith("scripts/"):
            need(relative in rows and hashlib.sha256(raw).hexdigest() == rows[relative]["sha256"],
                 "native_cloud_review_source_differs_from_signed_runtime")
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
    # The protocol considers only top-level manifest fields when this exact
    # 2708 upload journal matches owner/item/signed bytes and five-file inventory.
    # It never imports manifests from release_history or previous_release.
    protocol.unchanged(inputs["snapshots"])
    return inputs


protocol.local_inputs = local_inputs


def main(argv=None):
    return protocol.main(argv)


if __name__ == "__main__":
    raise SystemExit(main())
