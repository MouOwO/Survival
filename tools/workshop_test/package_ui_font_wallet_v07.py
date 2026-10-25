"""Read-only plan, or explicitly package the pinned v07 for the original item.

The frozen trust snapshot is accepted only after its complete public inventory
matches these reviewed hashes and the unchanged signed v06/v07 gates. Existing
packager authentication, admission, full-file and VPK guards remain in force.
No signing key, Steam API, alias, listing or publication journal is accessed.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_archive_font_candidate as builder

web, pack, ROOT = builder.web, builder.pack, builder.ROOT
CANDIDATE = Path("D:/Survival_发布候选/20261025_ws4_ui_font_wallet_v07")
TRUSTED = CANDIDATE.with_name(CANDIDATE.name + "_trusted_source")
CANDIDATE_SHA = "811170a2c77396faee948bf7a77021fe8ac07c2117a919a6c3eb7163e4525e7e"
OUTPUT = Path("D:/Survival_工坊输出/20261025_ws4_ui_font_wallet_v07")
WORKSHOP_ID = "3824360109"
BASE_SHA = "1dd9d88f885f8e1617985f933bbdb450884f91a7cdb96b10e0315d2b0cdaa884"
ALLOWLIST = frozenset({"panorama/scripts/custom_game/common/archive_font_v36.vjs_c",
                       "panorama/scripts/custom_game/daily_remaining_5d5c1152eb.vjs_c",
                       "panorama/scripts/custom_game/commerce_wallet.vjs_c"})
TRUST_PINS = {
    "scripts/vscripts/core/test_access_policy.lua": "fe6c77e68ef2806c948851c66943d141fc1af5d858eae0b502b4204860d0d681",
    "scripts/vscripts/addon_game_mode.lua": "32f371db9fc024710474e67818f360e0c8b0187bdc5189e4f76107871fface5e",
    "scripts/vscripts/systems/multiplayer_player_service.lua": "55aef4d45f1a2ad12fce95437547230f398455424c5244c9ae67f386deec0f29",
    "scripts/vscripts/systems/startup_loading_service.lua": "c0293001b2f1c85492b35cf28aff157e5d54ddbdcf00b3cbf7ccead0739d3a0d",
    "scripts/vscripts/systems/player_profile_service.lua": "ad2ba8edf96c45f8730df8f1d5289414f8e4f1a3bd05cd95827c9dc690e39a86",
    "scripts/vscripts/ui/ui_request_router.lua": "a2a1bba0a329daea539b89285fd93c7f1833a9f30e9b630167c0aafc2eb297fc",
    "scripts/vscripts/core/event_bus.lua": "316d424fc50cd86e639eb29c83cda3bcc4cc688fb10ac4954a86cbfd916d8cf9",
    "scripts/vscripts/systems/workshop_entry.lua": "1afaa3f740a2b3c5c53c8f802ec244f3b20e277f13f20157175088edaecc4fcc",
    "scripts/vscripts/addon_game_mode_client.lua": "db095896002b6f63b47484908285448c9ca2bdae70f2dce718ab2d53b02e3fd8",
    "scripts/vscripts/config/test_access.lua": "c8b3280e51afa1ffac0f7ed87bdc7823fc18cad190a906970f3a063f6c9e7e06",
    "tools/release_security/protection_policy.json": "8e8c2e50a6a983dda7336a083377bbf55de8625f89f5633977c8d7901b53da96",
    "tools/release_security/trusted_public_key.pem": "1717c28cb7476e5eb5326b780589c880e86d42cc026b6d4728d95ac95e8873bf",
}


def need(value, message):
    if not value:
        raise ValueError(message)


def trust_names():
    names = (*pack.handoff.GATE_FILES, *pack.handoff.ENTRY_GATE_FILES,
             pack.handoff.ACCESS_FILE, *web.POLICY_FILES)
    need(len(names) == len(set(names)) == 12 and set(names) == set(TRUST_PINS),
         "v07_package_trust_inventory_changed")
    return names


def snapshot_trust():
    """Do this before letting either snapshot supply authentication policy."""
    names, snapshots = trust_names(), {}
    for directory in (builder.BASE_TRUSTED, TRUSTED):
        directory = pack.handoff.regular_path(directory)
        need(directory.is_dir(), "v07_package_trust_directory_invalid")
        found = set()
        for path in directory.rglob("*"):
            need(not pack.protect_data.linked(path), "v07_package_trust_link_forbidden")
            if path.is_file():
                found.add(path.relative_to(directory).as_posix())
        need(found == set(names), "v07_package_trust_inventory_changed")
        for name in names:
            path = pack.protect_data.source_path(directory, name)
            raw = path.read_bytes()
            need(web.sha(raw) == TRUST_PINS[name], "v07_package_trust_hash_changed:" + name)
            snapshots[path] = raw
    # A candidate-supplied public key cannot redefine trust. Both public files
    # must also match the original reviewed checkout's pinned policy/key.
    for name in web.POLICY_FILES:
        path = pack.protect_data.source_path(ROOT, name)
        raw = path.read_bytes()
        need(web.sha(raw) == TRUST_PINS[name], "v07_package_checkout_trust_changed:" + name)
        snapshots[path] = raw
    for directory in (builder.BASE, CANDIDATE):
        for name in set(names) - set(web.POLICY_FILES):
            path = pack.protect_data.source_path(directory, name)
            raw = path.read_bytes()
            need(web.sha(raw) == TRUST_PINS[name], "v07_package_signed_gate_changed:" + name)
            snapshots[path] = raw
    return snapshots


def unchanged(snapshots):
    for path, raw in snapshots.items():
        need(pack.protect_data.source_path(path.parent, path.name).read_bytes() == raw,
             "v07_package_reviewed_input_changed")


def authenticate_release():
    snapshots = snapshot_trust()
    base, old, old_signature = builder.authenticate_base()
    need(old["content_sha256"] == BASE_SHA and old["file_count"] == 6630
         and old_signature["release_sequence"] == 2026102501,
         "v07_package_ancestor_identity_mismatch")
    with web.trusted_root(TRUSTED):
        candidate, new, signature, signed_snapshots = pack.authenticate(CANDIDATE)
    need(new["content_sha256"] == CANDIDATE_SHA and new["file_count"] == 6630,
         "v07_package_candidate_identity_mismatch")
    need(signature["release_sequence"] == 2026102502
         and signature["key_id"] == old_signature["key_id"]
         and signature["signature_valid"] is True, "v07_package_signature_identity_mismatch")
    protected = builder.protected_paths(old)
    need(len(protected) == len(set(protected)) == 180 and builder.ALLOWLIST == ALLOWLIST,
         "v07_package_protected_or_change_scope_mismatch")
    source_snapshots, patches = builder.capture_inputs(builder.COMPILE_REPORT)
    changes = builder.audit_changes(old, new, patches, protected)
    pack.runtime.require_production(candidate)
    need(pack.handoff.configured_ids(base) == pack.handoff.configured_ids(candidate),
         "v07_package_test_accounts_changed")
    snapshots.update(source_snapshots)
    # pack.authenticate returns raw, bounded manifest/signature snapshots.
    snapshots.update({candidate / name: raw for name, raw in signed_snapshots.items()})
    unchanged(snapshots)
    return new, signature, changes, snapshots


def package(*, build=False):
    output = pack.handoff.regular_path(OUTPUT)
    need(output.is_dir() and not any(output.iterdir()), "v07_package_output_must_be_empty")
    for protected in (ROOT, pack.handoff.INSTALL, builder.BASE, builder.BASE_TRUSTED, CANDIDATE, TRUSTED):
        need(not pack.runtime.within(output, protected) and not pack.runtime.within(protected, output),
             "v07_package_output_overlap")
    manifest, signature, changes, snapshots = authenticate_release()
    # The existing packager still independently authenticates every candidate
    # byte and calls its original gate validator in this bounded trust context.
    with web.trusted_root(TRUSTED):
        result = pack.package(CANDIDATE, output, WORKSHOP_ID, build=build)
    unchanged(snapshots)
    need(result["content_sha256"] == manifest["content_sha256"] == CANDIDATE_SHA
         and result["release_sequence"] == signature["release_sequence"] == 2026102502
         and result["files"] == 6630 and result["signature_valid"] is True
         and result["payload_changed"] is False and result["workshop_upload_performed"] is False
         and result["dry_run"] is (not build), "v07_package_packager_identity_mismatch")
    result.update(ok=True, revision=builder.REVISION,
                  base_content_sha256=builder.BASE_SHA, changed_paths=sorted(builder.ALLOWLIST),
                  reviewed_changes=changes, protected_modules_preserved=180,
                  trusted_snapshot_files=len(TRUST_PINS), trusted_snapshot_hashes_verified=True,
                  checkout_public_policy_hashes_verified=True, existing_packager_guards_preserved=True,
                  alias_install_performed=False, game_started=False, private_key_read=False,
                  listing_changed=False, publication_journal_changed=False)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true", help="Create only new VPK files in the fixed empty external directory")
    args = parser.parse_args()
    try:
        result = package(build=args.build)
    except Exception as error:
        result = dict(ok=False, error=str(error), status="BLOCKED_PRESERVE_EXISTING_ARTIFACTS",
                      workshop_upload_performed=False, alias_install_performed=False, game_started=False)
    print(json.dumps(result, ensure_ascii=True))
    return 0 if result["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
