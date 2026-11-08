"""Record generated storage and refresh a read-only, dependency-aware review list.

No removal, move, compression, SDK, game, database or key-content operation.
Registration records are immutable and completed by a separate digest marker;
interrupted records remain visible and cannot be mistaken for completed records.
Only latest.json is replaceable. Receipt data is reduced to an explicit whitelist.

Refresh lists each directory once, stats entries and directory roots and uses the separate
Win32 metadata provider for file identities/allocation. It never hashes payloads.
Directory totals include descendants; physical identities may occur in several
directory rows, so only global_unique_storage_bytes is additive across roots.
All graph and scan limits fail closed; unknown allocation is never reported as 0.
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone, timedelta
import hashlib
import html
import io
import json
import os
from pathlib import Path, PureWindowsPath
import re
import stat
import sys
import time
import uuid

REPO = Path(__file__).resolve().parents[1]
LEDGER_ROOT = Path("D:/Survival_清理记录")
ROOTS = (
    "D:/Survival_MovieLab", "D:/survival_ui_backups", "D:/survival_安全工具",
    "D:/Survival_本地工具", "D:/Survival_本地排演", "D:/Survival_测试配置",
    "D:/Survival_发布候选", "D:/Survival_工坊备份", "D:/Survival_工坊输出",
    "D:/Survival_加密备份", "D:/Survival_密钥", "D:/Survival_排演归档",
    "D:/Survival_排演实验归档", "D:/Survival_清理归档", "D:/Survival_清理记录",
    "D:/Survival_双机测试",
)
KEY_ROOT = "D:/Survival_密钥"
ESSENTIAL_ROOTS = (KEY_ROOT, "D:/survival_安全工具", "D:/Survival_本地工具",
                   "D:/Survival_测试配置", "D:/Survival_双机测试", str(LEDGER_ROOT),
                   "D:/Survival_加密备份", "D:/survival_ui_backups", "D:/Survival_工坊备份", "D:/Survival_清理归档")
TRANSACTIONS = Path("D:/Survival_本地排演/complete_delivery_20261103")
AUTHORITY = REPO / "publishing/workshop/release_authority_complete_20261103.json"
HOOK = REPO / "tools/release_sdk_lineage_hook.py"
MAX_JSON = 32 * 1024 * 1024
MAX_DOCUMENTS = 2048
MAX_GRAPH_NODES = 250000
MAX_ENTRIES = 2000000
MAX_DEPTH = 64
SHA = re.compile(r"[0-9a-f]{64}\Z")
RECEIPT_NAMES = re.compile(
    r"(?:package|pipeline_inputs|production_preparation|proof|collection|projection|"
    r"unsigned_review|transaction|restored|interrupted_recovery|state|steam_upload_state|"
    r"_lua_protection_report|_release_manifest|_release_signature|ui_static_catalog_manifest|"
    r"release_authority_complete_20261103|baseline_package_0104|final_gen5_item_generator_strict|"
    r"online_signed_candidate|online_latest|[A-Za-z0-9_-]+_reference_scan|"
    r"[A-Za-z0-9_-]*(?:receipt|proof|plan|review|manifest|handoff|verification|execution)[A-Za-z0-9_-]*|"
    r"collect_request_[A-Za-z0-9_-]+)\.json\Z", re.I)
DIRECTORY_FIELDS = frozenset(("candidate", "view", "candidate_dir", "output", "package",
    "package_dir", "overlay", "trusted", "trusted_source", "parent_trusted", "parent_view",
    "unsigned_root", "artifact_root", "external_stage", "source_root", "destination",
    "install_folder", "backup_directory", "backup_folder", "original_directory", "parent_root"))
PATH_FIELDS = frozenset(("artifact_path", "log_path", "compiler_log", "plan_path", "full_manifest", "parent_vpk"))
SKIP_FIELDS = frozenset(("previous_release", "release_history", "reconciliation_history", "history",
    "argv", "environment", "env", "credentials", "tokens", "sessions", "players", "accounts",
    "private", "authentication", "auth", "source_sha256s", "source_readset", "plain_inputs",
    "protected_bindings", "protection_selected", "executed_operator_inputs", "resource_origins",
    "projected_rows", "coverage_ledger", "original_evidence"))


def need(ok, code):
    if not ok:
        raise ValueError(code)


def stamp():
    return datetime.now(timezone.utc).isoformat()


def canonical(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def json_object(raw):
    def unique(pairs):
        result = {}
        for name, value in pairs:
            need(name not in result, "duplicate_json_key")
            result[name] = value
        return result
    return json.loads(raw, object_pairs_hook=unique)


def normalized(value):
    """Pure Windows path validation; no resolving/following links or UNC aliases."""
    need(isinstance(value, (str, Path)), "absolute_windows_path_required")
    value = str(value).replace("\\", "/")
    need(re.match(r"^[A-Za-z]:/", value) is not None and len(value) > 3, "absolute_windows_path_required")
    parts = value[3:].split("/")
    need(len(parts) <= MAX_DEPTH and all(p and p not in (".", "..") and not p.endswith((".", " "))
        and not any(ord(c) < 32 or c in ':<>"|?*%' for c in p)
        and not re.fullmatch(r"(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?", p) for p in parts),
        "unsafe_or_ambiguous_path")
    return value[0].upper() + ":/" + "/".join(parts)


def key(path):
    return normalized(path).casefold()


def under(path, parent):
    a, b = key(path), key(parent)
    return a == b or a.startswith(b + "/")


def overlaps(a, b):
    return under(a, b) or under(b, a)


class PathIndex:
    """One prefix trie; bounded overlap lookup, not a full report scan per row."""
    def __init__(self, paths):
        self.root = {"children": {}, "ends": [], "samples": []}
        for path in paths:
            node = self.root
            for part in key(path).split("/"):
                if len(node["samples"]) < 4: node["samples"].append(path)
                node = node["children"].setdefault(part, {"children": {}, "ends": [], "samples": []})
            node["ends"].append(path)
            if len(node["samples"]) < 4: node["samples"].append(path)

    def matches(self, path):
        node = self.root; result = []
        for part in key(path).split("/"):
            result.extend(node["ends"][:4])
            node = node["children"].get(part)
            if node is None: return sorted(set(result))[:4]
        return sorted(set(result + node["samples"][:4] + node["ends"][:4]))[:4]


def reparse(info):
    return stat.S_ISLNK(info.st_mode) or bool(getattr(info, "st_file_attributes", 0) & 0x400)


def checked_chain(path):
    """Reject reparse points in existing ancestors before opening/writing."""
    path = Path(normalized(path))
    for item in reversed((path, *path.parents)):
        if item == Path(item.anchor):
            continue
        try:
            info = item.lstat()
        except FileNotFoundError:
            continue
        need(not reparse(info), "reparse_path_refused")
    return path


class ReceiptReader:
    def __init__(self, repo=REPO, roots=ROOTS):
        self.repo = Path(repo)
        self.roots = tuple(roots)
        self.cache = {}
        self.bytes_read = 0

    def permitted(self, path):
        path = normalized(path)
        need(not under(path, KEY_ROOT), "key_contents_forbidden")
        allowed = under(path, self.repo / "output") or key(path) == key(self.repo / "publishing/workshop/release_authority_complete_20261103.json")
        allowed |= any(under(path, root) for root in self.roots if key(root) != key(KEY_ROOT))
        need(allowed and RECEIPT_NAMES.fullmatch(PureWindowsPath(path).name), "not_a_whitelisted_receipt_path")
        return path

    def read(self, path, expected=None):
        path = self.permitted(path)
        if key(path) not in self.cache:
            need(len(self.cache) < MAX_DOCUMENTS, "receipt_document_budget_exceeded")
            p = checked_chain(path)
            info = p.lstat()
            need(stat.S_ISREG(info.st_mode) and info.st_size <= MAX_JSON, "bounded_regular_receipt_required")
            with p.open("rb") as stream:
                raw = stream.read(MAX_JSON + 1)
            need(len(raw) <= MAX_JSON, "receipt_size_budget_exceeded")
            value = json_object(raw)
            need(isinstance(value, dict), "receipt_object_required")
            self.cache[key(path)] = (value, digest(raw))
            self.bytes_read += len(raw)
        value, actual = self.cache[key(path)]
        need(expected is None or isinstance(expected, str) and SHA.fullmatch(expected) and actual == expected,
             "receipt_digest_mismatch")
        return value, actual


def facts_from_receipt(path, value, raw_sha, roots=ROOTS):
    """Extract only provenance, explicit artifact paths and bounded JSON refs."""
    artifacts, refs = {}, {}
    budget = 0

    def artifact(candidate, reason, directory=True):
        if not isinstance(candidate, str):
            return
        try:
            candidate = normalized(candidate)
        except ValueError:
            return
        if under(candidate, KEY_ROOT):
            return
        if not any(under(candidate, root) for root in roots):
            return
        if not directory or candidate.lower().endswith((".vpk", ".json", ".txt", ".log")):
            candidate = normalized(str(PureWindowsPath(candidate).parent))
        artifacts.setdefault(candidate, set()).add(reason)

    def visit(item, depth=0):
        nonlocal budget
        budget += 1
        need(budget <= MAX_GRAPH_NODES and depth <= 24, "receipt_graph_budget_exceeded")
        if isinstance(item, dict):
            if isinstance(item.get("path"), str) and isinstance(item.get("sha256"), str) and SHA.fullmatch(item["sha256"]):
                try:
                    candidate = normalized(item["path"])
                    if candidate.lower().endswith(".json"):
                        refs[(candidate, item["sha256"])] = {"path": candidate, "sha256": item["sha256"]}
                except ValueError:
                    pass
            for name, child in item.items():
                if name in SKIP_FIELDS:
                    continue
                if name in DIRECTORY_FIELDS:
                    artifact(child, name)
                elif name in PATH_FIELDS:
                    artifact(child, name, directory=False)
                if isinstance(child, (dict, list)):
                    visit(child, depth + 1)
        elif isinstance(item, list):
            for child in item:
                if isinstance(child, (dict, list)):
                    visit(child, depth + 1)

    visit(value)
    if PureWindowsPath(str(path)).name in ("production_preparation.json", "_lua_protection_report.json"):
        parent = PureWindowsPath(str(path)).parent
        if parent.name == "protected_lua":
            parent = parent.parent
        artifact(str(parent), "production_receipt_directory")
    sources = value.get("source_revisions", {})
    sources = {name: rev for name, rev in sources.items() if name in ("game", "content", "operator", "atlas_reference")
               and isinstance(rev, str) and re.fullmatch(r"[0-9a-f]{40}", rev)} if isinstance(sources, dict) else {}
    return {"receipt_path": normalized(path), "receipt_sha256": raw_sha,
            "receipt_kind": value.get("kind") if isinstance(value.get("kind"), str) and re.fullmatch(r"[A-Z0-9_]{1,160}", value["kind"]) else None,
            "receipt_status": value.get("status") if isinstance(value.get("status"), str) and re.fullmatch(r"[A-Z0-9_]{1,160}", value["status"]) else None,
            "release_sequence": value.get("release_sequence") if type(value.get("release_sequence")) is int else None,
            "source_revisions": sources,
            "artifacts": [{"path": p, "roles": sorted(roles)} for p, roles in sorted(artifacts.items())],
            "references": sorted(refs.values(), key=lambda v: (v["path"].casefold(), v["sha256"]))}


def new_file(path, raw):
    path = checked_chain(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


def record(receipt, *, repo=REPO, ledger_root=LEDGER_ROOT, reader=None):
    reader = reader or ReceiptReader(repo)
    value, raw_sha = reader.read(receipt)
    facts = facts_from_receipt(receipt, value, raw_sha)
    need(facts["artifacts"] or facts["references"], "receipt_has_no_known_storage_bindings")
    record_id = digest(canonical({"receipt_path": key(receipt), "receipt_sha256": raw_sha}))
    folder = checked_chain(Path(ledger_root) / "records")
    target, marker = folder / (record_id + ".json"), folder / (record_id + ".complete.json")
    if target.exists() or marker.exists():
        need(target.is_file() and marker.is_file(), "incomplete_registration_preserved")
        checked_chain(target); checked_chain(marker)
        need(target.stat().st_size <= MAX_JSON and marker.stat().st_size <= 4096, "bounded_registration_required")
        raw = target.read_bytes(); existing = json_object(raw); complete = json_object(marker.read_bytes())
        need(complete == {"record_id": record_id, "sha256": digest(raw), "status": "COMPLETE"}
             and existing.get("facts") == facts, "existing_registration_changed")
        return {"status": "ALREADY_RECORDED", "record_id": record_id, "record": str(target), "record_sha256": digest(raw)}
    raw = canonical({"schema": 1, "created_utc": stamp(), "record_id": record_id, "facts": facts})
    new_file(target, raw)
    new_file(marker, canonical({"record_id": record_id, "sha256": digest(raw), "status": "COMPLETE"}))
    return {"status": "RECORDED", "record_id": record_id, "record": str(target), "record_sha256": digest(raw)}


def dependency_closure(seeds, reader, roots=ROOTS):
    pending = list(seeds); seen = set(); documents = []; protected = {}; blockers = []
    while pending:
        reference = pending.pop()
        identity = (key(reference["path"]), reference.get("sha256"))
        if identity in seen:
            continue
        seen.add(identity)
        if len(seen) > MAX_DOCUMENTS:
            blockers.append("dependency_document_budget_exceeded"); break
        try:
            value, raw_sha = reader.read(reference["path"], reference.get("sha256"))
            facts = facts_from_receipt(reference["path"], value, raw_sha, roots)
            documents.append(facts)
            for row in facts["artifacts"]:
                protected.setdefault(row["path"], []).append(facts["receipt_path"])
            pending.extend(facts["references"])
        except (OSError, ValueError, TypeError, RecursionError):
            blockers.append("current_dependency_unreadable_or_changed:" + reference["path"])
    return {"documents": documents, "protected": protected, "blockers": sorted(set(blockers))}


def current_dependencies(reader, *, repo=REPO, transaction_root=TRANSACTIONS):
    repo = Path(repo); errors = []; seeds = []; protected = {}; pending_reports = set()
    authority_path = repo / "publishing/workshop/release_authority_complete_20261103.json"
    try:
        # Parse the constant only; never execute the hook or any publisher.
        raw_hook = checked_chain(repo / "tools/release_sdk_lineage_hook.py").read_bytes()
        need(len(raw_hook) <= 1024 * 1024, "hook_budget_exceeded")
        pin = re.search(rb"AUTHORITY_SHA256\s*=\s*['\"]([0-9a-f]{64})['\"]", raw_hook)
        need(pin is not None, "authority_pin_missing")
        auth, auth_sha = reader.read(authority_path, pin.group(1).decode("ascii"))
        report = normalized(auth["report_directory"])
        need(under(report, repo / "output"), "authority_report_outside_project_output")
        binding, _ = reader.read(repo / "output/test_entry_runtime/online_signed_candidate.json")
        need(binding["expected_newest"]["release_sequence"] == auth["release_sequence"], "candidate_sequence_mismatch")
        package, package_sha = reader.read(report + "/package.json", binding["candidate"]["package_report_sha256"])
        need(package.get("release_sequence") == auth["release_sequence"], "package_sequence_mismatch")
        need(all(package.get(field) == binding["candidate"].get(field) and package.get(field)
                 for field in ("content_sha256", "signed_manifest_sha256")), "candidate_binding_mismatch")
        pipeline_sha = package["pipeline_inputs_sha256"]
        need(isinstance(pipeline_sha, str) and SHA.fullmatch(pipeline_sha), "pipeline_pin_required")
        seeds += [{"path": report + "/pipeline_inputs.json", "sha256": pipeline_sha},
                  {"path": report + "/package.json", "sha256": package_sha}]
        for field in ("canonical_journal", "lineage_state"):
            doc, doc_sha = reader.read(auth[field])
            if field == "canonical_journal":
                facts = facts_from_receipt(auth[field], doc, doc_sha)
                for item in facts["artifacts"]:
                    protected.setdefault(item["path"], []).append("current_official_journal")
                # History attribution is deliberately not a protection edge.
            elif doc.get("pending") is not None:
                facts = facts_from_receipt(auth[field], {"pending": doc["pending"]}, doc_sha)
                for item in facts["artifacts"]:
                    protected.setdefault(item["path"], []).append("unclosed_publication_intent")
                seeds += facts["references"]
                pending = doc["pending"]
                if isinstance(pending, dict) and SHA.fullmatch(str(pending.get("report_sha256", ""))):
                    pending_reports.add(pending["report_sha256"])
                errors.append("publication_intent_pending")
    except (OSError, ValueError, KeyError, TypeError):
        errors.append("current_authority_or_journal_unavailable")

    transactions = []
    try:
        store = checked_chain(transaction_root)
        for number, entry in enumerate(os.scandir(store)):
            need(number < MAX_DOCUMENTS, "transaction_inventory_budget_exceeded")
            info = entry.stat(follow_symlinks=False)
            if reparse(info):
                protected[normalized(entry.path)] = ["transaction_reparse_unknown"]
                errors.append("transaction_reparse_unknown"); continue
            if not stat.S_ISDIR(info.st_mode):
                continue
            path = Path(entry.path); state = "UNKNOWN_OR_UNCLOSED"
            try:
                tx, _ = reader.read(path / "transaction.json")
                try:
                    restored, _ = reader.read(path / "restored.json")
                except FileNotFoundError:
                    restored, _ = reader.read(path / "interrupted_recovery.json")
                closed = (restored.get("status") in ("ORIGINAL0104_COMPLETE_SET_FULLY_RESTORED", "INTERRUPTED_NATIVE_REJECTED_ORIGINAL0104_FULLY_RECOVERED")
                          and restored.get("backups_preserved") is True
                          and isinstance(tx.get("original_files"), list) and bool(tx["original_files"])
                          and tx["original_files"] == restored.get("original_files")
                          and all(tx.get(k) and tx.get(k) == restored.get(k) for k in
                                  ("package_report_sha256", "content_sha256", "original_content_sha256", "signed_manifest_sha256")))
                if closed:
                    state = "RESTORED_RECEIPT_MATCHES_TRANSACTION"
            except (OSError, ValueError, TypeError):
                try: tx, _ = reader.read(path / "transaction.json")
                except (OSError, ValueError, TypeError): tx = {}
            if state == "UNKNOWN_OR_UNCLOSED":
                protected[normalized(path)] = ["unclosed_or_unknown_transaction"]
                value = tx.get("package_report_sha256")
                if isinstance(value, str) and SHA.fullmatch(value): pending_reports.add(value)
            transactions.append({"path": normalized(path), "state": state})
    except (OSError, ValueError):
        errors.append("transaction_inventory_unavailable")
    graph = dependency_closure(seeds, reader)
    for path, reasons in protected.items(): graph["protected"].setdefault(path, []).extend(reasons)
    graph["blockers"].extend(errors)
    graph["transactions"] = transactions
    graph["pending_report_sha256s"] = sorted(pending_reports)
    return graph


def historical_attribution(reader, ledger_root=LEDGER_ROOT, repo=REPO):
    """Index historical controls once; their dependencies are NOT active roots."""
    attribution = {}; reports = []; errors = []
    folder = Path(ledger_root) / "records"
    if folder.exists():
        try:
            checked_chain(folder)
            for number, entry in enumerate(os.scandir(folder)):
                need(number < 2 * MAX_DOCUMENTS, "registration_inventory_budget_exceeded")
                if not re.fullmatch(r"[0-9a-f]{64}\.json", entry.name): continue
                try:
                    p = checked_chain(entry.path); marker = checked_chain(p.with_name(p.stem + ".complete.json"))
                    need(p.stat().st_size <= MAX_JSON and marker.stat().st_size <= 4096, "registration_budget")
                    raw = p.read_bytes(); record_value = json.loads(raw); confirmation = json.loads(marker.read_bytes())
                    need(confirmation == {"record_id": p.stem, "sha256": digest(raw), "status": "COMPLETE"}, "registration_marker_mismatch")
                    facts = record_value["facts"]
                    reports.append(facts)
                    for item in facts["artifacts"]:
                        attribution.setdefault(normalized(item["path"]), []).append(facts["receipt_path"])
                except (OSError, ValueError, KeyError, TypeError): errors.append("incomplete_or_invalid_registration:" + entry.name)
        except (OSError, ValueError): errors.append("registration_inventory_unavailable")
    try:
        for number, entry in enumerate(os.scandir(Path(repo) / "output")):
            need(number < MAX_DOCUMENTS, "historical_inventory_budget_exceeded")
            info = entry.stat(follow_symlinks=False)
            if reparse(info) or not stat.S_ISDIR(info.st_mode): continue
            for name in ("package.json", "pipeline_inputs.json"):
                p = Path(entry.path) / name
                if not p.is_file(): continue
                try:
                    v, h = reader.read(p); facts = facts_from_receipt(p, v, h)
                    reports.append(facts)
                    for item in facts["artifacts"]:
                        attribution.setdefault(item["path"], []).append(facts["receipt_path"])
                except (OSError, ValueError, TypeError): errors.append("historical_report_unreadable:" + str(p))
    except (OSError, ValueError): errors.append("historical_report_inventory_unavailable")
    return {"artifacts": attribution, "reports": reports, "errors": errors}


def scan_storage(roots, provider, *, root_only=(KEY_ROOT,), excluded=(str(LEDGER_ROOT),), max_entries=MAX_ENTRIES, max_seconds=900):
    """Single scandir/lstat traversal; file-content reads are impossible here."""
    directories = {}; identities = {}; warnings = []; visited = 0; native_unknown = 0
    started = time.monotonic(); budget_exceeded = False
    root_keys = {key(p) for p in roots}; root_only = {key(p) for p in root_only}; excluded = tuple(excluded)
    stack = [(normalized(p), None, 0) for p in reversed(roots)]
    order = []
    while stack:
        path, parent, depth = stack.pop()
        row = {"path": path, "parent": parent, "status": "MEASURED", "logical_bytes": 0,
               "files": 0, "directories": 0, "unknown_files": 0, "errors": []}
        directories[key(path)] = row; order.append(key(path))
        try:
            info = Path(path).lstat()
            if reparse(info): row.update(status="REPARSE_NOT_FOLLOWED", logical_bytes=None); continue
            need(stat.S_ISDIR(info.st_mode), "root_not_directory")
            if key(path) in root_only:
                row.update(status="ROOT_METADATA_ONLY", logical_bytes=None); continue
            if any(under(path, item) for item in excluded):
                row.update(status="EXCLUDED_REPORT_STORAGE", logical_bytes=None); continue
            if depth > MAX_DEPTH:
                row.update(status="DEPTH_BUDGET_EXCEEDED", logical_bytes=None); continue
            with os.scandir(path) as entries:
                for entry in entries:
                    visited += 1
                    if visited > max_entries or time.monotonic() - started > max_seconds:
                        budget_exceeded = True
                        raise ValueError("scan_entry_budget_exceeded")
                    child = normalized(entry.path)
                    try:
                        item = entry.stat(follow_symlinks=False)
                        if reparse(item):
                            row["errors"].append("child_reparse_not_followed"); continue
                        if stat.S_ISDIR(item.st_mode):
                            stack.append((child, path, depth + 1)); row["directories"] += 1
                        elif stat.S_ISREG(item.st_mode):
                            row["files"] += 1; row["logical_bytes"] += item.st_size
                            metadata = provider.inspect_file(child, item)
                            identity, storage, links = metadata.get("identity"), metadata.get("storage_bytes"), metadata.get("number_of_links")
                            if (metadata.get("status") != "MEASURED" or not isinstance(identity, str) or not identity or type(storage) is not int or storage < 0
                                    or type(links) is not int or links < 1):
                                row["unknown_files"] += 1; native_unknown += 1; continue
                            group = identities.setdefault(identity, {"storage_bytes": storage, "number_of_links": links, "paths": [], "consistent": True})
                            if group["storage_bytes"] != storage or group["number_of_links"] != links:
                                group["consistent"] = False
                            group["paths"].append(child)
                        else: row["errors"].append("unsupported_entry_type")
                    except (OSError, ValueError, TypeError):
                        row["errors"].append("entry_metadata_unavailable")
        except FileNotFoundError: row.update(status="MISSING", logical_bytes=None)
        except (OSError, ValueError):
            row.update(status="SCAN_INCOMPLETE"); row["errors"].append("directory_scan_incomplete")
            if budget_exceeded:
                warnings.append("scan_entry_or_time_budget_exceeded")
                for pending_path, pending_parent, _ in stack:
                    directories[key(pending_path)] = {"path": pending_path, "parent": pending_parent, "status": "SCAN_INCOMPLETE",
                        "logical_bytes": None, "files": 0, "directories": 0, "unknown_files": 0, "errors": ["scan_entry_budget_exceeded"]}
                stack.clear()
    # Each directory receives child totals once. Unknown/excluded descendants
    # make the inclusive total unknown while retaining a known lower bound.
    for name in reversed(order):
        row = directories[name]; row["known_logical_bytes"] = row["logical_bytes"] or 0
        row["logical_complete"] = row["logical_bytes"] is not None and not row["errors"] and row["status"] == "MEASURED"
        for child in row.pop("_children", []):
            row["known_logical_bytes"] += child["known_logical_bytes"]
            row["files"] += child["files"]; row["unknown_files"] += child["unknown_files"]
            row["directories"] += child["directories"]
            row["logical_complete"] &= child["logical_complete"]
        row["logical_bytes"] = row["known_logical_bytes"] if row["logical_complete"] else None
        row["physical_known_unique_bytes"] = 0; row["physical_unknown_identities"] = 0
        if row["parent"] and key(row["parent"]) in directories:
            directories[key(row["parent"])].setdefault("_children", []).append(row)
    for row in directories.values():
        row.setdefault("known_logical_bytes", 0); row.setdefault("logical_complete", False)
        row.setdefault("physical_known_unique_bytes", 0); row.setdefault("physical_unknown_identities", 0)
    unique_total = 0; inconsistent = 0; linked_groups = 0; outside_links = 0
    for group in identities.values():
        owners = set()
        for path in group["paths"]:
            parent = normalized(str(PureWindowsPath(path).parent))
            while key(parent) in directories:
                owners.add(key(parent))
                if key(parent) in root_keys: break
                parent = normalized(str(PureWindowsPath(parent).parent))
        if group["number_of_links"] > 1: linked_groups += 1
        if group["number_of_links"] > len(group["paths"]): outside_links += 1
        if not group["consistent"]:
            inconsistent += 1
            for owner in owners: directories[owner]["physical_unknown_identities"] += 1
            continue
        unique_total += group["storage_bytes"]
        for owner in owners: directories[owner]["physical_known_unique_bytes"] += group["storage_bytes"]
    for row in directories.values():
        complete = row["logical_complete"] and row["unknown_files"] == 0 and row["physical_unknown_identities"] == 0
        row["physical_unique_bytes"] = row["physical_known_unique_bytes"] if complete else None
        row["potential_reclaimed_bytes"] = None  # allocation is not deletion eligibility
    complete = all(directories[k]["logical_complete"] for k in root_keys) and native_unknown == inconsistent == 0
    return {"rows": sorted(directories.values(), key=lambda r: key(r["path"])),
            "global_unique_storage_bytes": unique_total if complete else None,
            "global_known_unique_storage_bytes": unique_total,
            "unknown_file_metadata": native_unknown, "inconsistent_file_identities": inconsistent,
            "hardlink_groups": linked_groups, "groups_with_links_outside_scan": outside_links,
            "metrics": {"entries_statted": visited, "directory_lstat_calls": len(order), "payload_bytes_read": 0,
                        "provider": dict(provider.metrics), "elapsed_seconds": round(time.monotonic() - started, 3)}, "warnings": warnings}


def classify(path, graph, attribution, *, protected_index=None, historical_index=None):
    reasons = []
    for essential in ESSENTIAL_ROOTS:
        if under(path, essential): reasons.append("工具、配置或受保护根目录")
    protected_index = protected_index or PathIndex(graph["protected"])
    historical_index = historical_index or PathIndex(attribution)
    for protected in protected_index.matches(path):
        reasons.append("当前依赖或未收口事务：" + protected)
    if reasons:
        return "必须保留", sorted(set(reasons))
    if graph["blockers"]:
        return "来源未知", ["当前依赖核查不完整，禁止推断可删除"]
    matches = historical_index.matches(path)
    if matches:
        return "未发现当前引用，待复核", ["有历史回执归属；本次当前依赖未引用", "尚未作占用、官方下载及删除门禁核验"]
    return "来源未知", ["没有完整登记或无法唯一归属，禁止按日期推断"]


def publish_snapshot(report, root=LEDGER_ROOT):
    root = checked_chain(root)
    name = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + "_" + uuid.uuid4().hex[:8]
    folder = root / "snapshots" / name
    raw = canonical(report); new_file(folder / "storage.json", raw)
    text = io.StringIO(newline="")
    writer = csv.writer(text); writer.writerow(("目录", "状态", "逻辑字节", "物理唯一字节_行间可重叠", "已知逻辑下界", "原因"))
    for row in report["rows"]:
        writer.writerow((row["path"], row["retention_status"], row["logical_bytes"], row["physical_unique_bytes"], row["known_logical_bytes"], "；".join(row["retention_reasons"])))
    new_file(folder / "storage.csv", b"\xef\xbb\xbf" + text.getvalue().encode("utf8"))
    lines = ["项目存储保留记录单", "生成时间：" + report["created_shanghai"], "", "本工具只记录，不授权或执行删除。未知数值为空，不表示零。", "目录物理字节可能因硬链接重叠，不能逐行相加。", ""]
    for row in report["summary_rows"]:
        lines.append(f"{row['retention_status']} | {row['path']} | 逻辑字节={row['logical_bytes']} | " + "；".join(row["retention_reasons"]))
    new_file(folder / "说明.txt", ("\n".join(lines) + "\n").encode("utf8"))
    new_file(folder / "清理记录单.html", render_html(report).encode("utf8"))
    marker = {"status": "STORAGE_REVIEW_SNAPSHOT_COMPLETE_NOT_DELETE_AUTHORITY", "report": str(folder / "storage.json"), "sha256": digest(raw), "created_utc": report["created_utc"]}
    new_file(folder / "complete.json", canonical(marker))
    # Only the well-known latest pointer is replaceable; immutable snapshots
    # and append-only records are never rewritten or automatically removed.
    temporary = root / ("latest." + uuid.uuid4().hex + ".pending.json")
    new_file(temporary, canonical(marker)); checked_chain(root / "latest.json")
    os.replace(temporary, root / "latest.json")
    return marker


def render_html(report):
    """Standalone report; one DOM index, explicit user filtering only."""
    def size(value):
        return "未知" if value is None else f"{value / 1024 ** 3:.3f} GiB"
    def table_rows(rows):
        return "".join("<tr><td>" + html.escape(row["path"]) + "</td><td>" + html.escape(row["retention_status"])
                       + "</td><td>" + size(row["logical_bytes"]) + "</td><td>" + size(row["physical_unique_bytes"])
                       + "</td><td>" + html.escape("；".join(row["retention_reasons"])) + "</td></tr>" for row in rows)
    head = "<tr><th>目录</th><th>处理状态</th><th>逻辑大小</th><th>去重物理占用</th><th>依据</th></tr>"
    warnings = report["active_dependencies"]["blockers"] + report.get("observations", []) + report["attribution_errors"]
    return ("<!doctype html><html lang=zh-CN><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>"
            "<title>Survival 清理记录单</title><style>body{font:15px/1.6 system-ui,sans-serif;background:#f3f5f7;color:#172333;margin:28px}"
            "table{border-collapse:collapse;width:100%;background:white;margin:18px 0}td,th{border:1px solid #ccd4dd;padding:9px;text-align:left}"
            "td:first-child{overflow-wrap:anywhere}th{background:#dae4ef}input,select{padding:10px;margin:6px}small{color:#4c5f70}"
            ".notice{padding:15px;background:#fff3d2;border-left:5px solid #b58000}[hidden]{display:none}</style>"
            "<h1>Survival 清理记录单</h1><p>生成时间（北京时间）：" + html.escape(report["created_shanghai"]) + "</p>"
            "<p class=notice>本轮只读盘点，未删除旧包。‘未发现当前引用’仍须复核占用、恢复事务和官方下载门禁后才能删除。"
            "硬链接可能跨目录共享，表格各行不能相加；物理占用不等于可释放空间。未知数值不表示零。密钥目录不展开。</p>"
            "<h2>16个目录概览</h2><table>" + head + table_rows(report["summary_rows"]) + "</table>"
            "<h2>按产物复核</h2><input id=q aria-label=搜索目录 placeholder='搜索目录或依据'>"
            "<select id=state aria-label=筛选状态><option value=''>所有状态</option>"
            + "".join("<option>" + html.escape(v) + "</option>" for v in sorted({r["retention_status"] for r in report["rows"]}))
            + "</select><small id=count></small><table id=details>" + head + table_rows(report["rows"]) + "</table>"
            "<h2>核查提示</h2><ul>" + "".join("<li>" + html.escape(v) + "</li>" for v in warnings) + "</ul>"
            "<script>const q=document.getElementById('q'),s=document.getElementById('state'),c=document.getElementById('count');"
            "const rows=Array.from(document.querySelectorAll('#details tr')).slice(1).map(e=>({e,text:e.textContent.toLowerCase(),state:e.cells[1].textContent}));"
            "function filter(){const term=q.value.toLowerCase();let count=0;for(const r of rows){const hidden=(!r.text.includes(term))||(s.value&&r.state!==s.value);"
            "if(r.e.hidden!==!!hidden)r.e.hidden=!!hidden;if(!hidden)count++;}c.textContent=count+' / '+rows.length+'项';}"
            "q.addEventListener('input',filter);s.addEventListener('change',filter);filter();</script></html>")


def refresh(*, repo=REPO, ledger_root=LEDGER_ROOT, provider=None):
    if provider is None:
        from release_storage_metrics import MetadataProvider
        provider = MetadataProvider()
    reader = ReceiptReader(repo)
    graph = current_dependencies(reader, repo=repo)
    history = historical_attribution(reader, ledger_root, repo)
    # Pending transactions pin their exact package report and its original
    # producer closure; other historical reports remain attribution only.
    pending = set(graph["pending_report_sha256s"])
    for report in history["reports"]:
        if report["receipt_sha256"] in pending:
            extra = dependency_closure([{"path": report["receipt_path"], "sha256": report["receipt_sha256"]},
                                        {"path": str(PureWindowsPath(report["receipt_path"]).parent / "pipeline_inputs.json")}], reader)
            graph["blockers"] += extra["blockers"]
            graph["documents"] += extra["documents"]
            for path, reasons in extra["protected"].items(): graph["protected"].setdefault(path, []).extend(reasons)
            pending.discard(report["receipt_sha256"])
    if pending: graph["blockers"].append("unclosed_transaction_package_report_not_found")
    scan = scan_storage(ROOTS, provider, excluded=(str(ledger_root),))
    all_rows = scan.pop("rows")
    root_keys = {key(p) for p in ROOTS}
    # Report artifacts, not every internal source/resource subdirectory. The
    # underlying scan still measures every file once for shared identity totals.
    rows = [r for r in all_rows if key(r["path"]) in root_keys or r["parent"] and key(r["parent"]) in root_keys
            or under(r["path"], "D:/Survival_本地排演") and len(PureWindowsPath(r["path"]).parts) == 4]
    protected_index, historical_index = PathIndex(graph["protected"]), PathIndex(history["artifacts"])
    for row in rows:
        row["retention_status"], row["retention_reasons"] = classify(row["path"], graph, history["artifacts"],
                                                                  protected_index=protected_index, historical_index=historical_index)
        if row["status"] == "MISSING":
            row["retention_status"] = "已不存在"; row["retention_reasons"] = ["本次只读检查未发现此目录"]
        if row["status"] in ("REPARSE_NOT_FOLLOWED", "SCAN_INCOMPLETE", "DEPTH_BUDGET_EXCEEDED"):
            row["retention_status"] = "来源未知"; row["retention_reasons"].append("目录计量不完整")
        row["deletion_authorized"] = False
    top = [row for row in rows if any(key(row["path"]) == key(p) for p in ROOTS)]
    observations = []
    try:
        marker, _ = reader.read(Path(repo) / "output/test_entry_runtime/online_latest.json")
        if marker.get("restoration_required") is True:
            observations.append("最近联网入口留有恢复标记；须与真实事务及正式文件核对，记录单不执行恢复或关闭事务。")
    except (OSError, ValueError):
        observations.append("最近联网入口标记无法读取；本记录不证明恢复事务已关闭。")
    report = {"schema": 1, "status": "READ_ONLY_STORAGE_REVIEW_NOT_DELETE_AUTHORITY", "created_utc": stamp(),
              "created_shanghai": datetime.now(timezone(timedelta(hours=8))).isoformat(),
              "roots": list(ROOTS), "root_only": [KEY_ROOT], "excluded_from_measurement": [str(ledger_root)],
              "rows": rows, "summary_rows": top, "measurement": scan, "active_dependencies": graph, "observations": observations,
              "attribution_errors": history["errors"], "receipt_reads": len(reader.cache), "receipt_bytes_read": reader.bytes_read,
              "official_download_retirement_gate": "NOT_ASSERTED_USE_CANONICAL_RETIRE_PLAN_AND_FRESH_OCCUPANCY_CHECK",
              "delete_operations": 0, "move_operations": 0, "compression_operations": 0, "sdk_calls": 0}
    return publish_snapshot(report, ledger_root)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    registration = commands.add_parser("record", help="Append one actual generated receipt registration")
    registration.add_argument("--receipt", required=True, type=Path)
    commands.add_parser("refresh", help="Write a new metadata-only storage review and latest pointer")
    args = parser.parse_args(argv)
    try:
        result = record(args.receipt) if args.action == "record" else refresh()
        print(json.dumps(result, ensure_ascii=False, indent=2)); return 0
    except Exception as error:
        print(json.dumps({"status": "STORAGE_LEDGER_REFUSED_EXISTING_EVIDENCE_PRESERVED", "error_type": type(error).__name__,
                          "reason": str(error) if isinstance(error, ValueError) else "IO_OR_METADATA_OPERATION_FAILED",
                          "delete_operations": 0, "sdk_calls": 0}, ensure_ascii=False)); return 2


if __name__ == "__main__":
    raise SystemExit(main())
