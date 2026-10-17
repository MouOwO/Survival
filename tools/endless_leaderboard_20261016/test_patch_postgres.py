"""No-network checks of the exact live-source PostgreSQL RPC patch."""
from pathlib import Path
import ast
import copy
import hashlib
import json
import unittest

from patch_postgres import (
    ADDITION, REVIEWED_BASE_SHA256, patch_postgres, restore_postgres,
)

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "design_refs/endless_leaderboard_20261016/deployment/online_baseline/backend/fishing_api/postgres.py"
HISTORICAL = ROOT / "output/endless_batch_20261010/baseline/backend/fishing_api/postgres.py"
SQL = ROOT / "server/migrations/202610160001_endless_leaderboard.sql"


def signatures(text):
    tree = ast.parse(text)
    node = next(n.value for n in tree.body if isinstance(n, ast.Assign)
                and isinstance(n.targets[0], ast.Name)
                and n.targets[0].id == "RPC_SIGNATURES")
    return {ast.literal_eval(key): [ast.literal_eval(arg) for arg in value.args]
            for key, value in zip(node.keys, node.values)}


class PatchPostgresTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = BASE.read_text(encoding="utf-8")
        cls.patched = patch_postgres(cls.original)

    def test_reviewed_live_source_and_historical_baseline_agree(self):
        self.assertEqual(hashlib.sha256(self.original.encode()).hexdigest(), REVIEWED_BASE_SHA256)
        self.assertEqual(BASE.read_bytes(), HISTORICAL.read_bytes())

    def test_exact_reverse_and_idempotence(self):
        self.assertEqual(restore_postgres(self.patched).encode(), BASE.read_bytes())
        self.assertEqual(restore_postgres(self.original), self.original)
        self.assertEqual(patch_postgres(self.patched), self.patched)
        self.assertEqual(self.patched.replace(ADDITION, "", 1), self.original)

    def test_exact_new_sql_signatures_and_old_signatures_untouched(self):
        before, after = signatures(self.original), signatures(self.patched)
        self.assertEqual(len(after), len(before) + 2)
        self.assertEqual({k: after[k] for k in before}, before)
        self.assertEqual(after["archive_bind_leaderboard_identity"], [
            ("p_account", "text", "hash"), ("p_public_account_id", "text", "nullable_error")])
        self.assertEqual(after["archive_endless_leaderboard"], [])
        sql = SQL.read_text(encoding="utf-8")
        self.assertIn("FUNCTION public.archive_bind_leaderboard_identity", sql)
        self.assertIn("FUNCTION public.archive_endless_leaderboard()", sql)
        self.assertIn("p_account text,p_public_account_id text", sql)
        self.assertIn("archive_bind_leaderboard_identity(text,text)", sql)
        self.assertIn("archive_endless_leaderboard()", sql)

    def test_derived_allowlist_and_runtime_guards_unchanged(self):
        a, b = ast.parse(self.original), ast.parse(self.patched)
        def without_signatures(tree):
            tree = copy.deepcopy(tree)
            tree.body = [n for n in tree.body if not (isinstance(n, ast.Assign)
                and isinstance(n.targets[0], ast.Name) and n.targets[0].id == "RPC_SIGNATURES")]
            return ast.dump(tree, include_attributes=False)
        self.assertEqual(without_signatures(a), without_signatures(b))
        self.assertIn("ALLOWED_FUNCTIONS = tuple(_signature(name, parameters) for name, parameters in RPC_SIGNATURES.items())", self.patched)

    def test_unreviewed_source_or_modified_patch_is_rejected(self):
        variants = [self.original + "\n", self.original.replace('RUNTIME_ROLE = "goufayu_app"', 'RUNTIME_ROLE = "owner"'),
                    self.patched.replace('("p_public_account_id", "text", "nullable_error")', '("p_public_account_id", "text", "hash")'),
                    self.patched + ADDITION, self.original.replace("\n", "\r\n")]
        for text in variants:
            with self.subTest(digest=hashlib.sha256(text.encode()).hexdigest()):
                with self.assertRaises(ValueError):
                    patch_postgres(text)

    def test_input_type_and_partial_marker_are_rejected(self):
        for value in (None, b"source", 1, {}, self.original + "# SURVIVAL_ENDLESS_LEADERBOARD_RPC_V1"):
            with self.assertRaises(ValueError):
                patch_postgres(value)


if __name__ == "__main__":
    unittest.main(verbosity=2)
