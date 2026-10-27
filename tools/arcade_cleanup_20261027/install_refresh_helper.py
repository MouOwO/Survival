"""Install the signed refresh thin overlay into the fixed helper; audit by default.

The existing transaction engine owns backups, compare-and-swap, recovery and
strict rollback. Only authenticated release input assembly differs. No full
candidate view, private key, launch, Steam update or cloud write is needed.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / "arcade_payment_link_20261027"))
import patch_helper_policy as policy_patch
sys.path.insert(0, str(HERE))
import incremental_vpk as frozen

# Independent module globals: never retarget a previously imported installer.
spec = importlib.util.spec_from_file_location("refresh_helper_transaction_core",
    HERE.parent / "arcade_payment_link_20261027/install_helper.py")
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
web, pack, need = engine.web, engine.pack, engine.need
TARGET = ROOT.parent / "svt_w24"
OVERLAY = Path("D:/Survival_发布候选/20261027_ws4_refresh_helper_v04_overlay")
TRUSTED = OVERLAY.with_name(OVERLAY.name + "_trusted_source")
OLD_SHA = "8f7c7956fc4e50a2c5865442dbfc379e43d3c3de513a4e921a241d8206cfb664"
OLD_SEQUENCE, OLD_COUNT = 2026102702, 6639
OLD_MARKER_SHA = "845ab1ceb93c3c5543c19c534f2aed61793b3bcc5c325b2216c1a1cb6fa9f352"
SEQUENCE, COUNT = 2026102706, 6655
# Reviewed helper04 projection from the official corrected-wallet receipt.
NEW_SHA = "c7264a14a09a8bc9961578213b85c4e7c1b829e16eacc045e4fe4672f71a7872"
STORE = ROOT / "output/arcade_cleanup_20261027/helper04_alias_transactions"
DELETED_CSS = "panorama/styles/custom_game/commerce_wallet.vcss_c"


def fixed_paths():
    need(TARGET.absolute() == (ROOT.parent / "svt_w24").absolute()
         and STORE.absolute() == (ROOT / "output/arcade_cleanup_20261027/helper04_alias_transactions").absolute()
         and engine.SHARED.absolute() == (ROOT / "output/ui_qa_20261025/release/alias_updates").absolute(),
         "refresh_helper_paths_not_fixed")
    target = engine.regular(TARGET)
    need(target.is_dir(), "refresh_helper_target_missing")
    return target


def source(root, name):
    # Immutable SHOP02 may now have read-only hardlink names in another frozen
    # candidate. Its bytes are hashed, never written. Alias/overlay/backup paths
    # retain the transaction engine's stricter no-hardlink rule.
    return pack.protect_data.source_path(root, name)


def old_release():
    original, signed, metadata = policy_patch.authenticate_base()
    raw, old, patch_snapshot = policy_patch.read_patch(original, metadata)
    need(old["content_sha256"] == OLD_SHA and old["file_count"] == OLD_COUNT,
         "refresh_helper_old_identity_changed")
    need(policy_patch.SEQUENCE == OLD_SEQUENCE, "refresh_helper_old_sequence_changed")
    return old, metadata, patch_snapshot


def input_paths():
    need(OVERLAY == Path("D:/Survival_发布候选/20261027_ws4_refresh_helper_v04_overlay")
         and TRUSTED == OVERLAY.with_name(OVERLAY.name + "_trusted_source"),
         "refresh_helper_input_paths_not_fixed")


def helper_guards(sources, old, new):
    rows = {r["path"]: r for r in new["files"]}
    def root_for(name):
        path = sources[name]
        return path.parents[len(Path(name).parts) - 1]
    profile = pack.runtime.RELEASE_PROFILE
    pack.runtime.require_production(root_for(profile))
    pack.handoff.require_single_map(root_for("addoninfo.txt"))
    info = pack.handoff.kv(sources["addoninfo.txt"].read_text(encoding="utf-8-sig"))["addoninfo"]
    need(info["maps"] == "template_map", "refresh_helper_wrong_map")
    maps = pack.runtime.map_files(root_for("addoninfo.txt"))
    need(pack.runtime.CRITICAL | maps <= rows.keys(), "refresh_helper_missing_required_runtime")
    for name in rows:
        parts = Path(name).parts
        allowed = name in pack.runtime.EXACT | pack.runtime.OPTIONAL_EXACT | maps or any(
            name.startswith(folder + "/") and Path(name).suffix.lower() in extensions
            for folder, extensions in pack.runtime.RULES.items())
        need(allowed and name not in pack.runtime.EXCLUDED_EXACT
             and not any(part in pack.runtime.BLOCKED_PARTS or part.startswith(".") for part in parts),
             "refresh_helper_outside_runtime_policy")
    need(set(pack.handoff.configured_ids(root_for(pack.handoff.ACCESS_FILE))) == engine.ROSTER,
         "refresh_helper_four_accounts_required")
    engine.literal_config(root_for("scripts/vscripts/config/player_web_auth.lua"),
        "scripts/vscripts/config/player_web_auth.lua", {
            "enabled": True, "base_url": "https://pay.xiaofengnet.com/ws4-web"})
    engine.literal_config(root_for("scripts/vscripts/config/session_multiplayer_test.lua"),
        "scripts/vscripts/config/session_multiplayer_test.lua", {
            "enabled": False, "expected_map": "template_map"})
    engine.literal_config(root_for("scripts/vscripts/config/commerce_payment_access.lua"),
        "scripts/vscripts/config/commerce_payment_access.lua", {
            "enabled": True, "connection_helper": True, "expected_map": "template_map",
            "base_url": "https://pay.xiaofengnet.com/ws4-web"})
    policy = pack.handoff.load_json(ROOT / "tools/lua_protection_policy.json")
    need(web.sha(pack.runtime.canonical_bytes(policy)) == engine.LUA_POLICY_SHA,
         "refresh_helper_protection_policy_changed")
    web.protect_runtime_lua.check_policy(policy)
    old_rows = {r["path"]: r for r in old["files"]}
    sets = [{r["path"] for r in web.protect_runtime_lua.selected_files(list(doc), policy)}
            for doc in (old_rows, rows)]
    need(sets[0] == sets[1] and len(sets[0]) == 180
         and all(old_rows[name] == rows[name] for name in sets[0]),
         "refresh_helper_protected_modules_changed")
    name = "scripts/vscripts/core/release_policy.lua"
    need(old_rows[name] == rows[name], "refresh_helper_debug_policy_changed")


def releases():
    need(isinstance(NEW_SHA, str) and re.fullmatch(r"[0-9a-f]{64}", NEW_SHA),
         "refresh_helper_new_identity_not_pinned")
    input_paths()
    old, old_metadata, old_patch_snapshot = old_release()
    with frozen.trusted_source(frozen.BASE_TRUSTED):
        _, base, base_signed, base_metadata = pack.authenticate(frozen.BASE)
    need(base["content_sha256"] == frozen.BASE_CONTENT and base["file_count"] == frozen.BASE_COUNT
         and base_signed["release_sequence"] == frozen.BASE_SEQUENCE,
         "refresh_helper_fallback_identity_changed")
    new, document, metadata = frozen.metadata(OVERLAY)
    need(new["content_sha256"] == NEW_SHA and new["file_count"] == COUNT,
         "refresh_helper_new_identity_changed")
    need(engine.inventory(TRUSTED) == set(engine.trust_names()), "refresh_helper_trusted_inventory_changed")
    for name in web.POLICY_FILES:
        need(engine.file_path(TRUSTED, name).read_bytes() == engine.file_path(ROOT, name).read_bytes(),
             "refresh_helper_public_trust_changed")
    with web.trusted_root(TRUSTED):
        policy, public = pack.handoff.trusted_policy(pack.handoff.POLICY)
        signature = pack.verify_signed_snapshot(new, document, public,
            policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
    need(signature["signature_valid"] is True and signature["release_sequence"] == SEQUENCE
         and signature["key_id"] == base_signed["key_id"], "refresh_helper_new_signature_changed")
    # This validates every raw source with MD5/SHA256/length and exact thin
    # inventory; deleted rows intentionally have no fallback in the new image.
    sources, changed = frozen.validate_merged(frozen.BASE, OVERLAY, base, new, TRUSTED)
    need(engine.inventory(OVERLAY) == changed | set(engine.METADATA),
         "refresh_helper_overlay_inventory_changed")
    for name in (*pack.handoff.GATE_FILES, *pack.handoff.ENTRY_GATE_FILES, pack.handoff.ACCESS_FILE):
        need(name in sources and source(TRUSTED, name).read_bytes() == sources[name].read_bytes(),
             "refresh_helper_reviewed_gate_changed")
    helper_guards(sources, old, new)
    before, after = ({r["path"]: r for r in doc["files"]} for doc in (old, new))
    modified = {name for name in before.keys() & after.keys() if before[name] != after[name]}
    added, removed = set(after.keys() - before.keys()), set(before.keys() - after.keys())
    need(removed == {DELETED_CSS}, "refresh_helper_removed_scope_changed")
    need(engine.MARKER not in before and engine.MARKER not in after
         and not (engine.METADATA | engine.CACHES) & (before.keys() | after.keys()),
         "refresh_helper_runtime_metadata_forbidden")
    patches = {name: sources[name].read_bytes() for name in modified | added}
    for name, raw in patches.items():
        need(engine.row_bytes(raw) == engine.row_only(after[name]), "refresh_helper_payload_changed")
    pack.inventory_unchanged(frozen.BASE, base_metadata)
    policy_patch.unchanged(old_metadata, old_patch_snapshot)
    pack.inventory_unchanged(OVERLAY, metadata)
    return dict(old=old, new=new, base=policy_patch.BASE, candidate=OVERLAY,
        old_metadata=old_metadata, metadata=metadata, patches=patches,
        old_rows=before, new_rows=after, modified=modified, added=added, removed=removed,
        controlled=modified | added | removed | {engine.MARKER})


def configure():
    engine.ROOT, engine.TARGET = ROOT, TARGET
    engine.BASE_SHA, engine.BASE_SEQUENCE, engine.BASE_FILES = OLD_SHA, OLD_SEQUENCE, OLD_COUNT
    engine.CANDIDATE_SHA, engine.RELEASE_SEQUENCE, engine.EXPECTED_FILES = NEW_SHA, SEQUENCE, COUNT
    engine.OLD_MARKER_SHA, engine.STORE = OLD_MARKER_SHA, STORE
    engine.releases, engine.fixed_paths = releases, fixed_paths


def run(*, apply=False, restore=False):
    configure()
    result = engine.run(apply=apply, restore=restore)
    result.update(thin_overlay=True, full_candidate_view_created=False,
                  removed_runtime_paths=[DELETED_CSS], workshop_upload_performed=False)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--apply", action="store_true")
    modes.add_argument("--rollback", dest="restore", action="store_true")
    args = parser.parse_args()
    try:
        report = run(apply=args.apply, restore=args.restore)
    except engine.TransactionFailure as error:
        report = error.report
    except Exception as error:
        report = dict(ok=False, error=engine.error_code(error), changed=False, private_key_read=False)
    print(json.dumps(report, ensure_ascii=True))
    return 0 if report["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
