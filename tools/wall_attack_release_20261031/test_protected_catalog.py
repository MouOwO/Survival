"""Boundary/real Lua verifier regressions; the real pinned transform is a release check."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import protected_catalog as catalog


def table_source(skin: int, *, name: str = "unchanged", extra: str = "") -> bytes:
    return (f'local row={{asset_id="hero_permanent_hero_blademaster",model_skin={skin},name="{name}",'
            'value=0.33333333333333331,values={true,false,1000000000000}};'
            f'local M={{rows={{row}},by_id={{hero_permanent_hero_blademaster=row}}}};{extra}return M\n').encode("utf-8")


def private_fixture(source: bytes) -> bytes:
    # Deliberately a fixture, not an alternative production obfuscator.
    return (b"return(function(...)\nlocal shared_math=math\nlocal math={}\n"
            b"for key,value in pairs(shared_math) do math[key]=value end\n"
            b"math.randomseed=function() error('PRIVATE_DATA_RNG_SEED_FIXED') end\n" + source + b"\nend)(...)\n")


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.baseline = self.root / "baseline" / catalog.RELATIVE
        self.baseline.parent.mkdir(parents=True)
        self.baseline.write_bytes(private_fixture(table_source(1)))
        self.baseline_hash = hashlib.sha256(self.baseline.read_bytes()).hexdigest()
        self.source = self.root / "plaintext" / "source.lua"
        self.source.parent.mkdir()
        self.source.write_bytes(table_source(0))
        self.work = self.root / "new_work"
        self.dependency = self.root / "dependency"
        self.dependency.mkdir()

    def call(self, **changes):
        options = dict(target_source=self.source.read_bytes(), baseline_catalog=self.baseline, work=self.work,
                       dependency=self.dependency, expected_baseline_sha256=self.baseline_hash, source_path=self.source)
        options.update(changes)
        return catalog.reprotect_asset_catalog(**options)

    def fake_transform(self, *, corrupt=None, mutate_source=False):
        real_run = catalog.protection.run

        def execute(command, **kwargs):
            if len(command) > 1 and command[1] == str(catalog.protection.SUPPORT / "prometheus_offline_driver.lua"):
                self.assertEqual(command[-1], "generated_table_strings")
                source = Path(command[3]).read_bytes()
                Path(command[4]).write_bytes(private_fixture(corrupt if corrupt is not None else source))
                if mutate_source:
                    self.source.write_bytes(self.source.read_bytes() + b"-- concurrently modified\n")
                return ""
            return real_run(command, **kwargs)
        return execute

    def test_immutable_bytes_expected_hash_and_canonical_path_required(self):
        for values in (dict(target_source=bytearray(b"return {}")), dict(target_source=b""),
                       dict(expected_baseline_sha256="0" * 64), dict(expected_baseline_sha256="ABC")):
            with self.subTest(values=values), self.assertRaises(ValueError):
                self.call(**values)
        other = self.root / "asset_catalog.lua"
        other.write_bytes(self.baseline.read_bytes())
        with self.assertRaisesRegex(ValueError, "canonical"):
            self.call(baseline_catalog=other)
        self.assertFalse(self.work.exists())

    def test_plaintext_baseline_is_rejected_instead_of_downgraded(self):
        self.baseline.write_bytes(table_source(1))
        with self.assertRaisesRegex(ValueError, "private RNG"):
            self.call(expected_baseline_sha256=hashlib.sha256(self.baseline.read_bytes()).hexdigest())
        self.assertFalse(self.work.exists())

    def test_no_overwrite_relative_installed_or_baseline_nested_work(self):
        self.work.mkdir()
        for path in (self.work, Path("relative_work"), catalog.protection.ROOT / "output/forbidden_catalog", self.baseline.parents[4] / "work"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                self.call(work=path)
        self.assertEqual(list(self.work.iterdir()), [])

    def test_tracked_source_mismatch_and_dependency_overlap_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "Tracked source"):
            self.call(target_source=table_source(0, name="wrong"))
        with self.assertRaisesRegex(ValueError, "overlaps"):
            self.call(work=self.dependency / "output")
        self.assertFalse(self.work.exists())

    def test_real_pinned_dependency_guard_rejects_substitute_before_creating_work(self):
        (self.dependency / "src").mkdir()
        for name in ("cli.lua", "LICENSE", "src/fake.lua"):
            (self.dependency / name).write_bytes(b"not the pinned dependency")
        with self.assertRaisesRegex(ValueError, "pinned"):
            self.call()
        self.assertFalse(self.work.exists())

    @unittest.skipUnless(catalog.LUA.is_file() and catalog.LUAC.is_file(), "Real local Lua5.1 executables required")
    def test_real_restricted_deep_verifier_and_exact_alias_precision_pass(self):
        before = self.source.read_bytes(), self.baseline.read_bytes()
        with mock.patch.object(catalog.protection, "dependency_identity", return_value={"fixture": True}) as identity, \
             mock.patch.object(catalog.protection, "run", side_effect=self.fake_transform()):
            report = self.call()
        self.assertEqual(report["status"], "PASS_REQUIRES_NATIVE_SMOKE")
        self.assertEqual(report["business_modules_transformed"], [])
        self.assertTrue(report["baseline_delta_verification"]["all_generated_values_exact"])
        self.assertTrue(report["semantic_verification"]["gameplay_rng_untouched_while_loading"])
        self.assertEqual(identity.call_count, 2)
        self.assertEqual((self.source.read_bytes(), self.baseline.read_bytes()), before)
        self.assertNotEqual(Path(report["output_path"]).read_bytes(), self.source.read_bytes())

    @unittest.skipUnless(catalog.LUA.is_file() and catalog.LUAC.is_file(), "Real local Lua5.1 executables required")
    def test_any_additional_catalogue_delta_fails_before_transform(self):
        for source in (table_source(0, name="unauthorized_name"), table_source(1),
                       table_source(0, extra="M.by_id.hero_permanent_hero_blademaster={asset_id=row.asset_id,model_skin=0};")):
            with self.subTest(source=source):
                self.work = self.root / ("delta_" + hashlib.sha256(source).hexdigest()[:10])
                self.source.write_bytes(source)
                with mock.patch.object(catalog.protection, "dependency_identity", return_value={"fixture": True}), \
                     mock.patch.object(catalog.protection, "run", side_effect=self.fake_transform()), \
                     self.assertRaises(ValueError):
                    self.call()
                report = json.loads((self.work / "catalog_protection_report.json").read_text("utf-8"))
                self.assertEqual(report["status"], "FAILED_DO_NOT_PUBLISH")
                self.assertFalse((self.work / "protected" / catalog.RELATIVE).exists())

    @unittest.skipUnless(catalog.LUA.is_file() and catalog.LUAC.is_file(), "Real local Lua5.1 executables required")
    def test_corrupt_or_rng_consuming_transformed_result_is_never_returned(self):
        for source in (table_source(0, name="changed_by_transform"),
                       b"local bad=shared_math.random();" + table_source(0)):
            with self.subTest(source=source):
                self.work = self.root / ("bad_output_" + hashlib.sha256(source).hexdigest()[:10])
                with mock.patch.object(catalog.protection, "dependency_identity", return_value={"fixture": True}), \
                     mock.patch.object(catalog.protection, "run", side_effect=self.fake_transform(corrupt=source)), \
                     self.assertRaises(ValueError):
                    self.call()
                self.assertFalse((self.work / "protected" / catalog.RELATIVE).exists())

    @unittest.skipUnless(catalog.LUA.is_file() and catalog.LUAC.is_file(), "Real local Lua5.1 executables required")
    def test_concurrent_source_change_fails_and_marks_integrity_error(self):
        with mock.patch.object(catalog.protection, "dependency_identity", return_value={"fixture": True}), \
             mock.patch.object(catalog.protection, "run", side_effect=self.fake_transform(mutate_source=True)), \
             self.assertRaisesRegex(ValueError, "Tracked development source changed"):
            self.call()
        report = json.loads((self.work / "catalog_protection_report.json").read_text("utf-8"))
        self.assertEqual(report["status"], "FAILED_DO_NOT_PUBLISH")
        self.assertFalse(report["source_hashes_unchanged"])
        self.assertFalse((self.work / "protected" / catalog.RELATIVE).exists())

    @unittest.skipUnless(catalog.LUA.is_file() and catalog.LUAC.is_file(), "Real local Lua5.1 executables required")
    def test_adapter_failure_has_no_plaintext_fallback(self):
        real_run = catalog.protection.run
        def fail(command, **kwargs):
            if len(command) > 1 and command[1] == str(catalog.protection.SUPPORT / "prometheus_offline_driver.lua"):
                raise ValueError("fixture adapter failure")
            return real_run(command, **kwargs)
        with mock.patch.object(catalog.protection, "dependency_identity", return_value={"fixture": True}), \
             mock.patch.object(catalog.protection, "run", side_effect=fail), \
             self.assertRaisesRegex(ValueError, "fixture adapter failure"):
            self.call()
        report = json.loads((self.work / "catalog_protection_report.json").read_text("utf-8"))
        self.assertFalse(report["plaintext_fallback"])
        self.assertEqual(report["status"], "FAILED_DO_NOT_PUBLISH")
        self.assertFalse((self.work / "protected" / catalog.RELATIVE).exists())


if __name__ == "__main__":
    unittest.main()
