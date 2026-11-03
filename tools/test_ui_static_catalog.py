"""Immutable-source catalogue and identity tests; no engine/SDK/HTTP/player IO."""
from pathlib import Path
import copy
import json
import shutil
import subprocess
import tempfile
import unittest

import build_ui_static_catalog as m

GAME = "0056e2bf88106a2045b0575011196d15b7ee2383"
CONTENT = "cb2fa4eaa13f34ce2e566b61fef0e21926bff7c7"
LUA = shutil.which("lua5.1") or shutil.which("lua") or "C:/Program Files/lua/bin/lua5.1.exe"


class StaticCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = m.GitSource(m.ROOT, GAME)
        cls.outputs, cls.registry = m.build(cls.source, CONTENT, LUA)
        cls.records, cls.auxiliary = m.make_catalog(cls.source, LUA)
        cls.by_key = {row["key"]: row for row in cls.registry["records"]}

    def test_real_three_domains_and_public_configuration_coverage(self):
        self.assertEqual(len(self.registry["records"]), 1314)
        manifest = json.loads(self.outputs[m.MANIFEST_PATH])
        self.assertEqual(manifest["domain_counts"], {"archive": 1146, "daily": 75, "lottery": 83, "hud": 1, "wire": 9})
        self.assertTrue(manifest["csv_runtime_config_rows_equal"])
        self.assertFalse(manifest["runtime_connected"])
        self.assertFalse(manifest["workshop_uploaded"])
        for key in ("archive:pet:cage_01", "daily:state", "daily:cycle:7", "daily:calendar:28", "lottery:pool:summer"):
            if key == "archive:pet:cage_01":
                self.assertEqual(sum(row.get("category") == "pet" and row["kind"] == "row" for row in self.registry["records"]), 81)
            else: self.assertIn(key, self.by_key)
        self.assertEqual(sum(row.get("category") == "shadow" and row["kind"] == "row" for row in self.registry["records"]), 23)
        self.assertEqual(len(self.auxiliary["lottery_public"]["snapshots"]), 4)
        self.assertEqual(sum(len(row["items"]) for row in self.auxiliary["lottery_public"]["snapshots"]), 105)

    def test_display_data_has_no_account_state_or_private_weights(self):
        dynamic = {"count", "owned_count", "unlocked", "completed", "can_claim", "can_upgrade", "claimed", "tickets", "rank"}
        for row in self.records.values():
            self.assertFalse(dynamic.intersection(row["definition"]), row["key"])
            self.assertNotIn("item_weight", row["definition"])
            self.assertNotIn("effect_values", row["definition"])
        for snapshot in self.auxiliary["lottery_public"]["snapshots"]:
            self.assertNotIn("account_id", snapshot)
            self.assertNotIn("quality_weights", snapshot["selected_pool"])

    def test_output_is_deterministic_and_rebuild_does_not_create_new_history(self):
        rebuilt, registry = m.build(self.source, CONTENT, LUA, self.registry)
        self.assertEqual(rebuilt, self.outputs)
        self.assertEqual(registry, self.registry)
        self.assertEqual(m.update_registry(dict(reversed(list(self.records.items()))), self.registry), self.registry)

    def test_record_ids_append_independent_of_sort_order_or_display_name(self):
        changed = copy.deepcopy(self.records)
        first = next(iter(changed))
        changed[first]["definition"]["name"] = "新的展示名称"
        self.assertEqual(m.update_registry(changed, self.registry), self.registry)
        changed["aaa:new"] = {"key": "aaa:new", "domain": "daily", "kind": "item", "business_id": "new", "definition": {}}
        updated = m.update_registry(changed, self.registry)
        self.assertEqual(updated["records"][:-1], self.registry["records"])
        self.assertEqual(updated["records"][-1]["id"], 1315)
        self.assertEqual(updated["records"][-1]["key"], "aaa:new")

    def test_deleted_records_become_permanent_tombstones(self):
        changed = copy.deepcopy(self.records);removed = next(iter(changed));del changed[removed]
        updated = m.update_registry(changed, self.registry)
        row = next(row for row in updated["records"] if row["key"] == removed)
        self.assertEqual(row["id"], self.by_key[removed]["id"])
        self.assertTrue(row["tombstone"])
        self.assertEqual(len(updated["records"]), len(self.registry["records"]))
        with self.assertRaisesRegex(ValueError, "tombstoned_business_key"):
            m.update_registry(self.records, updated)

    def test_reassigned_removed_or_recycled_ids_are_rejected(self):
        for kind in ("reassigned", "removed", "identity", "new_hole"):
            with self.subTest(kind=kind):
                candidate = copy.deepcopy(self.registry)
                if kind == "reassigned": candidate["records"][0]["key"] = "wrong:key"
                elif kind == "removed": candidate["records"].pop(0)
                elif kind == "identity": candidate["records"][0]["domain"] = "lottery"
                else:
                    candidate["records"].append({"id": 1, "key": "wrong:new", "domain": "daily", "kind": "item", "business_id": "new", "tombstone": False})
                with self.assertRaises(ValueError): m.validate_registry(candidate, self.registry)

    def test_history_preserves_parents_and_detects_tampering(self):
        changed = dict(self.records)
        changed.pop(next(iter(changed)))
        second = m.update_registry(changed, self.registry)
        with tempfile.TemporaryDirectory(prefix="static-catalog-history-") as directory:
            parent = Path(directory) / (m.digest(m.canonical(self.registry)) + ".json")
            parent.write_bytes(m.canonical(self.registry))
            m.registry_history(second, directory)
            parent.write_bytes(m.canonical(dict(self.registry, generation=99)))
            with self.assertRaisesRegex(ValueError, "digest_or_generation"):
                m.registry_history(second, directory)
            parent.unlink()
            with self.assertRaisesRegex(ValueError, "parent_missing"):
                m.registry_history(second, directory)

    def test_field_ids_types_units_and_unknown_defaults_are_fixed(self):
        fields = self.registry["fields"]
        self.assertEqual(fields[0], dict(id=1, name="known", kind="bool", min=0, max=1, default=0, unit="flag"))
        self.assertEqual(fields[21]["name"], "expires_at")
        self.assertEqual(fields[21]["unit"], "unix_utc_seconds")
        self.assertEqual(fields[25]["name"], "rank_delta")
        self.assertEqual(fields[25]["min"], -2147483647)
        self.assertTrue(all(row["default"] is None for row in fields[1:]))
        self.assertEqual(fields[8]["enum"], list(range(8)))
        candidate = copy.deepcopy(self.registry);candidate["fields"][1]["name"] = "different_meaning"
        with self.assertRaises(ValueError): m.validate_registry(candidate)

    def test_historical_field_prefix_can_only_be_extended(self):
        old = copy.deepcopy(self.registry);old["fields"] = old["fields"][:22]
        m.validate_registry(old)
        updated = m.update_registry(self.records, old)
        self.assertEqual(updated["fields"][:22], old["fields"])
        self.assertEqual(len(updated["fields"]), 127)
        self.assertEqual(updated["generation"], 2)

    def test_public_csv_and_generated_runtime_drift_is_a_hard_failure(self):
        class ChangedSource:
            def __init__(self, original): self.original = original
            def read(self, relative):
                raw = self.original.read(relative)
                return raw.replace("成长宝石".encode(), "错误名称".encode()) if relative.endswith("archive_daily_items.csv") else raw
        with self.assertRaisesRegex(ValueError, "csv_runtime_generated_config_drift:archive_daily_items"):
            m.make_catalog(ChangedSource(self.source), LUA)

    def test_lua_lookup_uses_the_same_hash_ids_types_and_unknown_holes(self):
        encoder = self.source.read("scripts/vscripts/core/json_encoder.lua").decode("utf8")
        lookup = self.outputs[m.LOOKUP_PATH].decode("utf8")
        script = ("local x=assert(loadstring(" + m.lua_literal(lookup) + "))();local json=assert(loadstring(" + m.lua_literal(encoder) + "))();"
                  "io.write(json.encode({sha256=x.sha256,id=x.by_key['daily:state'],field=x.fields[9],missing=x.records[65535]==nil}))")
        result = subprocess.run([LUA, "-"], input=script.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        value = json.loads(result.stdout)
        self.assertEqual(value["sha256"], json.loads(self.outputs[m.MANIFEST_PATH])["schema_sha256"])
        self.assertEqual(value["id"], self.by_key["daily:state"]["id"])
        self.assertEqual(value["field"]["enum"], list(range(8)))
        self.assertTrue(value["missing"])

    def test_js_unknown_schema_ids_and_repeated_lookup_have_no_native_or_scan_work(self):
        node = shutil.which("node")
        if not node: self.skipTest("node unavailable")
        script = self.outputs[m.CATALOG_PATH].decode()
        probe = ("const vm=require('node:vm'),assert=require('node:assert/strict');const cfg={};let native=0;"
                 "const env={GameUI:{CustomUIConfig:()=>cfg},GameEvents:{SendCustomGameEventToServer(){native++;throw Error('unexpected send');}}};"
                 "vm.runInNewContext(" + json.dumps(script) + ",env);const c=cfg.SurvivalUICatalog;"
                 "const id=c.ByKey['daily:state'];assert(c.Resolve(id,c.Data.sha256));assert.equal(c.Resolve(id,'wrong'),null);"
                 "assert.equal(c.Resolve(65535,c.Data.sha256),null);assert(Object.isFrozen(c.Data));"
                 "vm.runInNewContext('var lookupScans=0;Object.keys=function(){lookupScans++;throw Error(\"lookup scanned data\");};',env);"
                 "for(let i=0;i<1000;i++)assert(c.Definition(id,c.Data.sha256));assert.equal(env.lookupScans,0);assert.equal(native,0);"
                 "console.log('STATIC_CATALOG_JS_PASS');")
        run = subprocess.run([node, "-"], input=probe.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        self.assertIn(b"STATIC_CATALOG_JS_PASS", run.stdout)


if __name__ == "__main__":
    unittest.main()
