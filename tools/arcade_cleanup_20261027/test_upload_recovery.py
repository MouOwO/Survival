"""Offline recovery/secret-redaction tests, never Steam or real journal writes."""
import copy
import ctypes as C
from contextlib import nullcontext, redirect_stdout
from datetime import datetime, timedelta, timezone
import hashlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import capture_upload_failure as captured
import recover_failed_upload as recovery


class CaptureTests(unittest.TestCase):
    def test_proxy_and_url_diagnostics_do_not_export_credentials_or_queries(self):
        value = captured.endpoint("http://alice:secret@127.0.0.1:7890/private?token=hidden")
        self.assertEqual(value, dict(scheme="http", host="127.0.0.1", port=7890, userinfo_present=True))
        raw = captured.redact("POST https://alice:secret@host.test/a?token=hidden handle 123456 token=alsosecret")
        for secret in ("alice", "secret", "hidden", "123456", "alsosecret"):
            self.assertNotIn(secret, raw)
        self.assertIn("host.test", raw)
        self.assertNotIn("bearer_secret", captured.redact("Authorization: Bearer bearer_secret"))

    def test_default_capture_plan_never_opens_steam_network_or_output(self):
        with patch.object(captured, "capture", side_effect=AssertionError("capture forbidden")), \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(captured.main([]), 0)
        self.assertIn("READ_ONLY_FAILED_UPLOAD_CAPTURE_PLAN", output.getvalue())


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.state, self.directory = self.root / "state.json", self.root / "transaction"
        self.directory.mkdir()
        self.baseline = dict(content_sha256=recovery.CONTENT, release_sequence=recovery.SEQUENCE,
            vpk_sha256=recovery.INDEX, vpk_bytes=recovery.incremental.BASE_PACKAGE[0]["bytes"],
            package_files=copy.deepcopy(recovery.incremental.BASE_PACKAGE), package="historical-shop02.vpk",
            verification=dict(files=6637, archive_count=4, **{name: True for name in recovery.callbacks.CHECKS}),
            uploaded=True, status="SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST",
            native_test="HISTORICAL_NATIVE_PASS", ordinary_workshop_match="HISTORICAL_NATIVE_PASS")
        self.history_last = dict(release_sequence=2026102603, content_sha256="old-prior")
        self.pending = dict(schema=1, owner=recovery.api.OWNER, app_id=570, workshop_id=recovery.ITEM,
            visibility_requested=3, status="SUBMIT_REQUEST_PENDING", uploaded=False,
            release_sequence=2026102703, content_sha256="failed-new", previous_release=self.baseline,
            release_history=[{"release_sequence": 2026102405}, self.history_last],
            native_test="NOT_RUN", ordinary_workshop_match="NOT_RUN", ready_for_public_release=False)
        self.raw = recovery.callbacks.encoded(self.pending)
        self.state.write_bytes(self.raw)
        context = patch.object(recovery, "STATE", self.state)
        context.start(); self.addCleanup(context.stop)
        context = patch.object(recovery, "PENDING_SHA", hashlib.sha256(self.raw).hexdigest())
        context.start(); self.addCleanup(context.stop)
        self.inputs = dict(pending=self.pending, pending_raw=self.raw, baseline=self.baseline,
            snapshots={self.state: self.raw})

    def item(self):
        return dict(id=recovery.ITEM, result=1, file_type=0, creator_app_id=570, consumer_app_id=570,
            owner=recovery.api.OWNER, visibility=3, total_files_bytes=recovery.TOTAL,
            time_updated=recovery.REMOTE_TIME, cached=False, max_cache_age_seconds=0,
            banned=False, tags_truncated=False, tags="Custom Game", observed_utc=recovery.callbacks.now())

    def proof(self):
        return dict(status="FRESH_OFFICIAL_SHOP02_FULLY_VERIFIED_AFTER_FAILED_REFRESH",
            pending_sha256=recovery.PENDING_SHA, failed_attempt_evidence_sha256=recovery.EVIDENCE_SHA,
            content_sha256=recovery.CONTENT, release_sequence=recovery.SEQUENCE,
            steam_manifest=recovery.MANIFEST, verified_utc=recovery.callbacks.now(),
            pre_query=self.item(), post_query=self.item(), acf_installed_entry=dict(manifest=recovery.MANIFEST,
                size=str(recovery.TOTAL), timeupdated=str(recovery.REMOTE_TIME)),
            download=dict(callback=dict(callback_id=3406, app_id=570, workshop_id=recovery.ITEM, result=1)),
            signed_download=dict(signature_valid=True, vpk_sha256=recovery.INDEX,
                package_files=copy.deepcopy(recovery.incremental.BASE_PACKAGE),
                verification=dict(files=6637, archive_count=4, **{name: True for name in recovery.callbacks.CHECKS})))

    def test_default_recovery_cannot_initialize_sdk_lock_download_or_write(self):
        with patch.object(recovery, "local_inputs", return_value=self.inputs), \
                patch.object(recovery.api, "publication_lock", side_effect=AssertionError("lock forbidden")), \
                patch.object(recovery, "verify_live", side_effect=AssertionError("download forbidden")), \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(recovery.main([]), 0)
        self.assertIn("READ_ONLY_FAILED_REFRESH_RECONCILIATION_PLAN", output.getvalue())
        self.assertEqual(self.state.read_bytes(), self.raw)

    def test_sdk_allowlist_forbids_publication_and_subscription_changes(self):
        steam = recovery.RecoverySteam()
        for name in ("CreateItem", "SubmitItemUpdate", "StartItemUpdate", "SetItemContent", "SubscribeItem", "UnsubscribeItem"):
            with self.subTest(name=name), self.assertRaises(recovery.callbacks.Refused):
                steam.ug(name, C.c_bool, [])

    def test_full_live_proof_rejects_missing_callback_checks_wrong_manifest_stale_time_and_remote_change(self):
        examples = []
        value = self.proof(); value["download"]["callback"]["callback_id"] = 1; examples.append(value)
        value = self.proof(); value["signed_download"]["verification"]["crc32_verified"] = False; examples.append(value)
        value = self.proof(); value["acf_installed_entry"]["manifest"] = "other"; examples.append(value)
        value = self.proof(); value["post_query"]["tags"] = "Custom Game,changed"; examples.append(value)
        value = self.proof(); value["verified_utc"] = (datetime.now(timezone.utc)-timedelta(seconds=301)).isoformat(); examples.append(value)
        value = self.proof(); value["pending_sha256"] = "other"; examples.append(value)
        for proof in examples:
            with self.subTest(proof=proof), self.assertRaises(recovery.callbacks.Refused):
                recovery.commit_local(self.inputs, proof, self.directory)
            self.assertEqual(self.state.read_bytes(), self.raw)
            self.assertEqual(list(self.directory.iterdir()), [])

    def test_verified_commit_preserves_exact_pending_and_original_facts_without_promoting_native(self):
        result = recovery.commit_local(self.inputs, self.proof(), self.directory)
        self.assertEqual((self.directory / "pending.original.json").read_bytes(), self.raw)
        new = recovery.api.pack.handoff.decode_json(self.state.read_bytes())
        for name in recovery.FACT_FIELDS:
            self.assertEqual(new[name], self.baseline[name])
        self.assertEqual(new["previous_release"], self.history_last)
        self.assertEqual(new["release_history"], [{"release_sequence": 2026102405}])
        self.assertEqual(new["native_test"], "HISTORICAL_ONLY_NOT_RUN_DURING_RECONCILIATION")
        self.assertFalse(new["ready_for_public_release"])
        self.assertEqual(new["failed_attempts"][-1]["failed_release_sequence"], 2026102703)
        self.assertEqual(new["failed_attempts"][-1]["result"], 2)
        self.assertEqual(result["updates_submitted"], 0)
        self.assertFalse(result["automatic_retry_performed"])

    def test_cas_drift_before_or_after_temporary_write_keeps_competing_state(self):
        self.state.write_bytes(b"other producer")
        with self.assertRaises(recovery.callbacks.Refused):
            recovery.commit_local(self.inputs, self.proof(), self.directory)
        self.assertEqual(self.state.read_bytes(), b"other producer")
        self.state.write_bytes(self.raw)
        original = recovery.unchanged
        calls = [0]
        def race(inputs):
            calls[0] += 1
            if calls[0] == 2:
                self.state.write_bytes(b"other producer")
            return original(inputs)
        with patch.object(recovery, "unchanged", side_effect=race), self.assertRaises(recovery.callbacks.Refused):
            recovery.commit_local(self.inputs, self.proof(), self.directory)
        self.assertEqual(self.state.read_bytes(), b"other producer")
        self.assertEqual(list(self.root.glob("*.part")), [])

    def test_verify_mode_calls_new_live_verification_and_never_commits(self):
        context = patch.object(recovery, "OUTPUT", self.root / "proofs")
        with context, patch.object(recovery, "local_inputs", return_value=self.inputs), \
                patch.object(recovery.api, "publication_lock", return_value=nullcontext()), \
                patch.object(recovery, "verify_live", return_value=self.proof()) as live, \
                patch.object(recovery, "commit_local", side_effect=AssertionError("commit forbidden")), \
                redirect_stdout(io.StringIO()):
            self.assertEqual(recovery.main(["--verify"]), 0)
        live.assert_called_once_with(self.inputs)
        self.assertEqual(self.state.read_bytes(), self.raw)

    def test_apply_must_call_live_verification_and_cannot_import_saved_receipt(self):
        with patch.object(recovery, "OUTPUT", self.root / "proofs"), \
                patch.object(recovery, "local_inputs", return_value=self.inputs), \
                patch.object(recovery.api, "publication_lock", return_value=nullcontext()), \
                patch.object(recovery, "verify_live", side_effect=recovery.callbacks.Refused("live failed")) as live, \
                patch.object(recovery, "commit_local", side_effect=AssertionError("commit forbidden")), \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(recovery.main(["--apply"]), 1)
        live.assert_called_once_with(self.inputs)
        self.assertIn("live failed", output.getvalue())
        self.assertEqual(self.state.read_bytes(), self.raw)


if __name__ == "__main__":
    unittest.main()
