"""Exercise evidence/provenance failures and the real managed-builder boundary."""
from pathlib import Path
import copy
import importlib.util
import json
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def load(relative, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Profiles(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load("tools/rich_n2_n3_20261018/build_profiles.py", "reviewed_profiles")
        cls.temporary = tempfile.TemporaryDirectory(prefix="rich_profiles_", dir=ROOT / "output")
        cls.fixture = Path(cls.temporary.name)
        (cls.fixture / "scripts/vscripts/config/generated").mkdir(parents=True)
        cls.original = json.loads((ROOT / cls.builder.SOURCE).read_text(encoding="utf-8"))
        files = [cls.builder.SOURCE, "data/balance/rich_n1_wave_stats.json",
            "data/csv/怪物与波次系统/wave_definitions.csv",
            "data/csv/挑战与奖励系统/challenge_combat_profiles.csv",
            "tools/rich_waves_20261018/build_profiles.py",
            "tools/rich_n2_n3_20261018/build_profiles.py"]
        files += [row["evidence"]["frame"] for row in cls.original["observations"]
                  if row["difficulty_id"] != "N1"]
        for relative in files:
            target = cls.fixture / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def setUp(self):
        self.data = copy.deepcopy(self.original)

    def generate(self):
        (self.fixture / self.builder.SOURCE).write_text(
            json.dumps(self.data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        return self.builder.generate(self.fixture)

    def test_real_outputs_and_managed_regeneration(self):
        self.generate()
        # Execute the real two child builders. Their output names participate in
        # the main CSV builder's stale-file keep set.
        configs = load("tools/build_configs.py", "managed_configs")
        configs.ROOT = self.fixture
        outputs = configs.build_mode_balance_configs()
        self.assertEqual(outputs, {"rich_wave_profiles.lua", "rich_monster_profiles.lua"})
        for filename in outputs:
            relative = "scripts/vscripts/config/generated/" + filename
            self.assertEqual((self.fixture / relative).read_bytes(), (ROOT / relative).read_bytes())

    def test_missing_wave_batch_is_rejected(self):
        del self.data["difficulties"]["N2"]["waves"]["1"]["batches"]["1N1"]
        with self.assertRaisesRegex(AssertionError, "wave batches"):
            self.generate()

    def test_observed_value_cannot_be_rewritten(self):
        self.data["difficulties"]["N2"]["waves"]["1"]["batches"]["1N1"]["health"] += 1
        with self.assertRaisesRegex(AssertionError, "Observed value changed"):
            self.generate()

    def test_estimate_cannot_be_claimed_as_observation(self):
        self.data["difficulties"]["N3"]["encounters"]["encounter_rebirth_10"]["estimated"] = False
        with self.assertRaisesRegex(AssertionError, "Estimated flag"):
            self.generate()

    def test_estimate_operands_must_match_the_result(self):
        profile = self.data["difficulties"]["N3"]["encounters"]["encounter_rebirth_10"]
        profile["health"] += 1
        with self.assertRaisesRegex(AssertionError, "operands"):
            self.generate()

    def test_large_health_display_units_are_checked(self):
        record = next(row for row in self.data["observations"] if row["record_id"] == "N2-REBIRTH-10")
        record["stats"]["health"] /= 10
        with self.assertRaisesRegex(AssertionError, "unit conversion"):
            self.generate()

    def test_evidence_bytes_cannot_change_silently(self):
        record = next(row for row in self.data["observations"] if row["difficulty_id"] == "N2")
        path = self.fixture / record["evidence"]["frame"]
        original = path.read_bytes()
        try:
            path.write_bytes(original[:-1] + bytes([original[-1] ^ 1]))
            with self.assertRaisesRegex(AssertionError, "Evidence changed"):
                self.generate()
        finally:
            path.write_bytes(original)


if __name__ == "__main__":
    unittest.main(verbosity=2)
