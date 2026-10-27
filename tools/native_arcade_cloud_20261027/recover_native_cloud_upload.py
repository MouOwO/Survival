"""Reconcile only failed native-cloud 2707 to a fresh signed native05 download.

Default reads local evidence only. --verify requests one official 1313/3406
download and leaves the canonical journal untouched. --apply obtains that same
new proof under the publisher lock, preserves the exact failed attempt, then
CAS-restores original 2705 facts. No publication, listing change, retry, imported
proof, history-based manifest selection, or prior 2703 capsule is supported.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import sys
import uuid

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]


def frozen_module(name, path, pin):
    need_hash = hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
    if need_hash != pin:
        raise ValueError("Frozen recovery dependency changed: " + path.name)
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PROTOCOL_FILE = ROOT / "tools/arcade_cleanup_20261027/verify_download.py"
PROTOCOL_SHA = "1f7afed91128c8601ccd9848b092300d0869067853422fe87cc5c5e511eb237f"
REDACTOR_FILE = ROOT / "tools/arcade_cleanup_20261027/capture_upload_failure.py"
REDACTOR_SHA = "00607ca20e8920d7b2e9ee131a45d099bd01b4a87d82ec076a427369e73d5c30"
protocol = frozen_module("private_native05_recovery_protocol", PROTOCOL_FILE, PROTOCOL_SHA)
redactor = frozen_module("native07_failure_redaction_only", REDACTOR_FILE, REDACTOR_SHA)
api, callbacks, need = protocol.api, protocol.callbacks, protocol.need
ITEM, SEQUENCE, CONTENT = protocol.ITEM, 2026102705, protocol.CONTENT
STATE = ROOT / "output/four_accounts_20261022/steam_upload_state.json"
PENDING_SHA = "26f2b63800977246e24676205d5e4aa14ce214a6f5bfd5bfa4fdedc06204c82b"
UPLOAD = ROOT / "output/native_arcade_cloud_20261027/native_cloud_upload.log"
UPLOAD_SHA = "1108eb76f6999bc977aae310eda27e4477a995d4b647bf4fff32d352a027f7d2"
REPORT_SHA = "ef0ca02e81345d71f4839ec1ab0f730d5a5c83f29d1648734eb4c4998baca886"
FAILED_SEQUENCE = 2026102707
FAILED_CONTENT = "13953ffb33dd94d4de4f681a5d8c05bddacf89ee8e98c7d38939b157a17c3dd1"
FAILED_INDEX = "ed088f86586b23f9097cfc17190c18e7872213ef8f2e3f92ebbcad1c5c9ed7a5"
INDEX = "31a7a2a2bde5e82510f5f353cff830aea4815b24ccbb7a3450ff371eae2329a0"
MANIFEST, TOTAL, REMOTE_NOT_BEFORE = "3674261806658465753", 3767192138, 1793069949
PACKAGE = [
    dict(name=ITEM + ".vpk", bytes=274275, sha256=INDEX),
    dict(name=ITEM + "_000.vpk", bytes=1073604924, sha256="4bc9faf1688e0ae3fb7cfd51f4272ac44d51becd67114584837d9b40ca1fc27c"),
    dict(name=ITEM + "_001.vpk", bytes=1068730788, sha256="68cfc41f2c46f91ade8396ebe3f3597da03ab2d1f5bb06577feee49182cddff0"),
    dict(name=ITEM + "_002.vpk", bytes=1072379183, sha256="94a2a3b26731ea2a15fe0fad8116eb9043cb8bf960139a26c95e810192d56141"),
    dict(name=ITEM + "_003.vpk", bytes=552202968, sha256="b0b35246011e92994bf738556c59f3f03169eaacec8b1f6cf3c9d3565d037084"),
]
OUTPUT = ROOT / "output/native_arcade_cloud_20261027/upload_recovery07"
FACT_FIELDS = ("content_sha256", "release_sequence", "vpk_sha256", "vpk_bytes", "package_files", "verification", "package")
NATIVE_FIELDS = ("native_test", "ordinary_workshop_match", "native_acceptance", "multiplayer_acceptance",
                 "native_four_archive_reads_verified")
_live_proof = None
_lock_held = False


def valid_checks(value):
    return (isinstance(value, dict) and value.get("files") == 6655 and value.get("archive_count") == 4
            and all(value.get(name) is True for name in callbacks.CHECKS))


def local_inputs():
    snapshots = {}
    def pinned(path, pin, maximum=api.pack.MAX_MANIFEST):
        raw = callbacks.read_pinned(path, pin, maximum)
        snapshots[path] = raw
        return raw
    raw = pinned(STATE, PENDING_SHA)
    upload = pinned(UPLOAD, UPLOAD_SHA, 1024 * 1024)
    # Do not export raw logs. Even JSONL errors pass through the existing URL,
    # header/password/token redactor before interpretation or future display.
    safe_upload = "\n".join(redactor.redact(line) for line in upload.decode("utf8", errors="strict").splitlines()) + "\n"
    records = [api.pack.handoff.decode_json(line.encode("utf8")) for line in safe_upload.splitlines()]
    need(records and records[-1].get("status") == "BLOCKED_PRESERVE_RECOVERY_JOURNAL"
         and records[-1].get("error") == "RuntimeError: Steam API callback 3404 returned EResult=2",
         "native07_exact_explicit_failed_3404_result2_required")
    pending = api.pack.handoff.decode_json(raw)
    need(pending.get("owner") == api.OWNER and pending.get("app_id") == api.APP
         and pending.get("workshop_id") == ITEM and pending.get("visibility_requested") == 3
         and pending.get("status") == "SUBMIT_REQUEST_PENDING" and pending.get("uploaded") is False
         and pending.get("legal_agreement_required") is False and pending.get("release_sequence") == FAILED_SEQUENCE
         and pending.get("content_sha256") == FAILED_CONTENT and pending.get("vpk_sha256") == FAILED_INDEX,
         "native07_pinned_failed_pending_identity_required")
    baseline = pending.get("previous_release", {})
    need(baseline.get("uploaded") is True and baseline.get("release_sequence") == SEQUENCE
         and baseline.get("content_sha256") == CONTENT and baseline.get("vpk_sha256") == INDEX
         and baseline.get("vpk_bytes") == PACKAGE[0]["bytes"] and baseline.get("package_files") == PACKAGE
         and baseline.get("package") == str(protocol.VPK) and valid_checks(baseline.get("verification"))
         and baseline.get("steam_manifest") == MANIFEST and baseline.get("download_manifest") == MANIFEST,
         "native07_original_previous_release05_facts_required")
    report = api.pack.handoff.decode_json(pinned(protocol.REPORT, REPORT_SHA))
    need(report.get("content_sha256") == CONTENT and report.get("release_sequence") == SEQUENCE
         and report.get("files") == 6655 and report.get("vpk_sha256") == INDEX
         and report.get("package_files") == PACKAGE and report.get("container_bytes") == TOTAL
         and report.get("dry_run") is False and report.get("signature_valid") is True
         and report.get("full_input_hash_verification") is True and report.get("full_runtime_validator_passed") is True
         and valid_checks(report.get("verification")), "native07_original05_completed_package_required")
    for relative, pin in protocol.PUBLIC_PINS.items():
        pinned(ROOT / relative, pin, 1024 * 1024)
    manifest_raw = protocol.read_snapshot(protocol.CANDIDATE / api.pack.handoff.MANIFEST, api.pack.MAX_MANIFEST, snapshots)
    signed_raw = protocol.read_snapshot(protocol.CANDIDATE / api.pack.handoff.SIGNATURE, api.pack.MAX_SIGNATURE, snapshots)
    manifest, signed = [api.pack.handoff.decode_json(data) for data in (manifest_raw, signed_raw)]
    api.pack.runtime.validate_manifest(manifest)
    policy, public = api.pack.handoff.trusted_policy(api.pack.handoff.POLICY)
    signature = api.pack.verify_signed_snapshot(manifest, signed, public,
        policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
    need(signature["release_sequence"] == SEQUENCE and signature["content_sha256"] == CONTENT
         and manifest["file_count"] == 6655, "native07_original05_signed_metadata_required")
    protected = protocol.protected_inventory(manifest,
        api.pack.handoff.decode_json(snapshots[ROOT / "tools/lua_protection_policy.json"]))
    old, old_document, old_raw = protocol.incremental.metadata(protocol.incremental.BASE)
    old_signature = api.pack.verify_signed_snapshot(old, old_document, public,
        policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
    need(old["content_sha256"] == protocol.incremental.BASE_CONTENT
         and old_signature["release_sequence"] == protocol.incremental.BASE_SEQUENCE,
         "native07_independent_protected_baseline_required")
    snapshots.update({protocol.incremental.BASE / name: data for name, data in old_raw.items()})
    before, after = [{row["path"]: row for row in value["files"]} for value in (old, manifest)]
    need(all(before.get(name) == after[name] for name in protected), "native07_protected_180_bytes_changed")
    for relative in (*api.pack.handoff.GATE_FILES, *api.pack.handoff.ENTRY_GATE_FILES, api.pack.handoff.ACCESS_FILE):
        data = protocol.read_snapshot(protocol.TRUSTED / relative, api.pack.MAX_MANIFEST, snapshots)
        need(relative in after and hashlib.sha256(data).hexdigest() == after[relative]["sha256"],
             "native07_original05_reviewed_gate_changed")
    for relative in protocol.PUBLIC_PINS:
        if relative != "tools/lua_protection_policy.json":
            data = protocol.read_snapshot(protocol.TRUSTED / relative, api.pack.MAX_MANIFEST, snapshots)
            need(data == snapshots[ROOT / relative], "native07_original05_public_trust_changed")
    for file, pin in ((PROTOCOL_FILE, PROTOCOL_SHA), (REDACTOR_FILE, REDACTOR_SHA)):
        data = protocol.read_snapshot(file, api.pack.MAX_MANIFEST, snapshots)
        need(hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest() == pin, "native07_recovery_dependency_changed")
    result = dict(pending=pending, pending_raw=raw, baseline=baseline, snapshots=snapshots,
                  upload_raw=upload, upload_redacted=safe_upload.encode("utf8"))
    unchanged(result)
    return result


def unchanged(inputs):
    protocol.unchanged(inputs["snapshots"])


def temporary_journal(inputs):
    # Only pinned prior release facts and pinned same-item identity are used.
    # This journal is an isolated verifier adapter, never canonical evidence.
    state = {name: copy.deepcopy(inputs["baseline"][name]) for name in FACT_FIELDS}
    state.update(schema=1, owner=api.OWNER, app_id=api.APP, workshop_id=ITEM, visibility_requested=3,
        legal_agreement_required=False, uploaded=inputs["baseline"]["uploaded"],
        steam_manifest=inputs["baseline"]["steam_manifest"], download_manifest=inputs["baseline"]["download_manifest"])
    return state


@contextmanager
def publisher_lock():
    global _lock_held
    need(not _lock_held, "native07_nested_recovery_lock_forbidden")
    with api.publication_lock(STATE):
        _lock_held = True
        try:
            yield
        finally:
            _lock_held = False


def preserve_failure(inputs, directory):
    unchanged(inputs)
    for name, raw in (("pending.original.json", inputs["pending_raw"]),
                      ("upload_failure.original.log", inputs["upload_raw"]),
                      ("upload_failure.redacted.log", inputs["upload_redacted"])):
        callbacks.write_exclusive(directory / name, raw)
        inputs["snapshots"][directory / name] = raw
    evidence = dict(schema=1, failed_release_sequence=FAILED_SEQUENCE, failed_content_sha256=FAILED_CONTENT,
        pending_sha256=PENDING_SHA, upload_log_sha256=UPLOAD_SHA, callback_id=3404, result=2,
        original_pending_preserved=True, original_upload_log_preserved=True, logs_redacted_for_display=True,
        previous_release_sequence=SEQUENCE, previous_content_sha256=CONTENT,
        failed_release_official_download_verified=False, native_acceptance="NOT_RUN")
    raw = callbacks.encoded(evidence)
    callbacks.write_exclusive(directory / "failed_attempt_evidence.json", raw)
    inputs["snapshots"][directory / "failed_attempt_evidence.json"] = raw


def validate_official(proof):
    need(proof.get("status") == "OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED"
         and proof.get("workshop_id") == ITEM and proof.get("release_sequence") == SEQUENCE
         and proof.get("content_sha256") == CONTENT and proof.get("vpk_sha256") == INDEX
         and type(proof.get("steam_manifest")) is str and proof["steam_manifest"] == MANIFEST
         and protocol.steam_manifest(proof["steam_manifest"])
         and proof.get("package_report_sha256") == REPORT_SHA and proof.get("canonical_journal_unchanged") is True
         and proof.get("protected_modules_verified") == 180 and proof.get("signed_resources_verified") == 6655,
         "native07_same_native05_complete_official_proof_required")
    pre, post = proof.get("pre_query", {}), proof.get("post_query", {})
    protocol.validate_remote(pre, TOTAL); protocol.validate_remote(post, TOTAL)
    need(pre["time_updated"] >= REMOTE_NOT_BEFORE and
         {k: v for k, v in pre.items() if k != "observed_utc"} == {k: v for k, v in post.items() if k != "observed_utc"},
         "native07_remote_changed_or_predates_verified_native05")
    subscribe, download = proof.get("subscription_refresh", {}), proof.get("download", {})
    subscribed, downloaded = subscribe.get("callback", {}), download.get("callback", {})
    need(subscribe.get("subscribe_calls") == 1 and subscribe.get("unsubscribe_calls") == 0
         and subscribed.get("callback_id") == 1313 and subscribed.get("result") == 1
         and subscribed.get("workshop_id") == ITEM and downloaded.get("callback_id") == 3406
         and downloaded.get("app_id") == api.APP and downloaded.get("workshop_id") == ITEM
         and downloaded.get("result") == 1, "native07_fresh_matching_1313_and_3406_required")
    verified, acf = proof.get("verification", {}), proof.get("acf_installed_entry", {})
    need(verified.get("signature_valid") is True and verified.get("vpk_sha256") == INDEX
         and verified.get("package_files") == PACKAGE and valid_checks(verified.get("verification")),
         "native07_complete_five_vpk_signed_native05_required")
    need(type(acf.get("manifest")) is str and acf["manifest"] == MANIFEST and acf.get("size") == str(TOTAL)
         and acf.get("timeupdated") == str(post["time_updated"]), "native07_raw_string_manifest_acf_binding_required")


def verify_live(inputs, directory):
    global _live_proof
    need(_lock_held, "native07_publisher_lock_required")
    _live_proof = None
    unchanged(inputs)
    need(shutil.disk_usage(protocol.INSTALLED.anchor).free >= TOTAL + 1024**3,
         "native07_insufficient_full_package_plus_one_gib_staging_space")
    # The frozen protocol performs process/space checks, full candidate + VPK
    # verification, uncached queries, 1313, 3406, all signed payload checks, and
    # exact App570/Item/uint64-string ACF binding. No canonical journal rewrite.
    temporary = directory / "native05.verifier-adapter.json"
    raw = callbacks.encoded(temporary_journal(inputs))
    callbacks.write_exclusive(temporary, raw)
    original = protocol.STATE, protocol.OUTPUT
    try:
        protocol.STATE, protocol.OUTPUT = temporary, directory / "official_download"
        verified_inputs = protocol.local_inputs(True, full=True)
        need(verified_inputs["report_sha256"] == REPORT_SHA and verified_inputs["total"] == TOTAL
             and verified_inputs["state"]["package_files"] == PACKAGE
             and verified_inputs["expected_manifest"] == MANIFEST, "native07_adapter_identity_drift")
        answer = protocol.download_once(verified_inputs)
        path = api.pack.handoff.regular_path(Path(answer["evidence"]))
        need(api.pack.runtime.within(path, directory / "official_download"), "native07_official_evidence_escaped_owned_directory")
        proof_raw = api.pack.read_metadata(path, api.pack.MAX_MANIFEST)
        official = api.pack.handoff.decode_json(proof_raw)
        validate_official(official)
        need(official.get("canonical_journal_sha256") == hashlib.sha256(raw).hexdigest(),
             "native07_official_proof_not_from_same_isolated_adapter")
    finally:
        protocol.STATE, protocol.OUTPUT = original
    unchanged(inputs)
    proof = dict(schema=1, status="FRESH_NATIVE05_FULLY_VERIFIED_AFTER_FAILED_NATIVE07",
        verified_utc=callbacks.now(), pending_sha256=PENDING_SHA, failed_upload_sha256=UPLOAD_SHA,
        official_evidence=str(path), official_evidence_sha256=hashlib.sha256(proof_raw).hexdigest(),
        official=official, canonical_pending_unchanged=True, adapter_journal_sha256=hashlib.sha256(raw).hexdigest(),
        official_journal_is_isolated_adapter=True, native_acceptance="NOT_RUN", updates_submitted=0)
    _live_proof = proof
    return proof


def require_live_proof(proof):
    need(_lock_held and proof is _live_proof, "native07_same_process_locked_live_proof_required")
    need(proof.get("status") == "FRESH_NATIVE05_FULLY_VERIFIED_AFTER_FAILED_NATIVE07"
         and proof.get("pending_sha256") == PENDING_SHA and proof.get("failed_upload_sha256") == UPLOAD_SHA,
         "native07_wrong_attempt_live_proof")
    validate_official(proof.get("official", {}))
    age = (datetime.now(timezone.utc) - datetime.fromisoformat(proof["verified_utc"])).total_seconds()
    need(0 <= age <= 300, "native07_live_proof_not_fresh")
    path = api.pack.handoff.regular_path(Path(proof["official_evidence"]))
    need(api.pack.runtime.digest(path) == proof["official_evidence_sha256"], "native07_live_official_evidence_changed")


def commit_local(inputs, proof, directory):
    global _live_proof
    unchanged(inputs)
    require_live_proof(proof)
    need((directory / "pending.original.json").read_bytes() == inputs["pending_raw"]
         and (directory / "upload_failure.original.log").read_bytes() == inputs["upload_raw"],
         "native07_exact_original_failure_backups_required")
    baseline, state = inputs["baseline"], copy.deepcopy(inputs["pending"])
    for name in list(state):
        if api.release_evidence(name) or name in FACT_FIELDS or name in NATIVE_FIELDS:
            state.pop(name)
    state.update(copy.deepcopy(baseline))
    history = copy.deepcopy(inputs["pending"].get("release_history", []))
    need(isinstance(history, list), "native07_invalid_release_history")
    if history:
        state["previous_release"], state["release_history"] = history[-1], history[:-1]
    else:
        state.pop("previous_release", None); state["release_history"] = []
    historical = {name: copy.deepcopy(baseline[name]) for name in NATIVE_FIELDS if name in baseline}
    for name in NATIVE_FIELDS:
        state.pop(name, None)
    receipt = directory / "fresh_verification.json"
    receipt_raw = callbacks.encoded(proof)
    callbacks.write_exclusive(receipt, receipt_raw)
    failure = dict(schema=1, status="FAILED_NATIVE_CLOUD_2026102707_3404_RESULT2", historical_only=True,
        failed_release_sequence=FAILED_SEQUENCE, failed_content_sha256=FAILED_CONTENT, callback_id=3404, result=2,
        pending_state_backup=str(directory / "pending.original.json"), pending_state_sha256=PENDING_SHA,
        upload_log_backup=str(directory / "upload_failure.original.log"), upload_log_sha256=UPLOAD_SHA,
        evidence=str(directory / "failed_attempt_evidence.json"), failed_release_official_download_verified=False,
        failed_attempt_evidence_sha256=api.pack.runtime.digest(directory / "failed_attempt_evidence.json"),
        native_acceptance="NOT_RUN")
    failures = inputs["pending"].get("failed_attempts", baseline.get("failed_attempts", []))
    need(isinstance(failures, list), "native07_invalid_failed_attempt_history")
    state.update(status="RECONCILED_ORIGINAL_NATIVE05_FRESH_OFFICIAL_DOWNLOAD_VERIFIED", uploaded=True,
        native_test="HISTORICAL_ONLY_NOT_RUN_DURING_RECONCILIATION", ordinary_workshop_match="HISTORICAL_ONLY_SEE_RECONCILIATION",
        historical_acceptance=historical, ready_for_public_release=False, download_verified=True,
        steam_manifest=MANIFEST, download_manifest=MANIFEST, download_evidence=proof["official_evidence"],
        failed_attempts=[*copy.deepcopy(failures), failure], reconciliation=dict(schema=1, performed_utc=callbacks.now(),
            from_pending_sha256=PENDING_SHA, fresh_verification=str(receipt),
            fresh_verification_sha256=hashlib.sha256(receipt_raw).hexdigest(), verified_remote_release_sequence=SEQUENCE,
            verified_remote_manifest=MANIFEST, publisher_calls=0, native_acceptance_promoted=False))
    need(all(state[name] == baseline[name] for name in FACT_FIELDS), "native07_original05_release_facts_changed")
    raw = callbacks.encoded(state)
    temporary = STATE.with_name(STATE.name + ".recover07-" + uuid.uuid4().hex + ".part")
    try:
        callbacks.write_exclusive(temporary, raw)
        unchanged(inputs)  # CAS immediately before the sole canonical mutation.
        require_live_proof(proof)
        os.replace(temporary, STATE)
    finally:
        temporary.unlink(missing_ok=True)
    _live_proof = None
    return dict(status="NATIVE07_LOCAL_JOURNAL_RECONCILED_TO_FRESH_NATIVE05", release_sequence=SEQUENCE,
        original_pending_sha256=PENDING_SHA, journal_sha256=hashlib.sha256(raw).hexdigest(),
        steam_manifest=MANIFEST, evidence_directory=str(directory), updates_submitted=0,
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
            free = shutil.disk_usage(protocol.INSTALLED.anchor).free
            required = TOTAL + 1024**3
            api.emit(dict(status="READ_ONLY_FAILED_NATIVE07_RECONCILIATION_PLAN", pending_sha256=PENDING_SHA,
                failed_release_sequence=FAILED_SEQUENCE, failed_upload_log_sha256=UPLOAD_SHA,
                original_release_sequence=SEQUENCE, original_content_sha256=CONTENT, original_steam_manifest=MANIFEST,
                original_package_bytes=TOTAL, journal_changed=False, steam_initialized=False, files_written=0,
                updates_submitted=0, native_acceptance="NOT_RUN", free_bytes=free,
                conservative_required_free_bytes=required, space_admitted=free >= required))
            return 0
        with publisher_lock():
            inputs = local_inputs()
            directory = api.pack.handoff.regular_path(OUTPUT / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ_")
                + uuid.uuid4().hex), must_exist=False)
            directory.mkdir(parents=True, exist_ok=False)
            preserve_failure(inputs, directory)
            proof = verify_live(inputs, directory)
            if args.apply:
                result = commit_local(inputs, proof, directory)
            else:
                require_live_proof(proof)
                callbacks.write_exclusive(directory / "fresh_verification.json", callbacks.encoded(proof))
                result = dict(status="ORIGINAL_NATIVE05_FRESH_DOWNLOAD_VERIFIED_CANONICAL_PENDING_PRESERVED",
                    journal_changed=False, evidence_directory=str(directory), updates_submitted=0)
        api.emit(result)
        return 0
    except Exception as error:
        # Exception messages from unexpected dependencies are never printed;
        # explicit refusal strings still pass through the existing redactor.
        reason = redactor.redact(str(error)) if isinstance(error, callbacks.Refused) else type(error).__name__
        api.emit(dict(status="NATIVE07_RECOVERY_REFUSED_CANONICAL_PENDING_PRESERVED", reason=reason,
            updates_submitted=0, automatic_retry_performed=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
