"""Hash-only planning plus actual Lua redemption and lottery projection.

All codes/accounts here are fixed synthetic fixtures, never registered. Database
claim/locking is the existing in-memory test double, not a real PostgreSQL test.
"""
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stdout
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "server"))
spec = importlib.util.spec_from_file_location("ticket_code_definitions", HERE / "definitions.py")
definitions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(definitions)
from archive_backend.redemption_codes import normalize
from archive_backend.service import ArchiveService, ArchiveError
from tests import test_archive_backend as archive_tests
from tests.test_redemption_codes import RedeemDatabase


def synthetic_codes():
    return {str(n): f"TEST-TICKET-{n:03d}" for n in definitions.QUANTITIES}


def synthetic_hashes():
    return {key: hashlib.sha256(normalize(code).encode("ascii")).hexdigest()
            for key, code in synthetic_codes().items()}


class DefinitionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog, _ = definitions.offers(ROOT)

    def compile(self, hashes=None):
        return definitions.compile_definitions(synthetic_hashes() if hashes is None else hashes,
                                               catalog=self.catalog)

    def test_exact_four_quantities_and_server_only_zero_cost_rewards(self):
        before = copy.deepcopy(self.catalog)
        result = self.compile()
        self.assertEqual(self.catalog, before)
        self.assertEqual(len(result["codes"]), 4)
        for row, quantity in zip(result["codes"], definitions.QUANTITIES):
            self.assertNotIn("code", row)
            self.assertNotIn("raw_code", row)
            self.assertEqual(row["code_id"], "r_" + row["code_hash"][:32])
            self.assertEqual(row["max_redemptions"], 0)
            reward = row["rewards"]
            self.assertEqual((reward["markers"], reward["wallet"], reward["entitlements"]), ([], {}, {}))
            product, = reward["products"]
            self.assertEqual((product["price"], product["currency"], product["purchase_method"]),
                             (0, "u_coin", "redemption"))
            self.assertEqual(product["grants"]["items"], {"lottery_ticket": quantity})
            self.assertEqual(product["grants"]["lines"][0]["quantity"], quantity)
            self.assertFalse(product["effects"])

    def test_hash_shape_duplicates_and_truncated_id_collision_refused(self):
        cases = [{}, {**synthetic_hashes(), "500": "f" * 64},
                 {**synthetic_hashes(), "10": "TEST-NOT-A-HASH"},
                 {**synthetic_hashes(), "10": None},
                 {str(n): "a" * 64 for n in definitions.QUANTITIES},
                 {str(n): "a" * 32 + str(i) * 32 for i, n in enumerate(definitions.QUANTITIES)}]
        for value in cases:
            with self.subTest(value_type=type(value).__name__), self.assertRaises(ValueError):
                self.compile(value)

    def test_changed_base_reward_or_purchase_limit_refused(self):
        for mutate in (lambda p: p["grants"]["items"].update(special_lottery_ticket=1),
                       lambda p: p.update(purchase_limit=1),
                       lambda p: p["effects"].update(initial_wood=1)):
            catalog = copy.deepcopy(self.catalog)
            mutate(catalog[definitions.BASE_SKU])
            with self.assertRaisesRegex(ValueError, "ticket_code_base_product_changed"):
                definitions.compile_definitions(synthetic_hashes(), catalog=catalog)

    def test_default_cli_is_plan_only_without_codes_or_server_actions(self):
        with redirect_stdout(io.StringIO()) as output:
            self.assertEqual(definitions.main([]), 0)
        result = json.loads(output.getvalue())
        self.assertEqual(result["quantities"], [10, 50, 100, 200])
        self.assertFalse(result["server_modified"])
        self.assertFalse(result["plaintext_codes_generated"])

    def test_local_compile_writes_only_new_hash_registry_in_private_directory(self):
        with tempfile.TemporaryDirectory(prefix="ticket-hash-only-") as directory:
            root = Path(directory)
            private = root / "private"
            input_path = root / "synthetic_hashes.json"
            input_path.write_text(json.dumps(synthetic_hashes()), encoding="utf-8")
            output_path = private / "server_codes.json"
            with patch.object(definitions, "PRIVATE", private), redirect_stdout(io.StringIO()):
                self.assertEqual(definitions.main(["--hashes", str(input_path), "--output", str(output_path)]), 0)
                before = output_path.read_bytes()
                value = json.loads(before)
                self.assertEqual(len(value["codes"]), 4)
                self.assertTrue(all(code.encode("ascii") not in before for code in synthetic_codes().values()))
                with self.assertRaisesRegex(ValueError, "ticket_code_new_output_required"):
                    definitions.main(["--hashes", str(input_path), "--output", str(output_path)])
                self.assertEqual(output_path.read_bytes(), before)

    def test_client_or_public_output_location_is_refused(self):
        with tempfile.TemporaryDirectory(prefix="ticket-hash-only-") as directory:
            root = Path(directory)
            input_path = root / "synthetic_hashes.json"
            input_path.write_text(json.dumps(synthetic_hashes()), encoding="utf-8")
            outside = root / "client/server_codes.json"
            with patch.object(definitions, "PRIVATE", root / "private"):
                with self.assertRaisesRegex(ValueError, "ticket_code_private_output_required"):
                    definitions.main(["--hashes", str(input_path), "--output", str(outside)])
            self.assertFalse(outside.exists())


