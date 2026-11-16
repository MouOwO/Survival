import sys
from pathlib import Path
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/"tools"))
from loadtest_lab.guard import resolve_database_pool
from loadtest_lab.experiments import resolve_database_resources, DB8_RESOURCE_PROFILES, DB16_RESOURCE_PROFILES

class DB16ProfileTests(unittest.TestCase):
    def options(self,**changes):
        v=dict(http_concurrency=32,db_concurrency=16,web_concurrency=128,pool_max_waiters=32,pool_wait_seconds=2,admission_mode="bounded-v6");v.update(changes);return v
    def test_explicit16_profile_has_fixed_hard_bounds(self):
        audit,limit=resolve_database_pool("bounded-v2",**self.options())
        self.assertEqual(limit,{"connections":16,"waiting":32,"wait_seconds":2})
        self.assertEqual(audit["effective"]["http_concurrency"],32)
    def test_legacy8_profile_preserved(self):
        _,limit=resolve_database_pool("bounded-v2",**self.options(db_concurrency=8,admission_mode="bounded-v5"))
        self.assertEqual(limit,{"connections":8,"waiting":32,"wait_seconds":2})
    def test_legacy_baseline_defaults_preserved(self):
        audit,limit=resolve_database_pool("baseline")
        self.assertIsNone(limit);self.assertEqual(audit["effective"]["db_concurrency"],4)
    def test_v6_requires_explicit16(self):
        for size in [4,8,15,True]:
            with self.subTest(size=size),self.assertRaises(ValueError):resolve_database_pool("bounded-v2",**self.options(db_concurrency=size))
    def test_v5_cannot_silently_enable16(self):
        with self.assertRaisesRegex(ValueError,"requires_eight"):resolve_database_pool("bounded-v2",**self.options(admission_mode="bounded-v5"))
    def test_only_reviewed_queue_and_http_budgets(self):
        for change in [dict(http_concurrency=31),dict(web_concurrency=127),dict(pool_max_waiters=31),dict(pool_wait_seconds=3)]:
            with self.subTest(change=change),self.assertRaises(ValueError):resolve_database_pool("bounded-v2",**self.options(**change))
    def test_v6_cannot_use_unbounded_or_old_pool(self):
        for mode in ["baseline","bounded-v1"]:
            with self.subTest(mode=mode),self.assertRaises(ValueError):resolve_database_pool(mode,**self.options())
    def test_db16_cpu_memory_are_fixed(self):
        self.assertEqual(resolve_database_resources("capacity",profile="db16-4cpu-4g-v1"),(4096,4))
        self.assertEqual(len(DB8_RESOURCE_PROFILES),3);self.assertEqual(len(DB16_RESOURCE_PROFILES),1)
    def test_db16_rejects_wrong_capacity_or_budget(self):
        for change in [dict(purpose="functional-smoke"),dict(memory=2048),dict(cpu=2),dict(memory=True),dict(cpu=float("nan"))]:
            args=dict(purpose="capacity",profile="db16-4cpu-4g-v1");args.update(change)
            with self.subTest(change=change),self.assertRaises(ValueError):resolve_database_resources(**args)
    def test_legacy8_resource_resolutions_are_identical(self):
        for profile,(cpu,memory) in DB8_RESOURCE_PROFILES.items():self.assertEqual(resolve_database_resources("capacity",profile=profile),(memory,cpu))
if __name__=="__main__":unittest.main()
