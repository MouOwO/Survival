"""Offline authored-mode admission, N50 accounting and packaged Lua worker.

Build into a temporary output directory only. No existing bundle pointers,
accounts, services or databases are modified.
"""
from copy import deepcopy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "server"), str(ROOT / "server/tests")]
from archive_backend import match_modes
from archive_backend.bundle import Bundle, build
from archive_backend.service import ArchiveService, ArchiveError
import test_archive_mode_admission_compatibility as admission_fixture
from test_stackable_pure_projection import override
ApiError = admission_fixture.ApiError


class HumanModeAdmissionTests(unittest.TestCase):
    """Use the established durable-session fixture with the new gates."""
    setUp = admission_fixture.ModeAdmissionCompatibilityTests.setUp
    login = admission_fixture.ModeAdmissionCompatibilityTests.login

    def test_exact_prerequisite_from_any_trusted_battle_mode(self):
        for mode, key in (("rich", "n3"), ("cold", "n5")):
            for source_mode in match_modes.MODE_IDS:
                self.session = f"human-spec-{mode}-{source_mode}"
                self.profile["save"]["archive"] = ({"mode_clear_counts": {"pure": {key: 1}}}
                    if source_mode == "pure" else {source_mode + "_clear_counts": {key: 1}})
                result = self.login(mode)
                self.assertEqual(result["game_mode"], mode)
                self.assertEqual(self.sessions[(self.app._database_account_id("100"), self.session)]["mode"], mode)
        before = deepcopy(self.profile)
        self.login("cold")
        self.assertEqual(self.profile, before, "admission never changes saved progress")
        for archive in ({"standard_clear_counts": {}, "clear_counts": {"n3": 1}},
                        {"standard_clear_counts": {}, "pure_clear_counts": {"n3": 1}},
                        {"standard_clear_counts": {}, "mode_clear_counts": {"standard": {"n3": 1}}},
                        {"standard_clear_counts": {}, "mode_clear_counts": {"rich": {"n3": 1}}}):
            self.profile["save"]["archive"] = archive
            self.session = "human-spec-no-mixed-fallback"
            with self.subTest(archive=archive), self.assertRaisesRegex(ApiError, "rich_mode_locked"):
                self.login("rich")
        self.profile["save"]["archive"] = {"standard_clear_counts": {},
                                            "mode_clear_counts": {"pure": {"n3": 1}}}
        self.session = "human-spec-proven-pure-clear"
        self.assertEqual(self.login("rich")["game_mode"], "rich")

    def test_invalid_or_higher_counts_and_payload_unlocks_never_admit(self):
        for mode, key in (("rich", "n3"), ("cold", "n5")):
            for value in (True, "1", 0, -1, 1.5, None):
                self.profile["save"]["archive"] = {"mode_clear_counts": {"pure": {key: value}},
                                                    "clear_counts": {"n50": 99}}
                with self.subTest(mode=mode, value=value), self.assertRaisesRegex(ApiError, mode + "_mode_locked"):
                    self.module.login(self.app, {"account_id": "100", "match_session_id": self.session,
                                                "mode": mode, "clear_counts": {key: 999}})
        self.assertEqual(self.calls, [], "rejected admission never creates a DB session")

    def test_closed_modes_are_rejected_before_reads_or_rpcs(self):
        self.profile["save"]["archive"] = {"clear_counts": {"n3": 1, "n5": 1, "n9": 1, "n11": 1}}
        for mode in ("scourge", "ruins", "celestial", "fishing"):
            with self.subTest(mode=mode), self.assertRaisesRegex(ApiError, "mode_not_released"):
                self.login(mode)
        self.assertEqual(self.calls, [])

    def test_retry_keeps_baseline_and_mode_identity(self):
        self.profile["save"]["archive"] = {"clear_counts": {"n3": 1, "n5": 1}}
        self.login("rich")
        key = self.app._database_account_id("100"), self.session
        original = deepcopy(self.sessions[key])
        self.profile["save"]["gameplay_stats"]["initial_wood"] = 999
        self.login("rich")
        self.assertEqual(self.sessions[key], original)
        with self.assertRaisesRegex(ApiError, "match_mode_locked"):
            self.login("cold")


