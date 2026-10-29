"""Real installed Lua grant rules, receipt recovery and public request boundaries."""
import copy
import hashlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import unittest

from tests import test_archive_backend as archive_tests
from tests.test_archive_backend import Database, App, ROOT
from archive_backend.service import ArchiveService, ArchiveError
from archive_backend.redemption_catalog import offers, reward_spec, vip_related
from archive_backend.redemption_codes import normalize


class RedeemDatabase(Database):
    def __init__(self, bundle, codes):
        super().__init__(bundle)
        self.codes, self.claims = codes, {}

    def rpc(self, name, p):
        with self.lock:
            if name == "redemption_prepare":
                if p["p_session"] != "redemption_test_session":
                    return {"ok": False, "terminal": True, "error": "match_session_missing"}
                code = self.codes.get(p["p_code_hash"])
                if not code:
                    return {"ok": False, "terminal": True, "error": "redeem_code_invalid"}
                key = p["p_account"], code["code_id"]
                old = self.claims.get(key)
                if old:
                    response = self.resume(key[0], old["id"])
                    if old["request_id"] != p["p_request"] and response["done"]:
                        return {"ok": False, "terminal": True, "error": "redeem_already_used"}
                    return response
                item = {"id": "redeem:" + code["code_id"], "kind": "redemption_redeem",
                        "code_id": code["code_id"], "label": code["label"],
                        "request_id": p["p_request"], "rewards": code["rewards"]}
                self.claims[key] = item
                return super().rpc("archive_prepare", {"p_account": p["p_account"], "p_id": item["id"],
                    "p_hash": p["p_hash"], "p_command": item, "p_fingerprint": "test_frozen_rewards"})
            if name == "redemption_commit":
                return super().rpc("archive_commit_lottery", {**p, "p_error": None})
            return super().rpc(name, p)