class ActualLuaTicketTests(unittest.TestCase):
    setUpClass = classmethod(archive_tests.ArchiveTests.setUpClass.__func__)

    def setUp(self):
        rows = definitions.compile_definitions(synthetic_hashes())["codes"]
        self.registry = {row["code_hash"]: row for row in rows}
        self.db = RedeemDatabase(self.bundle, self.registry)
        self.app = archive_tests.App(self.db)
        self.service = ArchiveService(self.app, self.bundle, self.lua)
        self.profile = self.db.profile(self.app._database_account_id("100"))
        self.profile["save"]["content_inventory"] = {
            "lottery_ticket": 7, "special_lottery_ticket": 11,
            "pay_lottery_ticket_single": 3, "material_synthesis_gem": 4}
        self.profile["save"]["archive"] = {"commerce": {"balances": {"u_coin": 88, "shop_points": 99}}}

    def redeem(self, tier, *, token=None, account="100", **extra):
        token = token or f"ticket_fixture_request_{tier}"
        return self.service.command({"account_id": account, "match_session_id": "redemption_test_session",
            "config_hash": self.bundle.hash, "command": {"id": "redeem:" + token,
                "kind": "redemption_redeem", "request_id": token,
                "code": synthetic_codes()[str(tier)], **extra}})

    def test_each_tier_adds_exact_tickets_and_projects_only_to_map_pool(self):
        expected = 7
        before_stats = copy.deepcopy(self.profile["save"]["gameplay_stats"])
        for quantity in definitions.QUANTITIES:
            self.assertTrue(self.redeem(quantity)["ok"])
            expected += quantity
            inventory = self.profile["save"]["content_inventory"]
            self.assertEqual(inventory["lottery_ticket"], expected)
            self.assertEqual(inventory["special_lottery_ticket"], 11)
            self.assertEqual(inventory["material_synthesis_gem"], 4)
            snapshots = self.service.lottery_snapshot({"account_id": "100", "config_hash": self.bundle.hash})
            for row in snapshots["snapshots"]:
                self.assertEqual(row["tickets"], expected if row["selected_pool_id"] == "map" else 11)
            self.assertEqual(self.profile["save"]["gameplay_stats"], before_stats)
            self.assertEqual(self.profile["save"]["archive"]["commerce"]["balances"],
                             {"u_coin": 88, "shop_points": 99})
        self.assertEqual(expected, 367)
        self.assertEqual(self.profile["save"]["content_inventory"]["pay_lottery_ticket_single"], 7)

    def test_same_account_same_code_once_and_another_account_independent(self):
        first = self.redeem(50)
        self.assertTrue(first["ok"])
        settled = copy.deepcopy(self.profile)
        self.assertTrue(self.redeem(50)["ok"])
        self.assertEqual(self.redeem(50, token="different_request_050")["error"], "redeem_already_used")
        self.assertEqual(self.profile, settled)
        self.assertTrue(self.redeem(50, token="other_actor_request_050", account="200")["ok"])
        peer = self.db.profile(self.app._database_account_id("200"))
        self.assertEqual(peer["save"]["content_inventory"]["lottery_ticket"], 50)

    def test_concurrent_same_code_reserves_one_grant(self):
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda n: self.redeem(200, token=f"parallel_ticket_request_{n}"), range(2)))
        self.assertTrue(any(row["ok"] for row in results))
        self.assertEqual(self.profile["save"]["content_inventory"]["lottery_ticket"], 207)
        self.assertEqual(len(self.db.claims), 1)
        self.assertEqual(len(self.db.ops), 1)

    def test_lost_commit_reply_retry_keeps_one_grant(self):
        self.db.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.redeem(100)
        saved = copy.deepcopy(self.profile)
        self.assertTrue(self.redeem(100)["ok"])
        self.assertEqual(self.profile, saved)
        self.assertEqual(saved["save"]["content_inventory"]["lottery_ticket"], 107)

    def test_client_cannot_choose_quantity_or_rewards_and_response_hides_definition(self):
        before = copy.deepcopy(self.profile)
        for extra in ({"quantity": 200}, {"rewards": {}}, {"sku": "lottery_ticket_single"}):
            with self.assertRaises(ArchiveError):
                self.redeem(10, **extra)
        self.assertEqual(self.profile, before)
        result = self.redeem(10)
        self.assertNotIn("command", result)
        self.assertNotIn("rewards", result)

    def test_existing_inventory_cap_skips_without_overflow_or_partial_grant(self):
        # Preserve the installed generic redemption policy: an over-cap product
        # is skipped and that code is consumed. This does not change that rule.
        self.profile["save"]["content_inventory"]["lottery_ticket"] = 2147483647 - 199
        before = copy.deepcopy(self.profile["save"]["content_inventory"])
        result = self.redeem(200)
        self.assertTrue(result["ok"])
        self.assertEqual(result["response"]["skipped"], 1)
        self.assertEqual(result["response"]["granted"], 0)
        self.assertEqual(self.profile["save"]["content_inventory"], before)


if __name__ == "__main__":
    unittest.main()
