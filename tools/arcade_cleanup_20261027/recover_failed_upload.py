"""Reconcile this one failed refresh upload to freshly verified remote SHOP02.

Default is read-only. --verify obtains a new official download and full signed
proof, leaving the canonical journal unchanged. --apply performs that SAME live
verification under the publisher lock, backs up the exact pending state, then
CAS-replaces only the local journal. Neither mode publishes or changes network
configuration. No imported receipt, force flag, automatic retry or pending clear.
"""
from __future__ import annotations
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import shutil
import sys
import uuid

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import capture_upload_failure as captured
import incremental_vpk as incremental

previous, callbacks, api, need = captured.previous, captured.callbacks, captured.api, captured.need
ITEM, SEQUENCE, CONTENT = previous.ITEM, previous.SEQUENCE, previous.CONTENT
INDEX, TOTAL, MANIFEST = previous.INDEX, captured.TOTAL, previous.EXPECTED_STEAM_MANIFEST
REMOTE_TIME, STATE, PENDING_SHA = captured.REMOTE_TIME, captured.STATE, captured.PENDING_SHA
EVIDENCE = captured.OUTPUT
EVIDENCE_SHA = "6479ce916c8af73d3d0198ca1022418ba047364e21630e9f4e730f1e9fd0de4b"
OUTPUT = EVIDENCE.parent / "upload_reconciliation"
FACT_FIELDS = ("content_sha256", "release_sequence", "vpk_sha256", "vpk_bytes", "package_files", "verification", "package")
NATIVE_FIELDS = ("native_test", "ordinary_workshop_match", "native_four_archive_reads_verified")


def local_inputs():
    raw = callbacks.read_pinned(STATE, PENDING_SHA, api.pack.MAX_MANIFEST)
    capsule_raw = callbacks.read_pinned(EVIDENCE / "evidence.json", EVIDENCE_SHA, 1024 * 1024)
    capsule = api.pack.handoff.decode_json(capsule_raw)
    need(capsule.get("pending_sha256") == PENDING_SHA and capsule.get("upload_report_sha256") == captured.UPLOAD_SHA
         and capsule.get("callback_id") == 3404 and capsule.get("result") == 2
         and capsule.get("manifest_bytes") == 104792 and capsule.get("failed_release_sequence") == 2026102703
         and capsule.get("original_depot_log_sha256") == captured.DEPOT_SHA
         and capsule.get("upload_endpoint_host") == captured.HOST,
         "recovery_exact_failed_attempt_capsule_required")
    snapshots = {STATE: raw, EVIDENCE / "evidence.json": capsule_raw}
    need(set(capsule.get("files", {})) == {"pending.original.json", "upload_failure.jsonl",
         "depot_failure.redacted.log", "workshop_failure.redacted.log", "network.json", "fresh_old_remote_query.json"},
         "recovery_evidence_inventory_changed")
    for name, pin in capsule["files"].items():
        snapshots[EVIDENCE / name] = callbacks.read_pinned(EVIDENCE / name, pin, api.pack.MAX_MANIFEST)
    need(snapshots[EVIDENCE / "pending.original.json"] == raw, "recovery_pending_backup_differs")
    upload = [api.pack.handoff.decode_json(line) for line in snapshots[EVIDENCE / "upload_failure.jsonl"].splitlines()]
    need(upload[-1].get("status") == "BLOCKED_PRESERVE_RECOVERY_JOURNAL"
         and upload[-1].get("error") == "RuntimeError: Steam API callback 3404 returned EResult=2",
         "recovery_explicit_failed_submit_callback_required")
    need(b"ERROR! Timeout uploading manifest (size 104792)" in snapshots[EVIDENCE / "depot_failure.redacted.log"]
         and b"2026-10-27 10:19:03" in snapshots[EVIDENCE / "workshop_failure.redacted.log"],
         "recovery_exact_manifest_timeout_evidence_required")
    pending = api.pack.handoff.decode_json(raw)
    need(pending.get("owner") == api.OWNER and pending.get("app_id") == api.APP
         and pending.get("workshop_id") == ITEM and pending.get("visibility_requested") == 3
         and pending.get("status") == "SUBMIT_REQUEST_PENDING" and pending.get("uploaded") is False
         and pending.get("release_sequence") == 2026102703
         and pending.get("content_sha256") == "339ff9744ea16a5049e69ea4801b50314531a22635c0ce12051f84d8a30cde07",
         "recovery_not_the_pinned_failed_pending_release")
    baseline = pending.get("previous_release", {})
    need(baseline.get("uploaded") is True and baseline.get("content_sha256") == CONTENT
         and baseline.get("release_sequence") == SEQUENCE and baseline.get("vpk_sha256") == INDEX
         and baseline.get("vpk_bytes") == incremental.BASE_PACKAGE[0]["bytes"]
         and baseline.get("package_files") == incremental.BASE_PACKAGE
         and baseline.get("verification", {}).get("files") == 6637
         and baseline.get("verification", {}).get("archive_count") == 4
         and all(baseline.get("verification", {}).get(name) is True for name in callbacks.CHECKS),
         "recovery_original_signed_shop02_baseline_required")
    # Public checkout trust and the old release metadata/report remain pinned.
    for name, pin in previous.PUBLIC_PINS.items():
        snapshots[previous.ROOT / name] = callbacks.read_pinned(previous.ROOT / name, pin)
    for name, pin in previous.METADATA_PINS.items():
        snapshots[previous.CANDIDATE / name] = callbacks.read_pinned(previous.CANDIDATE / name, pin, api.pack.MAX_MANIFEST)
    snapshots[previous.REPORT] = callbacks.read_pinned(previous.REPORT, previous.REPORT_SHA, api.pack.MAX_MANIFEST)
    captured.validate_old_remote(api.pack.handoff.decode_json(snapshots[EVIDENCE / "fresh_old_remote_query.json"]))
    return dict(pending=pending, pending_raw=raw, baseline=baseline, snapshots=snapshots, capsule=capsule)


