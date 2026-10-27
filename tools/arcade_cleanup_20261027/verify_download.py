"""Verify the real official download of native refresh 2026102705.

Default is a local read-only plan. --download makes one official subscription
refresh and one DownloadItem request, requires real callbacks and fresh details
before/after, then verifies all five VPKs and 6655 signed resources. The Steam
manifest is read from this upload's journal when available, otherwise from the
actual callback-confirmed ACF installation bound to the new bytes and queries.
No hard-coded historical Steam manifest, publication, journal edit or retry.
"""
from __future__ import annotations

import argparse
import ctypes as C
from datetime import datetime, timezone
import hashlib
from pathlib import Path
import re
import shutil
import sys
import uuid

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/workshop_test"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import incremental_vpk as incremental
import protect_runtime_lua
import verify_native_shop_download as previous

callbacks, verify = previous.callbacks, previous.verify
api, need = callbacks.api, callbacks.need
ITEM, SEQUENCE, FILE_COUNT = "3824360109", 2026102705, 6655
CONTENT = "8a01a5b66603804c683b879043c220e4f9496d7cca75f304ac5d9da210794cf6"
CANDIDATE = Path("D:/Survival_发布候选/20261027_ws4_refresh_native_v02_view")
TRUSTED = Path("D:/Survival_发布候选/20261027_ws4_refresh_native_v02_overlay_trusted_source")
VPK = Path("D:/Survival_工坊输出/20261027_ws4_refresh_native_v02/3824360109.vpk")
REPORT = ROOT / "output/arcade_cleanup_20261027/native_package_build_v02.json"
STATE = ROOT / "output/four_accounts_20261022/steam_upload_state.json"
OUTPUT = ROOT / "output/arcade_cleanup_20261027/download_evidence_v02"
INSTALLED, ACF = callbacks.INSTALLED, callbacks.ACF
EXPECTED_NAMES = [ITEM + ".vpk", *(f"{ITEM}_{index:03}.vpk" for index in range(4))]
MINIMUM_REMOTE_UPDATED = 1792989429  # Last SHOP02 publication, not a new-manifest guess.
PUBLIC_PINS = {
    "tools/release_security/protection_policy.json": "8e8c2e50a6a983dda7336a083377bbf55de8625f89f5633977c8d7901b53da96",
    "tools/release_security/trusted_public_key.pem": "1717c28cb7476e5eb5326b780589c880e86d42cc026b6d4728d95ac95e8873bf",
    "tools/lua_protection_policy.json": "bc03e38f2e0b9165299df5777dbb561a593d5d4e2f45eaef5e51c48f8856958a",
}


