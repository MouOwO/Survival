"""Complete0302 projection and isolated unsigned materialization.

This first stage deliberately cannot be installed as a publication recipe:
Unsigned preparation copies exact pinned bytes into a fresh external directory;
it grants no signature or publication authority. No fixed PAYLOADS/deferred set.
"""
from __future__ import annotations
import argparse
from collections import Counter
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys

TOOLS = Path(__file__).resolve().parents[1]
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
from complete_delivery_release_20261103 import ledger

ROOT = TOOLS.parent
EXECUTED_SOURCE_LF_SHA256 = hashlib.sha256(Path(__file__).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
REPORT = ROOT / "output/complete_delivery_release_20261107_v02"
SEQUENCE = 2026110702
MANIFEST = "_release_manifest.json"
SIGNATURE = "_release_signature.json"
MARKER = "_UNSIGNED_DO_NOT_INSTALL_OR_UPLOAD.json"
MAX_FILES = 100000
MAX_TREE_BYTES = 64 * 1024 ** 3
CHUNK = 1024 * 1024


def project(**inputs):
    audit = ledger.audit_complete(**inputs)
    parent = ledger.document(inputs["parent_raw"], inputs["parent_sha256"])
    old = ledger.parent_rows(parent); rows = {name: row.copy() for name, row in old.items()}
    changed, added, unchanged = {}, [], []
    for binding in audit["resource_bindings"]:
        name, target = binding["resource"], binding["output"]
        previous = old.get(name)
        if previous is not None and ledger.fingerprint(previous) == target:
            unchanged.append(name)
        else:
            changed[name] = target.copy()
            if previous is None:
                added.append(name)
            rows[name] = {**(previous or {}), "path": name, **target}
    for name in audit["removed_resources"]:
        del rows[name]
    ordered = [rows[name] for name in sorted(rows)]
    result = {"schema": 1, "status": "PLAN_ONLY_COMPLETE_RESOURCE_PROJECTION_NOT_PACKAGE", "release_sequence": SEQUENCE,
              "source_revisions": audit["source_revisions"], "parent_manifest_sha256": audit["parent_manifest_sha256"],
              "coverage_ledger": audit, "changed_resources": changed, "changed_runtime_paths": sorted(changed),
              "added_runtime_paths": sorted(added), "removed_runtime_paths": audit["removed_resources"],
              "reviewed_parent_identical_resources": sorted(unchanged), "projected_rows": ordered,
              "projected_rows_sha256": ledger.sha(ledger.canonical(ordered)), "files": len(rows), "bytes": sum(row["bytes"] for row in rows.values()),
              "unaffected_parent_rows_preserved": True, "comparison": "ACTUAL_AUTHENTICATED_PARENT_RESOURCE_BYTES_NOT_GIT_LABEL_DIFF",
              "steam_delivery": "COMPLETE_EXACT_FILE_SET_WITH_EXPLICIT_REMOVALS_NOT_OVERLAY_OR_HOTPATCH",
              "signed_package": False, "signature_valid": False, "native_admission_verified": False,
              "build_ready": False, "signing_ready": False, "publication_ready": False,
              "files_written": 0, "git_mutations": 0, "sdk_calls": 0, "journal_writes": 0}
    return {**result, "projection_sha256": ledger.sha(ledger.canonical(result))}


plan = project


def projected_manifest(parent, projection):
    """Use the existing runtime manifest's exact content-identity contract."""
    result = deepcopy(parent)
    ledger.need(result.get("schema") == 2 and result.get("kind") == "runtime_release_allowlist"
                and result.get("hash_algorithms") == ["md5", "sha256"], "runtime_dual_hash_manifest_required")
    result.update(files=deepcopy(projection["projected_rows"]), file_count=projection["files"], bytes=projection["bytes"],
                  by_directory=dict(sorted(Counter(row["path"].split("/")[0] for row in projection["projected_rows"]).items())))
    payload = {key: result[key] for key in ("schema", "kind", "hash_algorithms", "file_count", "bytes", "files")}
    # runtime.manifest_payload has no trailing newline; its JSON is ASCII/sorted.
    result["content_sha256"] = ledger.sha(ledger.canonical(payload)[:-1])
    return result


def _plain(value, *, exists=True, directory=None):
    value = Path(value)
    ledger.need(value.is_absolute() and ".." not in value.parts and value != Path(value.anchor), "absolute_non_root_path_required")
    for item in (value, *value.parents):
        if not os.path.lexists(item):
            continue
        info = item.lstat()
        ledger.need(not stat.S_ISLNK(info.st_mode) and not (getattr(info, "st_file_attributes", 0) & 0x400), "reparse_input_or_destination_refused")
    ledger.need(os.path.lexists(value) == exists, "existing_source_or_fresh_destination_required")
    if exists and directory is not None:
        ledger.need(value.is_dir() if directory else value.is_file(), "regular_source_type_required")
    return value.resolve(strict=exists)


def _inventory(root):
    names = set()
    for folder, dirs, files in os.walk(root, followlinks=False):
        for name in dirs:
            _plain(Path(folder) / name, directory=True)
        for name in files:
            entry = _plain(Path(folder) / name, directory=False)
            relative = entry.relative_to(root).as_posix(); ledger.path(relative)
            ledger.need(len(names) < MAX_FILES and relative.casefold() not in names, "tree_file_budget_or_case_collision")
            names.add(relative.casefold())
    return names


def _file_hash(value, target=None):
    """One streaming stable read, optional exclusive independent-file copy."""
    before = value.stat(); hashes = {"md5": hashlib.md5(usedforsecurity=False), "sha256": hashlib.sha256()}
    used = 0
    output = None
    try:
        if target is not None:
            target.parent.mkdir(parents=True, exist_ok=True)
            output = target.open("xb")
        with value.open("rb") as stream:
            for block in iter(lambda: stream.read(CHUNK), b""):
                used += len(block)
                ledger.need(used <= MAX_TREE_BYTES, "source_file_byte_budget_exceeded")
                for digest in hashes.values(): digest.update(block)
                if output is not None: output.write(block)
        if output is not None: output.flush(); os.fsync(output.fileno())
    finally:
        if output is not None: output.close()
    after = value.stat()
    ledger.need((before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
                == (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns) and used == before.st_size,
                "source_changed_during_read_or_copy")
    return {"bytes": used, **{name: digest.hexdigest() for name, digest in hashes.items()}}


def _write_new(path, raw):
    with path.open("xb") as stream:
        stream.write(raw); stream.flush(); os.fsync(stream.fileno())


def prepare_unsigned(*, inputs=None, reviewed_projection_raw=None, reviewed_projection_sha256=None,
                     parent_root=None, artifact_paths=None, destination=None, allowed_root=None, protected_paths=()):
    """Materialize an exact full unsigned tree; never execute code from receipts.

    ``inputs`` are audit_complete's raw documents. artifact_paths names EVERY
    reviewed binding, including parent-identical ones. allowed_root is explicit
    and must already exist; production callers use D:/Survival_发布候选. All
    sources/parents are checked before any output, copied (never hardlinked),
    then independently rehashed. Failures preserve the new partial directory
    and marker; no source, backup, package or old candidate is deleted.
    This verifies pinned parent bytes, not its detached signature: the common
    authenticated baseline/guard must still authenticate the original parent.
    """
    ledger.need(inputs is not None, "complete_unsigned_inputs_not_implemented_preserve_pending")
    reviewed = ledger.document(reviewed_projection_raw, reviewed_projection_sha256)
    actual = project(**inputs)
    ledger.need(ledger.canonical(reviewed) == ledger.canonical(actual), "reviewed_projection_changed_before_unsigned_preparation")
    parent = ledger.document(inputs["parent_raw"], inputs["parent_sha256"]); old = ledger.parent_rows(parent)
    manifest = projected_manifest(parent, actual)
    ledger.need(0 < len(old) <= MAX_FILES and manifest["file_count"] <= MAX_FILES
                and parent["bytes"] <= MAX_TREE_BYTES and manifest["bytes"] <= MAX_TREE_BYTES, "bounded_complete_runtime_tree_required")
    base = _plain(parent_root, directory=True); allowed = _plain(allowed_root, directory=True)
    target = _plain(destination, exists=False)
    ledger.need(target.parent == allowed and not target.is_relative_to(ROOT.parents[2])
                and not base.is_relative_to(target) and not target.is_relative_to(base), "fresh_external_candidate_child_required")
    for value in protected_paths:
        protected = _plain(value)
        ledger.need(not target.is_relative_to(protected) and not protected.is_relative_to(target), "protected_candidate_path_overlap")
    ledger.need(isinstance(artifact_paths, dict) and set(artifact_paths) == {b["resource"] for b in actual["coverage_ledger"]["resource_bindings"]},
                "exact_dynamic_artifact_path_set_required")
    artifacts = {name: _plain(value, directory=False) for name, value in artifact_paths.items()}
    ledger.need(all(not value.is_relative_to(target) for value in artifacts.values()), "artifact_destination_overlap")
    ledger.need(_plain(base / MANIFEST, directory=False).read_bytes() == inputs["parent_raw"]
                and (base / SIGNATURE).is_file(), "exact_parent_manifest_and_signature_presence_required")
    parent_signature = _file_hash(_plain(base / SIGNATURE, directory=False))
    ledger.need(_inventory(base) == {name.casefold() for name in old} | {MANIFEST, SIGNATURE}, "parent_contains_unknown_or_missing_files")
    for name, row in old.items():
        ledger.need(_file_hash(_plain(base / name, directory=False)) == ledger.fingerprint(row), "immutable_parent_file_hash_mismatch:" + name)
    for binding in actual["coverage_ledger"]["resource_bindings"]:
        ledger.need(_file_hash(artifacts[binding["resource"]]) == binding["output"], "target_artifact_hash_mismatch:" + binding["resource"])
    ledger.need(shutil.disk_usage(allowed).free >= manifest["bytes"] + 64 * 1024 * 1024, "unsigned_full_copy_disk_budget_exceeded")
    target.mkdir(exist_ok=False)
    marker = {"status": "UNSIGNED_COMPLETE_TREE_NOT_AUTHENTICATED_OR_PUBLISHABLE", "release_sequence": SEQUENCE,
              "projection_sha256": actual["projection_sha256"], "source_revisions": actual["source_revisions"],
              "parent_manifest_sha256": inputs["parent_sha256"], "content_sha256": manifest["content_sha256"],
              "signature_valid": False, "signing_key_read": False, "sdk_calls": 0}
    _write_new(target / MARKER, ledger.canonical(marker))
    for row in manifest["files"]:
        name = row["path"]; source = artifacts[name] if name in actual["changed_resources"] else base / name
        ledger.need(_file_hash(source, target / name) == ledger.fingerprint(row), "copied_runtime_file_hash_mismatch:" + name)
        ledger.need(not os.path.samefile(source, target / name), "unsigned_copy_must_have_independent_file_identity")
    _write_new(target / MANIFEST, ledger.canonical(manifest))
    ledger.need(_inventory(target) == {row["path"].casefold() for row in manifest["files"]} | {MANIFEST.casefold(), MARKER.casefold()}, "unsigned_exact_file_set_mismatch")
    for row in manifest["files"]:
        ledger.need(_file_hash(_plain(target / row["path"], directory=False)) == ledger.fingerprint(row), "unsigned_final_hash_mismatch")
    # Recheck original sources after all writes; never rewrite their metadata.
    for name, row in old.items():
        ledger.need(_file_hash(_plain(base / name, directory=False)) == ledger.fingerprint(row), "parent_changed_during_unsigned_preparation")
    for binding in actual["coverage_ledger"]["resource_bindings"]:
        ledger.need(_file_hash(artifacts[binding["resource"]]) == binding["output"], "artifact_changed_during_unsigned_preparation")
    ledger.need((base / MANIFEST).read_bytes() == inputs["parent_raw"] and _file_hash(base / SIGNATURE) == parent_signature,
                "parent_signed_metadata_changed_during_unsigned_preparation")
    return {**marker, "files": manifest["file_count"], "bytes": manifest["bytes"], "candidate": str(target),
            "removed_runtime_paths": actual["removed_runtime_paths"], "manifest_sha256": ledger.sha(ledger.canonical(manifest)),
            "parent_signature_sha256": parent_signature["sha256"], "full_parent_bytes_verified": True,
            "parent_signature_authenticated": False, "all_target_files_rehashed": True, "hardlinks_created": 0,
            "publication_ready": False, "native_admission_verified": False, "backend_deployment_performed": False}


def build_signed(*args, **kwargs):
    raise ValueError("complete_signing_native_and_publication_authority_not_implemented_preserve_pending")


def static_plan():
    return {"status": "PURE_COMPLETE_COVERAGE_PROJECTION_ONLY_NOT_REGISTERED_RELEASE_RECIPE", "release_sequence": SEQUENCE,
            "fixed_payload_list": False, "inherited_deferrals": False, "package_build_implemented": False,
            "unsigned_materialization_implemented": True,
            "files_written": 0, "signing_key_read": False, "sdk_calls": 0, "journal_writes": 0, "publication_ready": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args(argv)
    print(json.dumps(static_plan(), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
