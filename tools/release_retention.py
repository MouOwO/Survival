"""Pure post-delivery retirement planning; this module never deletes files.

Index construction is O(total path components + references), overlap lookup
O(path depth), with O(N log N) deterministic ordering. No recurring scan, SDK,
filesystem, network, process-control or journal-writing operation exists here.
Every plan still requires a fresh physical inventory/path/lock check at execution.
"""
from collections import Counter
import re

ROOTS = ("D:/Survival_发布候选", "D:/Survival_工坊输出")
RETIRABLE = frozenset(("build", "view", "unsigned", "temp"))
IDENTITY = ("workshop_id", "release_sequence", "content_sha256")
PROTECTED_FLAGS = ("current_upload", "current_install", "parent_baseline", "pending_restore",
                   "key", "keys", "backend", "user_backup", "player_backup")


def _path(value, *, allow_drive_root=False):
    if (not isinstance(value, str) or not re.match(r"^[A-Za-z]:[\\/]", value)
            or any(ord(c) < 32 for c in value)):
        raise ValueError("absolute_windows_path_required")
    body = value[3:]
    if not body and allow_drive_root:
        return value[0].upper() + ":\\", (value[:2].casefold(),)
    parts = re.split(r"[\\/]", body)
    if (not body or any(not p or p in (".", "..") or p.endswith((".", " "))
                        or any(c in p for c in ':<>"|?*%')
                        or re.fullmatch(r"(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?", p)
                        for p in parts)):
        raise ValueError("unsafe_or_ambiguous_windows_path")
    return value[0].upper() + ":\\" + "\\".join(parts), (value[:2].casefold(), *(p.casefold() for p in parts))


class _Paths:
    def __init__(self):
        self.root = dict(children={}, ends=0, count=0)

    def add(self, parts):
        node = self.root
        node["count"] += 1
        for part in parts:
            node = node["children"].setdefault(part, dict(children={}, ends=0, count=0))
            node["count"] += 1
        node["ends"] += 1

    def overlaps(self, parts, *, ignore_exact=False):
        node = self.root
        for part in parts:
            if node["ends"]:
                return True
            node = node["children"].get(part)
            if node is None:
                return False
        return node["count"] > (node["ends"] if ignore_exact else 0)


def _identity(value):
    if not isinstance(value, dict):
        return None
    result = {key: value.get(key) for key in IDENTITY}
    if (not isinstance(result["workshop_id"], str)
            or re.fullmatch(r"[1-9][0-9]{0,19}", result["workshop_id"]) is None
            or type(result["release_sequence"]) is not int or result["release_sequence"] <= 0
            or not isinstance(result["content_sha256"], str)
            or re.fullmatch(r"[a-f0-9]{64}", result["content_sha256"]) is None):
        return None
    return result


def _verified_target(state):
    if (not isinstance(state, dict) or state.get("status") != "WORKSHOP_SYNCED"
            or state.get("workshop_synchronized") is not True
            or state.get("source_binding_state") != "DUAL_SOURCE_BOUND"
            or state.get("upload_evidence_matches_target") is not True
            or state.get("official_download_evidence_matches_target") is not True
            or state.get("blockers") != [] or state.get("pending_resource_changes") != []
            or state.get("pending_source_changes") != []):
        return None
    sources = state.get("target_source_revisions")
    if (not isinstance(sources, dict) or set(sources) != {"game", "content"}
            or any(not isinstance(v, str) or re.fullmatch(r"[a-f0-9]{40}", v) is None for v in sources.values())):
        return None
    target = _identity(state.get("local_version"))
    return target if target and target == _identity(state.get("uploaded_version")) == _identity(state.get("downloaded_version")) else None


def _reserved_scope(parts):
    for part in parts[1:]:
        words = set(re.split(r"[_\-\s]+", part))
        if words.intersection(("backup", "backups", "rehearsal", "keys", "key", "backend")) or any(word in part for word in ("备份", "排演", "密钥")):
            return True
    return False


