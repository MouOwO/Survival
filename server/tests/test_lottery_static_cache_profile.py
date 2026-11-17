"""Negative binding checks for the isolated immutable-static-cache experiment."""
from copy import deepcopy
import unittest
from tools.loadtest_lab import lottery_cache_experiments as cache
from tools.loadtest_lab.guard import validate_settlement_cache,SETTLEMENT_RUNNER_SHA256

class StaticCacheProfile(unittest.TestCase):
    def cfg(self):
        revision="a"*40
        return {"schema":1,"kind":"SURVIVAL_ISOLATED_LOADTEST","purpose":"capacity","backend_db_pool":"bounded-v2",
            "csv_source_revision":revision,"sources":{cache.OPERATOR:cache.RECIPE_SHA,**cache.OUTPUTS},
            cache.KEY:{"id":"pool-revisions-v1","source_revision":revision,"recipe_sha256":cache.RECIPE_SHA,
                "parent_sources":dict(cache.PARENTS),"output_sources":dict(cache.OUTPUTS)}}
    def test_baseline_has_no_cache_or_source_reader_work(self):
        self.assertEqual(cache.validate({"sources":{}},lambda _:self.fail("baseline read")),{})
        self.assertEqual(cache.metadata({"sources":{}}),{})
    def test_all_exact_current_child_digests_required(self):
        cfg=self.cfg();self.assertEqual(cache.metadata(cfg),cache.PARENTS)
        for target in cache.OUTPUTS:
            bad=deepcopy(cfg);bad["sources"][target]="0"*64
            with self.assertRaises(ValueError):cache.metadata(bad)
    def test_wrong_revision_operator_or_parent_cannot_restore_archetype(self):
        cfg=self.cfg()
        for key,value in [("source_revision","b"*40),("recipe_sha256","0"*64),("parent_sources",{}),("output_sources",{})]:
            bad=deepcopy(cfg);bad[cache.KEY][key]=value
            with self.assertRaises(ValueError):cache.metadata(bad)
    def test_present_recipe_requires_explicit_profile(self):
        with self.assertRaises(ValueError):cache.metadata({"sources":{cache.OPERATOR:cache.RECIPE_SHA}})
    def test_optional_profile_requires_warmup(self):
        with self.assertRaisesRegex(ValueError,"explicit_warmup"):validate_settlement_cache(self.cfg())
    def test_recipe_bytes_rejected_before_execution(self):
        with self.assertRaisesRegex(ValueError,"recipe_changed"):cache.validate(self.cfg(),lambda _:b"raise AssertionError('must not execute')")
    def test_original_runner_pin_is_unchanged(self):
        self.assertEqual(SETTLEMENT_RUNNER_SHA256,cache.PARENTS["runtime/archive_backend/settlement_runner.py"])
        self.assertNotEqual(SETTLEMENT_RUNNER_SHA256,cache.OUTPUTS["runtime/archive_backend/settlement_runner.py"])
if __name__=="__main__":unittest.main()
