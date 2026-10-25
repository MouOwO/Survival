"""Build the additive onboarding release from a verified online baseline.

This tool performs local reads and creates a candidate directory only. It does
not contact a host, change a release pointer, apply SQL, or seal an operator.
"""
from __future__ import annotations

import argparse
import ast
from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import textwrap

ROOT = Path(__file__).resolve().parents[2]
TASK = ROOT / "tmp/onboarding_rollout_20261025"
SOURCE_COMMIT = "138dd727"
SERVICE = "backend/archive_backend/service.py"
POSTGRES = "backend/fishing_api/postgres.py"
ONBOARDING = "backend/archive_backend/onboarding.py"
MIGRATION_SOURCE = "server/aliyun/database/target/202610250001_onboarding.sql"
HARDEN_SOURCE = "server/aliyun/database/harden_onboarding.sql"
MIGRATION_PATH = "deploy/database/target/202610250001_onboarding.sql"
HARDEN_PATH = "deploy/database/harden_onboarding.sql"
SERVICE_ANCHOR = b'        kind = raw_command.get("kind") if isinstance(raw_command, dict) else None\n'
SERVICE_NEXT = b'        if not accepts(self.bundle, requested_hash, kind):'
SERVICE_ADDITION = b'''        # Account tutorial metadata has its own protocol and SQL persistence.
        # It neither settles rewards nor depends on a reward configuration hash.
        from .onboarding import KINDS as onboarding_kinds, command as onboarding_command
        if isinstance(kind, str) and kind in onboarding_kinds:
            try:
                return onboarding_command(self.app, payload)
            except ValueError as error:
                raise ArchiveError(str(error)) from error
'''


def need(condition, code):
    if not condition:
        raise ValueError(code)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def _command(tree):
    classes = [node for node in tree.body if isinstance(node, ast.ClassDef)
               and node.name == "ArchiveService"]
    need(len(classes) == 1, "archive_service_class_layout_invalid")
    methods = [node for node in classes[0].body if isinstance(node, ast.FunctionDef)
               and node.name == "command"]
    need(len(methods) == 1, "archive_command_layout_invalid")
    return methods[0]


def patch_service(source):
    """Insert precisely the reviewed branch; every original byte is retained."""
    need(isinstance(source, bytes), "archive_service_source_invalid")
    need(source.count(SERVICE_ANCHOR + SERVICE_NEXT) == 1,
         "archive_command_anchor_changed")
    need(b"from .onboarding import" not in source and
         b"onboarding_command" not in source,
         "archive_onboarding_branch_already_present")
    patched = source.replace(SERVICE_ANCHOR,
                             SERVICE_ANCHOR + SERVICE_ADDITION, 1)
    need(patched.replace(SERVICE_ADDITION, b"", 1) == source,
         "archive_original_bytes_changed")
    before, after = ast.parse(source), ast.parse(patched)
    reduced = deepcopy(after)
    method = _command(reduced)
    insertion = [index + 1 for index, node in enumerate(method.body)
                 if isinstance(node, ast.Assign) and len(node.targets) == 1
                 and isinstance(node.targets[0], ast.Name)
                 and node.targets[0].id == "kind"]
    need(len(insertion) == 1, "archive_command_kind_layout_invalid")
    offset = insertion[0]
    expected = ast.parse(textwrap.dedent(SERVICE_ADDITION.decode())).body
    need(ast.dump(ast.Module(body=method.body[offset:offset + 2], type_ignores=[]),
                  include_attributes=False) ==
         ast.dump(ast.Module(body=expected, type_ignores=[]), include_attributes=False),
         "archive_onboarding_branch_ast_changed")
    del method.body[offset:offset + 2]
    need(ast.dump(before, include_attributes=False) ==
         ast.dump(reduced, include_attributes=False),
         "archive_unrelated_ast_changed")
    compile(patched, "<onboarding-service-candidate>", "exec")
    return patched


def _source_at_commit(root, path):
    result = subprocess.run(["git", "show", SOURCE_COMMIT + ":" + path],
                            cwd=root, capture_output=True, check=False)
    need(result.returncode == 0, "reviewed_commit_source_missing")
    committed = result.stdout
    current = (root / path).read_bytes()
    # Preserve checked-out newline differences but reject a semantic/local
    # revision that has not received the same review as the approved commit.
    need(current.replace(b"\r\n", b"\n") == committed.replace(b"\r\n", b"\n"),
         "reviewed_source_worktree_changed")
    return committed.replace(b"\r\n", b"\n")


