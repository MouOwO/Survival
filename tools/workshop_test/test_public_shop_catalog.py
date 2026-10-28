"""Public shop projection contracts against the actual formal CSV compilers."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "public_shop_catalog", ROOT / "tools/workshop_test/build_public_shop_catalog.py")
SHOP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SHOP)


class PublicShopCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiled = SHOP.build(ROOT)
        reference = {name: (ROOT / "data/csv" / name).read_text(encoding="utf-8-sig")
                     for name in cls.compiled["reference_hashes"]}
        cls.commerce = SHOP.compile_commerce(
            cls.compiled["commerce_tables"], reference,
            cls.compiled["tables"]["payment_categories"])
        cls.data = SHOP.project(cls.compiled["catalog"], cls.commerce,
                                cls.compiled["catalog_hash"])

    def test_complete_enabled_formal_offers_remain_distinct(self):
        expected = {}
        for channel, rows in (("cash", self.compiled["catalog"]["products"]),
                              ("wallet", self.commerce["products"])):
            for product in rows:
                if product["enabled"] is True:
                    expected[channel + ":" + product["sku"]] = (channel, product)
        actual = {offer["offer_id"]: offer for offer in self.data["products"]}
        self.assertEqual(len(actual), 175)
        self.assertEqual(set(actual), set(expected))
        self.assertEqual(sum(p["currency"] == "CNY" for p in actual.values()), 49)
        shared = set(p["sku"] for p in self.compiled["catalog"]["products"] if p["enabled"]) & set(
            p["sku"] for p in self.commerce["products"] if p["enabled"])
        self.assertTrue(shared, "real catalog must exercise dual-channel SKUs")
        for identity, (channel, product) in expected.items():
            with self.subTest(offer=identity):
                offer = actual[identity]
                self.assertEqual(offer["currency"], "CNY" if channel == "cash" else product["currency"])
                self.assertEqual(offer["price"], product["amount"] if channel == "cash" else product["price"])
                self.assertEqual(offer["reward_lines"], product["grants"]["lines"])
                self.assertEqual(offer["purchase_limit"], product["purchase_limit"])
                self.assertEqual(offer["required_vip_level"], product["grants"].get("required_vip_level", 0))
                self.assertNotIn("grants", offer)
                self.assertNotIn("effects", offer)
                self.assertNotIn("balance", offer)
                self.assertNotIn("ownership_id", offer)
        for sku in shared:
            self.assertIn("cash:" + sku, actual)
            self.assertIn("wallet:" + sku, actual)

    def test_known_cash_price_units_and_three_wallet_units(self):
        offers = {p["offer_id"]: p for p in self.data["products"]}
        for sku, fen in (("archive_pass_monthly", 5800),
                         ("special_lottery_ticket_single", 600), ("lottery_ticket_single", 300), ("u_coin_recharge", 100)):
            self.assertEqual(offers["cash:" + sku]["price"], fen)
            self.assertEqual(offers["cash:" + sku]["currency"], "CNY")
        payment = copy.deepcopy(self.compiled["catalog"])
        commerce = copy.deepcopy(self.commerce)
        commerce["products"] = [copy.deepcopy(next(p for p in commerce["products"] if p["enabled"]))]
        for currency in ("u_coin", "shop_points", "shop_gold"):
            commerce["products"][0].update(currency=currency, price=123)
            projected = SHOP.project(payment, commerce, self.compiled["catalog_hash"])
            wallet = next(p for p in projected["products"] if p["offer_id"].startswith("wallet:"))
            self.assertEqual((wallet["currency"], wallet["price"]), (currency, 123))

    def test_vip_eligibility_is_from_grants_without_account_claim(self):
        actual = {p["offer_id"]: p for p in self.data["products"]}
        vip = [(channel + ":" + p["sku"], p["grants"]["required_vip_level"])
               for channel, rows in (("cash", self.compiled["catalog"]["products"]),
                                     ("wallet", self.commerce["products"]))
               for p in rows if p["enabled"] and p["grants"].get("required_vip_level")]
        self.assertTrue(vip)
        self.assertEqual(max(level for _, level in vip), 10)
        for identity, level in vip:
            self.assertEqual(actual[identity]["required_vip_level"], level)
            self.assertNotIn("eligible", actual[identity])
            self.assertNotIn("owned", actual[identity])

    def test_disabled_offers_never_escape_and_rewards_are_copied(self):
        payment = copy.deepcopy(self.compiled["catalog"])
        commerce = copy.deepcopy(self.commerce)
        sample = next(p for p in payment["products"] if p["enabled"])
        sample["enabled"] = False
        projected = SHOP.project(payment, commerce, self.compiled["catalog_hash"])
        self.assertNotIn("cash:" + sample["sku"], {p["offer_id"] for p in projected["products"]})
        offer = next(p for p in projected["products"] if p["offer_id"].startswith("cash:"))
        original = next(p for p in payment["products"] if p["sku"] == offer["sku"])
        snapshot = copy.deepcopy(original["grants"]["lines"])
        offer["reward_lines"][0]["label"] = "display mutation"
        self.assertEqual(original["grants"]["lines"], snapshot)

    def test_bad_prices_unknown_currency_and_duplicate_id_fail_closed(self):
        for bad in (0, -1, True, 1.5, "100"):
            payment = copy.deepcopy(self.compiled["catalog"])
            next(p for p in payment["products"] if p["enabled"])["amount"] = bad
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, "public_shop_price_invalid"):
                SHOP.project(payment, self.commerce, self.compiled["catalog_hash"])
        commerce = copy.deepcopy(self.commerce)
        next(p for p in commerce["products"] if p["enabled"])["currency"] = "USD"
        with self.assertRaisesRegex(ValueError, "public_shop_currency_invalid"):
            SHOP.project(self.compiled["catalog"], commerce, self.compiled["catalog_hash"])
        payment = copy.deepcopy(self.compiled["catalog"])
        payment["products"].append(copy.deepcopy(next(p for p in payment["products"] if p["enabled"])))
        with self.assertRaisesRegex(ValueError, "public_shop_duplicate_offer"):
            SHOP.project(payment, self.commerce, self.compiled["catalog_hash"])

    def test_hashes_bind_display_snapshot_and_it_cannot_enable_checkout(self):
        data = copy.deepcopy(self.data)
        identity = data.pop("catalog_sha256")
        self.assertEqual(identity, hashlib.sha256(SHOP.canonical(data)).hexdigest())
        self.assertEqual(data["payment_catalog_sha256"], self.compiled["catalog_hash"])
        self.assertEqual(data["commerce_catalog_sha256"], hashlib.sha256(SHOP.canonical(self.commerce)).hexdigest())
        self.assertIs(data["checkout_enabled"], False)
        self.assertEqual(data["availability"], "preview_only")
        self.assertEqual(SHOP.catalog(), self.data)

    def test_javascript_data_cannot_terminate_script_or_change_values(self):
        hostile = {"title": '</script><script>window.injected=1</script>&\u2028\u2029',
                   "reward": '<img src=x onerror="window.injected=1">', "quote": '"\\\n'}
        for target, prefix in (("browser", "window.SurvivalPublicShop = "),
                               ("panorama", "GameUI.CustomUIConfig().SurvivalArcadeShopCatalog = ")):
            raw = SHOP.javascript(hostile, target).decode("utf-8")
            assignment = raw.split("\r\n")[1]
            self.assertTrue(assignment.startswith(prefix))
            self.assertFalse(any(character in assignment for character in ("<", ">", "&", "\u2028", "\u2029")))
            self.assertEqual(json.loads(assignment[len(prefix):-1]), hostile)

    def test_static_release_manifest_and_existing_output_protection(self):
        output_root = ROOT / "output/payment_shop_20261026"
        output_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="catalog_test_", dir=output_root) as temporary:
            destination = Path(temporary) / "new_release"
            command = [sys.executable, "-B", "-X", "utf8", str(ROOT / "tools/workshop_test/build_public_shop_catalog.py"),
                       "--web-output", str(destination)]
            built = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", check=True)
            summary = json.loads(built.stdout)
            self.assertEqual((summary["offers"], summary["cash_offers"]), (175, 49))
            manifest = json.loads((destination / "manifest.json").read_text(encoding="utf-8"))
            self.assertIs(manifest["checkout_enabled"], False)
            self.assertEqual(set(manifest["files"]), {"index.html", "shop.css", "shop.js", "catalog.js", "catalog.json"})
            before = {file.name: file.read_bytes() for file in destination.iterdir()}
            for name, digest in manifest["files"].items():
                self.assertEqual(hashlib.sha256(before[name]).hexdigest(), digest)
            repeated = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
            self.assertNotEqual(repeated.returncode, 0)
            self.assertIn("new_web_output_required", repeated.stderr)
            self.assertEqual({file.name: file.read_bytes() for file in destination.iterdir()}, before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
