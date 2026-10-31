"""Offline thin-release guards. No real baseline, key, Steam or external build."""
from __future__ import annotations

import copy
from contextlib import ExitStack
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import build_release as build


def manifest(values):
    rows = [{"path": name, **build.checks(raw)} for name, raw in sorted(values.items())]
    result = {"schema": 2, "kind": "runtime_release_allowlist", "hash_algorithms": ["md5", "sha256"],
              "files": rows, "file_count": len(rows), "bytes": sum(row["bytes"] for row in rows)}
    result["content_sha256"] = build.sha(build.pack.runtime.manifest_payload(result))
    build.pack.runtime.validate_manifest(result)
    return result


class BuilderGuards(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.policy = json.loads((build.ROOT / "tools/lua_protection_policy.json").read_text("utf-8"))
        build.blob.cache_clear()
        build.revision.cache_clear()
        self.addCleanup(build.blob.cache_clear)
        self.addCleanup(build.revision.cache_clear)

    def approval(self, **changes):
        value = {"source_revision": "fixed-wall-revision", "paths": ["scripts/vscripts/systems/wall_attack.lua"],
                 "reason": "Reviewed wall targeting fix", "fix_confirmed": True}
        value.update(changes)
        path = self.root / "wall_approval.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def plan_fixture(self, *, values=None, bundle_matches=True, baseline_extra=None, wall=None):
        protected = {build.CATALOG, build.BUNDLE,
                     *(f"scripts/vscripts/config/generated/preserved_{i:03}.lua" for i in range(178)),
                     *self.policy["business_modules"]}
        assert len(protected) == 184
        reviews = [f"scripts/vscripts/admission/guard_{i:02}.lua" for i in range(16)]
        old_values = {name: ("old:" + name).encode() for name in protected | set(reviews)}
        old_values.update({build.UI_NAMES[0]: b"old UI", "maps/template_map.vpk": b"unchanged gameplay map",
                           "maps/portraits/retired.vpk": b"keep previous portrait map"})
        old_values.update(baseline_extra or {})
        old = manifest(old_values)
        payload = {build.CATALOG: b"new protected catalogue", build.UI_NAMES[0]: b"new UI", build.NEW_SCENE: b"new portrait"}
        if values is not None:
            payload.update(values)
        trusted = self.root / "trusted"
        for name in reviews:
            path = trusted / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(old_values[name])
        stack = ExitStack()
        stack.enter_context(mock.patch.object(build, "baseline", return_value=(old, {"package_files": [{"path": "fixture.vpk"}]})))
        stack.enter_context(mock.patch.object(build, "payloads", return_value=(payload, wall)))
        stack.enter_context(mock.patch.object(build, "BASE_TRUSTED", trusted))
        stack.enter_context(mock.patch.object(build, "load", return_value=self.policy))
        stack.enter_context(mock.patch.object(build, "revision", side_effect=lambda value: "resolved:" + value))
        stack.enter_context(mock.patch.object(build, "blob", return_value=build.EXPECTED_BUNDLE.encode() if bundle_matches else b"wrong bundle"))
        stack.enter_context(mock.patch.object(build.pack.runtime, "digest", return_value="f" * 64))
        stack.enter_context(mock.patch.object(build.inc, "read_entries", return_value=[]))
        stack.enter_context(mock.patch.object(build.previous.base.parent, "rotation_plan", return_value=(b"tree", [], set(), [])))
        stack.enter_context(mock.patch.object(build.inc, "capacity", return_value=[{"path": "fixture-volume", "free_bytes": 1000, "required_bytes": 100}]))
        return stack, old, payload, protected, reviews

    def test_projected_preserves_every_old_path_and_adds_only_new_payload(self):
        old = manifest({"maps/template_map.vpk": b"base map", "maps/portraits/retired.vpk": b"old scene",
                        "scripts/vscripts/unchanged.lua": b"old module"})
        before = copy.deepcopy(old)
        after, changed = build.projected(old, {"scripts/vscripts/unchanged.lua": b"old module",
                                              "maps/portraits/new.vpk": b"new scene"})
        self.assertEqual(old, before, "baseline manifest must not be mutated")
        self.assertEqual(set(changed), {"maps/portraits/new.vpk"})
        self.assertTrue({row["path"] for row in old["files"]} < {row["path"] for row in after["files"]})
        self.assertEqual(after["file_count"], old["file_count"] + 1)
        self.assertEqual(next(row for row in after["files"] if row["path"] == "maps/template_map.vpk"),
                         next(row for row in old["files"] if row["path"] == "maps/template_map.vpk"))

    def test_plan_enforces_183_preserved_one_catalog_and_unchanged_d573_gate_scope(self):
        stack, old, payload, _, _ = self.plan_fixture()
        with stack:
            plan, before, after, changed, *_ = build.make_plan()
        self.assertEqual(plan["protected_modules_preserved"], 183)
        self.assertEqual(plan["protected_modules_rebuilt"], 1)
        self.assertEqual(plan["protected_rebuilt_paths"], [build.CATALOG])
        self.assertEqual(plan["archive_bundle_hash"], build.EXPECTED_BUNDLE)
        self.assertTrue(plan["account_gates_payment_backend_preserved"])
        self.assertEqual(plan["removed_runtime_paths"], [])
        self.assertTrue(plan["pending_wall_fix"])
        self.assertFalse(plan["ready_for_signed_build"])
        self.assertFalse(plan["ready_for_upload"])
        self.assertEqual(set(changed), set(payload))
        self.assertTrue({row["path"] for row in before["files"]} <= {row["path"] for row in after["files"]})
        self.assertEqual(before, old)

    def test_plan_refuses_other_protected_module_and_reviewed_admission_change(self):
        for name, message in (("scripts/vscripts/config/generated/preserved_000.lua", "183 preserved"),
                              ("scripts/vscripts/admission/guard_00.lua", "gate/auth")):
            stack, *_ = self.plan_fixture(values={name: b"unreviewed delta"})
            with self.subTest(path=name), stack, self.assertRaisesRegex((ValueError, AssertionError), message):
                build.make_plan()
        stack, *_ = self.plan_fixture(bundle_matches=False)
        with stack, self.assertRaisesRegex((ValueError, AssertionError), "d573"):
            build.make_plan()

    def test_wall_approval_rejects_illegal_scope_duplicate_excess_or_unconfirmed(self):
        invalid = [
            {"paths": ["scripts/vscripts/config/release_profile.lua"]},
            {"paths": ["panorama/scripts/custom_game/combat_stats.vjs_c"]},
            {"paths": ["scripts/vscripts/systems/../config/gate.lua"]},
            {"paths": ["scripts/vscripts/systems/payment_delivery.lua"]},
            {"paths": ["scripts/vscripts/ui/archive_gate.lua"]},
            {"paths": [build.UI_NAMES[-1]]},
            {"paths": ["scripts/vscripts/systems/wall.lua"] * 2},
            {"paths": [f"scripts/vscripts/systems/wall_{i}.lua" for i in range(7)]},
            {"fix_confirmed": False}, {"fix_confirmed": 1}, {"reason": "   "},
        ]
        for delta in invalid:
            approval = self.approval(**delta)
            with self.subTest(delta=delta), mock.patch.object(build, "revision") as revision, \
                 mock.patch.object(build, "blob") as blob, self.assertRaises((ValueError, AssertionError)):
                build.wall_inputs(approval)
            revision.assert_not_called()
            blob.assert_not_called()

    def test_empty_wall_approval_cannot_unlock_a_signed_build(self):
        approval = self.approval(paths=[])
        with mock.patch.object(build, "revision", return_value="a" * 40), \
             mock.patch.object(build, "blob") as blob, self.assertRaises((ValueError, AssertionError)):
            build.wall_inputs(approval)
        blob.assert_not_called()

    def test_approved_but_unchanged_wall_source_cannot_unlock_signed_build(self):
        name = "scripts/vscripts/systems/wall_attack.lua"
        stack, *_ = self.plan_fixture(values={name: b"unchanged wall module"},
                                      baseline_extra={name: b"unchanged wall module"},
                                      wall={"paths": [name], "fix_confirmed": True})
        with stack, self.assertRaisesRegex((ValueError, AssertionError), "actually differ"):
            build.make_plan()

    def test_valid_wall_approval_resolves_revision_then_reads_exact_paths(self):
        approval = self.approval(paths=["scripts/vscripts/systems/wall_attack.lua", "scripts/vscripts/modifiers/wall_target.lua"])
        with mock.patch.object(build, "revision", return_value="a" * 40) as rev, \
             mock.patch.object(build, "blob", return_value=b"fixed committed wall") as blob:
            values, review = build.wall_inputs(approval)
        rev.assert_called_once_with("fixed-wall-revision")
        self.assertEqual(set(values), set(json.loads(approval.read_text())["paths"]))
        self.assertTrue(all(call.args[0] == "a" * 40 for call in blob.call_args_list))
        self.assertEqual(review["source_revision"], "a" * 40)
        self.assertEqual(review["approval_sha256"], build.sha(approval.read_bytes()))

    def test_pending_signed_build_stops_before_key_read_or_signing(self):
        pending = {"ready_for_signed_build": False, "pending_wall_fix": True}
        with mock.patch.object(build, "make_plan", return_value=(pending, None, None, None, None, None)), \
             mock.patch.object(build.pack.protect_data, "external", side_effect=AssertionError("key must not be inspected")) as key, \
             mock.patch.object(build.pack.protect_data, "sign_manifest", side_effect=AssertionError("must not sign")) as signing, \
             mock.patch.object(build, "load", side_effect=AssertionError("must not read reviewed/key material")):
            with self.assertRaisesRegex((ValueError, AssertionError), "Wall fix still pending"):
                build.build_signed(self.root / "unread_review.json", self.root / "unread_key.pem", None)
        key.assert_not_called()
        signing.assert_not_called()

    def test_pending_overlay_has_marker_but_no_manifest_or_signature_and_never_overwrites(self):
        pending = self.root / "new_pending"
        plan = {"pending_wall_fix": True, "ready_for_signed_build": False, "ready_for_upload": False}
        payload = {"scripts/vscripts/systems/performance.lua": b"return {}"}
        with mock.patch.object(build, "PENDING", pending), mock.patch.object(build.pack.protect_data, "sign_manifest", side_effect=AssertionError("no signing")):
            build.prepare_pending(plan, payload)
            self.assertEqual((pending / next(iter(payload))).read_bytes(), b"return {}")
            self.assertEqual(json.loads((pending / build.PENDING_MARKER).read_bytes()), plan)
            self.assertFalse((pending / build.pack.handoff.MANIFEST).exists())
            self.assertFalse((pending / build.pack.handoff.SIGNATURE).exists())
            original = {p.relative_to(pending): p.read_bytes() for p in pending.rglob("*") if p.is_file()}
            with self.assertRaises((ValueError, AssertionError)):
                build.prepare_pending(plan, payload)
            self.assertEqual({p.relative_to(pending): p.read_bytes() for p in pending.rglob("*") if p.is_file()}, original)

    def test_payload_capture_uses_fixed_revisions_and_never_head_or_working_source(self):
        def committed(commit, name):
            self.assertNotIn(commit, {"HEAD", "HEAD~1"})
            return ("committed:" + commit + ":" + name).encode()
        with mock.patch.object(build, "blob", side_effect=committed) as blob, \
             mock.patch.object(build, "catalog_payload", return_value=b"new protected catalog"):
            values, wall = build.payloads()
        self.assertIsNone(wall)
        self.assertEqual(set(values), set(build.UI_NAMES) | {build.NEW_SCENE, build.SCENE_JS, build.CATALOG})
        self.assertCountEqual(blob.call_args_list, [mock.call(build.UI_REVISION, name) for name in build.UI_NAMES]
                              + [mock.call(build.PORTRAIT_REVISION, name) for name in (build.NEW_SCENE, build.SCENE_JS)])

    def test_blob_ordinary_payload_reads_git_object_instead_of_working_source(self):
        name = "panorama/scripts/custom_game/combat_stats.vjs_c"
        commit = "a" * 40
        with mock.patch.object(build, "ROOT", self.root), mock.patch.object(build, "revision", return_value=commit), \
             mock.patch.object(build.subprocess, "check_output", return_value=b"fixed revision bytes") as command, \
             mock.patch.object(build.pack.protect_data, "source_path", side_effect=AssertionError("working tree read forbidden")):
            self.assertEqual(build.blob(build.UI_REVISION, name), b"fixed revision bytes")
        command.assert_called_once_with(["git", "cat-file", "blob", commit + ":" + name], cwd=self.root)

    def test_lfs_pointer_resolves_only_exact_pinned_size_and_real_sha(self):
        name = "maps/portraits/sample.vpk"
        local = self.root / name
        local.parent.mkdir(parents=True)
        raw = b"native compiled map fixture"
        pointer = ("version https://git-lfs.github.com/spec/v1\noid sha256:" + build.sha(raw) + "\nsize " + str(len(raw)) + "\n").encode()
        for payload, succeeds in ((raw, True), (raw + b"x", False), (b"x" * len(raw), False)):
            local.write_bytes(payload)
            build.blob.cache_clear()
            with self.subTest(payload=payload), mock.patch.object(build, "ROOT", self.root), \
                 mock.patch.object(build, "revision", return_value="a" * 40), \
                 mock.patch.object(build.subprocess, "check_output", return_value=pointer):
                if succeeds:
                    self.assertEqual(build.blob(build.PORTRAIT_REVISION, name), raw)
                else:
                    with self.assertRaisesRegex((ValueError, AssertionError), "Installed LFS bytes"):
                        build.blob(build.PORTRAIT_REVISION, name)

    def test_same_plan_ignores_only_disk_free_bytes_and_rejects_all_other_drift(self):
        original = {"source_revisions": {"portrait": "fixed"}, "target_pins": {"file": {"sha256": "a" * 64}},
                    "archive_bundle_hash": build.EXPECTED_BUNDLE, "release_sequence": build.SEQUENCE,
                    "disk_preflight": [{"volume": "D:/", "free_bytes": 1000, "required_bytes": 100}],
                    "changed_runtime_paths": [build.CATALOG], "ready_for_upload": False}
        a, b = copy.deepcopy(original), copy.deepcopy(original)
        b["disk_preflight"][0]["free_bytes"] = 1
        self.assertTrue(build.same_plan(a, b))
        self.assertEqual(a, original)
        changes = [lambda x: x.update(release_sequence=build.SEQUENCE + 1),
                   lambda x: x["source_revisions"].update(portrait="changed"),
                   lambda x: x["target_pins"]["file"].update(sha256="b" * 64),
                   lambda x: x.update(archive_bundle_hash="new backend"),
                   lambda x: x["disk_preflight"][0].update(required_bytes=101),
                   lambda x: x["disk_preflight"][0].update(volume="E:/"),
                   lambda x: x["changed_runtime_paths"].append("unreviewed.lua"),
                   lambda x: x.update(ready_for_upload=True),
                   lambda x: x.update(free_bytes=1000)]
        for mutate in changes:
            changed = copy.deepcopy(original)
            mutate(changed)
            self.assertFalse(build.same_plan(original, changed))


if __name__ == "__main__":
    unittest.main()
