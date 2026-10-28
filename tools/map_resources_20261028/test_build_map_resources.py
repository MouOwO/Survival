"""Map projection/overflow tests and a real signed temporary VPK roundtrip.

Only existing isolated test fixtures generate keys. No production key, map
compiler, Steam client or production artifact directory is used by these tests.
"""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


tool = load("map2802_builder_under_test", HERE / "build_map_resources.py")


def row(name, raw):
    return dict(path=name, bytes=len(raw), md5=hashlib.md5(raw, usedforsecurity=False).hexdigest(),
                sha256=hashlib.sha256(raw).hexdigest())


def manifest(rows):
    value = dict(schema=2, kind="runtime_release_allowlist", hash_algorithms=["md5", "sha256"],
                 file_count=len(rows), bytes=sum(r["bytes"] for r in rows), files=sorted(rows, key=lambda r:r["path"]))
    value["content_sha256"] = hashlib.sha256(tool.pack.runtime.manifest_payload(value)).hexdigest()
    return value


def pins(value):
    return {key:value[key] for key in ("bytes", "md5", "sha256")}


class MapProjectionTests(unittest.TestCase):
    def setUp(self):
        self.policy = json.loads((ROOT / "tools/lua_protection_policy.json").read_bytes())
        protected = [row(name, b"protected fixture") for name in self.policy["business_modules"]]
        protected += [row(self.policy["generated_prefix"] + f"map_fixture_{n:03}.lua", b"opaque") for n in range(176)]
        self.assertEqual(len(protected), 180)
        keep = [dict(row(name, b"fixed"), sha256=digest) for name,digest in tool.PRESERVED_RUNTIME_PINS.items()]
        self.before = manifest(protected + keep + [row(tool.MAP_TARGET, b"prior map")])

    def test_projection_replaces_only_exact_map_and_dependency_pins(self):
        targets = {tool.MAP_TARGET:pins(row(tool.MAP_TARGET,b"new map")),
                   "materials/overviews/template_map.vmat_c":pins(row("materials/overviews/template_map.vmat_c",b"overview"))}
        before = copy.deepcopy(self.before)
        after = tool.project(before,targets,self.policy)
        old = {r["path"]:r for r in before["files"]};new={r["path"]:r for r in after["files"]}
        self.assertEqual({name for name in new if old.get(name)!=new[name]},set(targets))
        self.assertEqual(after["file_count"],len(old)+1)
        self.assertEqual(before,self.before)
        for name in tool.PRESERVED_RUNTIME_PINS:self.assertEqual(old[name],new[name])

    def test_code_other_maps_traversal_and_unchanged_targets_are_rejected(self):
        good=pins(row(tool.MAP_TARGET,b"new map"))
        for name in ("scripts/vscripts/addon_game_mode.lua","panorama/scripts/custom_game/payment_test.vjs_c",
                     "maps/ws4_entry.vpk","maps/another.vpk","materials/../secret.vtex_c","C:/bad.vtex_c"):
            with self.subTest(name=name),self.assertRaises(ValueError):
                tool.project(self.before,{tool.MAP_TARGET:good,name:good},self.policy)
        with self.assertRaisesRegex(ValueError,"unchanged targets"):
            tool.project(self.before,{tool.MAP_TARGET:pins(next(r for r in self.before["files"] if r["path"]==tool.MAP_TARGET))},self.policy)

    def test_protected_qr_layout_and_entry_preimages_are_mandatory(self):
        targets={tool.MAP_TARGET:pins(row(tool.MAP_TARGET,b"new map"))}
        for name in tool.PRESERVED_RUNTIME_PINS:
            before=copy.deepcopy(self.before)
            next(r for r in before["files"] if r["path"]==name)["sha256"]="0"*64
            with self.subTest(name=name),self.assertRaisesRegex(ValueError,"entry/QR/layout"):
                tool.project(before,targets,self.policy)

    def test_streamed_payload_capture_detects_late_change_without_metadata_size_limit(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/"map.vpk"
            raw=b"compiled-map-data"*(1024*1024+1)
            path.write_bytes(raw)
            state={};tool.capture_payload(path,pins(row(tool.MAP_TARGET,raw)),state)
            self.assertGreater(path.stat().st_size,tool.pack.MAX_MANIFEST)
            tool.unchanged({},state)
            with path.open("ab") as out:out.write(b"drift")
            with self.assertRaisesRegex(ValueError,"payload changed"):tool.unchanged({},state)

    def test_unreviewed_build_is_closed_before_reading_any_private_key(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);base=root/"base";trusted=root/"review";vpk=root/"vpk"
            for path in (base,trusted,vpk):path.mkdir()
            values=dict(BASE=base,BASE_TRUSTED=trusted,BASE_VPK=vpk/"item.vpk",
                        OVERLAY=root/"overlay",TRUSTED=root/"trust-new",VIEW=root/"view",OUTPUT=root/"new-vpk")
            contexts=[patch.object(tool,name,value) for name,value in values.items()]
            for context in contexts:context.start();self.addCleanup(context.stop)
            (vpk/"item.vpk").write_bytes(b"placeholder")
            with patch.object(tool,"TARGET_PINS",{}),self.assertRaisesRegex(ValueError,"compile pins and archive plan"):
                tool.paths(root/"absent-private-key.pem",True)
            with self.assertRaisesRegex(ValueError,"only with --build"):
                tool.paths(root/"absent-private-key.pem",False)
            self.assertTrue(all(not path.exists() for path in (tool.OVERLAY,tool.TRUSTED,tool.VIEW,tool.OUTPUT)))


class MapRotationTests(unittest.TestCase):
    def test_overflow_moves_only_changed_map_and_rewrites_source_and_destination(self):
        before=manifest([row(tool.MAP_TARGET,b"m"*10),row("materials/a.vtex_c",b"a"*80),
                         row("materials/b.vtex_c",b"b"*90),row("materials/c.vtex_c",b"c"*90),row("materials/d.vtex_c",b"d"*10)])
        archive={tool.MAP_TARGET:0,"materials/a.vtex_c":0,"materials/b.vtex_c":1,"materials/c.vtex_c":2,"materials/d.vtex_c":3}
        entries=[dict(path=name,archive=index) for name,index in archive.items()]
        after=manifest([row(tool.MAP_TARGET,b"M"*30) if r["path"]==tool.MAP_TARGET else r for r in before["files"]])
        with patch.object(tool.pack,"ARCHIVE_BYTES",100):
            _,groups,changed,moves=tool.rotation_plan(entries,before,after,{tool.MAP_TARGET})
        self.assertEqual(changed,{0,3})
        self.assertEqual(moves,[dict(path=tool.MAP_TARGET,old_archive=0,new_archive=3,bytes=30)])
        placed={item["row"]["path"]:i for i,group in enumerate(groups) for item in group}
        for name,index in archive.items():self.assertEqual(placed[name],3 if name==tool.MAP_TARGET else index)

    def test_no_overflow_retains_assignments_and_new_assets_use_last_volume(self):
        before=manifest([row(tool.MAP_TARGET,b"map"),row("materials/a.vtex_c",b"a")])
        entries=[dict(path=tool.MAP_TARGET,archive=0),dict(path="materials/a.vtex_c",archive=1)]
        after=manifest([row(tool.MAP_TARGET,b"map2"),row("materials/a.vtex_c",b"a"),row("materials/new.vtex_c",b"new")])
        _,groups,changed,moves=tool.rotation_plan(entries,before,after,{tool.MAP_TARGET,"materials/new.vtex_c"})
        self.assertEqual(changed,{0,1});self.assertEqual(moves,[])
        self.assertEqual({item["row"]["path"] for item in groups[1]},{"materials/a.vtex_c","materials/new.vtex_c"})

    def test_overflow_does_not_rotate_unreviewed_assets_or_create_extra_volumes(self):
        before=manifest([row(tool.MAP_TARGET,b"m"*10),row("materials/a.vtex_c",b"a"*80),row("materials/b.vtex_c",b"b"*90)])
        entries=[dict(path=r["path"],archive=1 if r["path"]=="materials/b.vtex_c" else 0) for r in before["files"]]
        after=manifest([row(tool.MAP_TARGET,b"M"*30) if r["path"]==tool.MAP_TARGET else r for r in before["files"]])
        with patch.object(tool.pack,"ARCHIVE_BYTES",100),self.assertRaisesRegex(ValueError,"separate reviewed repack"):
            tool.rotation_plan(entries,before,after,{tool.MAP_TARGET})

    def test_deleted_files_or_wrong_changed_inventory_fail(self):
        before=manifest([row(tool.MAP_TARGET,b"map"),row("materials/a.vtex_c",b"a")])
        entries=[dict(path=r["path"],archive=i) for i,r in enumerate(before["files"])]
        with self.assertRaisesRegex(ValueError,"changed path set"):
            tool.rotation_plan(entries,before,manifest([row(tool.MAP_TARGET,b"new")]),{tool.MAP_TARGET})


class MapCompileEvidenceTests(unittest.TestCase):
    def proof(self):
        entries=[dict(path=f"maps/template_map/fixture_{i}.vmdl_c",bytes=1,sha256="1"*64,
                      expected_crc32=i,actual_crc32=i,crc_matches=True) for i in range(tool.MAP_CRC_ENTRIES)]
        entries[-1].update(path="maps/template_map.vmap_c",bytes=16)
        return dict(status="PASS",compiled_verified=True,runtime_verified=False,
            source=dict(bytes=tool.MAP_SOURCE_PIN["bytes"],sha256=tool.MAP_SOURCE_PIN["sha256"],
                        raw_crc32=tool.MAP_SOURCE_CRC,converted=False),
            package=dict(bytes=tool.TARGET_PINS[tool.MAP_TARGET]["bytes"],
                         sha256=tool.TARGET_PINS[tool.MAP_TARGET]["sha256"],version=2,
                         crc_entries=tool.MAP_CRC_ENTRIES,entries=entries),
            source_match=dict(source_name="maps/template_map.vmap",compiled_search_path="dota_addons/survival",
                              raw_source_crc32=tool.MAP_SOURCE_CRC,compiled_source_crc32=tool.MAP_SOURCE_CRC,matches=True),
            compiled_map=dict(path="maps/template_map.vmap_c",bytes=16,sha256="1"*64,dependency_block="RED2"))

    def test_map_package_and_source_crc_proof_binds_the_actual_compile(self):
        proof=self.proof()
        self.assertEqual(tool.verify_map_proof(json.dumps(proof).encode()),proof)
        cases=[("status","FAIL"),("compiled_verified",False),("source.sha256","0"*64),
               ("source.bytes",0),("source.raw_crc32",736803486),("source.converted",True),
               ("package.sha256","0"*64),("package.bytes",65143060),("package.version",1),
               ("package.crc_entries",306),("source_match.matches",False),
               ("source_match.compiled_source_crc32",736803486),("source_match.raw_source_crc32",0),
               ("source_match.source_name","maps/ws4_entry.vmap"),("source_match.compiled_search_path","another_addon"),
               ("compiled_map.path","maps/other.vmap_c"),("compiled_map.sha256",None),("compiled_map.dependency_block","REDI")]
        for field,value in cases:
            changed=copy.deepcopy(proof);parent=changed;parts=field.split(".")
            for name in parts[:-1]:parent=parent[name]
            parent[parts[-1]]=value
            with self.subTest(field=field),self.assertRaises(ValueError):
                tool.verify_map_proof(json.dumps(changed).encode())

    def test_entry_crc_count_duplicates_and_embedded_vmap_identity_are_required(self):
        for kind in ("crc_flag","crc_value","crc_boolean","duplicate","missing","vmap_sha","vmap_bytes"):
            proof=self.proof();entries=proof["package"]["entries"]
            if kind=="crc_flag":entries[0]["crc_matches"]=False
            elif kind=="crc_value":entries[0]["actual_crc32"]=100
            elif kind=="crc_boolean":entries[1]["actual_crc32"]=True
            elif kind=="duplicate":entries[0]["path"]=entries[1]["path"]
            elif kind=="missing":entries.pop()
            elif kind=="vmap_sha":entries[-1]["sha256"]="2"*64
            else:entries[-1]["bytes"]=17
            with self.subTest(kind=kind),self.assertRaises(ValueError):tool.verify_map_proof(json.dumps(proof).encode())

    def test_successful_log_and_the_pinned_report_bytes_are_both_required(self):
        raw=b"template_map.vmap template_map.vpk\nMap build finished.\nOK: 302 compiled, 0 failed, 1 skipped\n"
        tool.verify_compile_log(raw)
        for changed in (raw.replace(b"0 failed",b"1 failed"),raw.replace(b"Map build finished.",b""),raw.replace(b"template_map.vmap",b"other.vmap")):
            with self.assertRaisesRegex(ValueError,"successful actual Valve map compile"):
                tool.verify_compile_log(changed)
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/"proof.json";raw=json.dumps(self.proof()).encode();path.write_bytes(raw)
            digest=hashlib.sha256(raw).hexdigest();snapshots={}
            tool.verify_map_proof(tool.capture(path,snapshots,sha=digest))
            path.write_bytes(raw+b" ")
            with self.assertRaisesRegex(ValueError,"metadata hash differs"):tool.capture(path,{},sha=digest)
            with self.assertRaisesRegex(ValueError,"metadata changed|bounded read"):tool.unchanged(snapshots,{})


class RealMapMigrationTests(unittest.TestCase):
    def test_real_signed_roundtrip_keeps_unchanged_inodes_and_base_bytes(self):
        legacy=load("map2802_incremental_real_fixture",ROOT/"tools/arcade_cleanup_20261027/test_incremental_vpk.py")
        case=legacy.IncrementalVPKTests();case.setUp();self.addCleanup(case.doCleanups)
        entries=legacy.tool.read_entries(case.base_vpk);before=case.base_manifest
        placements={e["path"]:e["archive"] for e in entries};indices=sorted(set(placements.values()))
        sizes={i:sum(r["bytes"] for r in before["files"] if placements[r["path"]]==i) for i in indices}
        source=placements[tool.MAP_TARGET];last=indices[-1];limit=legacy.tool.pack.ARCHIVE_BYTES
        prior=next(r["bytes"] for r in before["files"] if r["path"]==tool.MAP_TARGET)
        amount=limit-sizes[source]+prior+1
        self.assertNotEqual(source,last);self.assertLessEqual(amount,limit-sizes[last])
        case.reseal({tool.MAP_TARGET:b"M"*amount})
        after,document,metadata=legacy.tool.metadata(case.overlay)
        policy,public=legacy.tool.pack.handoff.trusted_policy(legacy.tool.pack.handoff.POLICY)
        signature=legacy.tool.pack.verify_signed_snapshot(after,document,public,10,policy["integrity"]["trusted_key_id"])
        self.assertEqual(signature["release_sequence"],11)
        sources,changed=legacy.tool.validate_merged(case.fixture.candidate,case.overlay,before,after,case.fixture.source)
        with patch.object(tool.pack,"ARCHIVE_BYTES",limit):
            tree,groups,rewritten,moves=tool.rotation_plan(entries,before,after,changed)
        self.assertEqual(rewritten,{source,last});self.assertEqual(moves[0]["path"],tool.MAP_TARGET)
        legacy.tool.materialize(case.view,sources,changed,after,metadata)
        with legacy.tool.trusted_source(case.fixture.source):
            _,verified,_,_=legacy.tool.pack.authenticate(case.view)
        self.assertEqual(verified,after)
        with patch.object(tool.incremental,"ITEM","123456789"),patch.object(tool.pack,"ARCHIVE_BYTES",limit):
            verification,inventory=tool.incremental.build_volumes(case.view,case.output,case.base_vpk,tree,groups,rewritten,after,"hardlink")
        self.assertTrue(verification["manifest_dual_hashes_verified"])
        result=case.output/"123456789.vpk"
        self.assertEqual(inventory,tool.pack.package_inventory(result))
        for i in indices:
            self.assertEqual(os.path.samefile(case.output/f"123456789_{i:03}.vpk",case.base_vpk.with_name(f"123456789_{i:03}.vpk")),i not in rewritten)
        self.assertFalse(os.path.samefile(case.view/tool.MAP_TARGET,case.fixture.candidate/tool.MAP_TARGET))
        for name in sources:
            if name!=tool.MAP_TARGET:self.assertTrue(os.path.samefile(case.view/name,case.fixture.candidate/name))
        case.assert_base_unchanged()


if __name__ == "__main__":
    unittest.main()
