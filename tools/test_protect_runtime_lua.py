"""Protection boundary checks; the real pinned dependency is an offline integration check."""
import copy
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import protect_runtime_lua as protection


class ProtectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "source"
        self.root.mkdir()
        self.policy = json.loads(protection.POLICY.read_text(encoding="utf-8"))

    def test_only_generated_values_and_explicit_business_modules_are_selected(self):
        paths = ["scripts/vscripts/config/generated/data.lua", "scripts/vscripts/config/generated/index.lua",
                 "scripts/vscripts/config/generated/item_resources.lua", protection.runtime.RELEASE_PROFILE,
                 "scripts/vscripts/systems/arbitrary.lua", *self.policy["business_modules"]]
        rows = protection.selected_files(paths, self.policy)
        selected = {row["path"] for row in rows}
        self.assertEqual(selected, {paths[0], *self.policy["business_modules"]})
        self.assertNotIn(protection.runtime.RELEASE_PROFILE, selected)

    def test_missing_business_module_or_generated_data_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "missing"):
            protection.selected_files(["scripts/vscripts/config/generated/data.lua"], self.policy)
        with self.assertRaisesRegex(ValueError, "No generated"):
            protection.selected_files(self.policy["business_modules"], self.policy)

    def test_policy_rejects_unsupported_or_runtime_incompatible_steps(self):
        for value in (["AntiTamper"], ["Vmify"], ["EncryptStrings"], ["ConstantArray"]):
            data = copy.deepcopy(self.policy)
            data["steps"] = value
            with self.assertRaisesRegex(ValueError, "policy"):
                protection.check_policy(data)
        data = copy.deepcopy(self.policy)
        data["business_modules"].append(protection.runtime.RELEASE_PROFILE)
        with self.assertRaisesRegex(ValueError, "plaintext"):
            protection.check_policy(data)

    def test_dependency_hash_refuses_tampering_and_unreviewed_added_source(self):
        dependency = Path(self.temp.name) / "dependency"
        (dependency / "src").mkdir(parents=True)
        for relative, content in (("src/config.lua", b"return {}"), ("cli.lua", b"-- unused"), ("LICENSE", b"license")):
            (dependency / relative).write_bytes(content)
        paths = sorted([*dependency.glob("src/**/*.lua"), dependency / "cli.lua", dependency / "LICENSE"])
        records = [{"path": path.relative_to(dependency).as_posix(), "bytes": path.stat().st_size,
                    "sha256": protection.runtime.digest(path)} for path in paths]
        self.policy["dependency"].update({
            "source_tree_sha256": hashlib.sha256(protection.runtime.canonical_bytes(records)).hexdigest(),
            "source_tree_files": len(records), "license_sha256": protection.runtime.digest(dependency / "LICENSE")})
        protection.dependency_identity(dependency, self.policy)
        (dependency / "src/extra.lua").write_bytes(b"return 'unexpected'")
        with self.assertRaisesRegex(ValueError, "pinned"):
            protection.dependency_identity(dependency, self.policy)
        (dependency / "src/extra.lua").unlink()
        (dependency / "src/config.lua").write_bytes(b"return {changed=true}")
        with self.assertRaisesRegex(ValueError, "pinned"):
            protection.dependency_identity(dependency, self.policy)

    def test_output_is_new_external_and_cannot_overwrite_source(self):
        for target in (self.root, self.root / "candidate", self.root.parent, Path("relative")):
            with self.subTest(target=target), self.assertRaises(ValueError):
                protection.checked_destination(self.root, target)
        target = Path(self.temp.name) / "candidate"
        self.assertEqual(protection.checked_destination(self.root, target), target.resolve())
        target.mkdir()
        with self.assertRaisesRegex(ValueError, "already exists"):
            protection.checked_destination(self.root, target)

    def test_selected_transform_failure_never_copies_plaintext_fallback(self):
        paths = ["scripts/vscripts/config/generated/data.lua", protection.runtime.RELEASE_PROFILE,
                 "scripts/vscripts/systems/unselected.lua", *self.policy["business_modules"]]
        for relative in paths:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b'return { channel="production" }' if relative == protection.runtime.RELEASE_PROFILE else b'return {}')
        destination = Path(self.temp.name) / "failed_candidate"
        executable = self.root / "fake_lua.exe"
        executable.write_bytes(b"not executed")
        with patch.object(protection, "dependency_identity", return_value={"audited": True}), \
             patch.object(protection.runtime, "select", return_value=(sorted(paths), [])), \
             patch.object(protection, "syntax_check"), \
             patch.object(protection, "run", side_effect=ValueError("simulated transform failure")):
            with self.assertRaisesRegex(ValueError, "simulated"):
                protection.protect(self.root, destination, self.root, executable, executable, self.policy)
        report = json.loads((destination / "_lua_protection_report.json").read_text())
        self.assertEqual(report["status"], "FAILED_DO_NOT_PUBLISH")
        self.assertFalse((destination / paths[0]).exists())
        self.assertEqual((self.root / paths[0]).read_bytes(), b"return {}")
        self.assertEqual((destination / "scripts/vscripts/systems/unselected.lua").read_bytes(), b"return {}")

    @unittest.skipUnless(os.environ.get("SURVIVAL_PROMETHEUS_ROOT"), "Set an explicit audited offline dependency for integration checks")
    def test_real_transform_preserves_high_precision_numbers_and_isolates_string_rng(self):
        dependency = Path(os.environ["SURVIVAL_PROMETHEUS_ROOT"])
        protection.dependency_identity(dependency, self.policy)
        source = self.root
        destination = Path(self.temp.name) / "transformed"
        path = "scripts/vscripts/config/generated/probe.lua"
        for root in (source, destination):
            (root / path).parent.mkdir(parents=True, exist_ok=True)
        (source / path).write_text('local M={rows={{value=0.33333333333333331,name="精确数据",n=1000000000000}}};'
                                  'M.by_id={first=M.rows[1]};return M', encoding="utf-8")
        lua = Path("C:/Program Files/lua/bin/lua5.1.exe")
        luac = Path("C:/Program Files/lua/bin/luac5.1.exe")
        work = Path(self.temp.name) / "work"
        work.mkdir()
        for mode in ("baseline", "generated_table_strings"):
            protection.run([str(lua), str(protection.SUPPORT / "prometheus_offline_driver.lua"),
                            str(dependency), str(source / path), str(destination / path), "123456", mode])
            protection.syntax_check([destination / path], luac)
            result = protection.compare_values(source, destination, [{"path": path, "kind": "generated_table"}], lua, work)
            self.assertTrue(result["all_generated_values_exact"])
            self.assertTrue(result["gameplay_rng_untouched_while_loading"])


if __name__ == "__main__":
    unittest.main()