def plan_retirement(inventory, protected_paths, delivery_state):
    """Plan only old unreferenced immutable artifacts after verified delivery.

    Rows require path, kind, bytes, active=False, in_use=False,
    reparse_point=False, referenced_by=[], evidence_preserved=True and exact
    workshop_id/release_sequence/content_sha256 (directly or in ``package``).
    Optional evidence_paths must be outside each deletion target. Any protected
    role/flag or unknown safety state blocks that row. All receipts must remain
    outside retired directories. The caller must validate real paths, complete
    contents and process/file locks again before executing a returned plan.
    """
    target = _verified_target(delivery_state)
    global_reasons = [] if target else ["new_target_not_fully_workshop_synced"]
    if not isinstance(inventory, list) or len(inventory) > 10000:
        return dict(schema=1, status="BLOCKED", verified_target=target, retire=[], blocked=[], retire_bytes=0,
                    blockers=[*global_reasons, "bounded_inventory_list_required"], filesystem_actions=0, execution_revalidation_required=True)
    protection = _Paths()
    if not isinstance(protected_paths, list) or len(protected_paths) > 10000:
        global_reasons.append("protected_path_inventory_invalid")
    else:
        for path in protected_paths:
            try:
                protection.add(_path(path, allow_drive_root=True)[1])
            except ValueError:
                global_reasons.append("protected_path_inventory_invalid")
                break
    rows, candidate_paths = [], _Paths()
    for index, raw in enumerate(inventory):
        reasons = list(global_reasons)
        row = raw if isinstance(raw, dict) else {}
        path, parts = row.get("path"), None
        try:
            path, parts = _path(path)
            candidate_paths.add(parts)
        except ValueError as error:
            reasons.append(str(error))
        evidence = row.get("evidence_paths", [])
        if not isinstance(evidence, list) or len(evidence) > 10000:
            reasons.append("evidence_paths_unknown")
        else:
            for item in evidence:
                try:
                    protection.add(_path(item)[1])
                except ValueError:
                    reasons.append("evidence_paths_unknown")
        rows.append((index, row, path, parts, reasons))
    counts = Counter(parts for _, _, _, parts, _ in rows if parts is not None)
    allowed_roots = tuple(_path(root)[1] for root in ROOTS)
    retire, blocked = [], []
    for index, row, path, parts, reasons in rows:
        kind = row.get("kind")
        identity = _identity(row.get("package")) if "package" in row else _identity(row)
        if "package" in row and any(key in row for key in IDENTITY) and _identity(row) != identity:
            reasons.append("conflicting_package_identity")
        if not isinstance(kind, str) or kind not in RETIRABLE:
            reasons.append("protected_or_unknown_artifact_kind")
        if type(row.get("bytes")) is not int or row["bytes"] < 0:
            reasons.append("artifact_size_unknown")
        for flag in ("active", "in_use", "reparse_point"):
            if row.get(flag) is not False:
                reasons.append(flag + "_or_unknown")
        references = row.get("referenced_by")
        if (not isinstance(references, list) or len(references) > 10000 or any(not isinstance(r, str) or not r for r in references)):
            reasons.append("reference_state_unknown")
        elif references:
            reasons.append("artifact_still_referenced")
        if row.get("evidence_preserved") is not True:
            reasons.append("historical_evidence_not_preserved_externally")
        roles = row.get("roles", [])
        if not isinstance(roles, list) or roles or row.get("role"):
            reasons.append("protected_or_unknown_role")
        if any(flag in row and row[flag] is not False for flag in PROTECTED_FLAGS):
            reasons.append("protected_artifact_role")
        if parts is not None:
            if not any(len(parts) > len(root) and parts[:len(root)] == root for root in allowed_roots):
                reasons.append("outside_explicit_release_roots")
            if _reserved_scope(parts):
                reasons.append("backup_key_backend_or_rehearsal_scope")
            if protection.overlaps(parts):
                reasons.append("protected_path_ancestor_or_descendant")
            if counts[parts] > 1:
                reasons.append("duplicate_inventory_path")
            if candidate_paths.overlaps(parts, ignore_exact=True):
                reasons.append("overlapping_inventory_targets")
        if identity is None:
            reasons.append("package_identity_unknown")
        elif target:
            if identity["workshop_id"] != target["workshop_id"]:
                reasons.append("foreign_workshop")
            if identity == target:
                reasons.append("current_release_identity")
            elif identity["release_sequence"] >= target["release_sequence"]:
                reasons.append("not_older_than_verified_target")
        entry = dict(index=index, path=path if isinstance(path, str) else None, kind=kind,
                     package_identity=identity, bytes=row.get("bytes") if type(row.get("bytes")) is int and row["bytes"] >= 0 else None)
        if reasons:
            entry.update(status="BLOCKED", reasons=list(dict.fromkeys(reasons)))
            blocked.append(entry)
        else:
            entry.update(status="RETIRE", reasons=["older_unreferenced_artifact_after_verified_delivery"])
            retire.append(entry)
    key = lambda row: (row["path"] or "").casefold()
    retire.sort(key=key); blocked.sort(key=key)
    return dict(schema=1, status="RETIREMENT_PLAN_READY" if retire else "BLOCKED", verified_target=target,
                retire=retire, blocked=blocked, retire_bytes=sum(row["bytes"] for row in retire),
                blocked_known_bytes=sum(row["bytes"] or 0 for row in blocked), blockers=list(dict.fromkeys(global_reasons)),
                historical_evidence_policy="PRESERVE_RECEIPTS_OUTSIDE_RETIRED_DIRECTORIES",
                filesystem_actions=0, execution_revalidation_required=True)
