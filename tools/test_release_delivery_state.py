"""Delivery reports cannot promote local work, historical uploads or mixed files."""
import copy
import unittest

from release_delivery_state import report, resource_diff, LOCAL_ONLY, UPLOADED_PENDING_DOWNLOAD_VERIFICATION, WORKSHOP_SYNCED


def fixture():
    item = "3824360109"
    files = [{"name": item + ".vpk", "bytes": 10, "sha256": "1" * 64}]
    files += [{"name": item + "_%03d.vpk" % n, "bytes": 100 + n, "sha256": str(n + 2) * 64} for n in range(4)]
    identity = dict(workshop_id=item, release_sequence=2026110301, content_sha256="a" * 64)
    sources = dict(game="b" * 40, content="c" * 40)
    package = dict(identity, package_files=files, vpk_sha256=files[0]["sha256"], files=1,
                   signature_valid=True, full_runtime_validator_passed=True, source_revisions=sources)
    journal = dict(identity, status="SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST", app_id=570,
                   uploaded=True, legal_agreement_required=False, vpk_bytes=10, vpk_sha256=files[0]["sha256"], package_files=copy.deepcopy(files),verification=dict(files=1))
    query = dict(id=item, result=1, cached=False, max_cache_age_seconds=0, creator_app_id=570,
                 consumer_app_id=570, total_files_bytes=sum(r["bytes"] for r in files), time_updated=123)
    receipt = dict(identity, status="OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED",
                   steam_manifest="7025356658517360342", manifest_is_string=True, vpk_sha256=files[0]["sha256"],
                   canonical_journal_sha256="d" * 64, package_report_sha256="e" * 64, canonical_journal_unchanged=True,
                   signed_resources_verified=1, critical_resources_verified=True,
                   pre_query=copy.deepcopy(query), post_query=copy.deepcopy(query),
                   download=dict(download_requested=True, callback=dict(result=1, app_id=570, workshop_id=item)),
                   verification=dict(status="UNLISTED_WORKSHOP_DOWNLOAD_FULLY_VERIFIED", signature_valid=True,
                       vpk_sha256=files[0]["sha256"], package_files=copy.deepcopy(files), verification=dict(files=1, archive_count=4,
                       crc32_verified=True, manifest_dual_hashes_verified=True, section_md5s_verified=True, whole_vpk_md5_verified=True)))
    rows = [dict(path="panorama/a.vjs_c", bytes=5, sha256="9" * 64)]
    return dict(local_package=package, journal=journal, journal_sha256="d" * 64,
                download_receipt=receipt, local_package_report_sha256="e" * 64,
                expected_source_revisions=copy.deepcopy(sources), pending_source_changes=[],
                local_resources=rows, published_resources=copy.deepcopy(rows))


