"""Isolated callback contracts and real temporary journal/CAS recovery tests."""
from __future__ import annotations

import copy
from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


tool = load("native07_recovery_under_test", HERE / "recover_native_cloud_upload.py")
legacy = load("native07_recovery_official_protocol_tests", HERE.parent / "arcade_cleanup_20261027/test_verify_download.py")


class FrozenNative05ProtocolContracts(legacy.SafetyTests):
    def setUp(self):
        context = patch.object(legacy, "subject", tool.protocol)
        context.start(); self.addCleanup(context.stop)


class Native07RecoveryTests(unittest.TestCase):
    def patched(self, target, name, value):
        context = patch.object(target, name, value)
        context.start(); self.addCleanup(context.stop)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.state, self.upload = self.root / "state.json", self.root / "failed_upload.log"
        self.directory = self.root / "evidence"
        self.directory.mkdir()
        self.baseline = dict(content_sha256=tool.CONTENT, release_sequence=tool.SEQUENCE,
            vpk_sha256=tool.INDEX, vpk_bytes=tool.PACKAGE[0]["bytes"], package_files=copy.deepcopy(tool.PACKAGE),
            package=str(tool.protocol.VPK), verification=self.checks(), uploaded=True,
            steam_manifest=tool.MANIFEST, download_manifest=tool.MANIFEST,
            native_test="HISTORICAL_PASS", ordinary_workshop_match="HISTORICAL_PASS",
            native_acceptance={"historical": "PASS"}, multiplayer_acceptance="NOT_RUN")
        self.history = [{"release_sequence": 2026102603}, {"release_sequence": 2026102604}]
        self.pending = dict(schema=1, status="SUBMIT_REQUEST_PENDING", uploaded=False,
            owner=tool.api.OWNER, app_id=570, workshop_id=tool.ITEM, visibility_requested=3,
            legal_agreement_required=False, release_sequence=tool.FAILED_SEQUENCE,
            content_sha256=tool.FAILED_CONTENT, vpk_sha256=tool.FAILED_INDEX,
            previous_release=self.baseline, release_history=self.history,
            native_test="NOT_RUN", ordinary_workshop_match="NOT_RUN", ready_for_public_release=False)
        self.raw = tool.callbacks.encoded(self.pending)
        self.log = b'{"status":"BLOCKED_PRESERVE_RECOVERY_JOURNAL","error":"RuntimeError: Steam API callback 3404 returned EResult=2"}\n'
        self.state.write_bytes(self.raw); self.upload.write_bytes(self.log)
        self.inputs = dict(pending=self.pending, pending_raw=self.raw, baseline=self.baseline,
            upload_raw=self.log, upload_redacted=self.log, snapshots={self.state:self.raw, self.upload:self.log})
        for name, value in (("STATE", self.state), ("UPLOAD", self.upload), ("PENDING_SHA", hashlib.sha256(self.raw).hexdigest()),
                            ("UPLOAD_SHA", hashlib.sha256(self.log).hexdigest()), ("_live_proof", None), ("_lock_held", False)):
            self.patched(tool, name, value)

    def checks(self):
        return dict(files=6655, archive_count=4, **{name:True for name in tool.callbacks.CHECKS})

    def remote(self):
        return dict(id=tool.ITEM, result=1, file_type=0, creator_app_id=570, consumer_app_id=570,
            owner=tool.api.OWNER, visibility=3, total_files_bytes=tool.TOTAL,
            cached=False, max_cache_age_seconds=0, banned=False, tags_truncated=False,
            time_updated=tool.REMOTE_NOT_BEFORE+1, tags="Custom Game", observed_utc=tool.callbacks.now())

    def official(self):
        remote = self.remote()
        return dict(status="OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED", workshop_id=tool.ITEM,
            release_sequence=tool.SEQUENCE, content_sha256=tool.CONTENT, vpk_sha256=tool.INDEX,
            steam_manifest=tool.MANIFEST, package_report_sha256=tool.REPORT_SHA,
            canonical_journal_unchanged=True, protected_modules_verified=180, signed_resources_verified=6655,
            pre_query=remote, post_query=copy.deepcopy(remote),
            subscription_refresh=dict(subscribe_calls=1, unsubscribe_calls=0,
                callback=dict(callback_id=1313, result=1, workshop_id=tool.ITEM)),
            download=dict(callback=dict(callback_id=3406, result=1, app_id=570, workshop_id=tool.ITEM)),
            verification=dict(signature_valid=True, vpk_sha256=tool.INDEX, package_files=copy.deepcopy(tool.PACKAGE), verification=self.checks()),
            acf_installed_entry=dict(manifest=tool.MANIFEST, size=str(tool.TOTAL), timeupdated=str(remote["time_updated"])))

    def proof(self):
        official = self.official()
        path = self.directory / "official-proof.json"
        path.write_bytes(tool.callbacks.encoded(official))
        proof = dict(status="FRESH_NATIVE05_FULLY_VERIFIED_AFTER_FAILED_NATIVE07", verified_utc=tool.callbacks.now(),
            pending_sha256=tool.PENDING_SHA, failed_upload_sha256=tool.UPLOAD_SHA, official=official,
            official_evidence=str(path), official_evidence_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        tool._live_proof = proof
        return proof

    def preserve(self):
        tool.preserve_failure(self.inputs, self.directory)

    def test_default_never_creates_evidence_initializes_sdk_or_obtains_lock(self):
        with patch.object(tool, "local_inputs", return_value=self.inputs), \
                patch.object(tool, "publisher_lock", side_effect=AssertionError("lock forbidden")), \
                patch.object(tool, "preserve_failure", side_effect=AssertionError("writes forbidden")), \
                patch.object(tool.api.Steam, "__enter__", side_effect=AssertionError("SDK forbidden")), \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(tool.main([]), 0)
        self.assertIn("READ_ONLY_FAILED_NATIVE07_RECONCILIATION_PLAN", output.getvalue())
        self.assertEqual(self.state.read_bytes(), self.raw)
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_adapter_contains_only_verified_previous_facts_and_same_item_identity(self):
        state = tool.temporary_journal(self.inputs)
        for name in tool.FACT_FIELDS:
            self.assertEqual(state[name], self.baseline[name])
        self.assertEqual((state["owner"],state["app_id"],state["workshop_id"],state["visibility_requested"]),
                         (tool.api.OWNER,570,tool.ITEM,3))
        self.assertNotIn("native_acceptance", state)
        self.assertNotIn("previous_release", state)
        self.assertNotIn("release_history", state)
        self.assertEqual(tool.protocol.journal_manifest(state), tool.MANIFEST)

    def test_full_official_proof_requires_fresh_1313_3406_five_vpks_180_modules_and_raw_acf(self):
        good = self.official(); tool.validate_official(good)
        mutations = [
            lambda p:p["subscription_refresh"]["callback"].update(callback_id=1),
            lambda p:p["subscription_refresh"].update(subscribe_calls=2),
            lambda p:p["download"]["callback"].update(result=2),
            lambda p:p["download"]["callback"].update(app_id=571),
            lambda p:p["verification"]["verification"].update(crc32_verified=False),
            lambda p:p["verification"]["package_files"][1].update(sha256="a"*64),
            lambda p:p.update(protected_modules_verified=179),
            lambda p:p.update(release_sequence=2026102703),
            lambda p:p.update(steam_manifest=int(tool.MANIFEST)),
            lambda p:p["acf_installed_entry"].update(manifest=int(tool.MANIFEST)),
            lambda p:p["acf_installed_entry"].update(size="999"),
            lambda p:p["acf_installed_entry"].update(timeupdated="1"),
            lambda p:p["post_query"].update(tags="Custom Game,changed"),
            lambda p:p["pre_query"].update(cached=True),
            lambda p:p.update(package_report_sha256="b"*64),
        ]
        for index, mutate in enumerate(mutations):
            p = copy.deepcopy(good); mutate(p)
            with self.subTest(index=index), self.assertRaises(tool.callbacks.Refused): tool.validate_official(p)

    def test_saved_copied_stale_or_future_proof_and_unlocked_commit_are_refused(self):
        self.preserve(); proof = self.proof()
        with self.assertRaisesRegex(tool.callbacks.Refused, "locked_live_proof"):
            tool.commit_local(self.inputs, proof, self.directory)
        with tool.publisher_lock():
            with self.assertRaisesRegex(tool.callbacks.Refused, "locked_live_proof"):
                tool.commit_local(self.inputs, copy.deepcopy(proof), self.directory)
            for seconds in (-301, 10):
                proof["verified_utc"] = (datetime.now(timezone.utc)+timedelta(seconds=seconds)).isoformat()
                with self.assertRaisesRegex(tool.callbacks.Refused, "not_fresh"):
                    tool.commit_local(self.inputs, proof, self.directory)
        self.assertEqual(self.state.read_bytes(), self.raw)

    def test_real_temp_commit_preserves_originals_cas_restores05_facts_and_only_historical_native(self):
        self.preserve(); proof = self.proof()
        with tool.publisher_lock():
            result = tool.commit_local(self.inputs, proof, self.directory)
        state = tool.api.pack.handoff.decode_json(self.state.read_bytes())
        for name in tool.FACT_FIELDS:
            self.assertEqual(state[name], self.baseline[name])
        self.assertEqual((self.directory/"pending.original.json").read_bytes(), self.raw)
        self.assertEqual((self.directory/"upload_failure.original.log").read_bytes(), self.log)
        self.assertEqual(state["previous_release"], self.history[-1])
        self.assertEqual(state["release_history"], self.history[:-1])
        self.assertNotIn("native_acceptance", state)
        self.assertEqual(state["historical_acceptance"]["native_acceptance"], self.baseline["native_acceptance"])
        self.assertEqual(state["native_test"], "HISTORICAL_ONLY_NOT_RUN_DURING_RECONCILIATION")
        self.assertFalse(state["ready_for_public_release"])
        self.assertEqual(state["failed_attempts"][-1]["failed_release_sequence"], 2026102707)
        self.assertEqual(result["updates_submitted"], 0)
        self.assertIsNone(tool._live_proof)

    def test_cas_competing_journal_before_or_after_temp_write_is_preserved(self):
        self.preserve(); proof = self.proof()
        self.state.write_bytes(b"foreign producer")
        with tool.publisher_lock(), self.assertRaises(tool.callbacks.Refused):
            tool.commit_local(self.inputs, proof, self.directory)
        self.assertEqual(self.state.read_bytes(), b"foreign producer")
        self.state.write_bytes(self.raw)
        original = tool.unchanged
        calls = [0]
        def race(inputs):
            calls[0] += 1
            if calls[0] == 2: self.state.write_bytes(b"foreign producer")
            return original(inputs)
        with tool.publisher_lock(), patch.object(tool, "unchanged", side_effect=race), self.assertRaises(tool.callbacks.Refused):
            tool.commit_local(self.inputs, proof, self.directory)
        self.assertEqual(self.state.read_bytes(), b"foreign producer")
        self.assertEqual(list(self.root.glob("*.part")), [])

    def test_verify_mode_obtains_new_locked_proof_and_never_commits(self):
        proof = self.proof()
        def fresh(inputs, directory):
            self.assertTrue(tool._lock_held)
            self.assertEqual(inputs, self.inputs)
            return proof
        with patch.object(tool, "OUTPUT", self.root/"recovery"), \
                patch.object(tool, "local_inputs", return_value=self.inputs), \
                patch.object(tool, "verify_live", side_effect=fresh) as live, \
                patch.object(tool, "commit_local", side_effect=AssertionError("commit forbidden")), \
                redirect_stdout(io.StringIO()):
            self.assertEqual(tool.main(["--verify"]), 0)
        self.assertEqual(live.call_count, 1)
        self.assertEqual(self.state.read_bytes(), self.raw)

    def test_apply_cannot_reuse_saved_proof_when_this_attempt_live_verification_fails(self):
        self.proof()
        with patch.object(tool, "OUTPUT", self.root/"recovery"), \
                patch.object(tool, "local_inputs", return_value=self.inputs), \
                patch.object(tool, "verify_live", side_effect=tool.callbacks.Refused("live refused")) as live, \
                patch.object(tool, "commit_local", side_effect=AssertionError("commit forbidden")), \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(tool.main(["--apply"]), 1)
        self.assertEqual(live.call_count, 1)
        self.assertIn("live refused", output.getvalue())
        self.assertEqual(self.state.read_bytes(), self.raw)

    def test_live_adapter_runs_full_frozen_protocol_in_owned_directory_and_restores_module_globals(self):
        self.preserve()
        original = tool.protocol.STATE, tool.protocol.OUTPUT
        def local(require_success, *, full):
            self.assertTrue(require_success and full and tool._lock_held)
            self.assertNotEqual(tool.protocol.STATE, self.state)
            state = tool.api.pack.handoff.decode_json(tool.protocol.STATE.read_bytes())
            self.assertEqual(state, tool.temporary_journal(self.inputs))
            return dict(report_sha256=tool.REPORT_SHA,total=tool.TOTAL,state=state,expected_manifest=tool.MANIFEST)
        def download(inputs):
            self.assertTrue(tool._lock_held)
            path = tool.protocol.OUTPUT/"fresh"/"verification.json"
            path.parent.mkdir(parents=True)
            official = self.official()
            official["canonical_journal_sha256"] = hashlib.sha256(tool.protocol.STATE.read_bytes()).hexdigest()
            path.write_bytes(tool.callbacks.encoded(official))
            return dict(evidence=str(path))
        with tool.publisher_lock(), patch.object(tool.protocol,"local_inputs",side_effect=local) as full, \
                patch.object(tool.protocol,"download_once",side_effect=download) as downloaded, \
                patch.object(tool.shutil,"disk_usage",return_value=SimpleNamespace(free=2**40)), \
                patch.object(tool.api.Steam,"__enter__",side_effect=AssertionError("real SDK forbidden")):
            proof = tool.verify_live(self.inputs,self.directory)
            tool.require_live_proof(proof)
        self.assertEqual((tool.protocol.STATE,tool.protocol.OUTPUT),original)
        self.assertEqual(full.call_count,1);self.assertEqual(downloaded.call_count,1)
        self.assertEqual(self.state.read_bytes(),self.raw)

    def test_low_space_refuses_before_protocol_or_sdk_and_log_redactor_hides_credentials(self):
        self.preserve()
        with tool.publisher_lock(), patch.object(tool.shutil,"disk_usage",return_value=SimpleNamespace(free=0)), \
                patch.object(tool.protocol,"local_inputs",side_effect=AssertionError("protocol forbidden")), \
                self.assertRaisesRegex(tool.callbacks.Refused,"insufficient_full_package"):
            tool.verify_live(self.inputs,self.directory)
        line = tool.redactor.redact("https://alice:secret@host.test/signed/path?token=hidden password=alsohidden")
        for secret in ("alice","secret","signed/path","hidden","alsohidden"):
            self.assertNotIn(secret,line)
        self.assertEqual(self.state.read_bytes(),self.raw)


if __name__ == "__main__":
    unittest.main()
