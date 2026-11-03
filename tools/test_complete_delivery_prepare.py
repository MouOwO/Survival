"""Small isolated real-file tests: no SDK/key/Git/Dota or installed-tree writes."""
from copy import deepcopy
from pathlib import Path
import tempfile
import unittest

from test_complete_delivery_projection import fixture, inputs
from complete_delivery_release_20261103 import build_release as build, ledger


def case(root):
    f = fixture()
    f["parent"].update(schema=2, kind="runtime_release_allowlist", hash_algorithms=["md5", "sha256"])
    payload = {key: f["parent"][key] for key in ("schema", "kind", "hash_algorithms", "file_count", "bytes", "files")}
    f["parent"]["content_sha256"] = ledger.sha(ledger.canonical(payload)[:-1])
    f["inventory"]["recorded_parent_content_sha256"] = f["parent"]["content_sha256"]
    given = inputs(f); projection = build.project(**given)
    base = root / "parent"; artifacts = root / "artifacts"; allowed = root / "candidates"
    for directory in (base, artifacts, allowed): directory.mkdir()
    old = {"scripts/vscripts/a.lua": b"old code", "panorama/scripts/a.vjs_c": b"old compiled",
           "maps/template_map.vpk": b"unchanged real map", "scripts/vscripts/identical.lua": b"same published bytes",
           "panorama/styles/dead.vcss_c": b"deleted compiled"}
    new = {"scripts/vscripts/a.lua": b"new code", "panorama/scripts/a.vjs_c": b"official compiled",
           "scripts/vscripts/protected.lua": b"protected source with exact values verified upstream",
           "scripts/vscripts/identical.lua": b"same published bytes"}
    for folder, values in ((base, old), (artifacts, new)):
        for name, raw in values.items():
            target = folder / name; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(raw)
    (base / build.MANIFEST).write_bytes(given["parent_raw"])
    (base / build.SIGNATURE).write_bytes(b"original detached signature never copied or replaced")
    raw = ledger.canonical(projection)
    return dict(inputs=given, reviewed_projection_raw=raw, reviewed_projection_sha256=ledger.sha(raw),
                parent_root=base, artifact_paths={name: artifacts / name for name in new},
                destination=allowed / "fresh_unsigned", allowed_root=allowed)


class UnsignedPrepareTests(unittest.TestCase):
    def test_complete_independent_copy_explicit_removal_and_parent_unchanged(self):
        with tempfile.TemporaryDirectory() as temporary:
            c = case(Path(temporary)); before = {p: p.read_bytes() for p in c["parent_root"].rglob("*") if p.is_file()}
            result = build.prepare_unsigned(**c); target = c["destination"]
            self.assertEqual(result["files"], 5); self.assertTrue(result["all_target_files_rehashed"])
            self.assertFalse(result["parent_signature_authenticated"]); self.assertFalse(result["publication_ready"])
            self.assertFalse((target / build.SIGNATURE).exists()); self.assertTrue((target / build.MARKER).is_file())
            self.assertFalse((target / "panorama/styles/dead.vcss_c").exists())
            self.assertEqual((target / "scripts/vscripts/a.lua").read_bytes(), b"new code")
            self.assertEqual((target / "maps/template_map.vpk").read_bytes(), b"unchanged real map")
            for path, raw in before.items(): self.assertEqual(path.read_bytes(), raw)
            import os
            self.assertFalse(os.path.samefile(target / "maps/template_map.vpk", c["parent_root"] / "maps/template_map.vpk"))
            with self.assertRaisesRegex(ValueError, "fresh_destination"):
                build.prepare_unsigned(**c)

    def test_unpinned_extra_bad_hash_and_review_changes_fail_before_output(self):
        for kind in ("extra", "parent", "artifact", "review", "missing_artifact", "destination_parent"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temporary:
                c = case(Path(temporary))
                if kind == "extra": (c["parent_root"] / "stale.tmp").write_bytes(b"old candidate pollution")
                elif kind == "parent": (c["parent_root"] / "maps/template_map.vpk").write_bytes(b"corrupt parent")
                elif kind == "artifact": next(iter(c["artifact_paths"].values())).write_bytes(b"wrong target")
                elif kind == "review":
                    r = ledger.document(c["reviewed_projection_raw"], c["reviewed_projection_sha256"]); r["files"] += 1
                    c["reviewed_projection_raw"] = ledger.canonical(r); c["reviewed_projection_sha256"] = ledger.sha(c["reviewed_projection_raw"])
                elif kind == "missing_artifact": c["artifact_paths"].pop(next(iter(c["artifact_paths"])))
                elif kind == "destination_parent": c["destination"] = c["parent_root"] / "nested"
                with self.assertRaises(ValueError): build.prepare_unsigned(**c)
                self.assertFalse(c["destination"].exists())

    def test_protected_overlap_and_signature_or_manifest_absence_refused(self):
        for kind in ("protected", "signature", "manifest"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temporary:
                c = case(Path(temporary))
                if kind == "protected": c["protected_paths"] = [c["allowed_root"]]
                elif kind == "signature": (c["parent_root"] / build.SIGNATURE).unlink()
                else: (c["parent_root"] / build.MANIFEST).write_bytes(b"not pinned metadata")
                with self.assertRaises(ValueError): build.prepare_unsigned(**c)
                self.assertFalse(c["destination"].exists())

    def test_projection_manifest_content_id_matches_existing_runtime_contract(self):
        import sys
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import build_runtime_release as runtime
        f = fixture(); f["parent"].update(schema=2, kind="runtime_release_allowlist", hash_algorithms=["md5", "sha256"])
        result = build.project(**inputs(f)); manifest = build.projected_manifest(f["parent"], result)
        runtime.validate_manifest(manifest)
        self.assertEqual(manifest["content_sha256"], ledger.sha(runtime.manifest_payload(manifest)))


if __name__ == "__main__": unittest.main()