def unchanged(inputs):
    for path, raw in inputs["snapshots"].items():
        need(api.pack.read_metadata(api.pack.handoff.regular_path(path), len(raw)) == raw,
             "recovery_input_or_pending_changed")


class RecoverySteam(previous.SHOP02Steam):
    ALLOWED = previous.SHOP02Steam.ALLOWED - {"SubscribeItem"}

    def __init__(self):
        super().__init__(TOTAL)

    def fresh_item(self):
        item = super().fresh_item()
        captured.validate_old_remote(item)
        return item


def verify_live(inputs):
    import test_entry
    processes = test_entry.process_inventory()
    need(processes.get("steam_running") is True and processes.get("dota_pids") == [],
         "recovery_close_dota_keep_steam_before_download")
    need(shutil.disk_usage(previous.INSTALLED.anchor).free >= TOTAL + 256 * 1024 * 1024,
         "recovery_insufficient_download_staging_space")
    with incremental.trusted_source(previous.TRUSTED):
        _, manifest, signature, metadata = api.pack.authenticate(previous.CANDIDATE)
    need(signature["content_sha256"] == CONTENT and signature["release_sequence"] == SEQUENCE,
         "recovery_shop02_full_signed_identity_mismatch")
    with RecoverySteam() as steam:
        pre = steam.fresh_item()
        # Inherited implementation drains old callbacks and requires a matching
        # newly requested 3406. It neither subscribes nor changes publisher state.
        downloaded = steam.download_installed()
        callback = downloaded.get("callback", {})
        need(callback.get("callback_id") == 3406 and callback.get("app_id") == api.APP
             and callback.get("workshop_id") == ITEM and callback.get("result") == 1,
             "recovery_real_matching_download_callback_required")
        baseline_state = dict(inputs["baseline"], workshop_id=ITEM, visibility_requested=3)
        verified = previous.verify.verify_installed(downloaded.copy(), previous.CANDIDATE, baseline_state)
        need(verified.get("package_files") == incremental.BASE_PACKAGE and verified.get("signature_valid") is True
             and verified.get("verification", {}).get("files") == 6637
             and verified.get("verification", {}).get("archive_count") == 4
             and all(verified.get("verification", {}).get(name) is True for name in callbacks.CHECKS),
             "recovery_complete_shop02_signed_download_required")
        folder = Path(verified["install_folder"])
        need(set(folder.iterdir()) == set(api.pack.package_paths(Path(verified["vpk"])))
             and api.pack.package_inventory(Path(verified["vpk"])) == incremental.BASE_PACKAGE,
             "recovery_download_changed_during_verification")
        post = steam.fresh_item()
    need({key: value for key, value in pre.items() if key != "observed_utc"}
         == {key: value for key, value in post.items() if key != "observed_utc"},
         "recovery_remote_changed_during_verification")
    acf_raw = api.pack.read_metadata(api.pack.handoff.regular_path(previous.ACF), api.pack.MAX_MANIFEST)
    acf = api.pack.handoff.kv(acf_raw.decode("utf-8-sig"))["appworkshop"]
    row = acf["workshopitemsinstalled"][ITEM]
    need(acf.get("appid") == str(api.APP) and row.get("manifest") == MANIFEST
         and row.get("size") == str(TOTAL) and row.get("timeupdated") == str(REMOTE_TIME),
         "recovery_official_shop02_installed_manifest_changed")
    api.pack.inventory_unchanged(previous.CANDIDATE, metadata)
    unchanged(inputs)
    return dict(schema=1, status="FRESH_OFFICIAL_SHOP02_FULLY_VERIFIED_AFTER_FAILED_REFRESH",
        verified_utc=callbacks.now(), pending_sha256=PENDING_SHA, failed_attempt_evidence_sha256=EVIDENCE_SHA,
        pre_query=pre, download=downloaded, signed_download=verified, post_query=post,
        steam_manifest=MANIFEST, acf_installed_entry=row, content_sha256=CONTENT, release_sequence=SEQUENCE,
        publisher_calls=0, updates_submitted=0, native_test="NOT_RUN", ready_for_public_release=False)