class DeliveryTests(unittest.TestCase):
    def test_actual_same_upload_and_full_download_is_synced_without_mutating_inputs(self):
        state = fixture(); before = copy.deepcopy(state)
        result = report(state)
        self.assertEqual(result["status"], WORKSHOP_SYNCED)
        self.assertEqual(result["blockers"], [])
        self.assertFalse(result["publication_performed"])
        self.assertFalse(result["sdk_authority_granted"])
        self.assertEqual(state, before)

    def test_signature_git_push_stage_and_historical_success_are_local_only(self):
        state = fixture(); state["journal"] = dict(release_history=[copy.deepcopy(state["journal"])])
        state.update(git_pushed=True, local_stage_verified=True, ready=True)
        self.assertEqual(report(state)["status"], LOCAL_ONLY)

    def test_old0104_upload_and_receipt_do_not_qualify_local0301(self):
        state = fixture()
        for key in ("journal", "download_receipt"):
            state[key].update(release_sequence=2026110104, content_sha256="f" * 64)
        self.assertEqual(report(state)["status"], LOCAL_ONLY)
        self.assertIn("uploaded_version_differs_from_local_target", report(state)["blockers"])

    def test_successful_upload_without_download_remains_pending(self):
        state = fixture(); state.pop("download_receipt")
        self.assertEqual(report(state)["status"], UPLOADED_PENDING_DOWNLOAD_VERIFICATION)

    def test_old_receipt_wrong_hash_or_report_and_journal_binding_cannot_promote(self):
        changes = (
            lambda v: v.update(release_sequence=2026110104),
            lambda v: v.update(content_sha256="f" * 64),
            lambda v: v.update(workshop_id="42"),
            lambda v: v.update(canonical_journal_sha256="f" * 64),
            lambda v: v.update(package_report_sha256="f" * 64),
            lambda v: v.update(steam_manifest=123),
        )
        for change in changes:
            with self.subTest(change=change):
                state = fixture(); change(state["download_receipt"])
                self.assertEqual(report(state)["status"], UPLOADED_PENDING_DOWNLOAD_VERIFICATION)

    def test_mixed_five_file_download_upload_extra_volume_or_missing_volume_refused(self):
        for location in ("upload", "download"):
            for kind in ("mixed", "missing", "extra", "duplicate"):
                with self.subTest(location=location, kind=kind):
                    state = fixture()
                    rows = state["journal"]["package_files"] if location == "upload" else state["download_receipt"]["verification"]["package_files"]
                    if kind == "mixed": rows[2]["sha256"] = "f" * 64
                    elif kind == "missing": rows.pop(2)
                    elif kind == "extra": rows.append(dict(name="stale.vpk", bytes=8, sha256="f" * 64))
                    else: rows.append(copy.deepcopy(rows[1]))
                    self.assertNotEqual(report(state)["status"], WORKSHOP_SYNCED)

    def test_pending_author_or_compiler_changes_prevent_synced(self):
        state = fixture(); state["pending_source_changes"] = ["content:panorama/a.js"]
        self.assertEqual(report(state)["status"], LOCAL_ONLY)
        state = fixture(); state["expected_source_revisions"]["content"] = "f" * 40
        self.assertEqual(report(state)["status"], LOCAL_ONLY)
        state = fixture(); state["local_resources"][0]["sha256"] = "f" * 64
        self.assertNotEqual(report(state)["status"], WORKSHOP_SYNCED)
        self.assertEqual(report(state)["pending_resource_changes"], [{"path": "panorama/a.vjs_c", "change": "modified"}])

    def test_unknown_or_incomplete_inventory_is_not_implicit_empty_diff(self):
        for key in ("pending_source_changes", "local_resources", "journal_sha256", "expected_source_revisions"):
            with self.subTest(key=key):
                state = fixture(); state.pop(key)
                self.assertNotEqual(report(state)["status"], WORKSHOP_SYNCED)
        state = fixture(); state.pop("local_resources"); state.pop("published_resources"); state["pending_resource_changes"] = []
        self.assertEqual(report(state)["status"], WORKSHOP_SYNCED)

    def test_crc_signature_callback_or_fresh_query_missing_stays_pending(self):
        changes = (
            lambda v: v["verification"].update(signature_valid=False),
            lambda v: v["verification"]["verification"].update(crc32_verified=False),
            lambda v: v["download"]["callback"].update(result=2),
            lambda v: v["pre_query"].update(cached=True),
            lambda v: v["post_query"].update(time_updated=999),
        )
        for change in changes:
            with self.subTest(change=change):
                state = fixture(); change(state["download_receipt"])
                self.assertEqual(report(state)["status"], UPLOADED_PENDING_DOWNLOAD_VERIFICATION)

    def test_resource_delta_includes_add_remove_and_modify_and_rejects_unsafe_rows(self):
        row = lambda p, s: dict(path=p, bytes=10, sha256=s * 64)
        self.assertEqual(resource_diff([row("a", "1"), row("b", "2")], [row("b", "3"), row("c", "4")]),
                         [{"path": "a", "change": "added"}, {"path": "b", "change": "modified"}, {"path": "c", "change": "removed"}])
        for p in ("../a", "/a", "a\\b", "a/../b", "C:/a"):
            with self.subTest(path=p), self.assertRaises(ValueError): resource_diff([row(p, "1")], [])

    def test_empty_or_malformed_input_cannot_claim_delivery(self):
        for value in (None, [], {}, {"local_package": True}, {"download_receipt": {"pre_query": 12}}):
            with self.subTest(value=value):
                self.assertEqual(report(value)["status"], LOCAL_ONLY)

    def test_old_report_remains_legacy_mixed_without_invented_dual_source_export(self):
        state=fixture();source=state["local_package"].pop("source_revisions")
        state["local_package"]["source_revision"]=source["game"]
        self.assertEqual(report(state)["status"],LOCAL_ONLY)
        state["legacy_source_binding"]=dict(kind="AUTHENTICATED_PUBLISHED_BASELINE",package_report_sha256=state["local_package_report_sha256"],
            report_source_revision=source["game"],source_revisions=source,source_inventory_sha256="f"*64)
        self.assertEqual(report(state)["status"],LOCAL_ONLY)
        self.assertEqual(report(state)["source_binding_state"],"LEGACY_MIXED_BASELINE")
        self.assertTrue(report(state)["upload_evidence_matches_target"])
        self.assertTrue(report(state)["official_download_evidence_matches_target"])

    def test_empty_manifest_is_not_a_complete_nonempty_package_inventory(self):
        state=fixture();state["local_resources"]=[];state["published_resources"]=[]
        self.assertEqual(report(state)["status"],LOCAL_ONLY)
        self.assertIn("local_resource_inventory_count_differs_from_report",report(state)["blockers"])


if __name__ == "__main__": unittest.main()
