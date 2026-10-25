"""Read-only audit, or explicitly borrow/restore the fixed svt_w24 alias.

Only the signed v08 -> v09 delta and local install marker are transacted. No
launcher, public release pin, protected module, credential or private key is
changed/read. Backups are small; the 3.5 GiB runtime is never copied wholesale.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import uuid

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_multiplayer_candidate as builder

ROOT, web, pack = builder.ROOT, builder.web, builder.pack
TARGET = ROOT.parent / "svt_w24"
CANDIDATE, TRUSTED = builder.DESTINATION, builder.TRUSTED_DESTINATION
CANDIDATE_SHA = "839fd6edb8373af2967d0cd7de93370fb737ed0e79200a9ae622624a27a6402d"
OLD_MARKER_SHA = "e1a03936b7a779a13835206970460e319ee8061eac3e58e5e0e38ee3f4815bfb"
MARKER = "_online_policy_install.json"
CACHES = frozenset(("tools_asset_info.bin", "tools_thumbnail_cache.sqlite3"))
STORE = ROOT / "output/arcade_multiplayer_20261025/alias_transactions"
SHARED = ROOT / "output/ui_qa_20261025/release/alias_updates"
CONTROLLED = builder.ALLOWLIST | builder.REMOVED | {MARKER}
METADATA = frozenset((pack.handoff.MANIFEST, pack.handoff.SIGNATURE))


def need(value, code):
    if not value:
        raise RuntimeError(code)


def error_code(error):
    value = str(error)
    return value if re.fullmatch(r"[a-z][a-z0-9_]{0,79}", value) else "mp_alias_operation_failed"


class TransactionFailure(RuntimeError):
    def __init__(self, error, stage, transaction, recovery):
        super().__init__(error_code(error))
        self.report = dict(ok=False, error=error_code(error), stage=stage, transaction=str(transaction),
                           recovery=recovery, game_started=False, private_key_read=False)


def regular(path, *, exists=True):
    path = Path(path).absolute()
    for part in (path, *path.parents):
        try:
            info = part.lstat()
        except FileNotFoundError:
            continue
        need(not stat.S_ISLNK(info.st_mode) and not (getattr(info, "st_file_attributes", 0) & 0x400),
             "mp_alias_links_forbidden")
        if stat.S_ISREG(info.st_mode):
            need(info.st_nlink == 1, "mp_alias_links_forbidden")
    need(not exists or path.exists(), "mp_alias_path_missing")
    return path


def fixed_paths():
    need(TARGET.absolute() == (ROOT.parent / "svt_w24").absolute(), "mp_alias_target_not_fixed")
    need(STORE.absolute() == (ROOT / "output/arcade_multiplayer_20261025/alias_transactions").absolute()
         and SHARED.absolute() == (ROOT / "output/ui_qa_20261025/release/alias_updates").absolute(),
         "mp_alias_store_not_fixed")
    target = regular(TARGET)
    need(target.is_dir() and target.name == "svt_w24", "mp_alias_target_not_fixed")
    return target


def file_path(root, name, *, exists=True):
    need(pack.protect_data.safe_name(name), "mp_alias_unsafe_relative_path")
    root = regular(root)
    path = regular(root / name, exists=exists)
    need(root in path.parents, "mp_alias_path_outside_root")
    return path


def row_bytes(raw):
    return dict(bytes=len(raw), md5=hashlib.md5(raw, usedforsecurity=False).hexdigest(), sha256=web.sha(raw))


def row_only(row):
    return None if row is None else {name: row[name] for name in ("bytes", "md5", "sha256")}


def actual_row(path):
    path = regular(path, exists=False)
    if not path.exists():
        return None
    need(path.is_file(), "mp_alias_not_regular_file")
    return pack.runtime.checksums(path)


def require_row(path, expected):
    need(actual_row(path) == row_only(expected), "mp_alias_compare_and_swap_conflict")


def inventory(root):
    """Inspect all names, including files outside the runtime selector."""
    root, names = regular(root), set()
    def fail(_):
        raise RuntimeError("mp_alias_inventory_unreadable")
    for folder, directories, files in os.walk(root, followlinks=False, onerror=fail):
        regular(folder)
        for name in directories:
            need(regular(Path(folder) / name).is_dir(), "mp_alias_not_regular_directory")
        for name in files:
            path = regular(Path(folder) / name)
            need(path.is_file(), "mp_alias_not_regular_file")
            names.add(path.relative_to(root).as_posix())
    return names


def verify_runtime(root, manifest, marker_raw):
    expected = {row["path"] for row in manifest["files"]}
    names = inventory(root)
    need(names - expected - CACHES - {MARKER} == set() and expected <= names,
         "mp_alias_unexpected_or_missing_files")
    require_row(file_path(root, MARKER), row_bytes(marker_raw))
    need(pack.runtime.verify(root, manifest)["ok"], "mp_alias_full_runtime_verification_failed")
    return {name: actual_row(file_path(root, name)) if name in names else None for name in sorted(CACHES)}


def guard_release(root, trusted, content_sha):
    root, trusted = regular(root), regular(trusted)
    raw = pack.read_metadata(file_path(root, pack.handoff.MANIFEST), pack.MAX_MANIFEST)
    manifest = pack.handoff.decode_json(raw)
    pack.runtime.validate_manifest(manifest)
    need(manifest["content_sha256"] == content_sha and manifest["file_count"] == builder.BASE_FILES,
         "mp_alias_release_identity_mismatch")
    provenance = "_ui_stackable_provenance.json" if root == regular(builder.BASE) else "_multiplayer_provenance.json"
    need(inventory(root) == {r["path"] for r in manifest["files"]} | METADATA | {provenance},
         "mp_alias_release_inventory_mismatch")
    for name in builder.trust_names():
        file_path(trusted, name)


def releases():
    need(isinstance(CANDIDATE_SHA, str) and re.fullmatch(r"[0-9a-f]{64}", CANDIDATE_SHA),
         "mp_alias_candidate_not_pinned")
    builder.require_review_pins()
    need(CANDIDATE == builder.DESTINATION and TRUSTED == builder.TRUSTED_DESTINATION,
         "mp_alias_candidate_not_fixed")
    guard_release(builder.BASE, builder.BASE_TRUSTED, builder.BASE_SHA)
    guard_release(CANDIDATE, TRUSTED, CANDIDATE_SHA)
    base, old, old_signature, old_metadata = builder.authenticate_base()
    with web.trusted_root(TRUSTED):
        candidate, new, signature, metadata = pack.authenticate(CANDIDATE)
    need(new["content_sha256"] == CANDIDATE_SHA and new["file_count"] == builder.BASE_FILES,
         "mp_alias_release_identity_mismatch")
    need(old_signature["release_sequence"] == builder.BASE_SEQUENCE
         and signature["release_sequence"] == builder.RELEASE_SEQUENCE
         and old_signature["key_id"] == signature["key_id"], "mp_alias_signature_identity_mismatch")
    for root in (base, candidate):
        pack.runtime.require_production(root)
        need(len(pack.handoff.configured_ids(root)) == 4, "mp_alias_four_accounts_required")
        need(b"enabled = true" in file_path(root, builder.WEB_CONFIG).read_bytes(), "mp_alias_web_auth_required")
    protected = builder.protected_paths(old)
    patches = {name: file_path(candidate, name).read_bytes() for name in builder.ALLOWLIST}
    builder.audit_changes(old, new, patches, protected)
    return dict(old=old, new=new, base=base, candidate=candidate, old_metadata=old_metadata,
                metadata=metadata, patches=patches, old_rows={r["path"]: r for r in old["files"]},
                new_rows={r["path"]: r for r in new["files"]})


def dota_pids():
    need(os.name == "nt", "mp_alias_windows_required")
    script = ("$ErrorActionPreference='Stop';"
              "[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false);"
              "$d=@(Get-CimInstance Win32_Process -Filter \"name='dota2.exe'\");"
              "[ordered]@{dota_pids=@($d|ForEach-Object{$_.ProcessId})}|ConvertTo-Json -Compress")
    result = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script],
                            capture_output=True, timeout=20, creationflags=subprocess.CREATE_NO_WINDOW)
    need(result.returncode == 0 and len(result.stdout) < 8192, "mp_alias_process_check_failed")
    values = json.loads(result.stdout.decode("utf-8-sig")).get("dota_pids")
    need(isinstance(values, list) and all(type(value) is int and value > 0 for value in values),
         "mp_alias_process_check_failed")
    return values


def require_idle():
    need(not dota_pids(), "mp_alias_dota_still_running")


def canonical(value):
    return pack.runtime.canonical_bytes(value) + b"\n"


def old_marker(target):
    raw = pack.read_metadata(file_path(target, MARKER), 65536)
    need(web.sha(raw) == OLD_MARKER_SHA, "mp_alias_old_marker_changed")
    value = pack.handoff.decode_json(raw)
    need(value.get("ok") is True and value.get("kind") == "verified_online_policy_install"
         and value.get("status") == "INSTALLED_FULLY_VERIFIED"
         and value.get("content_sha256") == builder.BASE_SHA and value.get("release_sequence") == builder.BASE_SEQUENCE
         and value.get("runtime_files") == builder.BASE_FILES and value.get("online_cheats_allowed") is False
         and value.get("signature_valid") is True and value.get("full_before_verification") is True
         and value.get("full_after_verification") is True, "mp_alias_old_marker_invalid")
    return raw


def new_marker(transaction_id):
    return canonical(dict(ok=True, kind="temporary_multiplayer_alias_install", status="INSTALLED_FULLY_VERIFIED",
        transaction_id=transaction_id, content_sha256=CANDIDATE_SHA, base_content_sha256=builder.BASE_SHA,
        release_sequence=builder.RELEASE_SEQUENCE, runtime_files=builder.BASE_FILES, signature_valid=True,
        online_cheats_allowed=False, offline_logic_test=False, full_before_verification=True,
        full_after_verification=True, previous_marker_sha256=OLD_MARKER_SHA))


def write_new(path, raw):
    path = regular(path, exists=False)
    need(not path.exists(), "mp_alias_exclusive_file_exists")
    path.parent.mkdir(parents=True, exist_ok=True)
    regular(path.parent)
    with path.open("xb") as stream:
        stream.write(raw); stream.flush(); os.fsync(stream.fileno())
    require_row(path, row_bytes(raw))


def atomic_document(path, expected, raw, transaction):
    require_row(path, expected)
    temporary = regular(transaction / "work" / (uuid.uuid4().hex + ".json.tmp"), exists=False)
    write_new(temporary, raw)
    require_row(path, expected)
    os.replace(temporary, path)
    require_row(path, row_bytes(raw))


def cas_change(context, transaction, name, before, raw):
    need(name in CONTROLLED, "mp_alias_mutation_scope_invalid")
    target = file_path(context["target"], name, exists=False)
    expected_after = None if raw is None else row_bytes(raw)
    allowed = (context["old_rows"].get(name), context["new_rows"].get(name)) if name != MARKER else (
        row_bytes(context["old_marker"]), row_bytes(context["new_marker"]))
    need(row_only(before) in [row_only(row) for row in allowed], "mp_alias_compare_and_swap_conflict")
    need(expected_after in [row_only(row) for row in allowed], "mp_alias_unreviewed_postimage")
    require_idle(); require_row(target, before)
    if raw is None:
        if before is not None:
            require_idle(); require_row(target, before); target.unlink()
    else:
        temporary = regular(transaction / "work" / (uuid.uuid4().hex + ".runtime.tmp"), exists=False)
        write_new(temporary, raw)
        target.parent.mkdir(parents=True, exist_ok=True)
        regular(target.parent)
        require_idle(); require_row(target, before)
        os.replace(temporary, target)
    require_row(target, expected_after)


def transition_rows(context):
    """A recovery may contain only unchanged signed files or exact old/new images."""
    names = inventory(context["target"])
    union = context["old_rows"].keys() | context["new_rows"].keys()
    need(not names - union - CACHES - {MARKER}, "mp_alias_unexpected_or_missing_files")
    for name in union:
        before, after = context["old_rows"].get(name), context["new_rows"].get(name)
        actual = actual_row(file_path(context["target"], name, exists=False))
        need(actual in (row_only(before), row_only(after)), "mp_alias_recovery_compare_and_swap_conflict")
    actual = actual_row(file_path(context["target"], MARKER, exists=False))
    need(actual in (row_bytes(context["old_marker"]), row_bytes(context["new_marker"])),
         "mp_alias_recovery_compare_and_swap_conflict")


def restore_images(context, transaction):
    transition_rows(context)
    for name in (*sorted(builder.ALLOWLIST | builder.REMOVED), MARKER):
        old = row_bytes(context["old_marker"]) if name == MARKER else context["old_rows"].get(name)
        path = file_path(context["target"], name, exists=False)
        actual = actual_row(path)
        if actual == row_only(old):
            continue
        raw = None if old is None else file_path(transaction / "backup", name).read_bytes()
        cas_change(context, transaction, name, actual, raw)
    return verify_runtime(context["target"], context["old"], context["old_marker"])


def read_json(path, maximum=262144):
    raw = pack.read_metadata(regular(path), maximum)
    return raw, pack.handoff.decode_json(raw)


def pointer_context(context):
    pointer = regular(STORE / "active.json", exists=False)
    if not pointer.exists():
        return None
    pointer_raw, value = read_json(pointer, 65536)
    identifier = value.get("transaction_id")
    need(isinstance(identifier, str) and re.fullmatch(r"[a-f0-9]{32}", identifier), "mp_alias_transaction_id_invalid")
    transaction = regular(STORE / identifier)
    plan_raw, plan = read_json(transaction / "plan.json")
    need(value == dict(kind="temporary_multiplayer_alias_pointer", transaction_id=identifier,
                       plan_sha256=web.sha(plan_raw), old=builder.BASE_SHA, new=CANDIDATE_SHA),
         "mp_alias_pointer_changed")
    need(plan.get("transaction_id") == identifier and plan.get("target") == "svt_w24"
         and plan.get("old") == builder.BASE_SHA and plan.get("new") == CANDIDATE_SHA
         and plan.get("old_marker_sha256") == OLD_MARKER_SHA, "mp_alias_plan_changed")
    backup = regular(transaction / "backup")
    expected = (builder.MODIFIED | builder.REMOVED | {MARKER})
    need(inventory(backup) == expected, "mp_alias_backup_inventory_changed")
    for name in expected:
        row = row_bytes(context["old_marker"]) if name == MARKER else context["old_rows"][name]
        require_row(file_path(backup, name), row)
    state_raw, state = read_json(transaction / "state.json", 65536)
    need(state.get("transaction_id") == identifier and state.get("status") in {
        "APPLYING", "ACTIVE", "RESTORING", "RECOVERY_REQUIRED", "RESTORED", "ROLLED_BACK"},
         "mp_alias_transaction_state_invalid")
    context.update(transaction=transaction, identifier=identifier, pointer_raw=pointer_raw,
                   state_raw=state_raw, state=state, new_marker=new_marker(identifier))
    return context


def old_marker_from_backup_or_target(context):
    pointer = regular(STORE / "active.json", exists=False)
    if not pointer.exists():
        return old_marker(context["target"])
    _, value = read_json(pointer, 65536)
    identifier = value.get("transaction_id")
    need(isinstance(identifier, str) and re.fullmatch(r"[a-f0-9]{32}", identifier), "mp_alias_transaction_id_invalid")
    return old_marker(regular(STORE / identifier / "backup"))


def state_write(context, status, **fields):
    raw = canonical(dict(transaction_id=context["identifier"], status=status, **fields))
    path = context["transaction"] / "state.json"
    try:
        atomic_document(path, row_bytes(context["state_raw"]), raw, context["transaction"])
    finally:
        if actual_row(path) == row_bytes(raw):
            context["state_raw"] = raw


def acquire_lock():
    regular(SHARED, exists=False).mkdir(parents=True, exist_ok=True)
    lock = regular(SHARED / "active.lock", exists=False)
    raw = ("mp09_" + uuid.uuid4().hex + "\n").encode("ascii")
    write_new(lock, raw)
    return lock, raw


def release_lock(lock, raw):
    require_row(lock, row_bytes(raw)); lock.unlink()


def clear_pointer(context):
    pointer = regular(STORE / "active.json")
    require_row(pointer, row_bytes(context["pointer_raw"])); pointer.unlink()


def apply_alias(context):
    require_idle()
    regular(STORE, exists=False).mkdir(parents=True, exist_ok=True)
    need(not regular(STORE / "active.json", exists=False).exists(), "mp_alias_transaction_already_active")
    lock, lock_raw = acquire_lock()
    transaction = STORE / uuid.uuid4().hex
    stage, pointer_created, outcome, failure = "prepare", False, None, None
    try:
        regular(transaction, exists=False).mkdir(exist_ok=False)
        context.update(transaction=transaction, identifier=transaction.name, new_marker=new_marker(transaction.name))
        for name in sorted(builder.MODIFIED | builder.REMOVED | {MARKER}):
            raw = context["old_marker"] if name == MARKER else file_path(context["target"], name).read_bytes()
            expected = row_bytes(context["old_marker"]) if name == MARKER else context["old_rows"][name]
            need(row_bytes(raw) == row_only(expected), "mp_alias_backup_source_changed")
            write_new(transaction / "backup" / name, raw)
        plan = canonical(dict(transaction_id=transaction.name, target="svt_w24", old=builder.BASE_SHA,
                              new=CANDIDATE_SHA, old_marker_sha256=OLD_MARKER_SHA, caches_before=context["caches"]))
        write_new(transaction / "plan.json", plan)
        context["state_raw"] = canonical(dict(transaction_id=transaction.name, status="APPLYING"))
        write_new(transaction / "state.json", context["state_raw"])
        context["pointer_raw"] = canonical(dict(kind="temporary_multiplayer_alias_pointer", transaction_id=transaction.name,
            plan_sha256=web.sha(plan), old=builder.BASE_SHA, new=CANDIDATE_SHA))
        verify_runtime(context["target"], context["old"], context["old_marker"])
        pack.inventory_unchanged(context["base"], context["old_metadata"])
        pack.inventory_unchanged(context["candidate"], context["metadata"])
        require_idle()
        atomic_document(STORE / "active.json", None, context["pointer_raw"], transaction)
        pointer_created = True
        for name in sorted(builder.ALLOWLIST | builder.REMOVED):
            stage = "apply_runtime"
            cas_change(context, transaction, name, context["old_rows"].get(name), context["patches"].get(name))
        stage = "verify_new_runtime"
        verify_runtime(context["target"], context["new"], context["old_marker"])
        stage = "commit_marker"
        cas_change(context, transaction, MARKER, row_bytes(context["old_marker"]), context["new_marker"])
        caches = verify_runtime(context["target"], context["new"], context["new_marker"])
        require_idle(); state_write(context, "ACTIVE", full_after_verification=True)
        outcome = dict(ok=True, status="TEMPORARY_V09_ACTIVE", transaction=str(transaction), caches=caches)
        return outcome
    except BaseException as error:
        recovery = dict(ok=True, status="NO_RUNTIME_CHANGE")
        pointer = regular(STORE / "active.json", exists=False)
        if not pointer_created and pointer.exists():
            pointer_created = actual_row(pointer) == row_bytes(context.get("pointer_raw", b""))
            if not pointer_created:
                recovery = dict(ok=False, status="RECOVERY_REQUIRED", error="mp_alias_pointer_changed")
        if pointer_created:
            try:
                require_idle(); restore_images(context, transaction)
                state_write(context, "ROLLED_BACK", error=error_code(error)); clear_pointer(context)
                recovery = dict(ok=True, status="V08_RESTORED_FULLY_VERIFIED")
            except BaseException as failure:
                recovery = dict(ok=False, status="RECOVERY_REQUIRED", error=error_code(failure))
                try: state_write(context, "RECOVERY_REQUIRED", error=error_code(failure))
                except BaseException: recovery["journal_write_failed"] = True
        failure = TransactionFailure(error, stage, transaction, recovery)
        raise failure from None
    finally:
        try: release_lock(lock, lock_raw)
        except BaseException as unlock_error:
            if failure is not None:
                failure.report["lock_release_error"] = error_code(unlock_error)
                failure.report["recovery"]["lock_preserved"] = True
            elif outcome is not None:
                outcome.update(ok=False, error=error_code(unlock_error), lock_preserved=True,
                               status="ALIAS_VERIFIED_LOCK_RECOVERY_REQUIRED")


def restore_alias(context):
    require_idle()
    lock, lock_raw = acquire_lock()
    outcome, failure = None, None
    try:
        # Recheck all public signed images and the immutable backup before CAS.
        pointer_context(context)
        transition_rows(context)
        require_idle(); state_write(context, "RESTORING")
        caches = restore_images(context, context["transaction"])
        require_idle(); state_write(context, "RESTORED", full_after_verification=True)
        clear_pointer(context)
        outcome = dict(ok=True, status="V08_RESTORED_FULLY_VERIFIED", transaction=str(context["transaction"]), caches=caches)
        return outcome
    except BaseException as error:
        recovery = dict(ok=False, status="RECOVERY_REQUIRED", error=error_code(error))
        try: state_write(context, "RECOVERY_REQUIRED", error=error_code(error))
        except BaseException: recovery["journal_write_failed"] = True
        failure = TransactionFailure(error, "restore", context["transaction"], recovery)
        raise failure from None
    finally:
        try: release_lock(lock, lock_raw)
        except BaseException as unlock_error:
            if failure is not None:
                failure.report["lock_release_error"] = error_code(unlock_error)
            elif outcome is not None:
                outcome.update(ok=False, error=error_code(unlock_error), lock_preserved=True,
                               status="ALIAS_VERIFIED_LOCK_RECOVERY_REQUIRED")


def run(*, apply=False, restore=False):
    need(not (apply and restore), "mp_alias_conflicting_modes")
    context = releases()
    context["target"] = fixed_paths()
    context["old_marker"] = old_marker_from_backup_or_target(context)
    active = pointer_context(context)
    if active:
        need(not apply, "mp_alias_transaction_already_active")
        if context["state"]["status"] == "ACTIVE" and not restore:
            context["caches"] = verify_runtime(context["target"], context["new"], context["new_marker"])
        else:
            transition_rows(context)
            context["caches"] = {name: actual_row(file_path(context["target"], name, exists=False)) for name in sorted(CACHES)}
    else:
        need(not restore, "mp_alias_no_active_transaction")
        context["caches"] = verify_runtime(context["target"], context["old"], context["old_marker"])
    report = dict(ok=True, status="VERIFIED_READ_ONLY_RESTORE_PLAN" if active else "VERIFIED_READ_ONLY_APPLY_PLAN",
        target="svt_w24", dry_run=not (apply or restore), old=builder.BASE_SHA, new=CANDIDATE_SHA,
        release_sequence=builder.RELEASE_SEQUENCE, runtime_files=builder.BASE_FILES, protected_modules_preserved=180,
        changed_paths=sorted(CONTROLLED), caches=context["caches"], game_started=False,
        private_key_read=False, public_pins_changed=False, online_cheats_allowed=False)
    if apply:
        report.update(apply_alias(context))
    elif restore:
        report.update(restore_alias(context))
    else:
        report["dota_running"] = bool(dota_pids())
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--apply", action="store_true", help="Temporarily install exact signed v09 while Dota is closed")
    modes.add_argument("--restore", action="store_true", help="Restore exact backed-up v08 while Dota is closed")
    args = parser.parse_args()
    try:
        result = run(apply=args.apply, restore=args.restore)
    except TransactionFailure as error:
        result = error.report
    except BaseException as error:
        result = dict(ok=False, error=error_code(error), game_started=False, private_key_read=False, changed=False)
    print(json.dumps(result, ensure_ascii=True))
    return 0 if result["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