class RedemptionTests(unittest.TestCase):
    setUpClass = classmethod(archive_tests.ArchiveTests.setUpClass.__func__)

    def setUp(self):
        self.catalog, self.excluded = offers(ROOT)
        self.codes = {}
        self.db = RedeemDatabase(self.bundle, self.codes)
        self.app = App(self.db)
        self.service = ArchiveService(self.app, self.bundle, self.lua)
        self.account = self.app._database_account_id("100")
        self.profile = self.db.profile(self.account)

    def define(self, code, skus):
        self.codes[hashlib.sha256(normalize(code).encode()).hexdigest()] = {
            "code_id": normalize(code).lower(), "label": "测试奖励",
            "rewards": reward_spec(self.catalog, skus)}

    def redeem(self, code="TEST-CODE-004", token="test_request_004", **extra):
        return self.service.command({"account_id": "100", "match_session_id": "redemption_test_session",
            "config_hash": self.bundle.hash, "command": {"id": "redeem:" + token,
                "kind": "redemption_redeem", "request_id": token, "code": code, **extra}})

    def test_catalog_has_all_implemented_nonvip_shop_products(self):
        self.assertTrue(all(not vip_related(p) for p in self.catalog.values()))
        self.assertIn("archive_pass_monthly", self.catalog)
        self.assertIn("u_coin_recharge", self.catalog)
        self.assertIn("video_p037", self.catalog)
        self.assertNotIn("starter_bundle_v4", self.catalog)
        spec = reward_spec(self.catalog, list(self.catalog))
        self.assertEqual(spec["entitlements"], {"archive_pass": 30})
        self.assertEqual(spec["wallet"], {"u_coin": 100})
        self.assertTrue(all(p["product_type"] != "bundle" for p in spec["products"]))

    def test_zero_cost_full_reward_and_once_only(self):
        self.define("TEST-CODE-004", ["video_p004"])
        before = copy.deepcopy(self.profile)
        first = self.redeem()
        self.assertTrue(first["ok"], first)
        self.assertNotIn("command", first)
        self.assertEqual(first["profile"]["account_id"], "100")
        self.assertEqual(self.profile["save"]["gameplay_stats"]["initial_wood"],
                         before["save"]["gameplay_stats"]["initial_wood"] + 200)
        self.assertEqual(self.profile["save"]["archive"]["commerce"]["balances"]["u_coin"], 0)
        settled = copy.deepcopy(self.profile)
        self.assertTrue(self.redeem()["ok"])
        self.assertEqual(self.redeem(token="new_request_004")["error"], "redeem_already_used")
        self.assertEqual(self.profile, settled)

    def test_all_rewards_no_vip_progress_and_bundle_duplicates(self):
        self.define("ALL-TEST-PRIZES", list(self.catalog))
        before = copy.deepcopy(self.profile)
        result = self.redeem("ALL-TEST-PRIZES")
        self.assertTrue(result["ok"], result)
        stats = self.profile["save"]["gameplay_stats"]
        for field in stats:
            if "vip" in field:
                self.assertEqual(stats[field], before["save"]["gameplay_stats"][field])
        inventory = self.profile["save"]["content_inventory"]
        self.assertEqual(inventory["commerce_p004"], 1)
        self.assertEqual(inventory["commerce_p025"], 1)
        self.assertEqual(inventory["commerce_video_bundle_b001"], 1)
        self.assertEqual(inventory["special_lottery_ticket"], 1)
        self.assertEqual(self.profile["save"]["archive"]["commerce"]["balances"]["u_coin"], 100)
        self.assertFalse(self.profile["save"]["archive"].get("vip_claimed"))

    def test_already_owned_leaf_does_not_block_remaining_bundle_rewards(self):
        self.define("TEST-CODE-004", ["video_p025"])
        self.assertTrue(self.redeem()["ok"])
        before = self.profile["save"]["gameplay_stats"]["starjoy_points"]
        self.define("BUNDLE-TEST-001", ["video_bundle_b001"])
        result = self.redeem("BUNDLE-TEST-001", "bundle_request_001")
        self.assertTrue(result["ok"])
        self.assertEqual(result["response"]["skipped"], 1)
        self.assertEqual(self.profile["save"]["content_inventory"]["commerce_p025"], 1)
        self.assertEqual(self.profile["save"]["gameplay_stats"]["starjoy_points"], before + 298)

    def test_lost_reply_and_revision_conflict(self):
        self.define("TEST-CODE-004", ["video_p004"])
        before = self.profile["save"]["gameplay_stats"]["initial_wood"]
        self.db.conflict = True
        self.db.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.redeem()
        saved = copy.deepcopy(self.profile)
        self.assertTrue(self.redeem()["ok"])
        self.assertEqual(self.profile, saved)
        self.assertEqual(saved["save"]["gameplay_stats"]["initial_wood"], before + 300)

    def test_concurrent_requests_share_one_grant(self):
        self.define("TEST-CODE-004", ["video_p004"])
        before = self.profile["save"]["gameplay_stats"]["initial_wood"]
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda n: self.redeem(token="concurrent_request_" + str(n)), range(2)))
        self.assertTrue(any(r["ok"] for r in results))
        self.assertEqual(self.profile["save"]["gameplay_stats"]["initial_wood"], before + 200)
        self.assertEqual(len(self.db.ops), 1)

    def test_bad_code_and_reward_tampering_never_grant(self):
        before = copy.deepcopy(self.profile)
        self.assertEqual(self.redeem()["error"], "redeem_code_invalid")
        for fields in ({"rewards": {}}, {"price": 0}, {"sku": "video_p004"}):
            with self.assertRaises(ArchiveError):
                self.redeem(**fields)
        for code in ("", "测试兑换码", "<script>", "A" * 81):
            with self.assertRaises(ArchiveError):
                self.redeem(code)
        self.assertEqual(self.profile, before)


if __name__ == "__main__":
    unittest.main()
