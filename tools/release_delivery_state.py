"""Pure delivery diagnostics. This module never grants publication authority.

One invocation indexes O(resource rows + package rows), then sorts only the R
changed paths O(R log R); there is no timer, SDK, filesystem, network or process.
The caller must load authenticated inputs and hash the original report/journal
bytes. Existing publication/download schemas are consumed without rewriting.
"""
from __future__ import annotations

import re

LOCAL_ONLY = "LOCAL_ONLY"
UPLOADED_PENDING_DOWNLOAD_VERIFICATION = "UPLOADED_PENDING_DOWNLOAD_VERIFICATION"
WORKSHOP_SYNCED = "WORKSHOP_SYNCED"
UPLOAD_STATUS = "SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST"
DOWNLOAD_STATUS = "OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED"
CHECKS = ("crc32_verified", "manifest_dual_hashes_verified", "section_md5s_verified", "whole_vpk_md5_verified")


def _digest(value, length=64):
    return isinstance(value, str) and re.fullmatch("[a-f0-9]{%d}" % length, value) is not None


def _positive(value):
    return type(value) is int and value > 0


def _sources(value):
    return (isinstance(value, dict) and set(value) == {"game", "content"}
            and all(_digest(commit, 40) for commit in value.values()))


def _identity(value):
    if not isinstance(value, dict):
        return None
    result = {key: value.get(key) for key in ("workshop_id", "release_sequence", "content_sha256")}
    return result


def _valid_identity(value):
    return (isinstance(value, dict) and isinstance(value.get("workshop_id"), str)
            and re.fullmatch("[1-9][0-9]{0,19}", value["workshop_id"]) is not None
            and _positive(value.get("release_sequence")) and _digest(value.get("content_sha256")))


def _package_rows(value, workshop):
    if not isinstance(value, list) or not 2 <= len(value) <= 257:
        return None
    rows = {}
    for row in value:
        if (not isinstance(row, dict) or not isinstance(row.get("name"), str)
                or not _positive(row.get("bytes")) or not _digest(row.get("sha256"))
                or row["name"] in rows):
            return None
        rows[row["name"]] = (row["bytes"], row["sha256"])
    expected = {workshop + ".vpk", *(workshop + "_%03d.vpk" % n for n in range(len(rows) - 1))}
    return rows if set(rows) == expected else None


def _change_list(value):
    return (isinstance(value, list) and len(value) <= 100000
            and all(isinstance(row, str) and bool(row) for row in value)
            and len(set(value)) == len(value))


def resource_diff(local_rows, published_rows):
    """Return added/modified/removed paths from complete manifest file lists."""
    def index(rows):
        if not isinstance(rows, list) or len(rows) > 100000:
            raise ValueError("complete_resource_manifest_required")
        result = {}
        for row in rows:
            if (not isinstance(row, dict) or not isinstance(row.get("path"), str)
                    or not row["path"] or row["path"].startswith(("/", "\\"))
                    or "\\" in row["path"] or ":" in row["path"]
                    or any(part in ("", ".", "..") for part in row["path"].split("/"))
                    or type(row.get("bytes")) is not int or row["bytes"] < 0
                    or not _digest(row.get("sha256")) or row["path"] in result):
                raise ValueError("invalid_resource_manifest_row")
            result[row["path"]] = (row["bytes"], row["sha256"])
        return result
    local, published = index(local_rows), index(published_rows)
    changes = [{"path": path, "change": "added" if path not in published else "removed" if path not in local else "modified"}
               for path in set(local) | set(published) if local.get(path) != published.get(path)]
    return sorted(changes, key=lambda row: row["path"])