def sha_pin(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def steam_manifest(value):
    return (isinstance(value, str) and re.fullmatch(r"[1-9][0-9]{0,19}", value) is not None
            and int(value) < 2**64)


def journal_manifest(state):
    # Only current release top-level fields count. Never inspect release_history
    # or previous_release for a conveniently available old manifest.
    values = [state[name] for name in ("steam_manifest", "download_manifest") if name in state]
    need(all(steam_manifest(value) for value in values), "refresh_invalid_current_journal_manifest")
    need(len(set(values)) <= 1, "refresh_conflicting_current_journal_manifests")
    return values[0] if values else None


def read_snapshot(path, maximum, snapshots):
    path = api.pack.handoff.regular_path(path)
    raw = api.pack.read_metadata(path, maximum)
    snapshots[path] = raw
    return raw


def unchanged(snapshots):
    for path, raw in snapshots.items():
        need(api.pack.read_metadata(api.pack.handoff.regular_path(path), len(raw)) == raw,
             "refresh_local_input_changed_during_verification")


def protected_inventory(manifest, policy):
    protect_runtime_lua.check_policy(policy)
    selected = protect_runtime_lua.selected_files([row["path"] for row in manifest["files"]], policy)
    paths = [row["path"] for row in selected]
    need(len(paths) == len(set(paths)) == 180, "refresh_protected_180_module_inventory_changed")
    need(api.pack.runtime.CRITICAL <= {row["path"] for row in manifest["files"]},
         "refresh_missing_critical_signed_resources")
    return paths


def local_inputs(require_success=False, *, full=False):
    snapshots = {}
    for relative, pin in PUBLIC_PINS.items():
        raw = read_snapshot(ROOT / relative, 1024 * 1024, snapshots)
        need(hashlib.sha256(raw).hexdigest() == pin, "refresh_checkout_public_trust_changed")
        if relative != "tools/lua_protection_policy.json":
            need(read_snapshot(TRUSTED / relative, 1024 * 1024, snapshots) == raw,
                 "refresh_frozen_public_trust_differs")
    manifest = api.pack.handoff.decode_json(read_snapshot(
        CANDIDATE / api.pack.handoff.MANIFEST, api.pack.MAX_MANIFEST, snapshots))
    document = api.pack.handoff.decode_json(read_snapshot(
        CANDIDATE / api.pack.handoff.SIGNATURE, api.pack.MAX_SIGNATURE, snapshots))
    api.pack.runtime.validate_manifest(manifest)
    policy, public = api.pack.handoff.trusted_policy(api.pack.handoff.POLICY)
    signature = api.pack.verify_signed_snapshot(manifest, document, public,
        policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
    need(signature["content_sha256"] == CONTENT and signature["release_sequence"] == SEQUENCE
         and manifest["file_count"] == FILE_COUNT, "refresh_signed_release_identity_mismatch")
    lua_policy = api.pack.handoff.decode_json(snapshots[ROOT / "tools/lua_protection_policy.json"])
    protected = protected_inventory(manifest, lua_policy)
    # The refresh builder preserves all 180 protected modules. Verify this
    # claim against the independently signed fixed SHOP02 metadata as well.
    old, old_document, old_metadata = incremental.metadata(incremental.BASE)
    old_signature = api.pack.verify_signed_snapshot(old, old_document, public,
        policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
    need(old["content_sha256"] == incremental.BASE_CONTENT
         and old_signature["release_sequence"] == incremental.BASE_SEQUENCE,
         "refresh_protected_baseline_identity_mismatch")
    snapshots.update({incremental.BASE / name: raw for name, raw in old_metadata.items()})
    before, after = [{row["path"]: row for row in value["files"]} for value in (old, manifest)]
    need(all(before.get(path) == after[path] for path in protected), "refresh_protected_module_bytes_changed")
    for relative in (*api.pack.handoff.GATE_FILES, api.pack.handoff.ACCESS_FILE):
        raw = read_snapshot(TRUSTED / relative, api.pack.MAX_MANIFEST, snapshots)
        need(relative in after and hashlib.sha256(raw).hexdigest() == after[relative]["sha256"],
             "refresh_frozen_admission_guard_differs")
    report_raw = read_snapshot(REPORT, api.pack.MAX_MANIFEST, snapshots)
    report = api.pack.handoff.decode_json(report_raw)
    rows = report.get("package_files")
    need(report.get("content_sha256") == CONTENT and report.get("release_sequence") == SEQUENCE
         and report.get("files") == FILE_COUNT and report.get("signature_valid") is True
         and report.get("dry_run") is False and report.get("payload_changed") is False
         and report.get("workshop_upload_performed") is False
         and report.get("full_input_hash_verification") is True
         and report.get("full_runtime_validator_passed") is True
         and isinstance(rows, list) and len(rows) == 5
         and [row.get("name") for row in rows] == EXPECTED_NAMES
         and all(type(row.get("bytes")) is int and row["bytes"] > 0 and sha_pin(row.get("sha256")) for row in rows)
         and report.get("vpk_sha256") == rows[0]["sha256"], "refresh_completed_package_report_required")
    checks = report.get("verification", {})
    need(checks.get("files") == FILE_COUNT and checks.get("archive_count") == 4
         and all(checks.get(name) is True for name in callbacks.CHECKS), "refresh_incomplete_package_verification")
    total = sum(row["bytes"] for row in rows)
    need(total == report.get("container_bytes") and manifest["bytes"] == report.get("payload_bytes"),
         "refresh_package_totals_mismatch")
    state_raw = read_snapshot(STATE, api.pack.MAX_MANIFEST, snapshots)
    state = api.pack.handoff.decode_json(state_raw)
    success = (state.get("uploaded") is True and state.get("owner") == api.OWNER
        and state.get("app_id") == api.APP and state.get("workshop_id") == ITEM
        and state.get("visibility_requested") == 3 and state.get("release_sequence") == SEQUENCE
        and state.get("content_sha256") == CONTENT and state.get("vpk_sha256") == rows[0]["sha256"]
        and state.get("vpk_bytes") == rows[0]["bytes"] and state.get("package_files") == rows
        and state.get("legal_agreement_required") is False)
    if require_success:
        need(success, "refresh_successful_same_release_original_item_upload_required")
    expected_manifest = journal_manifest(state) if success else None
    if full:
        with incremental.trusted_source(TRUSTED):
            _, verified, actual_signature, _ = api.pack.authenticate(CANDIDATE)
        need(verified == manifest and actual_signature == signature, "refresh_full_candidate_identity_mismatch")
        need(api.pack.package_inventory(VPK) == rows, "refresh_local_vpk_bytes_differ_from_report")
        api.pack.verify_vpk(VPK, manifest)
    unchanged(snapshots)
    return dict(report=report, manifest=manifest, signature=signature, state=state, snapshots=snapshots,
                success=success, expected_manifest=expected_manifest, total=total,
                report_sha256=hashlib.sha256(report_raw).hexdigest(),
                state_sha256=hashlib.sha256(state_raw).hexdigest(), protected_modules=180)


def validate_remote(item, total):
    expected = dict(id=ITEM, result=1, file_type=0, creator_app_id=api.APP, consumer_app_id=api.APP,
        owner=api.OWNER, visibility=3, total_files_bytes=total, cached=False, max_cache_age_seconds=0,
        banned=False, tags_truncated=False)
    need(all(type(item.get(key)) is type(value) and item.get(key) == value for key, value in expected.items())
         and type(item.get("time_updated")) is int and item["time_updated"] > MINIMUM_REMOTE_UPDATED
         and "Custom Game" in item.get("tags", "").split(","), "refresh_remote_identity_or_freshness_mismatch")


class RefreshSteam(previous.SHOP02Steam):
    """Reuse reviewed manual-dispatch/query/1313 ABI, never old release pins."""
    def __init__(self, total, expected_manifest=None):
        super().__init__(total)
        self.expected_manifest = expected_manifest

    def fresh_item(self):
        answer = super().fresh_item()
        validate_remote(answer, self.total)
        return answer

    def download_installed(self):
        before = self.ug("GetItemState", C.c_uint32, [C.c_uint64], int(ITEM))
        need(before & 1 and not before & (2 | 16 | 32 | 64), "refresh_another_download_or_unsupported_state")
        callback = self.dispatch.download(lambda: self.ug("DownloadItem", C.c_bool,
            [C.c_uint64, C.c_bool], int(ITEM), True))
        flags = self.ug("GetItemState", C.c_uint32, [C.c_uint64], int(ITEM))
        need(flags & 1 and flags & 4 and not flags & (2 | 8 | 16 | 32 | 64), "refresh_install_not_stable_after_3406")
        size, stamp, folder = C.c_uint64(), C.c_uint32(), C.create_string_buffer(4096)
        need(self.ug("GetItemInstallInfo", C.c_bool,
            [C.c_uint64, C.POINTER(C.c_uint64), C.c_void_p, C.c_uint32, C.POINTER(C.c_uint32)],
            int(ITEM), C.byref(size), folder, len(folder), C.byref(stamp)), "refresh_install_info_missing")
        actual = api.pack.handoff.regular_path(Path(folder.value.decode("utf8", errors="strict")))
        self.install_observation = dict(callback=callback, prior_flags=before, flags=flags,
            install_folder=str(actual), size_on_disk=size.value, installation_timestamp=stamp.value,
            expected_folder=str(INSTALLED.resolve()), expected_size_on_disk=self.total,
            journal_manifest=self.expected_manifest, download_requested=True, native_test="NOT_RUN")
        need(actual == api.pack.handoff.regular_path(INSTALLED) and size.value == self.total,
             "refresh_install_folder_or_size_mismatch")
        return self.install_observation.copy()


def acf_manifest(raw, post, total, expected_manifest=None):
    acf = api.pack.handoff.kv(raw.decode("utf-8-sig"))["appworkshop"]
    row = acf["workshopitemsinstalled"][ITEM]
    value = row.get("manifest")
    need(acf.get("appid") == str(api.APP) and steam_manifest(value)
         and row.get("size") == str(total) and row.get("timeupdated") == str(post["time_updated"]),
         "refresh_installed_manifest_not_bound_to_fresh_query")
    need(expected_manifest is None or value == expected_manifest, "refresh_journal_and_installed_manifest_differ")
    return value, row


def save_evidence(value):
    directory = OUTPUT / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ_") + uuid.uuid4().hex)
    api.pack.handoff.regular_path(directory, must_exist=False)
    directory.mkdir(parents=True, exist_ok=False)
    path = directory / "verification.json"
    callbacks.write_exclusive(path, callbacks.encoded(value))
    return path


def download_once(inputs):
    import test_entry
    processes = test_entry.process_inventory()
    need(processes.get("steam_running") is True and processes.get("dota_pids") == [],
         "refresh_close_dota_keep_steam_before_download")
    package, state = inputs["report"], inputs["state"]
    with RefreshSteam(inputs["total"], inputs["expected_manifest"]) as steam:
        pre = steam.fresh_item()
        subscribed = steam.refresh_subscription_once()
        try:
            downloaded = steam.download_installed()
        except callbacks.Refused:
            observation = getattr(steam, "install_observation", None)
            if observation is not None:
                path = save_evidence(dict(schema=1, status="REFRESH_INSTALL_IDENTITY_REFUSED",
                    observed_utc=callbacks.now(), pre_query=pre, subscription_refresh=subscribed,
                    install_observation=observation, canonical_journal_written=False,
                    automatic_retry_performed=False, full_verification="NOT_RUN_IDENTITY_MISMATCH"))
                api.emit(dict(status="REFRESH_INSTALL_DIAGNOSIS_SAVED", evidence=str(path)))
            raise
        installed = api.pack.handoff.regular_path(Path(downloaded["install_folder"]))
        need(set(installed.iterdir()) == {installed / name for name in EXPECTED_NAMES},
             "refresh_installed_exact_five_files_required")
        for path in installed.iterdir():
            api.pack.handoff.regular_path(path)
        verified = verify.verify_installed(downloaded.copy(), CANDIDATE, state)
        need(verified["signature_valid"] is True and verified["vpk_sha256"] == package["vpk_sha256"]
             and verified["package_files"] == package["package_files"]
             and verified["verification"].get("files") == FILE_COUNT
             and verified["verification"].get("archive_count") == 4
             and all(verified["verification"].get(name) is True for name in callbacks.CHECKS),
             "refresh_full_installed_verification_incomplete")
        need(set(installed.iterdir()) == set(api.pack.package_paths(Path(verified["vpk"])))
             and api.pack.package_inventory(Path(verified["vpk"])) == package["package_files"],
             "refresh_installed_bytes_changed")
        post = steam.fresh_item()
    need({key: value for key, value in pre.items() if key != "observed_utc"}
         == {key: value for key, value in post.items() if key != "observed_utc"},
         "refresh_remote_changed_during_verification")
    raw = api.pack.read_metadata(api.pack.handoff.regular_path(ACF), api.pack.MAX_MANIFEST)
    manifest, row = acf_manifest(raw, post, inputs["total"], inputs["expected_manifest"])
    unchanged(inputs["snapshots"])
    receipt = dict(schema=1, status="OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED",
        observed_utc=callbacks.now(), workshop_id=ITEM, release_sequence=SEQUENCE, content_sha256=CONTENT,
        vpk_sha256=package["vpk_sha256"], steam_manifest=manifest, manifest_is_string=True,
        manifest_source=("current_release_journal_and_fresh_callback_install" if inputs["expected_manifest"]
                         else "fresh_callback_install_acf_bound_to_queries_and_signed_bytes"),
        pre_query=pre, subscription_refresh=subscribed, download=downloaded, verification=verified,
        post_query=post, acf_installed_entry=row, package_report_sha256=inputs["report_sha256"],
        canonical_journal_sha256=inputs["state_sha256"], canonical_journal_unchanged=True,
        protected_modules_verified=inputs["protected_modules"], critical_resources_verified=True,
        signed_resources_verified=FILE_COUNT, items_created=0, updates_submitted=0,
        automatic_retry_performed=False, native_test="NOT_RUN", multiplayer_acceptance="NOT_RUN",
        ready_for_public_release=False)
    path = save_evidence(receipt)
    return dict(status=receipt["status"], workshop_id=ITEM, release_sequence=SEQUENCE,
        steam_manifest=manifest, files=FILE_COUNT, archive_count=4, protected_modules_verified=180,
        canonical_journal_unchanged=True, evidence=str(path))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args(argv)
    try:
        inputs = local_inputs(args.download)
        required = inputs["total"] + 1024**3
        free = shutil.disk_usage(INSTALLED.anchor).free
        if not args.download:
            api.emit(dict(status="READ_ONLY_REFRESH_NATIVE_DOWNLOAD_PLAN", workshop_id=ITEM,
                release_sequence=SEQUENCE, content_sha256=CONTENT, successful_current_upload_journal=inputs["success"],
                free_bytes=free, conservative_required_free_bytes=required, space_admitted=free >= required,
                journal_manifest=inputs["expected_manifest"], manifest_from_fresh_install_when_unpinned=True,
                will_refresh_existing_subscription_once=True, steam_initialized=False, files_written=0))
            return 0
        need(free >= required, "refresh_insufficient_full_package_plus_one_gib_staging_space")
        with api.publication_lock(STATE):
            unchanged(inputs["snapshots"])
            locked = local_inputs(True, full=True)
            need(locked["snapshots"] == inputs["snapshots"], "refresh_inputs_changed_before_download")
            api.emit(download_once(locked))
        return 0
    except Exception as error:
        api.emit(dict(status="REFRESH_NATIVE_DOWNLOAD_VERIFICATION_REFUSED",
            reason=str(error) if isinstance(error, callbacks.Refused) else type(error).__name__,
            updates_submitted=0, canonical_journal_written=False, automatic_retry_performed=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
