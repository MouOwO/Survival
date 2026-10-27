"""One-file signed helper policy patch; default is a read-only plan.

The immutable v01 candidate supplies every unchanged runtime byte. The patch
contains only one policy, a full Ed25519 manifest/signature and a base reference.
Never copies/hardlinks the full runtime, uploads, launches, or creates orders.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import install_helper as install

web, pack = install.web, install.pack
ROOT, TARGET = install.ROOT, install.TARGET
BASE, TRUSTED = install.CANDIDATE, install.TRUSTED
BASE_SHA, BASE_SEQUENCE, COUNT = install.CANDIDATE_SHA, 2026102701, 6639
SEQUENCE = 2026102702
POLICY = "scripts/vscripts/core/commerce_release_policy.lua"
POLICY_SHA = "6da29c9e100c9bb7c591d7a44b7a333dacad2a7895b98fdf4d1c1415e8afe1c2"
OLD_POLICY_SHA = "2865bc9c4752cf2978481eb1d3e2da13939d876aad5636f7347073628718d0ce"
OLD_MARKER_SHA = "5e531a24b8c55cf97f79becc70d051ee6c5c40164378cc188675b41b4e38ac13"
PATCH = Path("D:/Survival_发布候选/20261027_ws4_payment_helper_policy_v02_patch")
REFERENCE = "_patch_base.json"
STORE = ROOT / "output/arcade_payment_link_20261027/policy_patch_transactions"
LUA = Path("C:/Program Files/lua/bin/lua5.1.exe")
need, regular, path_at = install.need, install.regular, install.file_path
canonical, row_bytes, require_row = install.canonical, install.row_bytes, install.require_row


def rows(document):
    pack.runtime.validate_manifest(document)
    return {row["path"]: row for row in document["files"]}


def policy_source():
    # Git may restore Lua sources with CRLF. The reviewed patch ships LF bytes;
    # this normalization applies only to its worktree input, never signed bases,
    # patch metadata, installed files, backups or compare-and-swap preimages.
    return path_at(ROOT, POLICY).read_bytes().replace(b"\r\n", b"\n")


def project(old, raw):
    before = rows(old)
    need(old["content_sha256"] == BASE_SHA and old["file_count"] == COUNT and POLICY in before,
         "policy_patch_base_identity_changed")
    need(before[POLICY]["sha256"] == OLD_POLICY_SHA and web.sha(raw) == POLICY_SHA,
         "policy_patch_reviewed_policy_changed")
    result = {key: old[key] for key in ("schema", "kind", "hash_algorithms")}
    result["files"] = [dict(row, **row_bytes(raw)) if row["path"] == POLICY else dict(row) for row in old["files"]]
    result.update(file_count=COUNT, bytes=sum(row["bytes"] for row in result["files"]))
    result["content_sha256"] = web.sha(pack.runtime.manifest_payload(result))
    after = rows(result)
    need(set(before) == set(after) and {name for name in before if before[name] != after[name]} == {POLICY},
         "policy_patch_single_file_scope_changed")
    return result


def preflight(raw, manifest):
    need(web.sha(raw) == POLICY_SHA and b"-----BEGIN " not in raw and b"Bearer " not in raw,
         "policy_patch_reviewed_policy_changed")
    need("scripts/vscripts/debug/offline_logic_test.lua" not in rows(manifest),
         "policy_patch_expected_production_debug_absence_changed")
    need(b'require("debug/' not in raw and b"require('debug/" not in raw,
         "policy_patch_optional_debug_must_not_be_required")
    checked = subprocess.run([str(web.LUA_COMPILER), "-p", "-"], input=raw, capture_output=True, timeout=20)
    need(checked.returncode == 0, "policy_patch_lua_syntax_failed")
    # Isolated policy execution only. No game/backend/merchant/network fixture.
    prefix = b'''package.path=""
local modules={
 ["core/release_policy"]={is_production=function()return true end,development_allowed=function()return false end},
 ["config/commerce_payment_access"]={enabled=true,connection_helper=true,expected_map="template_map",base_url="https://pay.xiaofengnet.com/ws4-web"},
 ["config/player_web_auth"]={enabled=true,base_url="https://pay.xiaofengnet.com/ws4-web"},
 ["core/test_access_policy"]={enabled=function()return true end,init=function()return true end},
 ["config/test_access"]={enabled=true,allowed_steamids={"76561198424163156","76561198845461206","76561198104787442","76561198974301984"}}
}
require=function(name)assert(not name:match("^debug/"),"optional debug absent");return assert(modules[name],name)end
IsServer=function()return true end;IsInToolsMode=function()return true end;GetMapName=function()return "template_map" end
local policy=assert(loadstring([====[
'''
    need(b"]====]" not in raw, "policy_patch_lua_delimiter_invalid")
    script = prefix + raw + b'\n]====]))()\nassert(policy.real_money_allowed()==true,"helper policy blocked")\nprint("PRODUCTION_DEBUG_ABSENCE_OK")\n'
    checked = subprocess.run([str(LUA), "-"], input=script, capture_output=True, timeout=20)
    need(checked.returncode == 0 and checked.stdout.strip() == b"PRODUCTION_DEBUG_ABSENCE_OK",
         "policy_patch_production_debug_absence_preflight_failed")


def authenticate_base():
    install.guard_release(BASE, TRUSTED, BASE_SHA, COUNT, "_payment_helper_provenance.json")
    with web.trusted_root(TRUSTED): base, manifest, signature, metadata = pack.authenticate(BASE)
    need(signature["signature_valid"] is True and signature["release_sequence"] == BASE_SEQUENCE,
         "policy_patch_base_signature_changed")
    pack.runtime.require_production(base)
    need(set(pack.handoff.configured_ids(base)) == install.ROSTER, "policy_patch_roster_changed")
    return manifest, signature, metadata


def reference(metadata):
    return dict(kind="WS4_SIGNED_ONE_FILE_POLICY_PATCH", base=str(BASE), base_content_sha256=BASE_SHA,
                base_release_sequence=BASE_SEQUENCE, release_sequence=SEQUENCE, runtime_files=COUNT,
                base_manifest_sha256=web.sha(metadata[pack.handoff.MANIFEST]),
                base_signature_sha256=web.sha(metadata[pack.handoff.SIGNATURE]),
                policy=POLICY, policy_sha256=POLICY_SHA)


def signature_for(manifest, document):
    with web.trusted_root(TRUSTED):
        trust, public = pack.handoff.trusted_policy(pack.handoff.POLICY)
        signature = pack.verify_signed_snapshot(manifest, document, public,
            trust["integrity"]["minimum_release_sequence"], trust["integrity"]["trusted_key_id"])
    need(signature["release_sequence"] == SEQUENCE, "policy_patch_signature_sequence_changed")
    return signature


def read_patch(old, metadata):
    need(install.inventory(PATCH) == {POLICY, REFERENCE, pack.handoff.MANIFEST, pack.handoff.SIGNATURE},
         "policy_patch_inventory_changed")
    raw = pack.read_metadata(path_at(PATCH, POLICY), 65536)
    manifest_raw = pack.read_metadata(path_at(PATCH, pack.handoff.MANIFEST), pack.MAX_MANIFEST)
    signature_raw = pack.read_metadata(path_at(PATCH, pack.handoff.SIGNATURE), pack.MAX_SIGNATURE)
    ref_raw = pack.read_metadata(path_at(PATCH, REFERENCE), 65536)
    need(pack.handoff.decode_json(ref_raw) == reference(metadata), "policy_patch_base_reference_changed")
    new = pack.handoff.decode_json(manifest_raw)
    need(pack.runtime.manifest_payload(new) == pack.runtime.manifest_payload(project(old, raw)),
         "policy_patch_full_manifest_changed")
    signature_for(new, pack.handoff.decode_json(signature_raw))
    preflight(raw, new)
    return raw, new, {POLICY:raw, REFERENCE:ref_raw, pack.handoff.MANIFEST:manifest_raw, pack.handoff.SIGNATURE:signature_raw}


def target_marker():
    raw = pack.read_metadata(path_at(TARGET, install.MARKER), 65536)
    value = pack.handoff.decode_json(raw)
    need(web.sha(raw) == OLD_MARKER_SHA and value.get("ok") is True
         and value.get("status") == "INSTALLED_FULLY_VERIFIED" and value.get("content_sha256") == BASE_SHA
         and value.get("release_sequence") == BASE_SEQUENCE and value.get("runtime_files") == COUNT
         and value.get("signature_valid") is True and value.get("full_after_verification") is True
         and value.get("online_cheats_allowed") is False, "policy_patch_alias_marker_changed")
    return raw


def unchanged(metadata, patch_snapshot=None):
    pack.inventory_unchanged(BASE, metadata)
    if patch_snapshot:
        for name, expected in patch_snapshot.items():
            need(path_at(PATCH, name).read_bytes() == expected, "policy_patch_input_changed")


def marker(new, identifier):
    return canonical(dict(ok=True, kind="verified_online_policy_install", status="INSTALLED_FULLY_VERIFIED",
        transaction_id=identifier, content_sha256=new["content_sha256"], base_content_sha256=BASE_SHA,
        release_sequence=SEQUENCE, runtime_files=COUNT, signature_valid=True, online_cheats_allowed=False,
        offline_logic_test=False, full_before_verification=True, full_after_verification=True,
        full_before=True, full_after=True, previous_marker_sha256=OLD_MARKER_SHA, patch=str(PATCH)))


def cas(path, before, raw, transaction):
    install.require_idle(); require_row(path, before)
    temporary = transaction / "work" / (uuid.uuid4().hex + ".tmp")
    install.write_new(temporary, raw)
    install.require_idle(); require_row(path, before)
    os.replace(temporary, path); require_row(path, row_bytes(raw))


def apply_patch(old, new, raw, metadata, snapshot):
    install.require_idle()
    need(TARGET.absolute() == (ROOT.parent / "svt_w24").absolute()
         and STORE.absolute() == (ROOT / "output/arcade_payment_link_20261027/policy_patch_transactions").absolute(),
         "policy_patch_fixed_target_required")
    old_marker = target_marker()
    install.verify_runtime(TARGET, old, old_marker)
    unchanged(metadata, snapshot)
    lock, lock_raw = install.acquire_lock()
    transaction = regular(STORE / uuid.uuid4().hex, exists=False)
    state = None; changed = False; outcome = None
    try:
        transaction.mkdir(parents=True, exist_ok=False)
        old_raw = path_at(TARGET, POLICY).read_bytes()
        require_row(path_at(TARGET, POLICY), rows(old)[POLICY])
        install.write_new(transaction / "backup" / POLICY, old_raw)
        install.write_new(transaction / "backup" / install.MARKER, old_marker)
        new_marker = marker(new, transaction.name)
        install.write_new(transaction / "plan.json", canonical(dict(old=BASE_SHA, new=new["content_sha256"],
            old_marker_sha256=OLD_MARKER_SHA, new_marker_sha256=web.sha(new_marker), release_sequence=SEQUENCE)))
        state = transaction / "state.json"
        install.write_new(state, canonical(dict(status="APPLYING", full_before_verification=True)))
        install.verify_runtime(TARGET, old, old_marker); unchanged(metadata, snapshot)
        cas(path_at(TARGET, POLICY), rows(old)[POLICY], raw, transaction); changed = True
        install.verify_runtime(TARGET, new, old_marker)
        signature_for(new, pack.handoff.decode_json(snapshot[pack.handoff.SIGNATURE]))
        unchanged(metadata, snapshot)
        cas(path_at(TARGET, install.MARKER), row_bytes(old_marker), new_marker, transaction)
        install.verify_runtime(TARGET, new, new_marker); install.require_idle()
        install.atomic_document(state, install.actual_row(state), canonical(dict(status="ACTIVE",
            full_after_verification=True, content_sha256=new["content_sha256"])), transaction)
        outcome = dict(ok=True, status="POLICY_PATCH_INSTALLED_FULLY_VERIFIED", transaction=str(transaction),
            content_sha256=new["content_sha256"], release_sequence=SEQUENCE, full_before_verification=True,
            full_after_verification=True, signature_valid=True, changed_paths=[POLICY,install.MARKER])
        return outcome
    except BaseException as error:
        recovery = "NO_RUNTIME_CHANGE"
        # Even a failed postimage verification cannot restore foreign bytes.
        try:
            current = install.actual_row(path_at(TARGET, POLICY))
            if current != install.row_only(rows(old)[POLICY]):
                need(current == row_bytes(raw), "policy_patch_recovery_cas_conflict")
                cas(path_at(TARGET, POLICY), current, path_at(transaction / "backup", POLICY).read_bytes(), transaction)
            current_marker = install.actual_row(path_at(TARGET, install.MARKER))
            if current_marker != row_bytes(old_marker):
                need(current_marker == row_bytes(new_marker), "policy_patch_recovery_marker_conflict")
                cas(path_at(TARGET, install.MARKER), current_marker, old_marker, transaction)
            install.verify_runtime(TARGET, old, old_marker)
            recovery = "V01_RESTORED_FULLY_VERIFIED" if changed else recovery
        except BaseException:
            recovery = "RECOVERY_REQUIRED"
        if state and state.exists():
            install.atomic_document(state, install.actual_row(state), canonical(dict(status=recovery)), transaction)
        raise install.TransactionFailure(error,"policy_patch",transaction,dict(status=recovery)) from None
    finally:
        install.release_lock(lock, lock_raw)


def run(*, build=False, apply=False, signing_key=None):
    need(not (build and apply), "policy_patch_conflicting_modes")
    if build: need(signing_key is not None and not PATCH.exists(), "policy_patch_new_directory_and_external_key_required")
    old, signed, metadata = authenticate_base()
    raw = policy_source()
    new = project(old, raw); preflight(raw, new)
    report = dict(ok=True, status="READ_ONLY_POLICY_PATCH_PLAN", base_content_sha256=BASE_SHA,
        projected_content_sha256=new["content_sha256"], release_sequence=SEQUENCE, runtime_files=COUNT,
        policy_sha256=POLICY_SHA, policy=POLICY, patch=str(PATCH), changed_runtime_files=1,
        production_debug_absence_preflight=True, immutable_base_unchanged=True, game_started=False,
        workshop_upload_performed=False, actual_payment_verified=False)
    if build:
        need(PATCH == Path("D:/Survival_发布候选/20261027_ws4_payment_helper_policy_v02_patch"), "policy_patch_output_not_fixed")
        key = pack.protect_data.external(Path(signing_key))
        need(key.is_file() and PATCH not in key.parents, "policy_patch_external_key_required")
        regular(PATCH, exists=False).mkdir(parents=True, exist_ok=False)
        install.write_new(PATCH / POLICY, raw)
        install.write_new(PATCH / REFERENCE, canonical(reference(metadata)))
        install.write_new(PATCH / pack.handoff.MANIFEST, canonical(new))
        pack.protect_data.sign_manifest(PATCH / pack.handoff.MANIFEST,key,PATCH / pack.handoff.SIGNATURE,SEQUENCE)
        read_patch(old, metadata); unchanged(metadata)
        report.update(status="SIGNED_ONE_FILE_POLICY_PATCH",signature_valid=True)
    elif apply:
        raw, new, snapshot = read_patch(old, metadata)
        report.update(apply_patch(old,new,raw,metadata,snapshot))
    else:
        old_marker = target_marker(); install.verify_runtime(TARGET,old,old_marker); unchanged(metadata)
        report.update(full_before_verification=True, dota_running=bool(install.dota_pids()))
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__);modes=parser.add_mutually_exclusive_group()
    modes.add_argument("--build",action="store_true");modes.add_argument("--apply",action="store_true")
    parser.add_argument("--signing-key",type=Path);args=parser.parse_args()
    try: result=run(build=args.build,apply=args.apply,signing_key=args.signing_key)
    except install.TransactionFailure as error: result=error.report
    except BaseException as error: result=dict(ok=False,error=install.error_code(error),changed=False)
    print(json.dumps(result,ensure_ascii=True));return 0 if result["ok"] else 2


if __name__=="__main__":raise SystemExit(main())