class HumanModeProgressionTests(unittest.TestCase):
    def test_n50_progress_survives_both_public_projection_paths(self):
        values = {"n1": 1, "n20": 2, "n21": 3, "n49": 4, "n50": 5,
                  "n0": 99, "n51": 99, "n02": 99, "n5": True, "n6": "1", "n7": -1}
        expected = {"n1": 1, "n20": 2, "n21": 3, "n49": 4, "n50": 5}
        source = {"save": {"archive": {"clear_counts": values, "cold_clear_counts": values,
                                       "mode_clear_counts": {"cold": values}}}}
        before = deepcopy(source)
        view = match_modes.progression(source)
        self.assertEqual(view["clear_counts"], expected)
        self.assertEqual(view["cold_clear_counts"], expected)
        self.assertEqual(view["mode_clear_counts"]["cold"], expected)
        self.assertEqual(view["highest_difficulty"], 50)
        self.assertEqual(override().progression(source)["clear_counts"], expected)
        self.assertEqual(source, before)


class HumanModeWorkerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = Path(os.environ.get("LUA_EXECUTABLE", "C:/Program Files/lua/bin/lua5.1.exe"))
        if not cls.lua.is_file():
            raise unittest.SkipTest("Set LUA_EXECUTABLE to a native Lua 5.1 interpreter")
        parent = ROOT / "output/human_spec_backend_20261022"
        parent.mkdir(parents=True, exist_ok=True)
        cls.temporary = tempfile.TemporaryDirectory(prefix="bundle-", dir=parent)
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.production_paths = [ROOT / "server/bundles/current.json",
                                ROOT / "scripts/vscripts/config/generated/archive_http_bundle.lua"]
        cls.before = [path.read_bytes() for path in cls.production_paths]
        destination = Path(cls.temporary.name)
        cls.digest = build(ROOT, destination=destination, update_game_config=False)
        cls.bundle = Bundle(destination / cls.digest)
        cls.defaults = {row["field_id"]: row.get("default_value", 0)
                        for row in cls.bundle.configs["player_gameplay_stats"]["rows"]}

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "before"):
            assert [path.read_bytes() for path in cls.production_paths] == cls.before, "production bundle pointers changed"

    def worker(self, mode, difficulty):
        request = {"configs": self.bundle.configs, "seed": 123456, "server_time": 1900000000,
                   "profile": {"save": {"archive": {}, "gameplay_stats": self.defaults}},
                   "command": {"id": "human-mode-test:" + mode + difficulty, "kind": "mode_clear",
                               "mode_id": mode, "difficulty_id": difficulty, "count": 1,
                               "day_key": "22000", "today": 22000}}
        completed = subprocess.run([str(self.lua), "worker.lua"], cwd=self.bundle.directory,
                                   input=json.dumps(request), text=True, encoding="utf-8",
                                   capture_output=True, timeout=20)
        self.assertEqual(completed.returncode, 0, "packaged worker could not load its dependencies")
        return json.loads(completed.stdout)

    def test_bundle_executes_n50_clears_and_rejects_outside_mode_range(self):
        for mode, difficulty in (("cold", "n50"), ("rich", "n30"), ("scourge", "n50"),
                                 ("ruins", "n50"), ("celestial", "n35")):
            with self.subTest(mode=mode):
                result = self.worker(mode, difficulty)
                self.assertTrue(result.get("ok"), result.get("error"))
                self.assertEqual(result["archive"]["mode_clear_counts"][mode][difficulty], 1)
        for mode, difficulty in (("standard", "n11"), ("pure", "n11"), ("rich", "n31"), ("celestial", "n36")):
            with self.subTest(mode=mode, difficulty=difficulty):
                result = self.worker(mode, difficulty)
                self.assertFalse(result["ok"])
                self.assertEqual(result["error"], "archive_mode_difficulty_unavailable")

    def test_http_admission_keeps_n50_but_rejects_n51_and_extra_fields(self):
        service = ArchiveService(SimpleNamespace(), self.bundle, str(self.lua))
        for kind in ("clear", "mode_clear", "cold_clear", "rich_clear", "scourge_clear"):
            command = {"id": "human-spec-validate", "kind": kind, "count": 1, "difficulty_id": "n50"}
            self.assertEqual(service.validate(command)["difficulty_id"], "n50")
            for invalid in ("n51", "n0", "n01", True):
                with self.subTest(kind=kind, invalid=invalid), self.assertRaises(ArchiveError):
                    service.validate(dict(command, difficulty_id=invalid))
            with self.assertRaises(ArchiveError):
                service.validate(dict(command, mode_id="cold"))
        definition = next(row for row in self.bundle.configs["archive_challenge_definitions"]["rows"] if row.get("enabled"))
        command = {"id": "human-spec-challenge", "kind": "challenge", "challenge_id": definition["challenge_id"],
                   "difficulty_id": "n50", "kill_sequence": 1}
        self.assertEqual(service.validate(command)["difficulty_id"], "n50")
        with self.assertRaises(ArchiveError):
            service.validate(dict(command, difficulty_id="n51"))


if __name__ == "__main__":
    unittest.main()