def _postgres_patch(root, source):
    path = root / "server/fishing_api_overrides/onboarding_postgres.py"
    spec = importlib.util.spec_from_file_location("onboarding_release_postgres_patch", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    patched = module.patch_postgres(source.decode("utf-8")).encode("utf-8")
    need(patched.replace(module.ADDITION.encode("utf-8"), b"", 1) == source,
         "postgres_original_bytes_changed")
    return patched


def _validate_baseline(baseline, baseline_root):
    required = {"release", "manifest_sha256", "manifest", "payment_release",
                "payment_manifest_sha256", "services", "bundle", "ledger",
                "functions", "all_backend_hashes", "tables", "columns", "definitions"}
    need(required <= baseline.keys(), "baseline_fields_missing")
    need(re.fullmatch(r"[A-Za-z0-9_.-]{1,100}", baseline["release"]) is not None,
         "baseline_release_invalid")
    need(baseline["bundle"]["hash"] == baseline["manifest"]["archive_bundle"],
         "baseline_bundle_mismatch")
    need(baseline["bundle"]["protocol"] == 1, "baseline_bundle_protocol_changed")
    tables = baseline["tables"]
    need(isinstance(tables, list) and len(set(tables)) == len(tables) and
         all(isinstance(name, str) and
             re.fullmatch(r"(?:public|payments)\.[a-z_][a-z0-9_]*", name)
             for name in tables), "baseline_table_inventory_invalid")
    for name in (SERVICE, POSTGRES):
        raw = (baseline_root / name).read_bytes()
        digest = baseline["all_backend_hashes"].get(name)
        need(digest == sha(raw) and baseline["manifest"]["files"].get(name) == digest,
             "baseline_backend_digest_changed")
    need(ONBOARDING not in baseline["all_backend_hashes"] and
         ONBOARDING not in baseline["manifest"]["files"],
         "baseline_already_has_onboarding")
    for name in ("goufayu-api.service", "goufayu-payment.service"):
        need(baseline["services"][name]["ActiveState"] == "active",
             "baseline_service_not_active")
    for identity in ("target/202610250001_onboarding.sql", "security/harden_onboarding.sql"):
        need(identity not in baseline["ledger"], "onboarding_migration_already_recorded")


def build(*, root=ROOT, baseline_file=TASK / "baseline.json",
          baseline_root=TASK / "baseline", destination=TASK / "candidate"):
    root, baseline_file, baseline_root, destination = map(
        Path, (root, baseline_file, baseline_root, destination))
    need(not destination.exists() and not destination.is_symlink(),
         "candidate_directory_already_exists")
    baseline_raw = baseline_file.read_bytes()
    baseline = json.loads(baseline_raw)
    _validate_baseline(baseline, baseline_root)
    # Build and validate all bytes before creating any output directory.
    overlay = {
        SERVICE: patch_service((baseline_root / SERVICE).read_bytes()),
        POSTGRES: _postgres_patch(root, (baseline_root / POSTGRES).read_bytes()),
        ONBOARDING: _source_at_commit(root, "server/archive_backend/onboarding.py"),
        MIGRATION_PATH: _source_at_commit(root, MIGRATION_SOURCE),
        HARDEN_PATH: _source_at_commit(root, HARDEN_SOURCE),
    }
    compile(overlay[ONBOARDING], "<onboarding-module-candidate>", "exec")
    migrations = [
        {"id": "target/202610250001_onboarding.sql", "path": MIGRATION_PATH,
         "sha256": sha(overlay[MIGRATION_PATH]), "transaction_wrapper": True},
        {"id": "security/harden_onboarding.sql", "path": HARDEN_PATH,
         "sha256": sha(overlay[HARDEN_PATH]), "transaction_wrapper": False},
    ]
    hashes = {name: sha(raw) for name, raw in overlay.items()}
    identity = sha(canonical({"parent_manifest": baseline["manifest_sha256"],
                              "overlay": hashes, "source_commit": SOURCE_COMMIT}))[:12]
    plan = {
        "format": 1, "kind": "survival_onboarding_v1", "source_commit": SOURCE_COMMIT,
        "baseline_sha256": sha(baseline_raw), "baseline": baseline,
        "archive_release": baseline["release"],
        "archive_manifest_sha256": baseline["manifest_sha256"],
        "archive_bundle": baseline["bundle"]["hash"],
        "bundle": baseline["bundle"]["hash"],
        "payment_release": baseline["payment_release"],
        "payment_manifest_sha256": baseline["payment_manifest_sha256"],
        "payment_pid": baseline["services"]["goufayu-payment.service"]["MainPID"],
        "services": baseline["services"], "ledger": baseline["ledger"],
        "functions": baseline["functions"],
        "all_backend_hashes": baseline["all_backend_hashes"],
        "new_release": "20261025-onboarding-" + identity,
        "rollback_release": "20261025-onboarding-safe-" + identity,
        "overlay": hashes, "safe_overlay": {POSTGRES: hashes[POSTGRES]},
        "migrations": migrations, "reward_bundle_changed": False,
        "existing_receipts_changed": False, "operator_sealed": False,
    }
    destination.mkdir(parents=True, exist_ok=False)
    for name, raw in overlay.items():
        target = destination / "overlay" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
    safe_target = destination / "safe_overlay" / POSTGRES
    safe_target.parent.mkdir(parents=True, exist_ok=True)
    safe_target.write_bytes(overlay[POSTGRES])
    (destination / "plan.json").write_bytes(canonical(plan))
    (destination / "build_report.json").write_bytes(canonical({
        "ok": True, "phase": "LOCAL_CANDIDATE_NOT_SEALED", "files": len(overlay),
        "new_release": plan["new_release"], "safe_release": plan["rollback_release"],
        "bundle": plan["bundle"], "backend_changes": 3, "sql_files": 2,
        "remote_actions": 0, "reward_bundle_changed": False,
        "service_original_bytes_preserved": True,
        "postgres_original_bytes_preserved": True,
    }))
    return plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, default=TASK / "baseline.json")
    parser.add_argument("--baseline-root", type=Path, default=TASK / "baseline")
    parser.add_argument("--destination", type=Path, default=TASK / "candidate")
    args = parser.parse_args()
    plan = build(baseline_file=args.baseline, baseline_root=args.baseline_root,
                 destination=args.destination)
    print(json.dumps({"ok": True, "phase": "LOCAL_CANDIDATE_NOT_SEALED",
                      "new_release": plan["new_release"],
                      "safe_release": plan["rollback_release"],
                      "bundle": plan["bundle"], "files": len(plan["overlay"]),
                      "remote_actions": 0}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