def report(state):
    """Classify local target, actual top-level upload and full official download.

    Required keys: local_package, expected_source_revisions,
    local_package_report_sha256, journal, journal_sha256, download_receipt,
    pending_source_changes. Resource changes are computed from local_resources /
    published_resources, or supplied explicitly as pending_resource_changes.
    Missing or contradictory evidence never yields WORKSHOP_SYNCED. A valid
    upload with bad/missing download evidence stays uploaded-but-unverified.
    This is a diagnostic, not an authenticity proof for caller-supplied JSON.
    """
    state = state if isinstance(state, dict) else {}
    local = state.get("local_package")
    local = local if isinstance(local, dict) else {}
    journal = state.get("journal")
    journal = journal if isinstance(journal, dict) else {}
    receipt = state.get("download_receipt")
    receipt = receipt if isinstance(receipt, dict) else {}
    reasons, local_reasons, upload_reasons, download_reasons = [], [], [], []
    local_id = _identity(local)
    if not _valid_identity(local_id):
        local_reasons.append("local_package_identity_invalid")
    workshop = local.get("workshop_id", "")
    files = _package_rows(local.get("package_files"), workshop) if isinstance(workshop, str) else None
    if files is None:
        local_reasons.append("local_package_file_set_invalid")
    if local.get("signature_valid") is not True or local.get("full_runtime_validator_passed") is not True:
        local_reasons.append("local_package_not_fully_verified")
    if not _sources(local.get("source_revisions")) or local.get("source_revisions") != state.get("expected_source_revisions"):
        local_reasons.append("local_package_does_not_bind_target_sources")
    binding_state = ("DUAL_SOURCE_BOUND" if _sources(local.get("source_revisions")) else
                     "LEGACY_MIXED_BASELINE" if _digest(local.get("source_revision"), 40) else "UNKNOWN")
    if binding_state == "LEGACY_MIXED_BASELINE":
        local_reasons.append("legacy_mixed_baseline_is_not_a_complete_dual_source_export")
    pending_sources = state.get("pending_source_changes")
    if not _change_list(pending_sources):
        local_reasons.append("pending_source_inventory_unavailable")
        pending_sources = None
    elif pending_sources:
        local_reasons.append("local_source_changes_not_in_candidate")
    changes = None
    if "local_resources" in state or "published_resources" in state:
        try:
            changes = resource_diff(state.get("local_resources"), state.get("published_resources"))
            if len(state["local_resources"]) != local.get("files"):
                local_reasons.append("local_resource_inventory_count_differs_from_report")
            previous_count = (journal.get("verification") or {}).get("files") if isinstance(journal.get("verification"), dict) else None
            if journal.get("uploaded") is True and len(state["published_resources"]) != previous_count:
                local_reasons.append("published_resource_inventory_count_differs_from_journal")
        except ValueError:
            local_reasons.append("resource_inventory_invalid_or_incomplete")
    else:
        supplied = state.get("pending_resource_changes")
        if _change_list(supplied):
            changes = [{"path": path, "change": "pending"} for path in sorted(supplied)]
        else:
            local_reasons.append("resource_inventory_unavailable")

    # The canonical journal's historical entries cannot satisfy this target.
    if (journal.get("uploaded") is not True or journal.get("status") != UPLOAD_STATUS
            or journal.get("app_id") != 570 or type(journal.get("app_id")) is not int
            or journal.get("legal_agreement_required") is not False):
        upload_reasons.append("successful_current_upload_journal_required")
    if _identity(journal) != local_id:
        upload_reasons.append("uploaded_version_differs_from_local_target")
    journal_files = _package_rows(journal.get("package_files"), workshop) if isinstance(workshop, str) else None
    if files is None or journal_files != files:
        upload_reasons.append("uploaded_package_files_differ")
    index = files.get(workshop + ".vpk") if files is not None else None
    if index is None or (journal.get("vpk_bytes"), journal.get("vpk_sha256")) != index:
        upload_reasons.append("uploaded_vpk_index_differs")
    if not _digest(state.get("journal_sha256")):
        upload_reasons.append("original_journal_digest_required")
    uploaded = not local_reasons and not upload_reasons

    if receipt.get("status") != DOWNLOAD_STATUS or _identity(receipt) != local_id:
        download_reasons.append("matching_full_official_download_required")
    if (not _digest(state.get("local_package_report_sha256"))
            or receipt.get("package_report_sha256") != state.get("local_package_report_sha256")
            or receipt.get("canonical_journal_sha256") != state.get("journal_sha256")
            or receipt.get("canonical_journal_unchanged") is not True):
        download_reasons.append("download_report_or_journal_binding_differs")
    if (not isinstance(receipt.get("steam_manifest"), str)
            or re.fullmatch("[1-9][0-9]{0,19}", receipt.get("steam_manifest", "")) is None
            or receipt.get("manifest_is_string") is not True):
        download_reasons.append("official_steam_manifest_missing")
    verification = receipt.get("verification")
    verification = verification if isinstance(verification, dict) else {}
    downloaded_files = _package_rows(verification.get("package_files"), workshop) if isinstance(workshop, str) else None
    if files is None or downloaded_files != files or receipt.get("vpk_sha256") != (index or (None, None))[1]:
        download_reasons.append("downloaded_file_set_differs_or_is_mixed")
    checks = verification.get("verification")
    checks = checks if isinstance(checks, dict) else {}
    if (verification.get("status") != "UNLISTED_WORKSHOP_DOWNLOAD_FULLY_VERIFIED"
            or verification.get("signature_valid") is not True
            or verification.get("vpk_sha256") != (index or (None, None))[1]
            or type(local.get("files")) is not int or local["files"] <= 0
            or checks.get("files") != local.get("files")
            or checks.get("archive_count") != (len(files) - 1 if files else None)
            or not all(checks.get(key) is True for key in CHECKS)
            or receipt.get("signed_resources_verified") != local.get("files")
            or receipt.get("critical_resources_verified") is not True):
        download_reasons.append("full_resource_signature_crc_verification_missing")
    download = receipt.get("download")
    download = download if isinstance(download, dict) else {}
    callback = download.get("callback")
    callback = callback if isinstance(callback, dict) else {}
    if (download.get("download_requested") is not True or callback.get("workshop_id") != workshop
            or type(callback.get("result")) is not int or callback.get("result") != 1
            or callback.get("app_id") != 570):
        download_reasons.append("successful_official_download_callback_missing")
    pre, post = receipt.get("pre_query"), receipt.get("post_query")
    def fresh_query(value):
        return (isinstance(value, dict) and value.get("id") == workshop and type(value.get("result")) is int
                and value.get("result") == 1 and value.get("cached") is False
                and type(value.get("max_cache_age_seconds")) is int and value["max_cache_age_seconds"] == 0
                and value.get("consumer_app_id") == 570 and value.get("creator_app_id") == 570
                and value.get("total_files_bytes") == sum(row[0] for row in (files or {}).values())
                and _positive(value.get("time_updated")))
    if (not fresh_query(pre) or not fresh_query(post)
            or {k: v for k, v in (pre or {}).items() if k != "observed_utc"}
            != {k: v for k, v in (post or {}).items() if k != "observed_utc"}):
        download_reasons.append("fresh_stable_official_queries_required")
    if changes:
        local_reasons.append("local_resource_changes_not_published")
        uploaded = False
    reasons.extend(local_reasons + upload_reasons + download_reasons)
    status = (WORKSHOP_SYNCED if uploaded and not download_reasons else
              UPLOADED_PENDING_DOWNLOAD_VERIFICATION if uploaded else LOCAL_ONLY)
    return dict(status=status, workshop_synchronized=status == WORKSHOP_SYNCED,
                local_version=local_id, uploaded_version=_identity(journal), downloaded_version=_identity(receipt),
                source_binding_state=binding_state, upload_evidence_matches_target=not upload_reasons,
                official_download_evidence_matches_target=not download_reasons,
                target_source_revisions=dict(state.get("expected_source_revisions") or {}) if _sources(state.get("expected_source_revisions")) else None,
                pending_resource_changes=changes, pending_source_changes=list(pending_sources) if pending_sources is not None else None,
                blockers=list(dict.fromkeys(reasons)), publication_performed=False, sdk_authority_granted=False)
