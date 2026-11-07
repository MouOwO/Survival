"""Pure entry/lifecycle boundary tests; never authenticate a real package or run Dota.

Signature, immutable Git and complete-package verification remain the real
canonical implementation's responsibility; tests assert delegation and refusal,
not a synthetic substitute for signed-package/native acceptance.
"""
import copy
import hashlib
import importlib.util
import io
import json
from contextlib import redirect_stdout
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from release_lineage_20261101 import guard

spec = importlib.util.spec_from_file_location("signed_online_test", Path(__file__).with_name("online_signed_entry.py"))
entry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(entry)


class SignedOnlineTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.folder = self.root / "output/release0705"
        self.folder.mkdir(parents=True)
        self.binding_path = self.root / "output/test_entry_runtime/online_signed_candidate.json"
        self.binding_path.parent.mkdir(parents=True, exist_ok=True)
        self.expected = {"release_sequence": 2026110705,
                         "source_revisions": {"game": "a" * 40, "content": "b" * 40},
                         "operator_revision": "c" * 40}
        self.report = dict(self.expected, workshop_id=entry.WORKSHOP_ID,
                           status="BUILT_SIGNED_COMPLETE_CANDIDATE_PENDING_NATIVE_ADMISSION",
                           signature_valid=True, workshop_upload_performed=False,
                           content_sha256="d" * 64, signed_manifest_sha256="e" * 64,
                           production_policy_reviews=[dict(path=path, kind="AUTHENTICATED0104_CONSTANT_BYTES",
                               constant_policy_probe_required=True, production_sha256="f" * 64, parent_sha256="f" * 64)
                               for path in ("scripts/vscripts/config/release_profile.lua",
                                            "scripts/vscripts/config/player_web_auth.lua")])
        self.package_sha = "1" * 64
        self.binding = entry.build_binding(self.report, self.package_sha, expected_newest=self.expected)
        self.save_binding()
        self.authority = SimpleNamespace(policy={"workshop_id": entry.WORKSHOP_ID,
                "release_sequence": self.expected["release_sequence"], "report_directory": str(self.folder)})
        self.rehearsal = Mock()
        self.rehearsal.STORE = self.root / "external_lab"
        self.rehearsal.recipe.return_value = SimpleNamespace(REPORT=self.folder)
        self.rehearsal.package_auth.side_effect = lambda pin, full: (copy.deepcopy(self.report), {})
        self.facade = SimpleNamespace(guard=guard, authority=Mock(return_value=self.authority),
                                      pinned_module=Mock(return_value=self.rehearsal))
        for name, value in (("ROOT", self.root), ("BINDING", self.binding_path),
                            ("RUNTIME", self.root / "output/runtime"), ("_facade", lambda: self.facade)):
            current = patch.object(entry, name, value)
            current.start()
            self.addCleanup(current.stop)

    def save_binding(self):
        self.binding_path.write_text(json.dumps(self.binding), encoding="utf-8")

    def test_pure_binding_is_defensive_and_has_no_side_effect(self):
        value = entry.build_binding(self.report, self.package_sha, expected_newest=self.expected)
        value["expected_newest"]["source_revisions"]["game"] = "0" * 40
        self.assertEqual(self.expected["source_revisions"]["game"], "a" * 40)
        self.assertFalse(value["cheats_allowed"])
        self.assertEqual(value["publication_status"], "LOCAL_ONLINE_TEST_NOT_PUBLISHED")
        self.assertFalse(entry.RUNTIME.exists())

    def test_current_canonical_package_check_does_not_require_mutable_head(self):
        with patch.object(entry.subprocess, "run", side_effect=AssertionError("No git HEAD/native lookup")), \
                patch.object(entry, "_write_status", side_effect=AssertionError("Check is read-only")):
            value = entry.check()
        self.assertEqual(value["source_revisions"], self.expected["source_revisions"])
        self.assertFalse(value["game_started"])
        self.assertFalse(value["workshop_synchronized"])
        self.rehearsal.package_auth.assert_called_once_with(self.package_sha, full=False)
        self.facade.pinned_module.assert_called_once_with(self.authority, "rehearsal")
        for method in ("stage", "launch", "restore"):
            getattr(self.rehearsal, method).assert_not_called()
        self.assertFalse(entry.RUNTIME.exists())

    def test_stale_version_source_operator_or_signature_cannot_launch(self):
        changes = [("release_sequence", 2026110704), ("source_revisions", {"game": "0" * 40, "content": "b" * 40}),
                   ("operator_revision", "0" * 40), ("signature_valid", False),
                   ("workshop_upload_performed", True), ("workshop_id", "other"),
                   ("status", "READY"), ("content_sha256", "0" * 64), ("signed_manifest_sha256", "0" * 64)]
        original = copy.deepcopy(self.report)
        for key, value in changes:
            with self.subTest(key=key):
                self.report = dict(original, **{key: value})
                with self.assertRaises((RuntimeError, ValueError)):
                    entry.prepare()
        self.report = original

    def test_strict_binding_bools_and_hashes(self):
        original = copy.deepcopy(self.binding)
        for key, value in (("schema", True), ("schema", 2), ("route", "lobby"),
                           ("cheats_allowed", 0), ("cheats_allowed", True),
                           ("cloud_login_required", 1), ("publication_status", "PUBLISHED"),
                           ("unknown", "ignored?")):
            with self.subTest(key=key, value=value):
                self.binding = dict(original, **{key: value})
                self.save_binding()
                with self.assertRaisesRegex(RuntimeError, "online_binding_contract_invalid"):
                    entry.prepare()
        self.binding = copy.deepcopy(original)
        self.binding["candidate"]["package_report_sha256"] = "bad"
        self.save_binding()
        with self.assertRaisesRegex(RuntimeError, "online_candidate_hash_invalid"):
            entry.prepare()

    def test_invalid_expected_newest_fails_before_canonical(self):
        for invalid in ({}, {**self.expected, "release_sequence": True},
                        {**self.expected, "operator_revision": "HEAD"},
                        {**self.expected, "source_revisions": {"game": "a" * 40}}):
            with self.subTest(invalid=invalid), self.assertRaises(RuntimeError):
                entry.build_binding(self.report, self.package_sha, expected_newest=invalid)
        self.rehearsal.package_auth.assert_not_called()

    def test_authority_advancement_refuses_old_candidate(self):
        self.authority.policy["release_sequence"] += 1
        with self.assertRaisesRegex(RuntimeError, "online_authority_not_expected_newest"):
            entry.prepare()
        self.rehearsal.package_auth.assert_not_called()

    def test_missing_binding_never_falls_back_to_old_online_copy(self):
        self.binding_path.unlink()
        with self.assertRaisesRegex(ValueError, "bounded_regular_json_required"):
            entry.prepare()
        self.rehearsal.package_auth.assert_not_called()

    def test_oversized_or_nonobject_binding_refused_before_package_read(self):
        for raw in (b" " * (entry.MAX_RECORD + 1), b"[]", b"not-json"):
            with self.subTest(size=len(raw)):
                self.binding_path.write_bytes(raw)
                with self.assertRaises(ValueError):
                    entry.prepare()
        self.rehearsal.package_auth.assert_not_called()

    def test_report_must_match_fixed_authority_directory(self):
        self.rehearsal.recipe.return_value.REPORT = self.root / "output/old"
        with self.assertRaisesRegex(RuntimeError, "online_canonical_report_directory_mismatch"):
            entry.prepare()
        self.authority.policy["report_directory"] = str(self.root / "outside_output")
        with self.assertRaisesRegex(RuntimeError, "online_fixed_report_directory_required"):
            entry.prepare()

    def test_real_guard_rejects_bound_record_reparse(self):
        with patch.object(guard, "regular", side_effect=guard.Refused("reparse_path_refused")):
            with self.assertRaisesRegex(ValueError, "reparse_path_refused"):
                entry.prepare()
        self.rehearsal.package_auth.assert_not_called()

    def test_authentication_failure_propagates_without_install(self):
        for failure in ("signature_invalid", "immutable_source_missing", "production_override_mismatch"):
            with self.subTest(failure=failure):
                self.rehearsal.package_auth.side_effect = ValueError(failure)
                with self.assertRaisesRegex(ValueError, failure):
                    entry.prepare()
        self.rehearsal.stage.assert_not_called()

    def test_production_cloud_and_cheat_gate_proof_required(self):
        original = copy.deepcopy(self.report["production_policy_reviews"])
        for index in range(2):
            for key, value in (("kind", "LOCAL_SOURCE"), ("constant_policy_probe_required", 1),
                               ("production_sha256", "0" * 64), ("parent_sha256", None)):
                with self.subTest(index=index, key=key):
                    self.report["production_policy_reviews"] = copy.deepcopy(original)
                    self.report["production_policy_reviews"][index][key] = value
                    with self.assertRaisesRegex(RuntimeError, "online_production_auth_policy_unverified"):
                        entry.prepare()
        self.report["production_policy_reviews"] = []
        with self.assertRaisesRegex(RuntimeError, "online_production_auth_policy_unverified"):
            entry.prepare()

    def prepare_run(self):
        prepared = entry.prepare()
        self.calls = []
        def stage(transaction, pin):
            self.calls.append(("stage", transaction, pin))
            return {"status": "COMPLETE_SIGNED_CANDIDATE_INSTALLED"}
        self.rehearsal.stage.side_effect = stage
        def keeper(argv, **kwargs):
            transaction = argv[argv.index("--transaction") + 1]
            pin = argv[argv.index("--report-sha256") + 1]
            self.calls.append(("keeper", transaction, pin))
            self.assertEqual(argv, [sys.executable, "-B", "-X", "utf8", str(self.root / "tools/release_pipeline.py"),
                                  "rehearsal", "launch", "--transaction", transaction,
                                  "--report-sha256", pin, "--route", "direct"])
            self.assertEqual(kwargs, {"cwd": self.root})
            folder = self.rehearsal.STORE / transaction
            folder.mkdir(parents=True)
            (folder / "hold_end.json").write_text(json.dumps({"status": "OWNED_DOTA_EXITED_HOLDS_COMPLETED",
                         "package_report_sha256": pin, "restoration_still_required": True}), encoding="utf-8")
            return SimpleNamespace(wait=Mock(return_value=0))
        def restore(transaction, pin):
            self.calls.append(("restore", transaction, pin))
            return {"status": entry.RESTORED}
        self.rehearsal.restore.side_effect = restore
        return prepared, keeper

    def run_with(self, prepared, keeper):
        with patch.object(entry.subprocess, "Popen", side_effect=keeper), redirect_stdout(io.StringIO()):
            return entry.run_prepared(prepared)

    def test_canonical_keeper_child_exits_before_exact_restore(self):
        prepared, keeper = self.prepare_run()
        result = self.run_with(prepared, keeper)
        self.assertEqual([call[0] for call in self.calls], ["stage", "keeper", "restore"])
        self.assertEqual(len({call[1] for call in self.calls}), 1)
        self.assertEqual({call[2] for call in self.calls}, {self.package_sha})
        self.rehearsal.launch.assert_not_called()  # same-process keeper cannot be restored
        self.assertTrue(result["ok"])
        self.assertTrue(result["game_started"])
        self.assertFalse(result["restoration_required"])
        self.assertFalse(result["workshop_synchronized"])
        self.assertEqual(json.loads((entry.RUNTIME / "online_latest.json").read_bytes()), result)

    def test_binding_changed_before_stage_refuses_all_mutations(self):
        prepared, keeper = self.prepare_run()
        self.binding["expected_newest"]["source_revisions"]["game"] = "0" * 40
        self.save_binding()
        result = self.run_with(prepared, keeper)
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "online_binding_changed_before_launch")
        self.assertEqual(self.calls, [])
        self.assertFalse(result["restoration_required"])
        self.assertIsNone(result["recovery_argv"])

    def test_binding_or_authority_change_during_stage_preserves_for_recovery(self):
        for kind in ("binding", "authority"):
            with self.subTest(kind=kind):
                prepared, keeper = self.prepare_run()
                def stage(*_args):
                    if kind == "binding":
                        self.binding_path.write_bytes(b"{}")
                    else:
                        self.authority.policy["report_directory"] = "changed"
                    return {"status": "COMPLETE_SIGNED_CANDIDATE_INSTALLED"}
                self.rehearsal.stage.side_effect = stage
                result = self.run_with(prepared, keeper)
                self.assertFalse(result["ok"])
                self.assertTrue(result["restoration_required"])
                self.assertEqual(self.calls, [])
                self.rehearsal.restore.assert_not_called()
                self.save_binding()

    def test_failure_or_interrupt_never_blindly_restores_or_retries(self):
        for error in (RuntimeError("fixed_failure"), OSError("sensitive details"), KeyboardInterrupt()):
            with self.subTest(error=type(error).__name__):
                prepared, keeper = self.prepare_run()
                def failed(*_args, **_kwargs):
                    raise error
                result = self.run_with(prepared, failed)
                self.assertFalse(result["ok"])
                self.assertNotIn("sensitive", json.dumps(result))
                self.assertFalse(result["automatic_retry"])
                self.assertFalse(result["game_force_stopped"])
                self.assertIn("restore", result["recovery_argv"])
                self.rehearsal.restore.assert_not_called()

    def test_nonzero_keeper_missing_or_failed_hold_refuses_restore(self):
        for failure in ("exit", "missing", "failed", "wrong_hash", "wrong_status"):
            with self.subTest(failure=failure):
                prepared, keeper = self.prepare_run()
                def broken(argv, **kwargs):
                    value = keeper(argv, **kwargs)
                    folder = self.rehearsal.STORE / self.calls[-1][1]
                    if failure == "exit":
                        value.wait.return_value = 1
                    elif failure == "missing":
                        (folder / "hold_end.json").unlink()
                    elif failure == "failed":
                        (folder / "hold_failed.json").write_text("{}")
                    else:
                        path = folder / "hold_end.json"
                        data = json.loads(path.read_bytes())
                        data["package_report_sha256" if failure == "wrong_hash" else "status"] = "wrong"
                        path.write_text(json.dumps(data))
                    return value
                result = self.run_with(prepared, broken)
                self.assertFalse(result["ok"])
                self.rehearsal.restore.assert_not_called()

    def test_restore_rejection_remains_pending_and_preserves_evidence(self):
        prepared, keeper = self.prepare_run()
        self.rehearsal.restore.side_effect = ValueError("other_dota_still_alive")
        result = self.run_with(prepared, keeper)
        self.assertFalse(result["ok"])
        self.assertEqual(result["failed_phase"], "restore")
        self.assertTrue(result["restoration_required"])
        self.assertTrue((Path(result["transaction_directory"]) / "hold_end.json").exists())

    def test_partial_stage_or_restore_result_is_never_reported_complete(self):
        for phase in ("stage", "restore"):
            with self.subTest(phase=phase):
                prepared, keeper = self.prepare_run()
                target = getattr(self.rehearsal, phase)
                target.side_effect = None
                target.return_value = {"status": "PARTIAL"}
                result = self.run_with(prepared, keeper)
                self.assertFalse(result["ok"])
                self.assertEqual(result["failed_phase"], phase)
                self.assertTrue(result["restoration_required"])
                if phase == "stage":
                    self.assertEqual(self.calls, [])
                    self.rehearsal.restore.assert_not_called()

    def test_interrupted_wait_does_not_kill_keeper_or_attempt_restore(self):
        prepared, _keeper = self.prepare_run()
        child = Mock()
        child.wait.side_effect = KeyboardInterrupt()
        with patch.object(entry.subprocess, "run", side_effect=AssertionError("run kills interrupted children")):
            result = self.run_with(prepared, lambda *args, **kwargs: child)
        self.assertEqual(result["error"], "online_interrupted")
        child.kill.assert_not_called()
        child.terminate.assert_not_called()
        self.rehearsal.restore.assert_not_called()


if __name__ == "__main__":
    unittest.main()
