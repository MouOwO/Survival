"""Plan, or explicitly apply, the fixed v05 -> v06 update to svt_w24 only.

No private key, credential, gateway, launcher or public release-pin file is
read or changed. Only seven signed runtime files and the local receipt can
change. Backups/staging stay in ignored workspace output; no tree is moved or
recursively deleted. Native Dota testing remains a separate step.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_ui_qa_candidate as builder

web, pack = builder.web, builder.pack
ROOT = builder.ROOT
TARGET = ROOT.parent / "svt_w24"
CANDIDATE = Path("D:/Survival_发布候选/20261025_ws4_ui_qa_v06")
TRUSTED = CANDIDATE.with_name(CANDIDATE.name + "_trusted_source")
CANDIDATE_SHA = "1dd9d88f885f8e1617985f933bbdb450884f91a7cdb96b10e0315d2b0cdaa884"
RECEIPT = "_online_policy_install.json"
OLD_RECEIPT_SHA = "2003987e89b74120d3e90cb0586449c12d5003d789fc777f2f3784f32a09f48e"
STORE = ROOT / "output/ui_qa_20261025/release/alias_updates"
ALLOWLIST = builder.ALLOWLIST


def need(value, code):
    if not value:
        raise RuntimeError(code)


def code(error):
    value = str(error)
    return value if re.fullmatch(r"[a-z][a-z0-9_]{0,79}", value) else "alias_update_failed"


class UpdateFailure(RuntimeError):
    def __init__(self, stage, error, rollback, transaction):
        super().__init__(code(error))
        self.report = dict(ok=False, error=code(error), stage=stage,
                           rollback=rollback, transaction=str(transaction),
                           game_started=False, workshop_upload_performed=False)


def regular(path, *, exists=True):
    path = Path(path)
    for entry in (path, *path.parents):
        try:
            attributes = entry.lstat()
        except FileNotFoundError:
            continue
        need(not (getattr(attributes, "st_file_attributes", 0)
                  & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)), "alias_reparse_path_forbidden")
    return pack.handoff.regular_path(path, must_exist=exists)


def target_path():
    need(TARGET.absolute() == (ROOT.parent / "svt_w24").absolute(), "alias_target_not_fixed_svt_w24")
    target = regular(TARGET)
    need(target.is_dir() and target.name == "svt_w24" and target.parent == regular(ROOT.parent),
         "alias_target_not_fixed_svt_w24")
    return target


def file_path(root, name):
    need(pack.protect_data.safe_name(name), "alias_unsafe_relative_path")
    regular(root)
    regular(root / name)
    return regular(pack.protect_data.source_path(root, name))


def prospective(path, boundary):
    path, boundary = regular(path, exists=False), regular(boundary)
    need(path != boundary and boundary in path.parents, "alias_output_outside_boundary")
    return path


def row_bytes(raw):
    return dict(bytes=len(raw), md5=hashlib.md5(raw, usedforsecurity=False).hexdigest(), sha256=web.sha(raw))


def verify_file(path, row):
    path = regular(path)
    need(path.is_file() and pack.runtime.checksums(path) == {k: row[k] for k in ("bytes", "md5", "sha256")},
         "alias_file_hash_mismatch")


def verify_runtime(target, manifest):
    guard_inventory(target, manifest)
    need(pack.runtime.verify(regular(target), manifest)["ok"], "alias_full_runtime_verification_failed")


def guard_inventory(root, manifest):
    """Inspect every file and ancestor once before hashing the inventory."""
    root = regular(root)
    checked = {}
    for row in manifest["files"]:
        name = row["path"]
        need(pack.protect_data.safe_name(name), "alias_unsafe_relative_path")
        path = root
        for part in name.split("/"):
            path = path / part
            if path not in checked:
                attributes = path.lstat()
                need(not (getattr(attributes, "st_file_attributes", 0)
                          & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
                     and not pack.protect_data.linked(path), "alias_reparse_path_forbidden")
                checked[path] = attributes
            attributes = checked[path]
        need(stat.S_ISREG(attributes.st_mode), "alias_runtime_path_not_regular")


def guard_release(root, trusted):
    """Reject every reparse tag before signed payload hashing can follow it."""
    regular(root); regular(trusted)
    raw = pack.read_metadata(file_path(root, pack.handoff.MANIFEST), pack.MAX_MANIFEST)
    manifest = pack.handoff.decode_json(raw)
    pack.runtime.validate_manifest(manifest)
    if root.absolute() == builder.BASE.absolute():
        expected_sha, expected_trusted = builder.BASE_SHA, builder.BASE_TRUSTED
    else:
        need(root.absolute() == CANDIDATE.absolute(), "alias_release_source_not_fixed")
        expected_sha, expected_trusted = CANDIDATE_SHA, TRUSTED
    need(trusted.absolute() == expected_trusted.absolute(), "alias_release_trust_source_not_fixed")
    need(manifest["content_sha256"] == expected_sha and manifest["file_count"] == builder.BASE_FILES,
         "alias_pinned_manifest_identity_mismatch")
    file_path(root, pack.handoff.SIGNATURE)
    guard_inventory(root, manifest)
    for name in (*pack.handoff.GATE_FILES, *pack.handoff.ENTRY_GATE_FILES,
                 pack.handoff.ACCESS_FILE, *web.POLICY_FILES):
        file_path(trusted, name)


def dota_pids():
    need(os.name == "nt", "alias_windows_required")
    script = ("$ErrorActionPreference='Stop';"
              "[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false);"
              "$d=@(Get-CimInstance Win32_Process -Filter \"name='dota2.exe'\");"
              "[ordered]@{dota_pids=@($d|ForEach-Object{$_.ProcessId})}|ConvertTo-Json -Compress")
    reply = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script],
                           capture_output=True, timeout=20, creationflags=subprocess.CREATE_NO_WINDOW)
    need(reply.returncode == 0 and len(reply.stdout) < 8192, "alias_process_check_failed")
    data = json.loads(reply.stdout.decode("utf-8-sig"))
    values = data.get("dota_pids")
    need(isinstance(values, list) and all(type(p) is int and p > 0 for p in values),
         "alias_process_check_failed")
    return values


def require_idle():
    need(not dota_pids(), "alias_dota_still_running")


def releases():
    guard_release(builder.BASE, builder.BASE_TRUSTED)
    guard_release(CANDIDATE, TRUSTED)
    for name in (*web.POLICY_FILES, "tools/lua_protection_policy.json"):
        file_path(ROOT, name)
    base, old, old_signature = builder.authenticate_base()
    with web.trusted_root(TRUSTED):
        candidate, new, signature, _ = pack.authenticate(CANDIDATE)
    need(new["content_sha256"] == CANDIDATE_SHA and new["file_count"] == builder.BASE_FILES,
         "alias_v06_identity_mismatch")
    need(signature["release_sequence"] == builder.RELEASE_SEQUENCE
         and signature["key_id"] == old_signature["key_id"], "alias_v06_signature_identity_mismatch")
    protected = builder.protected_paths(old)
    replacements = {name: file_path(candidate, name).read_bytes() for name in sorted(ALLOWLIST)}
    builder.audit_changes(old, new, replacements, protected)
    return dict(base=base, candidate=candidate, old=old, new=new,
                old_signature=old_signature, signature=signature,
                old_rows={r["path"]: r for r in old["files"]}, new_rows={r["path"]: r for r in new["files"]})


def old_receipt(target):
    path = file_path(target, RECEIPT)
    need(path.stat().st_size <= 65536, "alias_old_receipt_invalid")
    raw = path.read_bytes()
    need(web.sha(raw) == OLD_RECEIPT_SHA, "alias_old_receipt_changed")
    value = pack.handoff.decode_json(raw)
    need(value.get("ok") is True and value.get("kind") == "verified_online_policy_install"
         and value.get("status") == "INSTALLED_FULLY_VERIFIED"
         and value.get("content_sha256") == builder.BASE_SHA
         and value.get("release_sequence") == builder.BASE_SEQUENCE
         and value.get("runtime_files") == builder.BASE_FILES
         and value.get("online_cheats_allowed") is False and value.get("signature_valid") is True
         and value.get("full_before_verification") is True and value.get("full_after_verification") is True,
         "alias_old_receipt_invalid")
    return raw


def inspect():
    context = releases()
    target = target_path()
    raw = old_receipt(target)
    verify_runtime(target, context["old"])
    context.update(target=target, receipt=raw, receipt_row=row_bytes(raw))
    return context


def copy_verified(source, destination, row, boundary, *, owned=None):
    source = regular(source)
    verify_file(source, row)
    destination = prospective(destination, boundary)
    destination.parent.mkdir(parents=True, exist_ok=True)
    prospective(destination, boundary)  # Recheck newly created ancestors too.
    with source.open("rb") as read, destination.open("xb") as write:
        if owned is not None:
            owned[destination] = row
        shutil.copyfileobj(read, write, 1024 * 1024)
        write.flush(); os.fsync(write.fileno())
    verify_file(source, row)
    verify_file(destination, row)
    return destination


def write_verified(destination, raw, boundary, *, owned=None):
    destination = prospective(destination, boundary)
    destination.parent.mkdir(parents=True, exist_ok=True)
    prospective(destination, boundary)
    with destination.open("xb") as write:
        if owned is not None:
            owned[destination] = row_bytes(raw)
        write.write(raw); write.flush(); os.fsync(write.fileno())
    verify_file(destination, row_bytes(raw))
    return destination


def sibling(target, transaction_id, role):
    need(role in ("new", "old") and re.fullmatch(r"[a-f0-9]{32}", transaction_id), "alias_temp_identity_invalid")
    return prospective(target.with_name("." + target.name + ".uiqa_" + transaction_id + "_" + role + ".tmp"),
                       TARGET)


def atomic_replace(source, target, row, *, allow_missing=False):
    source, target = regular(source), regular(target, exists=not allow_missing)
    need(source.parent == target.parent and target_path() in target.parents, "alias_replace_path_invalid")
    relative = target.relative_to(target_path()).as_posix()
    need(relative in ALLOWLIST or relative == RECEIPT, "alias_replace_scope_invalid")
    need(re.fullmatch(r"\." + re.escape(target.name) + r"\.uiqa_[a-f0-9]{32}_(new|old)\.tmp", source.name),
         "alias_temp_identity_invalid")
    verify_file(source, row)
    os.replace(source, target)
    verify_file(target, row)


def journal(transaction, data):
    prospective(transaction / "transaction.json", STORE)
    pack.runtime.atomic_write_json(transaction / "transaction.json", data)


def cleanup_temporaries(temporaries):
    errors = []
    for path, row in temporaries.items():
        if not path.exists():
            continue
        try:
            regular(path)
            need(target_path() in path.parents and ".uiqa_" in path.name and path.name.endswith(".tmp"),
                 "alias_temp_identity_invalid")
            verify_file(path, row)
            path.unlink()  # Only a verified, transaction-owned individual file.
        except BaseException as error:
            errors.append(code(error))
    return errors


def release_lock(lock, raw):
    need(file_path(STORE, lock.name).read_bytes() == raw, "alias_lock_identity_changed")
    lock.unlink()


def rollback(context, backup, transaction_id, temporaries, changed):
    errors = []
    if changed:
        for name in (*sorted(ALLOWLIST), RECEIPT):
            try:
                row = context["receipt_row"] if name == RECEIPT else context["old_rows"][name]
                source = file_path(backup, name)
                target = prospective(context["target"] / name, context["target"])
                temporary = sibling(target, transaction_id, "old")
                copy_verified(source, temporary, row, context["target"], owned=temporaries)
                atomic_replace(temporary, target, row, allow_missing=True)
            except BaseException as error:
                errors.append(code(error))
    try:
        verify_runtime(context["target"], context["old"])
        need(file_path(context["target"], RECEIPT).read_bytes() == context["receipt"], "alias_receipt_restore_mismatch")
    except BaseException as error:
        errors.append(code(error))
    return dict(ok=not errors, full_old_runtime_verified=not errors, errors=errors, attempted=changed)


def updated_receipt():
    return pack.runtime.canonical_bytes(dict(ok=True, kind="verified_online_policy_install",
        status="INSTALLED_FULLY_VERIFIED", base_content_sha256=builder.BASE_SHA,
        content_sha256=CANDIDATE_SHA, release_sequence=builder.RELEASE_SEQUENCE,
        signature_valid=True, runtime_files=builder.BASE_FILES, changed_paths=sorted(ALLOWLIST),
        online_cheats_allowed=False, full_before_verification=True, full_after_verification=True,
        previous_receipt_sha256=OLD_RECEIPT_SHA)) + b"\n"


def run(*, apply=False):
    context = inspect()
    report = dict(ok=True, status="VERIFIED_READ_ONLY_PLAN", target="svt_w24", dry_run=not apply,
                  base_content_sha256=builder.BASE_SHA, content_sha256=CANDIDATE_SHA,
                  release_sequence=builder.RELEASE_SEQUENCE, runtime_files=builder.BASE_FILES,
                  changed_paths=sorted(ALLOWLIST), protected_modules_preserved=180,
                  old_receipt_sha256=OLD_RECEIPT_SHA, signature_valid=True,
                  full_old_installed_verification=True, full_candidate_verification=True,
                  tools_caches_preserved=True, game_started=False, workshop_upload_performed=False,
                  public_pins_changed=False, credentials_read=False, private_key_read=False)
    if not apply:
        report["dota_running"] = bool(dota_pids())
        return report
    require_idle()
    need(STORE.absolute() == (ROOT / "output/ui_qa_20261025/release/alias_updates").absolute(),
         "alias_backup_store_not_fixed")
    prospective(STORE, regular(ROOT))
    STORE.mkdir(parents=True, exist_ok=True)
    regular(STORE)
    lock = prospective(STORE / "active.lock", STORE)
    need(not lock.exists(), "alias_update_locked")
    transaction_id = uuid.uuid4().hex
    lock_raw = (transaction_id + "\n").encode("ascii")
    write_verified(lock, lock_raw, STORE)  # Exclusive create prevents two updaters.
    transaction = STORE / ("v06_" + transaction_id)
    backup, staging = transaction / "backup", transaction / "stage"
    temporaries, changed, backup_ready, stage = {}, False, False, "create_transaction"
    try:
        prospective(transaction, STORE).mkdir(exist_ok=False)
        journal(transaction, dict(status="PREPARING", old=builder.BASE_SHA, new=CANDIDATE_SHA))
        for name in (*sorted(ALLOWLIST), RECEIPT):
            stage = "backup_old_files"
            row = context["receipt_row"] if name == RECEIPT else context["old_rows"][name]
            copy_verified(file_path(context["target"], name), backup / name, row, transaction)
        backup_ready = True
        for name in sorted(ALLOWLIST):
            stage = "stage_new_files"
            row = context["new_rows"][name]
            copy_verified(file_path(context["candidate"], name), staging / name, row, transaction)
            temporary = sibling(file_path(context["target"], name), transaction_id, "new")
            copy_verified(file_path(staging, name), temporary, row, context["target"], owned=temporaries)
        stage = "recheck_before_replace"
        refreshed = releases()  # Full signed sources and exact-seven diff again.
        need(refreshed["old"] == context["old"] and refreshed["new"] == context["new"],
             "alias_source_manifest_changed")
        verify_runtime(context["target"], context["old"])
        need(old_receipt(context["target"]) == context["receipt"], "alias_old_receipt_changed")
        for name in (*sorted(ALLOWLIST), RECEIPT):
            row = context["receipt_row"] if name == RECEIPT else context["old_rows"][name]
            verify_file(file_path(backup, name), row)
        for name in sorted(ALLOWLIST):
            verify_file(file_path(staging, name), context["new_rows"][name])
        require_idle()
        journal(transaction, dict(status="REPLACING", old=builder.BASE_SHA, new=CANDIDATE_SHA))
        changed = True
        for index, name in enumerate(sorted(ALLOWLIST), 1):
            stage = "replace_runtime_%d" % index
            require_idle()
            target = file_path(context["target"], name)
            verify_file(target, context["old_rows"][name])
            atomic_replace(sibling(target, transaction_id, "new"), target, context["new_rows"][name])
        stage = "verify_new_runtime"
        verify_runtime(context["target"], context["new"])
        require_idle()
        stage = "replace_receipt"
        need(file_path(context["target"], RECEIPT).read_bytes() == context["receipt"], "alias_old_receipt_changed")
        raw = updated_receipt()
        target = file_path(context["target"], RECEIPT)
        temporary = sibling(target, transaction_id, "new")
        write_verified(temporary, raw, context["target"], owned=temporaries)
        atomic_replace(temporary, target, row_bytes(raw))
        stage = "verify_final_installation"
        verify_runtime(context["target"], context["new"])
        need(file_path(context["target"], RECEIPT).read_bytes() == raw, "alias_new_receipt_mismatch")
        require_idle()
        need(not cleanup_temporaries(temporaries), "alias_temp_cleanup_failed")
        journal(transaction, dict(status="INSTALLED_FULLY_VERIFIED", old=builder.BASE_SHA,
                                  new=CANDIDATE_SHA, full_after_verification=True))
        stage = "release_lock"
        release_lock(lock, lock_raw)
        report.update(status="UPDATED_FULLY_VERIFIED", transaction=str(transaction),
                      full_after_verification=True, receipt_updated=True, dota_running=False)
        return report
    except BaseException as error:
        recovery = rollback(context, backup, transaction_id, temporaries, changed) if backup_ready else \
            rollback(context, backup, transaction_id, temporaries, False)
        recovery["cleanup_errors"] = cleanup_temporaries(temporaries)
        if recovery["cleanup_errors"]:
            recovery["ok"] = False
        try:
            journal(transaction, dict(status="ROLLED_BACK" if recovery["ok"] else "RECOVERY_REQUIRED",
                                      failed_stage=stage, error=code(error), rollback=recovery))
        except BaseException:
            recovery["journal_write_failed"] = True
        try:
            release_lock(lock, lock_raw)
        except BaseException as unlock_error:
            recovery["lock_release_error"] = code(unlock_error)
            recovery["ok"] = False
        raise UpdateFailure(stage, error, recovery, transaction) from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Apply only after the fixed v05/v06 checks and Dota exit")
    args = parser.parse_args()
    try:
        result = run(apply=args.apply)
    except UpdateFailure as error:
        result = error.report
    except Exception as error:
        result = dict(ok=False, error=code(error), changed=False,
                      game_started=False, workshop_upload_performed=False)
    print(json.dumps(result, ensure_ascii=True))
    return 0 if result["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
