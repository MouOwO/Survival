"""Immutable-source catalogue and identity tests; no engine/SDK/HTTP/player IO."""
from pathlib import Path
import copy
import json
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest import mock

import build_ui_static_catalog as m

GAME = "0056e2bf88106a2045b0575011196d15b7ee2383"
CONTENT = "cb2fa4eaa13f34ce2e566b61fef0e21926bff7c7"
LUA = shutil.which("lua5.1") or shutil.which("lua") or "C:/Program Files/lua/bin/lua5.1.exe"


class ReviewedInputFixture(m.GitSource):
    """Explicit test data injection, never exposed by the generation CLI."""
    input_origin = "UNIT_TEST_ONLY_REVIEWED_INPUT_FIXTURE"
    def __init__(self, paths):
        super().__init__(m.ROOT, GAME)
        self.fixture = {path:(m.ROOT/path).read_bytes().replace(b"\r\n",b"\n") for path in paths}
    def read(self, relative):
        if relative in self.fixture:
            self.cache[relative] = self.fixture[relative]
            return self.cache[relative]
        return super().read(relative)


class StaticCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from extract_grid_static_atlas_20261103 import PUBLIC_SOURCES
        cls.reference = m.GitSource(m.ROOT, GAME)
        cls.source = ReviewedInputFixture((*PUBLIC_SOURCES,"scripts/vscripts/ui/selected_stats_schema.lua",
                                          "data/ui/grid_static_atlas_candidate_20261103.json",
                                          "data/ui/lottery_catalog.json",
                                          "scripts/vscripts/config/generated/archive_http_bundle.lua",
                                          "scripts/vscripts/config/generated/lottery_catalog_manifest.lua"))
        cls.operator = ReviewedInputFixture(("tools/selected_stats_static_seed.lua","tools/production_ui_static_seed.lua",
                                             "tools/public_beta_ui_static_seed.lua",
                                             "tools/extract_grid_static_atlas_20261103.py"))
        cls.outputs, cls.registry = m.build(cls.source, CONTENT, LUA, operator=cls.operator, atlas_reference=cls.reference)
        cls.records, cls.auxiliary = m.make_catalog(cls.source, LUA, cls.operator, cls.reference)
        cls.by_key = {row["key"]: row for row in cls.registry["records"]}

    def test_real_three_domains_and_public_configuration_coverage(self):
        self.assertEqual(len(self.registry["records"]), 7935)
        manifest = json.loads(self.outputs[m.MANIFEST_PATH])
        self.assertEqual(manifest["domain_counts"], {"archive": 1146, "daily": 75, "lottery": 83, "hud": 1, "wire": 9,
                                                   "grid": 4390, "selected": 2183, "production":44, "vip":1,
                                                   "payment":1, "public_beta":2})
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
        rebuilt, registry = m.build(self.source, CONTENT, LUA, self.registry, self.operator, self.reference)
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
        self.assertEqual(updated["records"][-1]["id"], len(self.registry["records"]) + 1)
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
        self.assertEqual(len(updated["fields"]), 188)
        self.assertEqual(updated["generation"], 2)

    def test_grid_static_profiles_maps_and_capacity_have_no_invented_terrain(self):
        grid = self.auxiliary["grid"]
        self.assertEqual(len(grid["profiles"]), 11)
        self.assertEqual(max(row["grid_footprint_x"] * row["grid_footprint_y"] for row in grid["profiles"]), 16)
        self.assertEqual(set(grid["maps"]), {"default", "template_map", "survival_c6"})
        self.assertEqual(grid["maps"]["template_map"]["build_ground_height"], 384)
        self.assertNotIn("build_ground_height", grid["maps"]["default"])
        self.assertTrue(grid["terrain_atlas_local"])
        self.assertNotIn("terrain", grid)
        self.assertEqual(len(grid["atlases"]), 1)
        self.assertTrue(grid["atlases"][0]["binding_matches_source"] or grid["atlases"][0]["runtime_source_compatible"])
        self.assertFalse(grid["atlases"][0]["authority"])
        self.assertTrue(grid["atlases"][0]["requires_current_live_scan"])
        self.assertEqual(grid["atlases"][0]["source_identical_events"], 2)
        self.assertEqual(grid["atlases"][0]["word_count"], 576)
        self.assertEqual(grid["errors"][:2], ["", "grid_validation_failed"])
        self.assertIn("move_ability_cooldown", grid["errors"])
        for key in ("grid:cell:16", "grid:area:word:256", "grid:static:word:4096"):
            self.assertIn(key, self.by_key)
        self.assertNotIn("grid:cell:17", self.by_key)
        self.assertNotIn("grid:static:word:4097", self.by_key)

    def test_stale_map_candidate_is_only_unknown_cache_never_authority(self):
        original = self.source
        class ChangedMap:
            revision = original.revision
            def git(self, *args): return original.git(*args)
            def read(self, path): return original.read(path)
            def map_sha256(self, path): return "0" * 64
        grid = m.grid_projection_seed(ChangedMap(), LUA, self.reference, self.operator)
        self.assertFalse(grid["terrain_atlas_local"])
        self.assertFalse(grid["atlases"][0]["binding_matches_source"])
        self.assertFalse(grid["atlases"][0]["authority"])
        self.assertTrue(grid["atlases"][0]["requires_current_live_scan"])

    def test_only_exact_budget_expression_can_receive_source_compatibility(self):
        path = "scripts/vscripts/systems/grid_placement_system.lua"
        before = b"before count>=8 and clock()-started>=number(payload.time_budget,0.002) after"
        original = {path: before, "config": b"same"}
        current = {path: before.replace(b"count>=8", b"count>=1"), "config": b"same"}
        self.assertTrue(m.grid_budget_only_compatible(original, current))
        self.assertFalse(m.grid_budget_only_compatible(original, original))
        self.assertFalse(m.grid_budget_only_compatible(original, dict(current, config=b"changed")))
        self.assertFalse(m.grid_budget_only_compatible(original, {path: current[path] + b"new predicate", "config": b"same"}))

    def test_missing_immutable_schema_or_seed_never_reads_workspace_fallback(self):
        class MissingRuntime:
            revision=GAME
            def read(self,path):
                raise ValueError("immutable_runtime_missing:"+path)
        class MissingOperator:
            revision=GAME
            def read(self,path):
                raise ValueError("immutable_operator_missing:"+path)
        with self.assertRaisesRegex(ValueError,"immutable_runtime_missing"):
            m.selected_projection_seed(MissingRuntime(),LUA,self.operator)
        with self.assertRaisesRegex(ValueError,"immutable_operator_missing"):
            m.selected_projection_seed(self.source,LUA,MissingOperator())

    def test_committed_registry_history_requires_every_exact_node(self):
        registry=json.loads((m.ROOT/m.REGISTRY_PATH).read_bytes())
        nodes={p.name:p.read_bytes() for p in (m.ROOT/'data/ui/registry_history').glob('*.json')}
        class History:
            def read(self,path):return nodes[Path(path).name]
        history=m.registry_history_git(registry,History())
        self.assertEqual(len(history),registry['generation'])
        own=m.digest(m.canonical(registry))+'.json'
        nodes[own]=m.canonical(dict(registry,generation=999))
        with self.assertRaisesRegex(ValueError,'committed_registry_history_node_changed'):
            m.registry_history_git(registry,History())

    def test_cli_requires_operator_and_reference_before_any_git_source(self):
        with mock.patch('sys.argv',['build_ui_static_catalog.py','--source-revision',GAME,'--content-source-revision',CONTENT]), mock.patch.object(m,'GitSource') as source, mock.patch('sys.stderr'):
            with self.assertRaises(SystemExit) as caught:m.main()
            self.assertEqual(caught.exception.code,2);source.assert_not_called()

    def test_published_registry_prefix_and_grid_error_codes_cannot_be_recycled(self):
        path = m.ROOT / "data/ui/registry_history/49d5933002dd7280fdc35b75893f9d6e5dfd7e8bbb16ef07737e5c94f8134538.json"
        previous = json.loads(path.read_bytes())
        updated = m.update_registry(self.records, previous, {"grid_errors": self.auxiliary["grid"]["errors"]})
        self.assertEqual(updated["records"][:len(previous["records"])], previous["records"])
        self.assertEqual(updated["fields"][:127], previous["fields"])
        self.assertEqual(updated["parent_sha256"], m.digest(m.canonical(previous)))
        self.assertTrue(all(row["id"] > 1314 for row in updated["records"][1314:]))
        errors = updated["public_enums"]["grid_errors"]
        appended = m.update_registry(self.records, updated, {"grid_errors": errors + ["new_error_only_at_end"]})
        m.validate_registry(appended, updated)
        broken = copy.deepcopy(appended)
        broken["public_enums"]["grid_errors"][2:4] = list(reversed(broken["public_enums"]["grid_errors"][2:4]))
        with self.assertRaisesRegex(ValueError, "historical_public_enum_meaning_changed"):
            m.validate_registry(broken, updated)

    def test_selected_exact_text_dictionary_is_bound_and_lookup_keys_are_valid(self):
        selected = self.auxiliary["selected"]
        self.assertEqual(len(selected["numeric_paths"]), 126)
        self.assertEqual(len(selected["text_paths"]), 27)
        for text, key in selected["text_by_value"].items():
            self.assertEqual(key, "selected:text:" + m.digest(text.encode("utf8")))
            self.assertEqual(self.records[key]["definition"]["value"], text)
        self.assertIn("tools/selected_stats_static_seed.lua", selected["generator_inputs"])
        by_name = {row["name"]: row for row in self.registry["fields"]}
        self.assertEqual(by_name["grid_action"]["id"], 128)
        self.assertEqual(by_name["selected_value_hi"]["id"], 159)
        self.assertEqual(by_name["grid_map"]["id"], 161)
        self.assertEqual(by_name["selected_value_hi"]["unit"], "ieee754_binary64_high32")
        self.assertTrue(all(row["default"] is None for row in self.registry["fields"][127:]))

    def test_production_actual_static_corpus_reserved_targets_and_unknowns(self):
        production = self.auxiliary["production"]
        self.assertEqual(len(production["training"]), 8)
        self.assertEqual(len(production["research"]), 19)
        self.assertEqual(sum(len(row["levels"]) - 1 for row in production["research"]), 420)
        self.assertEqual(production["queue_capacity"], 7)
        self.assertEqual(production["cost_timing_text"], "开始训练时扣费，排队未扣费")
        for row in production["training"]:
            self.assertNotIn("count", row)
            self.assertNotIn("completed", row)
            self.assertNotIn("max_count", row)
            self.assertEqual(row["cost_wood"], row["wood_cost"])
        for row in production["research"]:
            self.assertEqual(row["group"], row["mapping"]["technology_group"])
            self.assertEqual(row["group"], row["definition"]["legacy_group"])
            for level, display in enumerate(row["levels"]):
                self.assertEqual(display["level"], level)
                self.assertEqual(display["fields"], [{"label":"当前累计", "value":display["effect_summary"]}])
                if level:
                    self.assertEqual(display["upgrade_effect_text"],
                                     "升级后Lv." + str(level) + "：" + display["effect_summary"] + "。")
            self.assertEqual(row["levels"][-1]["next_effect_text"], "")
        self.assertNotIn("production:receipt", self.by_key)
        for index in range(1, 9): self.assertIn("production:receipt:" + str(index), self.by_key)
        field_by_name = {row["name"]:row for row in self.registry["fields"]}
        self.assertEqual(field_by_name["production_entity"]["id"], 164)
        self.assertEqual(field_by_name["production_status"]["id"], 186)
        self.assertEqual(field_by_name["production_max_count"]["min"], -2147483647)
        self.assertEqual(field_by_name["production_started_hi"]["unit"], "ieee754_binary64_high32")
        self.assertTrue(all(row["default"] is None for row in self.registry["fields"][163:]))
        self.assertIn("tools/production_ui_static_seed.lua", production["generator_inputs"])

    def test_production_binary64_precision_and_append_only_status_dictionary(self):
        production = self.auxiliary["production"]
        speed = next(row for row in production["research"] if row["group"] == "advanced_lumberjack_speed")
        value = speed["levels"][6]["research_effect_value"]
        self.assertEqual(struct.pack(">d", value).hex(), "3faeb851eb851eb9")
        self.assertNotEqual(value, float(format(value, ".14g")))
        self.assertEqual(production["status_labels"]["queued_max_level"], "已排队至最高等级")
        self.assertEqual(production["errors"][:2], ["", "production_failed"])
        for name in ("production_errors", "production_status_codes"):
            candidate = copy.deepcopy(self.registry)
            candidate["public_enums"][name][2:4] = reversed(candidate["public_enums"][name][2:4])
            with self.assertRaisesRegex(ValueError, "historical_public_enum_meaning_changed"):
                m.validate_registry(candidate, self.registry)
        class MissingOperator:
            revision=GAME
            def read(self,path):raise ValueError("immutable_operator_missing:"+path)
        with self.assertRaisesRegex(ValueError, "immutable_operator_missing:tools/production_ui_static_seed.lua"):
            m.production_projection_seed(self.source, LUA, MissingOperator())

    def test_vip_state_has_no_reward_rule_or_private_static_metadata(self):
        row=self.records["vip:state"]
        self.assertEqual((row["domain"],row["kind"],row["business_id"]),("vip","state","state"))
        self.assertEqual(row["definition"],{})
        self.assertEqual(len(self.registry["fields"]),188)

    def test_payment_and_beta_records_keep_actual_display_metadata_only(self):
        row=self.records["payment:capability"]
        self.assertEqual((row["domain"],row["kind"],row["business_id"]),("payment","capability","capability"))
        self.assertEqual(row["definition"],{})
        beta=self.auxiliary["public_beta"]
        self.assertEqual(beta["ticket_id"],"special_lottery_ticket")
        self.assertEqual(beta["ticket_count"],int(beta["config"]["base_counts"][0]))
        self.assertEqual(beta["config"]["base_item_ids"],[beta["ticket_id"]])
        self.assertEqual(beta["config"]["reward_id"],beta["tier_id"])
        self.assertEqual(beta["errors"],["","claim_failed"])
        self.assertEqual(beta["failure_notice"],"领取未完成，请重试")
        self.assertFalse({"active","eligible","claimed","revision","day_key","account_id","session_id"}.intersection(beta))
        for kind in ("state","receipt"):
            row=self.records["public_beta:"+kind]
            self.assertEqual((row["domain"],row["kind"],row["business_id"]),("public_beta",kind,kind))

    def test_public_beta_real_config_drift_rejects_fixed_old_dto(self):
        original=self.source
        class ChangedReward:
            def read(self,path):
                raw=original.read(path)
                if path=="scripts/vscripts/config/generated/archive_benefit_rewards.lua":
                    assert raw.count(b"return M")==1
                    return raw.replace(b"return M",b"M.by_id.public_beta_login.base_counts={'3'}\nreturn M")
                return raw
        with self.assertRaises(subprocess.CalledProcessError)as caught:
            m.public_beta_projection_seed(ChangedReward(),LUA,self.operator)
        self.assertIn(b"beta_reward_count_changed",caught.exception.stderr)

    def test_public_beta_revision_hi_and_error_codes_append_without_reusing_ids(self):
        field=self.registry["fields"][-2]
        self.assertEqual((field["id"],field["name"],field["max"],field["default"]),
                         (187,"source_revision_hi",2097151,None))
        flags=self.registry["fields"][-1]
        self.assertEqual((flags["id"],flags["name"],flags["max"],flags["default"]),(188,"public_beta_flags",31,None))
        candidate=copy.deepcopy(self.registry)
        candidate["public_enums"]["public_beta_errors"][1]="changed_meaning"
        with self.assertRaises(ValueError):m.validate_registry(candidate,self.registry)

    def test_public_csv_and_generated_runtime_drift_is_a_hard_failure(self):
        class ChangedSource:
            def __init__(self, original): self.original = original
            def read(self, relative):
                raw = self.original.read(relative)
                return raw.replace("成长宝石".encode(), "错误名称".encode()) if relative.endswith("archive_daily_items.csv") else raw
        with self.assertRaisesRegex(ValueError, "csv_runtime_generated_config_drift:archive_daily_items"):
            m.make_catalog(ChangedSource(self.source), LUA, self.operator, self.reference)

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

    def test_two_xml_roots_reuse_catalog_before_literal_and_new_schema_replaces(self):
        node = shutil.which("node")
        if not node: self.skipTest("node unavailable")
        script = self.outputs[m.CATALOG_PATH].decode()
        self.assertLess(script.index(")return;"), script.index("var data="))
        probe = ("const vm=require('node:vm'),assert=require('node:assert/strict');const cfg={};let native=0;"
                 "const env=vm.createContext({GameUI:{CustomUIConfig:()=>cfg},GameEvents:{SendCustomGameEventToServer(){native++;throw Error('unexpected send');}}});"
                 "vm.runInContext('var work={keys:0,freeze:0,create:0};var k=Object.keys,f=Object.freeze,c=Object.create;Object.keys=function(v){work.keys++;return k(v);};Object.freeze=function(v){work.freeze++;return f(v);};Object.create=function(v){work.create++;return c(v);};',env);"
                 "const code=new vm.Script(" + json.dumps(script) + ");code.runInContext(env);const first=cfg.SurvivalUICatalog,counts={...env.work};"
                 "assert(first.FieldIds.grid_map===161);assert(Object.isFrozen(first.FieldIds));"
                 "code.runInContext(env);assert.equal(cfg.SurvivalUICatalog,first);assert.deepEqual({...env.work},counts);assert.equal(native,0);"
                 "cfg.SurvivalUICatalog={Data:{sha256:'other-schema'}};code.runInContext(env);assert.notEqual(cfg.SurvivalUICatalog,first);assert.equal(cfg.SurvivalUICatalog.Data.sha256,first.Data.sha256);"
                 "assert.equal(env.work.freeze,counts.freeze*2);assert.equal(env.work.keys,counts.keys*2);assert.equal(env.work.create,counts.create*2);"
                 "console.log(JSON.stringify({status:'STATIC_CATALOG_TWO_ROOTS_PASS',records:first.Data.records.length,fields:first.Data.fields.length,initial:counts,same_schema_extra:{keys:0,freeze:0,create:0},native}));")
        run = subprocess.run([node, "-"], input=probe.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        self.assertIn(b"STATIC_CATALOG_TWO_ROOTS_PASS", run.stdout)
        print(run.stdout.decode().strip())


if __name__ == "__main__":
    unittest.main()
