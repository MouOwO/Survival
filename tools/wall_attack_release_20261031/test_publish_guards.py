"""Mock-only publication/download admission checks; no SDK, key or baseline reads."""
from __future__ import annotations

import copy
from contextlib import nullcontext
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest import mock

import build_release as build
import publish
import verify_download as download


class CompositeProofGuards(unittest.TestCase):
    """Real local hashing and raw-receipt contracts; no native success is claimed."""
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.origin = self.root / "wall.json"
        self.package = {"content_sha256": "a" * 64}

    def write(self, name, value):
        path = self.root / name
        raw = value if isinstance(value, bytes) else json.dumps(value).encode()
        path.write_bytes(raw)
        return {"path": str(path), "sha256": hashlib.sha256(raw).hexdigest()}

    def behavior(self):
        timeline = b'{"snapshots":["fixture"]}'
        raw = {"storage": "session_memory", "online_multiplayer_acceptance": False,
               "test_kind": "actual_native_Tools_single_formal_wave_cohort", "observed_modes": sorted(publish.MODES),
               "timeline_sha256": hashlib.sha256(timeline).hexdigest(),
               "acceptance_actor_mutations": "No NPC teleport, PerformAttack or forced order after spawn.",
               "fixture": "cohort count=1 original wave table restored", "labels": {}}
        for mode in publish.MODES:
            raw["labels"]["after_" + mode + "_N1"] = {
                "native_autonomous_attack_pass": True, "all_unpaused": True, "all_world_current": True,
                "all_enemy_acquisition_zero": True, "max_native_records": 2, "max_selected_damage_events": 2,
                "max_wall_health_loss": 2, "final": {"match_mode": mode, "wall_rule_allowed": True,
                                                        "wall": {"under_construction": False}}}
        return raw, timeline

    def loaded(self):
        files, rows, frozen_rows, raw_nodes, metadata = {}, [], [], [], []
        for index, name in enumerate(sorted(publish.FIX2)):
            source = self.write(f"source{index}.lua", b"return {}\n")
            node = self.write(f"function{index}.luac", b"test-bytecode" + bytes([index]))
            function_path = f"fixture.function{index}"
            files[name] = {"frozen_source_sha256": source["sha256"], "native_live_dump_matches_frozen_source": True,
                           "native_function_count": 1, "native_function_dumps": [{**node, "function_path": function_path,
                                                                                     "exact_dump_equal": True}]}
            rows.append({"path": name, "sha256": source["sha256"]})
            frozen_rows.append({"source": name, "sha256": source["sha256"], "frozen_input": source["path"]})
            metadata.append({"source": name, "sha256": source["sha256"]})
            data = Path(node["path"]).read_bytes()
            raw_nodes.append({"path": function_path, "native_dump_hex": data.hex(), "live_bytes": len(data),
                              "expected_bytes": len(data), "exact_dump_equal": True})
        loaded = {"schema_version": 1, "kind": "WALL_ATTACK_FIX2_LOADED_SOURCE_PROOF", "scope": publish.SCOPE,
                  "fresh_vm": True, "online": False, "offline": True, "loaded_source_equivalence_proven": True,
                  "source_input_hashes_verified_on_host": True, "ok": True, "real_class_unchanged": True,
                  "real_contact_module_unchanged": True, "pid": 100, "world_entindex": 2,
                  "match_session_id": "fixture-session", "mode": "standard", "difficulty": "N1", "proof_id": "fixture-id",
                  "candidate_content_sha256": self.package["content_sha256"], "files": files,
                  "native_runtime": {"pid": 100, "world_entindex": 2, "match_session_id": "fixture-session",
                                     "offline_storage": "session_memory", "map": "template_map",
                                     "process_started_utc": "2026-10-31T12:01:00+00:00"}}
        frozen = self.write("inputs.json", {"candidate_content_sha256": self.package["content_sha256"],
                                            "created_utc": "2026-10-31T12:00:00+00:00", "inputs": frozen_rows})
        loaded.update(input_manifest=frozen["path"], input_manifest_sha256=frozen["sha256"])
        answer = {"proof_id": loaded["proof_id"], "ok": True, "fresh_vm": True, "pid": 100,
                  "world": 2, "match_session_id": "fixture-session", "real_class_unchanged": True,
                  "real_contact_module_unchanged": True, "inputs": metadata, "nodes": raw_nodes,
                  "scalar_upvalues": [{"equal": True}]}
        self.transport(loaded, answer)
        return loaded, {"files": rows}, answer

    def transport(self, loaded, answer):
        ref = self.write("transport.json", {"ok": True, "pid": 100,
                          "rows": ["[WALL_ADMISSION_LOADED_PROOF] " + json.dumps(answer)]})
        loaded.update(transport_capture=ref["path"], transport_sha256=ref["sha256"])

    def validate_loaded(self, loaded, manifest):
        publish.validate_loaded(loaded, self.origin, publish.ProofInputs(), manifest, self.package)

    def test_reference_missing_hash_and_byte_drift_are_rejected(self):
        inputs = publish.ProofInputs()
        for ref in ({"path": "missing.json", "sha256": "a" * 64}, {"path": "missing.json"}):
            with self.subTest(ref=ref), self.assertRaises((ValueError, OSError)):
                inputs.reference(ref, self.origin)
        ref = self.write("evidence.json", {"ok": True})
        inputs.reference(ref, self.origin)
        Path(ref["path"]).write_bytes(b"{}")
        with self.assertRaisesRegex(ValueError, "changed"):
            inputs.unchanged()

    def test_source_hash_and_missing_exception_are_rechecked(self):
        inputs = publish.ProofInputs()
        ref = self.write("source.lua", b"return {}")
        path = Path(ref["path"])
        inputs.source(path, {"bytes": path.stat().st_size, "sha256": ref["sha256"]})
        path.write_bytes(b"return 1 ")
        with self.assertRaisesRegex(ValueError, "source changed"):
            inputs.unchanged()
        missing = self.root / "removed.lua"
        inputs = publish.ProofInputs(); inputs.source(missing, None)
        missing.write_bytes(b"return {}")
        with self.assertRaisesRegex(ValueError, "appeared"):
            inputs.unchanged()

    def test_actual_raw_four_mode_contract_and_each_case_damage_required(self):
        raw, timeline = self.behavior()
        publish.validate_behavior(raw, timeline)
        for mode in publish.MODES:
            for field, value in (("native_autonomous_attack_pass", False), ("all_unpaused", False),
                                 ("all_world_current", False), ("all_enemy_acquisition_zero", False),
                                 ("max_native_records", 0), ("max_selected_damage_events", 0), ("max_wall_health_loss", 0)):
                bad = copy.deepcopy(raw); bad["labels"]["after_" + mode + "_N1"][field] = value
                with self.subTest(mode=mode, field=field), self.assertRaisesRegex(ValueError, "target AND wall damage"):
                    publish.validate_behavior(bad, timeline)

    def test_raw_timeline_mode_online_and_completed_wall_are_bound(self):
        raw, timeline = self.behavior()
        for changes in ({"online_multiplayer_acceptance": True}, {"observed_modes": ["standard"]},
                        {"timeline_sha256": "0" * 64}, {"fixture": "not restored"}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                publish.validate_behavior({**raw, **changes}, timeline)
        raw["labels"]["after_standard_N1"]["final"]["wall"]["under_construction"] = True
        with self.assertRaisesRegex(ValueError, "Completed wall"):
            publish.validate_behavior(raw, timeline)

    def test_live_dump_fixture_passes_and_old_or_online_vm_rejected(self):
        loaded, manifest, _ = self.loaded()
        self.validate_loaded(loaded, manifest)
        for changes in ({"fresh_vm": False}, {"online": True}, {"loaded_source_equivalence_proven": False},
                        {"source_input_hashes_verified_on_host": False}, {"real_class_unchanged": False},
                        {"real_contact_module_unchanged": False}):
            with self.subTest(changes=changes), self.assertRaisesRegex(ValueError, "Fresh VM"):
                self.validate_loaded({**loaded, **changes}, manifest)
        loaded["native_runtime"]["process_started_utc"] = "2026-10-31T11:59:00+00:00"
        with self.assertRaisesRegex(ValueError, "after candidate"):
            self.validate_loaded(loaded, manifest)

    def test_candidate_input_source_count_and_function_bytes_cannot_drift(self):
        loaded, manifest, answer = self.loaded()
        cases = []
        bad = copy.deepcopy(loaded); bad["candidate_content_sha256"] = "old"; cases.append((bad, manifest))
        bad = copy.deepcopy(manifest); bad["files"][0]["sha256"] = "0" * 64; cases.append((loaded, bad))
        bad = copy.deepcopy(loaded); next(iter(bad["files"].values()))["native_function_count"] = 2; cases.append((bad, manifest))
        for receipt, rows in cases:
            with self.subTest(receipt=receipt.get("candidate_content_sha256")), self.assertRaises(ValueError):
                self.validate_loaded(receipt, rows)
        answer["nodes"][0]["native_dump_hex"] = "00"; self.transport(loaded, answer)
        with self.assertRaisesRegex(ValueError, "function dump"):
            self.validate_loaded(loaded, manifest)

    def test_raw_transport_world_scalar_and_omitted_node_rejected(self):
        loaded, manifest, answer = self.loaded()
        for changes in ({"world": 999}, {"pid": 999}, {"scalar_upvalues": [{"equal": False}]},
                        {"inputs": []}, {"nodes": answer["nodes"][:1]}, {"real_contact_module_unchanged": False}):
            self.transport(loaded, {**answer, **changes})
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.validate_loaded(loaded, manifest)

    def test_draft_or_failed_equivalence_never_counts_as_proof(self):
        base = {"schema": 1, "scope": publish.SCOPE, "status": "PASS_SCOPED_COMBAT_EQUIVALENCE",
                "passed": True, "online_multiplayer_acceptance": False}
        for changes in ({"status": "REVIEW_SCOPED_COMBAT_EQUIVALENCE"}, {"passed": False},
                        {"scope": "FULL_PACKAGE_EQUAL"}, {"online_multiplayer_acceptance": True}):
            with self.subTest(changes=changes), self.assertRaisesRegex(ValueError, "Complete scoped"):
                publish.validate_equivalence({**base, **changes}, self.origin, publish.ProofInputs(), {"files": []})


class PublicationGuards(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.sha = "f" * 64
        self.package = {"content_sha256": "a" * 64, "files": 6915, "vpk_sha256": "b" * 64,
                        "package_files": [{"name": "fixture.vpk", "bytes": 40, "sha256": "b" * 64}]}
        self.native = {"status": "PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY", "content_sha256": "a" * 64,
                       "cheats": False, "signed_resources_verified": 6915}
        self.wall = {"schema": 1, "scope": publish.SCOPE, "candidate_content_sha256": "a" * 64,
                     "online_multiplayer_acceptance": False}
        for name in ("raw_acceptance", "raw_timeline", "loaded_proof", "equivalence_proof"):
            path = self.root / (name + ".json")
            path.write_text("{}", encoding="utf8")
            self.wall[name] = {"path": str(path), "sha256": hashlib.sha256(b"{}").hexdigest()}
        self.native_path, self.wall_path = self.root / "native.json", self.root / "wall.json"

    def acceptance(self, native=None, wall=None):
        values = {self.native_path: self.native if native is None else native,
                  self.wall_path: self.wall if wall is None else wall}
        with mock.patch.object(build, "load", side_effect=lambda path: copy.deepcopy(values[path])), \
             mock.patch.object(publish, "validate_behavior"), mock.patch.object(publish, "validate_loaded"), \
             mock.patch.object(publish, "validate_equivalence"):
            publish.acceptance(self.package, self.native_path, self.wall_path, {"files": []})

    def test_startup_only_cannot_substitute_for_observed_n1_wall_attack_and_damage(self):
        self.acceptance()
        failures = [{"schema": 0}, {"scope": "SAME_FULL_CONTENT"}, {"online_multiplayer_acceptance": True},
                    {"candidate_content_sha256": "old"}, {"content_sha256": self.package["content_sha256"]}]
        for delta in failures:
            wall = {**self.wall, **delta}
            with self.subTest(delta=delta), self.assertRaisesRegex((ValueError, AssertionError), "cross-run offline"):
                self.acceptance(wall=wall)

    def test_native_startup_is_bound_to_same_content_files_and_exact_cheats_false(self):
        for delta in ({"content_sha256": "old"}, {"signed_resources_verified": 6913}, {"cheats": True},
                      {"cheats": 0}, {"status": "PASS_OFFLINE_STARTUP"}):
            with self.subTest(delta=delta), self.assertRaisesRegex((ValueError, AssertionError), "signed production startup"):
                self.acceptance(native={**self.native, **delta})

    def test_publisher_reuses_original_unlisted_item_four_testers_and_apply_update_existing_only(self):
        listing_path = self.root / "baseline_listing.json"
        listing = {"workshop_id": build.ITEM, "visibility_requested": "unlisted", "cover": "cover.jpg",
                   "tester_steamids64": ["fixture-owner", "fixture-tester2", "fixture-tester3", "fixture-tester4"],
                   "title": "original title", "description": "original approved description"}
        report_dir = self.root / "report"
        for apply in (False, True):
            calls = []
            def validated(digest, *, full):
                calls.append(("validated", digest, full))
                return copy.deepcopy(self.package), {}, {}
            def read(path):
                if path == listing_path:
                    return copy.deepcopy(listing)
                return copy.deepcopy(self.native if path == self.native_path else self.wall)
            def sdk():
                calls.append(("sdk", list(sys.argv)))
                return 0
            argv = ["publish.py", "--report-sha256", self.sha, "--native-proof", str(self.native_path),
                    "--wall-proof", str(self.wall_path)] + (["--apply"] if apply else [])
            with self.subTest(apply=apply), mock.patch.object(build, "validated_package", side_effect=validated), \
                 mock.patch.object(build, "load", side_effect=read), mock.patch.object(build, "BASE_LISTING", listing_path), \
                 mock.patch.object(build, "REPORT", report_dir), mock.patch.object(build.inc, "trusted_source", return_value=nullcontext()), \
                 mock.patch.object(build, "scene_maps", return_value=nullcontext()), \
                 mock.patch.object(publish, "acceptance") as acceptance, \
                 mock.patch.object(publish.publisher, "main", side_effect=sdk), mock.patch.object(sys, "argv", argv):
                self.assertEqual(publish.main(), 0)
                acceptance.assert_called_once_with(self.package, self.native_path, self.wall_path, {})
            self.assertEqual(calls[0], ("validated", self.sha, True), "report pin validation must precede SDK delegation")
            passed = calls[-1][1]
            self.assertEqual("--apply" in passed, apply)
            self.assertEqual("--update-existing" in passed, apply)
            self.assertNotIn("--create", passed)
            self.assertEqual(passed[passed.index("--state-file") + 1], str(build.JOURNAL))
            changed = json.loads((report_dir / "listing.json").read_text("utf-8"))
            for key in ("workshop_id", "visibility_requested", "tester_steamids64", "title", "description"):
                self.assertEqual(changed[key], listing[key], key + " must be reused")
            self.assertEqual(changed["release_sequence"], build.SEQUENCE)
            self.assertEqual(changed["runtime_files"], self.package["files"])

    def test_wrong_report_pin_blocks_publisher_before_listing_or_sdk(self):
        argv = ["publish.py", "--report-sha256", self.sha, "--native-proof", str(self.native_path),
                "--wall-proof", str(self.wall_path), "--apply"]
        with mock.patch.object(build, "validated_package", side_effect=ValueError("reviewed report SHA mismatch")) as verified, \
             mock.patch.object(build, "load", side_effect=AssertionError("no listing/proof access before report admission")) as reads, \
             mock.patch.object(publish.publisher, "main", side_effect=AssertionError("no SDK")) as sdk, \
             mock.patch.object(sys, "argv", argv), self.assertRaisesRegex(ValueError, "SHA mismatch"):
            publish.main()
        verified.assert_called_once_with(self.sha, full=True)
        reads.assert_not_called()
        sdk.assert_not_called()

    def journal(self):
        return {"uploaded": True, "owner": download.api.OWNER, "app_id": download.api.APP,
                "workshop_id": build.ITEM, "visibility_requested": 3, "release_sequence": build.SEQUENCE,
                "content_sha256": self.package["content_sha256"], "package_files": copy.deepcopy(self.package["package_files"]),
                "vpk_sha256": self.package["vpk_sha256"], "legal_agreement_required": False,
                "status": "SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST", "steam_manifest": "1234567890123456789"}

    def local_context(self, state):
        report, manifest, signature = copy.deepcopy(self.package), {"content_sha256": "a" * 64}, {"release_sequence": build.SEQUENCE}
        def read(path, maximum, snapshots):
            raw = json.dumps(state).encode() if path == build.JOURNAL else b"fixture signed metadata"
            snapshots[path] = raw
            return raw
        return (mock.patch.object(download.protocol, "read_snapshot", side_effect=read),
                mock.patch.object(download.protocol, "unchanged"),
                mock.patch.object(build, "validated_package", return_value=(report, manifest, signature)),
                mock.patch.object(download, "REPORT_SHA", self.sha))

    def test_download_requires_same_release_success_ack_package_and_legal_clearance_before_steam(self):
        invalid = [{"uploaded": False}, {"release_sequence": build.BASE_SEQUENCE}, {"package_files": []},
                   {"vpk_sha256": "wrong"}, {"content_sha256": "old"}, {"workshop_id": "different item"},
                   {"visibility_requested": 0}, {"legal_agreement_required": True},
                   {"status": "SUBMIT_REQUEST_PENDING", "uploaded": False}]
        for delta in invalid:
            state = {**self.journal(), **delta}
            read, unchanged, validated, pin = self.local_context(state)
            with self.subTest(delta=delta), read, unchanged, validated, pin, \
                 mock.patch.object(download.protocol, "download_once", side_effect=AssertionError("no Steam download")) as sdk, \
                 mock.patch.object(download.api, "publication_lock", side_effect=AssertionError("no publication lock before admission")), \
                 self.assertRaisesRegex((ValueError, AssertionError), "Successful same-release"):
                download.local_inputs(require_success=True)
            sdk.assert_not_called()

    def test_download_good_local_identity_binds_report_pin_and_snapshot_without_steam(self):
        state = self.journal()
        read, unchanged, validated, pin = self.local_context(state)
        with read, unchanged as checked, validated as admission, pin, \
             mock.patch.object(download.protocol, "download_once", side_effect=AssertionError("no Steam")) as sdk:
            values = download.local_inputs(require_success=True, full=True)
        admission.assert_called_once_with(self.sha, full=True)
        checked.assert_called_once()
        sdk.assert_not_called()
        self.assertTrue(values["success"])
        self.assertEqual(values["expected_manifest"], state["steam_manifest"])
        self.assertEqual(values["report_sha256"], self.sha)
        self.assertEqual(values["state_sha256"], hashlib.sha256(json.dumps(state).encode()).hexdigest())
        self.assertEqual(values["protected_modules"], 184)

    def test_download_cli_checks_reviewed_report_before_official_protocol_delegation(self):
        fake = types.SimpleNamespace(main=mock.Mock(return_value=0))
        argv = ["verify_download.py", "--report-sha256", self.sha, "--download"]
        with mock.patch.object(download, "protocol", fake), mock.patch.object(download, "REPORT_SHA", None), \
             mock.patch.object(build, "validated_package", side_effect=ValueError("bad reviewed report")), \
             mock.patch.object(sys, "argv", argv), self.assertRaisesRegex(ValueError, "bad reviewed report"):
            download.main()
        fake.main.assert_not_called()
        order = []
        def admission(digest):
            order.append(("validated", digest))
            return self.package, {}, {}
        def protocol_main():
            order.append(("protocol", list(sys.argv)))
            return 0
        fake.main.side_effect = protocol_main
        with mock.patch.object(download, "protocol", fake), mock.patch.object(download, "REPORT_SHA", None), \
             mock.patch.object(build, "validated_package", side_effect=admission), \
             mock.patch.object(build, "scene_maps", return_value=nullcontext()), \
             mock.patch.object(build.inc, "trusted_source", return_value=nullcontext()), mock.patch.object(sys, "argv", argv):
            self.assertEqual(download.main(), 0)
        self.assertEqual(order[0], ("validated", self.sha))
        self.assertEqual(order[1][1][1:], ["--download"])
        self.assertEqual(fake.ITEM, build.ITEM)
        self.assertEqual(fake.SEQUENCE, build.SEQUENCE)
        self.assertEqual(fake.CONTENT, self.package["content_sha256"])
        self.assertEqual(fake.FILE_COUNT, self.package["files"])


if __name__ == "__main__":
    unittest.main()