def require_live_proof(proof):
    need(proof.get("status") == "FRESH_OFFICIAL_SHOP02_FULLY_VERIFIED_AFTER_FAILED_REFRESH"
         and proof.get("pending_sha256") == PENDING_SHA
         and proof.get("failed_attempt_evidence_sha256") == EVIDENCE_SHA
         and proof.get("content_sha256") == CONTENT and proof.get("release_sequence") == SEQUENCE
         and proof.get("steam_manifest") == MANIFEST, "recovery_same_process_full_live_proof_required")
    captured.validate_old_remote(proof.get("pre_query", {}))
    captured.validate_old_remote(proof.get("post_query", {}))
    need({key: value for key, value in proof["pre_query"].items() if key != "observed_utc"}
         == {key: value for key, value in proof["post_query"].items() if key != "observed_utc"},
         "recovery_live_remote_observations_changed")
    acf = proof.get("acf_installed_entry", {})
    need(acf.get("manifest") == MANIFEST and acf.get("size") == str(TOTAL)
         and acf.get("timeupdated") == str(REMOTE_TIME), "recovery_live_acf_identity_changed")
    verified, callback = proof.get("signed_download", {}), proof.get("download", {}).get("callback", {})
    need(callback.get("callback_id") == 3406 and callback.get("app_id") == api.APP
         and callback.get("workshop_id") == ITEM and callback.get("result") == 1
         and verified.get("signature_valid") is True and verified.get("vpk_sha256") == INDEX
         and verified.get("package_files") == incremental.BASE_PACKAGE
         and verified.get("verification", {}).get("files") == 6637
         and verified.get("verification", {}).get("archive_count") == 4
         and all(verified.get("verification", {}).get(name) is True for name in callbacks.CHECKS),
         "recovery_incomplete_live_download_proof")
    age = (datetime.now(timezone.utc) - datetime.fromisoformat(proof["verified_utc"])).total_seconds()
    need(0 <= age <= 300, "recovery_live_proof_not_fresh")


