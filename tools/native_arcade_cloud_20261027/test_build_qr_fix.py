"""Real signed temporary native08 -> QR09 packages; no production signing."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import struct
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


tool = load("qr09_build_under_test", HERE / "build_qr_fix.py")
legacy = load("qr09_native08_real_fixture", HERE / "test_package_native_cloud.py")
REAL_ROOT = tool.ROOT


def compiled_fixture(source):
    return struct.pack("<IHHII", 28 + len(source), 12, 0, 8, 1) + struct.pack("<4sII", b"DATA", 8, len(source)) + source


class QR09BuildTests(unittest.TestCase):
    def patched(self, target, name, value):
        context = patch.object(target, name, value)
        context.start(); self.addCleanup(context.stop)

    def setUp(self):
        self.native = legacy.NativeCloudPackageTests()
        self.native.setUp()
        self.addCleanup(self.native.doCleanups)
        f = self.native.fixture
        self.native.replacements[tool.TARGET] = b"native08 compiled checkout fixture"
        self.native.reseal()
        base_report = legacy.tool.run(build=True)
        self.changed_archive = next(row["archive"] for row in tool.incremental.read_entries(Path(base_report["output"])) if row["path"] == tool.TARGET)
        self.before = copy.deepcopy(self.native.after)
        self.root = f.base
        self.base_report = self.root / "native08.package.json"
        self.base_report.write_text(json.dumps(base_report), encoding="utf8")
        self.download = self.root / "native08.download.json"
        self.download.write_text(json.dumps(dict(status="OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED",
            release_sequence=2026102708, content_sha256=self.before["content_sha256"],
            steam_manifest=tool.BASE_STEAM_MANIFEST, signed_resources_verified=self.before["file_count"],
            protected_modules_verified=180)), encoding="utf8")
        self.source, self.mirror, self.compiled, self.log = [self.root/name for name in ("payment.js","mirror.js","payment.vjs_c","compile.log")]
        self.source.write_bytes(b"// synthetic checkout source fixture\n")
        self.mirror.write_bytes(self.source.read_bytes())
        self.compiled.write_bytes(compiled_fixture(self.source.read_bytes()))
        self.log.write_bytes(b"payment_test.js\nOK: 1 compiled, 0 failed, 0 skipped\n")
        self.key = self.root / "private-vault/sign.pem"
        self.key.parent.mkdir(); self.key.write_bytes(f.private.read_bytes())
        self.overlay, self.trusted, self.view, self.output = [self.root/name for name in ("qr09-thin","qr09-trust","qr09-view","qr09-vpk")]
        protected_policy = f.source/"tools/lua_protection_policy.json"
        protected_policy.parent.mkdir(parents=True, exist_ok=True)
        protected_policy.write_bytes((REAL_ROOT/"tools/lua_protection_policy.json").read_bytes())
        (f.source/"tools/build_runtime_release.py").write_bytes((REAL_ROOT/"tools/build_runtime_release.py").read_bytes())
        # Public-policy/key fixture hashes are independent from the generated
        # private key, and production constants are not exposed as CLI options.
        public_pins = {name:hashlib.sha256((f.source/name).read_bytes()).hexdigest() for name in tool.PUBLIC_PINS}
        for name,value in dict(ROOT=f.source, BASE=self.native.view, BASE_TRUSTED=self.native.trusted,
                BASE_VPK=Path(base_report["output"]), BASE_CONTENT=self.before["content_sha256"],
                COUNT=self.before["file_count"], ARCHIVE_COUNT=base_report["verification"]["archive_count"],
                REBUILT_ARCHIVE=self.changed_archive,
                BASE_REPORT=self.base_report, BASE_REPORT_SHA=hashlib.sha256(self.base_report.read_bytes()).hexdigest(),
                BASE_DOWNLOAD=self.download, BASE_DOWNLOAD_SHA=hashlib.sha256(self.download.read_bytes()).hexdigest(),
                BEFORE_SHA=hashlib.sha256(self.native.replacements[tool.TARGET]).hexdigest(),
                SOURCE=self.source, MIRROR=self.mirror, SOURCE_SHA=hashlib.sha256(self.source.read_bytes()).hexdigest(),
                COMPILED=self.compiled, AFTER_SHA=hashlib.sha256(self.compiled.read_bytes()).hexdigest(),
                AFTER_BYTES=self.compiled.stat().st_size, COMPILE_LOG=self.log,
                COMPILE_LOG_SHA=hashlib.sha256(self.log.read_bytes()).hexdigest(), PUBLIC_PINS=public_pins,
                OVERLAY=self.overlay, TRUSTED=self.trusted, VIEW=self.view, OUTPUT=self.output, ITEM="123456789").items():
            self.patched(tool,name,value)
        self.patched(tool.incremental,"ITEM","123456789")
        self.patched(tool.incremental.pack,"ARCHIVE_BYTES",legacy.tool.pack.ARCHIVE_BYTES)

    def assert_base_intact(self):
        self.assertTrue(tool.pack.runtime.verify(tool.BASE,self.before)["ok"])
        self.assertEqual(tool.pack.package_inventory(tool.BASE_VPK),json.loads(self.base_report.read_bytes())["package_files"])

    def test_default_is_complete_read_only_plan_without_private_key_read(self):
        with patch.object(tool.pack.protect_data,"sign_manifest",side_effect=AssertionError("signing forbidden")):
            result=tool.run()
        self.assertEqual(result["release_sequence"],2026102709)
        self.assertEqual(result["changed_runtime_paths"],[tool.TARGET])
        self.assertEqual(result["protected_modules_preserved"],180)
        self.assertEqual(result["rebuilt_archives"],[self.changed_archive])
        self.assertTrue(result["full_view_canonical_guard"].startswith("NOT_RUN"))
        self.assertTrue(all(not path.exists() for path in (self.overlay,self.trusted,self.view,self.output)))
        self.assert_base_intact()

    def test_single_build_signs_real_manifest_canonical_view_and_incremental_vpk(self):
        result=tool.run(build=True,key=self.key)
        self.assertTrue(result["signature_valid"] and result["immutable_base_unchanged"])
        self.assertEqual(result["full_view_canonical_guard"],"PASS")
        self.assertTrue(result["verification"]["manifest_dual_hashes_verified"])
        self.assertEqual(result["package_files"],tool.pack.package_inventory(Path(result["output"])))
        self.assertEqual(tool.incremental.all_files(self.overlay),{tool.TARGET,tool.pack.handoff.MANIFEST,tool.pack.handoff.SIGNATURE})
        self.assertEqual(tool.incremental.all_files(self.trusted),set(tool.TRUST_NAMES)|{tool.SOURCE_REL})
        self.assertFalse((self.view/tool.SOURCE_REL).exists())
        for row in self.before["files"]:
            self.assertEqual(os.path.samefile(self.view/row["path"],tool.BASE/row["path"]),row["path"]!=tool.TARGET)
        for index in result["reused_archives"]:
            self.assertTrue(os.path.samefile(self.output/f"123456789_{index:03}.vpk",tool.BASE_VPK.with_name(f"123456789_{index:03}.vpk")))
        self.assertFalse(os.path.samefile(self.output/f"123456789_{self.changed_archive:03}.vpk",tool.BASE_VPK.with_name(f"123456789_{self.changed_archive:03}.vpk")))
        self.assert_base_intact()

    def test_source_mirror_compile_or_pinned_old_report_drift_refuse_before_any_output(self):
        for file in (self.source,self.mirror,self.compiled,self.log,self.base_report,self.download):
            raw=file.read_bytes();file.write_bytes(raw+b"tampered")
            with self.subTest(file=file.name),self.assertRaises(ValueError):tool.run(build=True,key=self.key)
            file.write_bytes(raw)
        self.assertTrue(all(not path.exists() for path in (self.overlay,self.trusted,self.view,self.output)))
        self.assert_base_intact()

    def test_protected_inventory_and_base_checkout_pin_cannot_change(self):
        after=copy.deepcopy(self.before)
        name=next(iter(self.native.protected))
        next(row for row in after["files"] if row["path"]==name)["sha256"]="a"*64
        policy=json.loads((REAL_ROOT/"tools/lua_protection_policy.json").read_bytes())
        with self.assertRaisesRegex(ValueError,"protected 180"):tool.verify_protected(self.before,after,policy)
        with patch.object(tool,"BEFORE_SHA","a"*64),self.assertRaisesRegex(ValueError,"base checkout"):
            tool.run(build=True,key=self.key)
        self.assertFalse(self.overlay.exists())

    def test_compiled_data_binds_exact_source_even_with_an_independently_pinned_container(self):
        bad = compiled_fixture(self.source.read_bytes() + b"// mismatched source\n")
        self.compiled.write_bytes(bad)
        with patch.object(tool,"AFTER_SHA",hashlib.sha256(bad).hexdigest()), \
                patch.object(tool,"AFTER_BYTES",len(bad)), \
                self.assertRaisesRegex(ValueError,"DATA differs from reviewed source"):
            tool.run(build=True,key=self.key)
        self.assertFalse(self.overlay.exists())
        for raw in (b"short", compiled_fixture(b"x").replace(b"DATA",b"REDI",1),
                    compiled_fixture(b"x")[:20] + struct.pack("<I",0) + compiled_fixture(b"x")[24:]):
            with self.subTest(raw=raw[:4]),self.assertRaises(ValueError):tool.compiled_data(raw)

    def test_existing_outputs_key_requirements_and_capacity_fail_before_creation(self):
        with self.assertRaisesRegex(ValueError,"requires an external"):tool.run(build=True)
        with self.assertRaisesRegex(ValueError,"only with --build"):tool.run(key=self.key)
        self.overlay.mkdir();(self.overlay/"keep.txt").write_bytes(b"foreign")
        with self.assertRaisesRegex(ValueError,"entirely new"):tool.run(build=True,key=self.key)
        self.assertEqual((self.overlay/"keep.txt").read_bytes(),b"foreign")
        (self.overlay/"keep.txt").unlink();self.overlay.rmdir()
        with patch.object(tool.incremental,"capacity",side_effect=ValueError("insufficient space")),self.assertRaisesRegex(ValueError,"insufficient space"):
            tool.run(build=True,key=self.key)
        self.assertFalse(self.overlay.exists())

    def test_late_compiled_mutation_never_writes_to_base_or_publishes_vpk(self):
        original=tool.unchanged
        calls=[0]
        def mutate(snapshots):
            calls[0]+=1
            if calls[0]==2:self.compiled.write_bytes(self.compiled.read_bytes()+b"late")
            return original(snapshots)
        with patch.object(tool,"unchanged",side_effect=mutate),self.assertRaisesRegex(ValueError,"input changed|bounded read limit"):
            tool.run(build=True,key=self.key)
        self.assertFalse(self.output.exists())
        self.assert_base_intact()


if __name__=="__main__":unittest.main()
