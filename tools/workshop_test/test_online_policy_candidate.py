"""Scope and real pinned-protection checks for the single-module v03 update."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_online_policy_candidate as candidate
from test_web_auth_candidate import manifest


class OnlinePolicyCandidateTest(unittest.TestCase):
    def test_default_never_builds_or_requires_a_private_key(self):
        args = candidate.parser().parse_args([])
        self.assertFalse(args.build)
        self.assertIsNone(args.signing_key)
        self.assertEqual(args.sequence, 2026102403)

    def fixture(self):
        protected = [candidate.POLICY_MODULE] + ["scripts/vscripts/config/generated/fixture_%03d.lua" % n for n in range(179)]
        files = {name: ("protected:" + name).encode() for name in protected}
        files[candidate.RELEASE_PROFILE] = b'return {channel="production"}\n'
        files["materials/unchanged.vmat_c"] = b"unchanged compiled resource"
        return protected, files

    def test_only_one_protected_policy_changes_and_other_179_stay_identical(self):
        protected, files = self.fixture()
        changed = dict(files, **{candidate.POLICY_MODULE: b"reprotected single policy"})
        result = candidate.audit_change(manifest(files), manifest(changed), changed[candidate.POLICY_MODULE], protected)
        self.assertEqual(result["path"], candidate.POLICY_MODULE)
        for name in (protected[1], candidate.RELEASE_PROFILE, "materials/unchanged.vmat_c"):
            invalid = dict(changed, **{name: b"unreviewed change"})
            with self.assertRaises(ValueError):
                candidate.audit_change(manifest(files), manifest(invalid), changed[candidate.POLICY_MODULE], protected)

    def test_inventory_addition_or_missing_protection_is_rejected(self):
        protected, files = self.fixture()
        changed = dict(files, **{candidate.POLICY_MODULE: b"reprotected single policy"})
        with self.assertRaises(ValueError):
            candidate.audit_change(manifest(files), manifest(dict(changed, unexpected=b"extra")), changed[candidate.POLICY_MODULE], protected)
        with self.assertRaises(ValueError):
            candidate.audit_change(manifest(files), manifest(changed), changed[candidate.POLICY_MODULE], protected[:-1])

    def test_real_pinned_prometheus_protects_and_preserves_48_policy_cases(self):
        if not all(path.exists() for path in (candidate.LUA, candidate.LUAC, candidate.DEPENDENCY)):
            self.skipTest("Pinned offline Lua protection tools are not installed")
        raw = (candidate.ROOT / candidate.POLICY_MODULE).read_bytes()
        with tempfile.TemporaryDirectory(prefix="ws4-policy-fixture-") as folder:
            work = Path(folder)
            base = work / "base"
            for name, data in ((candidate.RELEASE_PROFILE, b'return {channel="production"}\n'),
                               (candidate.WEB_CONFIG, b'return {enabled=true}\n')):
                target = base / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            output, proof = candidate.protect_one(raw, base, work / "work", candidate.DEPENDENCY, candidate.LUA, candidate.LUAC)
            self.assertNotEqual(output, raw)
            self.assertFalse(proof["plaintext_substitution"])
            self.assertEqual(proof["behavior_matrix_cases"], 48)
            self.assertEqual(proof["steps"], ["ConstantArray", "NumbersToExpressions", "WrapInFunction"])
            self.assertEqual(proof["semantic_verification"]["status"], "PASS")
            self.assertEqual(proof["generated_modules_rebuilt"], 0)


if __name__ == "__main__":
    unittest.main()
