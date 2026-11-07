"""Real immutable production sources, explicit test-only operator seed injection.

No runtime initialization, external service, player API or catalogue artifact write.
The optional environment inputs support review before committing the seed fix.
"""
from pathlib import Path
import hashlib
import os
import subprocess
import sys
import unittest

ROOT = Path.cwd()
sys.path.insert(0, str(ROOT / "tools"))
import build_ui_static_catalog as catalog

LUA = os.environ.get("LUA51", "C:/Program Files/lua/bin/lua5.1.exe")
SOURCE = os.environ.get("SURVIVAL_TEST_SOURCE_REVISION") or subprocess.check_output(
    ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
SEED = Path(os.environ.get("SURVIVAL_TEST_PRODUCTION_SEED_FILE",
                           str(ROOT / "tools/production_ui_static_seed.lua"))).read_bytes()


class ReviewedSeed:
    input_origin = "UNIT_TEST_ONLY_REVIEWED_PRODUCTION_SEED"

    def __init__(self, seed):
        self.seed = seed
        self.revision = "UNIT_TEST_SEED_" + hashlib.sha256(seed).hexdigest()

    def read(self, relative):
        assert relative == "tools/production_ui_static_seed.lua"
        return self.seed


class ProductionSeedTests(unittest.TestCase):
    def test_current_public_projection_includes_pure_exported_helpers(self):
        source = catalog.GitSource(ROOT, SOURCE)
        result = catalog.production_projection_seed(source, LUA, ReviewedSeed(SEED))
        self.assertEqual(len(result["training"]), 8)
        self.assertEqual(len(result["research"]), 19)
        self.assertEqual(sum(len(row["levels"]) - 1 for row in result["research"]), 420)
        self.assertEqual(set(result["status_codes"]), {
            "", "available", "max_level", "prerequisite_not_met", "queue_available",
            "queued_max_level", "research_queue_full"})
        generator = result["generator_inputs"]["tools/production_ui_static_seed.lua"]
        self.assertEqual(generator["origin"], ReviewedSeed.input_origin)
        self.assertEqual(generator["sha256"], hashlib.sha256(SEED.replace(b"\r\n", b"\n")).hexdigest())

    def test_missing_private_module_reproduces_the_real_new_export_failure(self):
        seed = SEED.replace(b"\r\n", b"\n")
        self.assertIn(b"    M = {},\n", seed)
        with self.assertRaises(subprocess.CalledProcessError) as failure:
            catalog.production_projection_seed(catalog.GitSource(ROOT, SOURCE), LUA,
                ReviewedSeed(seed.replace(b"    M = {},\n", b"", 1)))
        self.assertIn(b"attempt to index global 'M'", failure.exception.stderr)


if __name__ == "__main__":
    unittest.main()