def commit_local(inputs, proof, directory):
    """Caller holds publication_lock; current pending bytes must match twice."""
    unchanged(inputs)
    require_live_proof(proof)
    pending, baseline = inputs["pending"], inputs["baseline"]
    backup, receipt = directory / "pending.original.json", directory / "fresh_verification.json"
    callbacks.write_exclusive(backup, inputs["pending_raw"])
    receipt_raw = callbacks.encoded(proof)
    callbacks.write_exclusive(receipt, receipt_raw)
    # Restore release fields from the archived original, retaining the complete
    # pending state separately and undoing archive_release's last history push.
    state = copy.deepcopy(pending)
    for name in list(state):
        if api.release_evidence(name) or name in FACT_FIELDS or name in NATIVE_FIELDS:
            state.pop(name)
    state.update(copy.deepcopy(baseline))
    history = copy.deepcopy(pending.get("release_history", []))
    need(isinstance(history, list), "recovery_release_history_invalid")
    if history:
        state["previous_release"] = history[-1]
        state["release_history"] = history[:-1]
    else:
        state.pop("previous_release", None)
        state["release_history"] = []
    prior_acceptance = {name: baseline.get(name) for name in NATIVE_FIELDS}
    failure = dict(schema=1, status="FAILED_REFRESH_2026102703_NOT_PUBLISHED", historical_only=True,
        callback_id=3404, result=2, diagnosis="manifest_upload_timeout", manifest_bytes=104792,
        failed_release_sequence=2026102703, failed_content_sha256=pending["content_sha256"],
        failed_attempt_evidence=str(EVIDENCE / "evidence.json"), failed_attempt_evidence_sha256=EVIDENCE_SHA,
        pending_state_backup=str(backup), pending_state_sha256=PENDING_SHA,
        failed_release_official_download_verified=False, native_test="NOT_RUN")
    failures = state.get("failed_attempts", [])
    need(isinstance(failures, list), "recovery_failed_attempt_history_invalid")
    state.update(status="RECONCILED_UNLISTED_SHOP02_REMOTE_VERIFIED", uploaded=True,
        native_test="HISTORICAL_ONLY_NOT_RUN_DURING_RECONCILIATION",
        ordinary_workshop_match="HISTORICAL_ONLY_SEE_RECONCILIATION", ready_for_public_release=False,
        download_verified=True, download_manifest=MANIFEST, historical_acceptance=prior_acceptance,
        failed_attempts=[*failures, failure], reconciliation=dict(schema=1, performed_utc=callbacks.now(),
            from_pending_sha256=PENDING_SHA, original_pending_backup=str(backup),
            fresh_verification=str(receipt), fresh_verification_sha256=hashlib.sha256(receipt_raw).hexdigest(),
            verified_remote_release_sequence=SEQUENCE, verified_remote_manifest=MANIFEST,
            failed_attempt_evidence_sha256=EVIDENCE_SHA, publisher_calls=0, native_acceptance_promoted=False))
    need(all(state[name] == baseline[name] for name in FACT_FIELDS), "recovery_original_release_facts_changed")
    raw = callbacks.encoded(state)
    temporary = STATE.with_name(STATE.name + ".recover-" + uuid.uuid4().hex + ".part")
    try:
        callbacks.write_exclusive(temporary, raw)
        unchanged(inputs)  # CAS immediately before atomic replace.
        os.replace(temporary, STATE)
    finally:
        temporary.unlink(missing_ok=True)
    return dict(status="LOCAL_JOURNAL_RECONCILED_TO_FRESHLY_VERIFIED_SHOP02", workshop_id=ITEM,
        release_sequence=SEQUENCE, steam_manifest=MANIFEST, journal_sha256=hashlib.sha256(raw).hexdigest(),
        original_pending_sha256=PENDING_SHA, evidence_directory=str(directory), updates_submitted=0,
        native_test="NOT_RUN", automatic_retry_performed=False)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--verify", action="store_true")
    modes.add_argument("--apply", action="store_true")
    args = parser.parse_args(argv)
    try:
        inputs = local_inputs()
        if not args.verify and not args.apply:
            api.emit(dict(status="READ_ONLY_FAILED_REFRESH_RECONCILIATION_PLAN", pending_sha256=PENDING_SHA,
                old_release_sequence=SEQUENCE, old_steam_manifest=MANIFEST, journal_changed=False,
                steam_initialized=False, files_written=0, updates_submitted=0))
            return 0
        directory = api.pack.handoff.regular_path(OUTPUT / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ_")
            + uuid.uuid4().hex), must_exist=False)
        directory.mkdir(parents=True, exist_ok=False)
        with api.publication_lock(STATE):
            inputs = local_inputs()
            proof = verify_live(inputs)
            if args.apply:
                result = commit_local(inputs, proof, directory)
            else:
                callbacks.write_exclusive(directory / "fresh_verification.json", callbacks.encoded(proof))
                result = dict(status="SHOP02_OFFICIAL_DOWNLOAD_VERIFIED_JOURNAL_UNCHANGED",
                    journal_changed=False, evidence_directory=str(directory), updates_submitted=0)
        api.emit(result)
        return 0
    except Exception as error:
        api.emit(dict(status="RECONCILIATION_REFUSED_JOURNAL_PRESERVED", reason=str(error)
            if isinstance(error, callbacks.Refused) else type(error).__name__,
            updates_submitted=0, automatic_retry_performed=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
