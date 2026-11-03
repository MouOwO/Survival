"""Read-only, one-pass release artifact inventory. No deletion or SDK operation.

The pure producer indexes reports/paths once. The filesystem adapter lists only
the two release roots, their immediate directory entries and output/*/package.json.
It reads bounded JSON control files, never VPK volumes or recursive payload trees.
Unobserved occupancy/reparse safety and unarchived evidence remain unknown/blocked.
"""
from pathlib import Path
import hashlib
import json
import os
import stat
import time

from release_retention import ROOTS, _identity, _path, _Paths

CONTROL_NAMES = ("_release_manifest.json", "_release_signature.json", "_UNSIGNED_DO_NOT_INSTALL_OR_UPLOAD.json")
MAX_JSON = 8 * 1024 * 1024
ROLE_FIELDS = {"candidate": "view", "view": "view", "candidate_dir": "view", "unsigned_review": "unsigned",
               "output": "build", "package": "build", "package_dir": "build", "overlay": "temp", "trusted_source": "unknown"}
ROOT_PARTS = tuple(_path(root)[1] for root in ROOTS)


def _sha(raw):
    return hashlib.sha256(raw).hexdigest()


def _digest(value):
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def _canonical(raw):
    return json.dumps(raw, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def _under_roots(parts):
    return any(len(parts) > len(root) and parts[:len(root)] == root for root in ROOT_PARTS)


def _child(path):
    normalized, parts = _path(path)
    if not any(len(parts) == len(root) + 1 and parts[:len(root)] == root for root in ROOT_PARTS):
        raise ValueError("release_root_immediate_child_required")
    return normalized, parts


def _record(value):
    if isinstance(value, dict) and isinstance(value.get("document"), dict):
        return value["document"]
    return value if isinstance(value, dict) else {}


def _key(identity):
    return tuple(identity[k] for k in ("workshop_id", "release_sequence", "content_sha256"))


def _artifact_bindings(document):
    result = []
    for field, role in ROLE_FIELDS.items():
        value = document.get(field)
        if not isinstance(value, str):
            continue
        try:
            normalized, parts = _path(value)
            if normalized.lower().endswith(".vpk"):
                normalized, parts = _path(normalized.rsplit("\\", 1)[0])
            normalized, parts = _child(normalized)
            result.append((normalized, parts, role))
        except ValueError:
            pass
    return result


def produce_inventory(directory_snapshots, report_records, registered_report, canonical_journal,
                      active_baseline_paths, pending_report_sha256s, *, observations=None, evidence_confirmations=None):
    """Pure core; snapshots and report_records are explicit read-only observations.

    Report records: {path, sha256, document}. Snapshots: {path, entries,
    controls: {name: {sha256, bytes, document}}, root_reparse_point, scan_errors}.
    Safety observations are keyed by absolute artifact path, with explicit bool
    active/in_use/reparse_point. Evidence confirmations need preserved=True,
    identity, inventory_fingerprint and nonempty evidence_paths outside both
    release roots. Default missing information is never filled with False.
    """
    observations = observations or {}; evidence_confirmations = evidence_confirmations or {}
    global_errors = []; protected = {}; protection = _Paths(); baseline_index = _Paths()
    def protect(path):
        try:
            normalized, parts = _path(path, allow_drive_root=True)
            if parts not in protected:
                protected[parts] = normalized; protection.add(parts)
            return parts
        except (ValueError, TypeError):
            global_errors.append("invalid_active_protection_path"); return None
    for path in active_baseline_paths if isinstance(active_baseline_paths, (list, tuple, set)) else []:
        parts = protect(path)
        if parts: baseline_index.add(parts)
    if not isinstance(active_baseline_paths, (list, tuple, set)):
        global_errors.append("active_baseline_inventory_unknown")
    registered = _record(registered_report); current_identity = _identity(registered)
    journal = canonical_journal if isinstance(canonical_journal, dict) else {}
    journal_identity = _identity(journal)
    if not current_identity: global_errors.append("registered_package_identity_invalid")
    if not journal_identity: global_errors.append("current_journal_identity_unknown")
    valid_pending = isinstance(pending_report_sha256s, (set, list, tuple)) and all(_digest(v) for v in pending_report_sha256s)
    pending = set(pending_report_sha256s) if valid_pending else set()
    if not valid_pending:
        global_errors.append("pending_report_inventory_invalid")
    by_path = {}; by_identity = {}; by_content = {}; by_release_content = {}; known_shas = set(); valid_reports = []
    records = list(report_records) if isinstance(report_records, list) else []
    if isinstance(registered_report, dict) and "document" in registered_report:
        records.append(registered_report)
    for record in records:
        document = _record(record); identity = _identity(document)
        digest = record.get("sha256") if isinstance(record, dict) else None
        if not identity or not _digest(digest): continue
        known_shas.add(digest); valid_reports.append(record)
        ikey = _key(identity); by_identity.setdefault(ikey, []).append(record)
        by_content.setdefault(ikey[2], set()).add(ikey)
        by_release_content.setdefault((ikey[1], ikey[2]), set()).add(ikey)
        for path, parts, role in _artifact_bindings(document):
            by_path.setdefault(parts, []).append((identity, role, record))
            if identity == current_identity or identity == journal_identity or digest in pending:
                protect(path)
    if pending - known_shas: global_errors.append("pending_report_binding_unresolved")
    # Only current top-level journal paths matter. Historical entries are not
    # traversed: previous_release/release_history cannot pin every old artifact.
    for field in ("package", "install_folder"):
        value = journal.get(field)
        if isinstance(value, str): protect(value)
    download = journal.get("download")
    if isinstance(download, dict) and isinstance(download.get("install_folder"), str): protect(download["install_folder"])
    observation_index = {}; evidence_index = {}
    for source, destination in ((observations, observation_index), (evidence_confirmations, evidence_index)):
        if not isinstance(source, dict):
            global_errors.append("external_observation_inventory_invalid"); continue
        for path, value in source.items():
            try: destination[_path(path)[1]] = value
            except ValueError: global_errors.append("external_observation_path_invalid")
    rows = []; metrics = dict(report_records_indexed=len(valid_reports), report_path_bindings=sum(map(len, by_path.values())),
                               artifact_directories=0, control_files_used=0, payload_bytes_read=0, large_volume_files_hashed=0)
    snapshots = directory_snapshots if isinstance(directory_snapshots, list) else []
    if not isinstance(directory_snapshots, list): global_errors.append("directory_snapshot_inventory_invalid")
    for snapshot in snapshots:
        errors = list(global_errors); snapshot = snapshot if isinstance(snapshot, dict) else {}
        path, parts = snapshot.get("path"), None
        try: path, parts = _child(path)
        except (ValueError, TypeError): errors.append("artifact_path_outside_immediate_release_roots")
        metrics["artifact_directories"] += 1
        controls = snapshot.get("controls", {}); controls = controls if isinstance(controls, dict) else {}
        entries = snapshot.get("entries", []); entries = entries if isinstance(entries, list) else []
        errors.extend(snapshot.get("scan_errors", []) if isinstance(snapshot.get("scan_errors", []), list) else ["snapshot_scan_errors_unknown"])
        hashes = set(); sequences = set(); control_shas = {}; control_identities = {}
        for name, value in controls.items():
            if name not in CONTROL_NAMES or not isinstance(value, dict) or not _digest(value.get("sha256")) or not isinstance(value.get("document"), dict):
                errors.append("invalid_control_metadata"); continue
            metrics["control_files_used"] += 1; control_shas[name] = value["sha256"]
            document = value["document"]
            explicit_identity = _identity(document)
            if explicit_identity: control_identities[_key(explicit_identity)] = explicit_identity
            if "content_sha256" in document:
                if _digest(document["content_sha256"]): hashes.add(document["content_sha256"])
                else: errors.append("invalid_control_content_hash")
            if "release_sequence" in document:
                if type(document["release_sequence"]) is int and document["release_sequence"] > 0: sequences.add(document["release_sequence"])
                else: errors.append("invalid_control_release_sequence")
        if len(hashes) > 1 or len(sequences) > 1: errors.append("conflicting_control_identity")
        bindings = by_path.get(parts, []) if parts else []
        candidates = {_key(identity): identity for identity, _, _ in bindings}
        if not candidates and len(hashes) == 1:
            digest = next(iter(hashes))
            matches = by_release_content.get((next(iter(sequences)), digest), set()) if len(sequences) == 1 else by_content.get(digest, set())
            candidates = {ikey: dict(zip(("workshop_id", "release_sequence", "content_sha256"), ikey)) for ikey in matches}
        if control_identities:
            candidates = {key: value for key, value in candidates.items() if key in control_identities} if candidates else control_identities
        if hashes: candidates = {key: value for key, value in candidates.items() if key[2] in hashes}
        if sequences: candidates = {key: value for key, value in candidates.items() if key[1] in sequences}
        identity = next(iter(candidates.values())) if len(candidates) == 1 and "conflicting_control_identity" not in errors else None
        if identity is None: errors.append("artifact_identity_not_uniquely_bound")
        bound_records = by_identity.get(_key(identity), []) if identity else []
        matched_shas = sorted({record["sha256"] for record in bound_records})
        roles = {role for candidate, role, _ in bindings if candidate == identity}
        if "_UNSIGNED_DO_NOT_INSTALL_OR_UPLOAD.json" in controls: roles.add("unsigned")
        if not roles and "_release_manifest.json" in controls and "_release_signature.json" in controls: roles.add("view")
        kind = next(iter(roles)) if len(roles) == 1 else "unknown"
        if kind == "unknown": errors.append("artifact_role_unknown_or_ambiguous")
        references = []
        if identity and identity == current_identity: references.append("registered_current_package")
        if identity and identity == journal_identity: references.append("current_upload_journal")
        if pending.intersection(matched_shas): references.append("unclosed_rehearsal_report")
        if parts and baseline_index.overlaps(parts): references.append("explicit_active_baseline")
        if references and parts: protect(path)
        observation = observation_index.get(parts, {}); observation = observation if isinstance(observation, dict) else {}
        safety = {name: observation.get(name) if type(observation.get(name)) is bool else None for name in ("active", "in_use", "reparse_point")}
        if references: safety["active"] = True
        if snapshot.get("root_reparse_point") is True: safety["reparse_point"] = True
        size = None; estimated = False
        if kind == "build":
            if entries and all(isinstance(e, dict) and e.get("kind") == "file" and type(e.get("bytes")) is int and e["bytes"] >= 0 for e in entries):
                size = sum(e["bytes"] for e in entries)
                expected = set()
                for record in bound_records:
                    files = _record(record).get("package_files")
                    if isinstance(files, list) and all(isinstance(f, dict) and isinstance(f.get("name"), str) and type(f.get("bytes")) is int for f in files):
                        expected.add(tuple(sorted((f["name"], f["bytes"]) for f in files)))
                if len(expected) != 1 or tuple(sorted((e["name"], e["bytes"]) for e in entries)) not in expected:
                    errors.append("build_file_set_not_uniquely_bound_to_report")
            else: errors.append("build_size_or_nested_contents_unknown")
        else:
            manifest = controls.get("_release_manifest.json", {}).get("document", {})
            if isinstance(manifest, dict) and type(manifest.get("bytes")) is int and manifest["bytes"] >= 0:
                size = manifest["bytes"]; estimated = True
            else: errors.append("artifact_size_unknown")
        fingerprint = _sha(_canonical(dict(path=path, controls=control_shas, entries=entries, reports=matched_shas)))
        evidence = evidence_index.get(parts, {}); evidence = evidence if isinstance(evidence, dict) else {}
        evidence_paths = evidence.get("evidence_paths", [])
        archived = (evidence.get("preserved") is True and evidence.get("identity") == identity and identity is not None
                    and evidence.get("inventory_fingerprint") == fingerprint and isinstance(evidence_paths, list) and bool(evidence_paths))
        if archived:
            for item in evidence_paths:
                try:
                    ep = _path(item)[1]
                    if _under_roots(ep): archived = False
                except ValueError: archived = False
        if not archived: evidence_paths = []
        reasons = list(dict.fromkeys(errors))
        references += ["inventory_blocked:" + code for code in reasons]
        row = dict(path=path, kind=kind, bytes=size, bytes_estimated=estimated, **safety,
                   referenced_by=references, evidence_preserved=archived, evidence_paths=evidence_paths,
                   inventory_fingerprint=fingerprint, bound_report_sha256s=matched_shas,
                   inventory_blockers=reasons, payload_content_verification="NOT_RUN_CONTROL_METADATA_ONLY")
        if identity: row.update(identity)
        row["inventory_status"] = "BLOCKED" if reasons or references or not archived or any(value is not False for value in safety.values()) else "OBSERVED_UNREFERENCED_ARTIFACT"
        rows.append(row)
    return dict(schema=1, inventory=rows, protected_paths=sorted(protected.values(), key=str.casefold),
                blockers=list(dict.fromkeys(global_errors)), metrics=metrics, deletion_actions=0, sdk_actions=0,
                execution_revalidation_required=True)


def scan_inventory(repo_root, registered_report_path, journal_path, active_baseline_paths, pending_report_sha256s,
                   *, observations=None, evidence_confirmations=None, root_map=None):
    """Offline filesystem adapter. root_map only maps fixed logical roots for tests."""
    started = time.perf_counter(); metrics = dict(json_reads=0, control_bytes_read=0, directory_lists=0, stat_calls=0)
    def reparse(info):
        return stat.S_ISLNK(info.st_mode) or bool(getattr(info, "st_file_attributes", 0) & 0x400)
    def read(path):
        info = path.lstat(); metrics["stat_calls"] += 1
        if reparse(info) or not stat.S_ISREG(info.st_mode) or info.st_size > MAX_JSON: raise ValueError("unsafe_or_oversized_control_file")
        with path.open("rb") as stream: raw = stream.read(MAX_JSON + 1)
        if len(raw) > MAX_JSON: raise ValueError("oversized_control_file")
        document = json.loads(raw); metrics["json_reads"] += 1; metrics["control_bytes_read"] += len(raw)
        if not isinstance(document, dict): raise ValueError("control_json_object_required")
        return dict(path=str(path), sha256=_sha(raw), bytes=len(raw), document=document)
    registered = read(Path(registered_report_path)); journal = read(Path(journal_path))["document"]
    records = []; snapshots = []; scan_errors = []
    output = Path(repo_root) / "output"
    if output.is_dir():
        metrics["directory_lists"] += 1
        for directory in output.iterdir():
            info = directory.lstat(); metrics["stat_calls"] += 1
            if reparse(info) or not stat.S_ISDIR(info.st_mode): continue
            candidate = directory / "package.json"
            if candidate.exists():
                try: records.append(read(candidate))
                except (OSError, ValueError, json.JSONDecodeError): scan_errors.append("unreadable_package_report")
    mapping = root_map or {root: Path(root) for root in ROOTS}
    for logical in ROOTS:
        physical = Path(mapping[logical])
        try:
            info = physical.lstat(); metrics["stat_calls"] += 1
            if reparse(info) or not stat.S_ISDIR(info.st_mode): raise ValueError("unsafe_release_root")
            metrics["directory_lists"] += 1
            for child in physical.iterdir():
                info = child.lstat(); metrics["stat_calls"] += 1
                is_link = reparse(info)
                if not stat.S_ISDIR(info.st_mode) and not is_link: continue
                snapshot = dict(path=logical + "/" + child.name, root_reparse_point=is_link, controls={}, entries=[], scan_errors=[])
                if is_link: snapshot["scan_errors"].append("artifact_root_reparse_point")
                else:
                    try:
                        metrics["directory_lists"] += 1
                        for entry in child.iterdir():
                            item = entry.lstat(); metrics["stat_calls"] += 1
                            entry_kind = "reparse" if reparse(item) else "directory" if stat.S_ISDIR(item.st_mode) else "file" if stat.S_ISREG(item.st_mode) else "unknown"
                            snapshot["entries"].append(dict(name=entry.name, kind=entry_kind, bytes=item.st_size if entry_kind == "file" else None))
                        snapshot["entries"].sort(key=lambda e: e["name"])
                        for name in CONTROL_NAMES:
                            control = child / name
                            if control.exists(): snapshot["controls"][name] = read(control)
                    except (OSError, ValueError, json.JSONDecodeError): snapshot["scan_errors"].append("artifact_control_scan_failed")
                snapshots.append(snapshot)
        except (OSError, ValueError): scan_errors.append("release_root_scan_incomplete")
    result = produce_inventory(snapshots, records, registered, journal, active_baseline_paths, pending_report_sha256s,
                               observations=observations, evidence_confirmations=evidence_confirmations)
    if "release_root_scan_incomplete" in scan_errors:
        result["blockers"].append("release_root_scan_incomplete")
        for row in result["inventory"]:
            row["inventory_status"] = "BLOCKED"; row["referenced_by"].append("inventory_blocked:release_root_scan_incomplete")
    result["scan_warnings"] = scan_errors; result["metrics"].update(metrics)
    result["metrics"]["elapsed_seconds"] = round(time.perf_counter() - started, 6)
    return result
