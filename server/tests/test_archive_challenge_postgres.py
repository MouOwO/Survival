"""The dedicated receipt RPC adds no inventory or untrusted SQL transport."""
from __future__ import annotations

import ast
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
from fishing_api_overrides.archive_challenge_postgres import ADDITION, patch_postgres, signatures
from fishing_api_overrides.onboarding_postgres import patch_postgres as onboarding


class ChallengePostgresOverlayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "design_refs/endless_leaderboard_20261016/deployment/online_baseline/backend/fishing_api/postgres.py").read_text(encoding="utf-8-sig")

    def test_only_new_signature_and_no_inventory_parameter(self):
        patched = patch_postgres(self.source)
        self.assertEqual(patched.replace(ADDITION, "", 1), self.source)
        tree = signatures(ast.parse(patched))
        spec = eval(compile(ast.Expression(tree), "<constant-rpc-signatures>", "eval"),
                    {"__builtins__": {}, "_params": lambda *values: values})
        self.assertEqual(spec["archive_commit_challenge"], (
            ("p_account", "text", "hash"), ("p_id", "text", "archive_id"),
            ("p_revision", "bigint", "revision"), ("p_archive", "jsonb", "object"),
            ("p_deltas", "jsonb", "object"), ("p_error", "text", "nullable_error"),
            ("p_response", "jsonb", "object")))
        self.assertEqual(spec["archive_commit_challenge"][:-1], spec["archive_commit"])
        self.assertEqual(patch_postgres(patched), patched)

    def test_independent_onboarding_overlay_composes_without_changing_either(self):
        first = patch_postgres(onboarding(self.source))
        second = onboarding(patch_postgres(self.source))
        self.assertEqual(first.replace(ADDITION, "", 1), onboarding(self.source))
        first_tree, second_tree = signatures(ast.parse(first)), signatures(ast.parse(second))
        # Dictionary order does not affect membership or transport behavior.
        self.assertEqual({ast.literal_eval(key): ast.dump(value, include_attributes=False)
                          for key, value in zip(first_tree.keys, first_tree.values)},
                         {ast.literal_eval(key): ast.dump(value, include_attributes=False)
                          for key, value in zip(second_tree.keys, second_tree.values)})

    def test_changed_partial_patch_or_unreviewed_transport_layout_is_rejected(self):
        patched = patch_postgres(self.source)
        for broken in (patched.replace('("p_response", "jsonb", "object")', '("p_response", "jsonb", "array")'),
                       self.source.replace('RUNTIME_ROLE = "goufayu_app"', 'RUNTIME_ROLE = "owner"'),
                       self.source.replace('ALLOWED_FUNCTIONS = tuple(_signature', 'ALLOWED_FUNCTIONS = set(_signature')):
            with self.subTest(source=broken[:20]), self.assertRaises(ValueError):
                patch_postgres(broken)


if __name__ == "__main__":
    unittest.main()
