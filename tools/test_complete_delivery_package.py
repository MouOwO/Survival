"""Real VPK deletion/rotation tests; no real signing key, SDK, install or game."""
from copy import deepcopy
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys
import subprocess

sys.path.insert(0, str(Path(__file__).resolve().parent))
from complete_delivery_release_20261103 import package as m
from complete_delivery_release_20261103 import build_release as build, ledger
import test_complete_delivery_projection as projection_fixture


def fp(raw):
    return {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(),
            "md5": hashlib.md5(raw, usedforsecurity=False).hexdigest()}


def manifest(values):
    rows = [{"path": key, **fp(value)} for key, value in sorted(values.items())]
    result = {"schema": 2, "kind": "runtime_release_allowlist", "hash_algorithms": ["md5", "sha256"],
              "files": rows, "file_count": len(rows), "bytes": sum(row["bytes"] for row in rows)}
    result["content_sha256"] = ledger.sha(m.pack.runtime.manifest_payload(result))
    return result


def entries(values, assignments):
    return [{"path": name, "archive": assignments[name], "bytes": len(raw)} for name, raw in values.items()]


class RotationTests(unittest.TestCase):
    def test_delete_marks_original_volume_and_preserves_all_survivor_assignments(self):
        old = {"resource/a.txt": b"aaa", "resource/b.txt": b"bbb", "resource/c.txt": b"ccc"}
        new = {name: raw for name, raw in old.items() if name != "resource/a.txt"}
        plan = m.rotation_plan(entries(old, {"resource/a.txt": 0, "resource/b.txt": 0, "resource/c.txt": 1}),
                               manifest(old), manifest(new), set(), {"resource/a.txt"})
        self.assertEqual(plan["rewritten"], {0})
        self.assertEqual(plan["assignments"], {"resource/b.txt": 0, "resource/c.txt": 1})
        self.assertEqual(plan["moves"], [])

    def test_incorrect_delete_or_changed_set_is_rejected(self):
        old = {"resource/a.txt": b"a", "resource/b.txt": b"b"}
        new = {"resource/b.txt": b"B"}
        for changed, removed in [(set(), {"resource/a.txt"}), ({"resource/b.txt"}, set()),
                                  ({"resource/a.txt", "resource/b.txt"}, {"resource/a.txt"})]:
            with self.assertRaisesRegex(ValueError, "exact_reviewed"):
                m.rotation_plan(entries(old, dict.fromkeys(old, 0)), manifest(old), manifest(new), changed, removed)

    def test_growth_moves_only_changed_to_existing_free_archive(self):
        old = {"resource/a.txt": b"aa", "resource/b.txt": b"bbbbbbbb", "resource/c.txt": b"c"}
        new = {**old, "resource/a.txt": b"aaaaa"}
        with patch.object(m.pack, "ARCHIVE_BYTES", 10):
            plan = m.rotation_plan(entries(old, {"resource/a.txt": 0, "resource/b.txt": 0, "resource/c.txt": 1}),
                                   manifest(old), manifest(new), {"resource/a.txt"}, set())
        self.assertEqual(plan["assignments"]["resource/b.txt"], 0)
        self.assertEqual(plan["assignments"]["resource/c.txt"], 1)
        self.assertEqual(plan["assignments"]["resource/a.txt"], 1)
        self.assertEqual(plan["rewritten"], {0, 1})

    def test_append_volume_only_when_changed_items_need_it(self):
        old = {"resource/a.txt": b"aa", "resource/b.txt": b"bbbbbbbb", "resource/c.txt": b"ccccccccc"}
        new = {**old, "resource/a.txt": b"aaaaa"}
        with patch.object(m.pack, "ARCHIVE_BYTES", 10):
            plan = m.rotation_plan(entries(old, {"resource/a.txt": 0, "resource/b.txt": 0, "resource/c.txt": 1}),
                                   manifest(old), manifest(new), {"resource/a.txt"}, set())
            self.assertEqual(plan["assignments"]["resource/a.txt"], 2)
            with self.assertRaisesRegex(ValueError, "cannot_fit"):
                m.rotation_plan(entries(old, {"resource/a.txt": 0, "resource/b.txt": 0, "resource/c.txt": 1}),
                                manifest(old), manifest(new), {"resource/a.txt"}, set(), allow_new_volumes=False)

    def test_empty_policy_is_explicit_and_interior_volume_never_silently_dropped(self):
        old = {"resource/a.txt": b"a", "resource/b.txt": b"b"}
        assignments = {"resource/a.txt": 0, "resource/b.txt": 1}
        new = {"resource/a.txt": b"a"}
        with self.assertRaisesRegex(ValueError, "empty_volume"):
            m.rotation_plan(entries(old, assignments), manifest(old), manifest(new), set(), {"resource/b.txt"})
        plan = m.rotation_plan(entries(old, assignments), manifest(old), manifest(new), set(), {"resource/b.txt"},
                               empty_volume_policy="trim_trailing")
        self.assertEqual(plan["dropped_empty_archives"], [1])
        self.assertEqual(plan["rewritten"], {1})
        with self.assertRaisesRegex(ValueError, "empty_volume"):
            m.rotation_plan(entries(old, assignments), manifest(old), manifest({"resource/b.txt": b"b"}),
                            set(), {"resource/a.txt"}, empty_volume_policy="trim_trailing")

    def test_external_metadata_supports_total_larger_than_four_gib_without_allocating_payload(self):
        rows = [{"path": f"resource/{i}.bin", "bytes": 900 * 1024**2, "md5": "0"*32, "sha256": "0"*64}
                for i in range(5)]
        tree, ordered = m.external_tree(rows)
        self.assertTrue(tree)
        self.assertEqual(sum(item["row"]["bytes"] for item in ordered), 4500 * 1024**2)
        with self.assertRaisesRegex(ValueError, "native_sized"):
            m.external_tree([{**rows[0], "bytes": m.pack.ARCHIVE_BYTES + 1}])

    def test_actual_vpk_delete_update_reuse_and_exact_crc_hashes(self):
        old = {"resource/a.txt": b"AAA", "resource/b.txt": b"BBB", "resource/c.txt": b"CCC"}
        new = {"resource/b.txt": b"changed-B", "resource/c.txt": old["resource/c.txt"]}
        assignments = {"resource/a.txt": 0, "resource/b.txt": 0, "resource/c.txt": 1}
        with tempfile.TemporaryDirectory(prefix="complete-vpk-delete-") as directory:
            root = Path(directory).resolve(); old_view, new_view = root/"old", root/"new"
            for view, values in [(old_view, old), (new_view, new)]:
                for name, raw in values.items():
                    path = view/name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
            before, after = manifest(old), manifest(new)
            initial = m.rotation_plan(entries(old, assignments), before, before, set(), set())
            old_output = root/"base_vpk"
            with patch.object(m.pack.runtime, "verify", return_value={"ok": True}):
                m.inc.build_volumes(old_view, old_output, root/"unused.vpk", initial["tree"], initial["groups"],
                                    {0,1}, before, "copy")
                base = old_output/(m.ITEM+".vpk")
                base_inventory = m.pack.package_inventory(base)
                final = m.rotation_plan(m.inc.read_entries(base), before, after, {"resource/b.txt"}, {"resource/a.txt"})
                output = root/"new_vpk"
                verification, inventory = m.inc.build_volumes(new_view, output, base, final["tree"], final["groups"],
                                                               final["rewritten"], after, "copy")
            self.assertTrue(verification["manifest_dual_hashes_verified"])
            self.assertEqual({row["path"] for row in m.inc.read_entries(output/(m.ITEM+".vpk"))}, set(new))
            self.assertEqual(m.pack.package_inventory(base), base_inventory)
            self.assertEqual({path.name for path in output.iterdir()}, {row["name"] for row in inventory})
            self.assertEqual((output/(m.ITEM+"_001.vpk")).read_bytes(), old["resource/c.txt"])


class BoundaryTests(unittest.TestCase):
    def test_default_import_never_exposes_a_sign_or_upload_automatic_entry(self):
        self.assertFalse(hasattr(m, "main"))
        self.assertNotIn("PAYLOADS", vars(m))

    def test_unsigned_rederivation_rejects_tampering_and_never_signs(self):
        f = projection_fixture.fixture()
        f["parent"].update(schema=2, kind="runtime_release_allowlist", hash_algorithms=["md5", "sha256"])
        inputs = projection_fixture.inputs(f); projected = build.project(**inputs)
        target = build.projected_manifest(f["parent"], projected)
        values = {"scripts/vscripts/a.lua": b"new code", "panorama/scripts/a.vjs_c": b"official compiled",
                  "scripts/vscripts/protected.lua": b"protected source with exact values verified upstream",
                  "scripts/vscripts/identical.lua": b"same published bytes", "maps/template_map.vpk": b"unchanged real map"}
        with tempfile.TemporaryDirectory(prefix="complete-unsigned-proof-") as directory:
            root = Path(directory)
            for name, raw in values.items():
                path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
            manifest_raw=ledger.canonical(target);(root/build.MANIFEST).write_bytes(manifest_raw)
            marker={"projection_sha256":projected["projection_sha256"],"content_sha256":target["content_sha256"],
                    "source_revisions":projected["source_revisions"]}
            (root/build.MARKER).write_bytes(ledger.canonical(marker))
            report={**marker,"status":"UNSIGNED_COMPLETE_TREE_NOT_AUTHENTICATED_OR_PUBLISHABLE",
                    "candidate":str(root.resolve()),"parent_manifest_sha256":inputs["parent_sha256"],
                    "all_target_files_rehashed":True,"hardlinks_created":0,"signature_valid":False,
                    "publication_ready":False,"manifest_sha256":ledger.sha(manifest_raw)}
            kwargs=dict(inputs=inputs,reviewed_projection_raw=ledger.canonical(projected),
                        reviewed_projection_sha256=ledger.sha(ledger.canonical(projected)),unsigned_root=root.resolve(),
                        unsigned_review_raw=ledger.canonical(report),unsigned_review_sha256=ledger.sha(ledger.canonical(report)))
            with patch.object(m.pack.protect_data,"sign_manifest",side_effect=AssertionError("no real signing")) as signer:
                self.assertEqual(m.verify_unsigned(**kwargs)[2],target)
                (root/"scripts/vscripts/a.lua").write_bytes(b"tampered")
                with self.assertRaisesRegex(ValueError,"complete_tree_hash_mismatch"):
                    m.verify_unsigned(**kwargs)
                signer.assert_not_called()

    def test_missing_original_evidence_cannot_be_replaced_by_true_flags(self):
        with self.assertRaisesRegex(ValueError,"original_semantic_evidence"):
            m.verify_original_evidence({"all_verified":True},{},manifest({"resource/a":b"a"}),[])

    def test_actual_original_producer_is_distinct_from_collection_operator(self):
        pins={"game":"a"*40,"content":"b"*40,"operator":"c"*40}
        producer={**pins,"operator":"d"*40};target=manifest({"resource/a":b"a"})
        answer={"compiler":{"outputs":{}},"protection":{"protected_outputs":{},"production_overrides":{}},
                "item_generator":{"outputs":{}}}
        evidence={key:{"source_revisions":producer} for key in answer}
        with patch.object(m.ledger,"verify_compiler_receipt",return_value=answer["compiler"]), \
             patch.object(m.ledger,"verify_protection_receipt",return_value=answer["protection"]), \
             patch.object(m.ledger,"verify_item_generator_receipt",return_value=answer["item_generator"]):
            self.assertEqual(m.verify_original_evidence(evidence,pins,target,[]),answer)
            bad=deepcopy(evidence);bad["compiler"]["source_revisions"]={**producer,"game":"e"*40}
            with self.assertRaisesRegex(ValueError,"runtime_source"):
                m.verify_original_evidence(bad,pins,target,[])

    def test_two_real_compiler_receipt_interfaces_keep_original_results_and_reject_conflict(self):
        pins={"game":"a"*40,"content":"b"*40,"operator":"c"*40}
        producer={**pins,"operator":"d"*40}
        target=manifest({"resource/a":b"a","resource/b":b"b"})
        evidence={"compiler":[{"source_revisions":producer,"proof_sha256":"1"*64},
                              {"source_revisions":producer,"proof_sha256":"2"*64}],
                  "protection":{"source_revisions":producer},"item_generator":{"source_revisions":producer}}
        first={"outputs":{"resource/a":fp(b"a")},"proof_sha256":"1"*64}
        second={"outputs":{"resource/b":fp(b"b")},"proof_sha256":"2"*64}
        with patch.object(m.ledger,"verify_compiler_receipt",side_effect=[first,second]) as verify, \
             patch.object(m.ledger,"verify_protection_receipt",return_value={"protected_outputs":{},"production_overrides":{}}), \
             patch.object(m.ledger,"verify_item_generator_receipt",return_value={"outputs":{}}):
            result=m.verify_original_evidence(evidence,pins,target,[],source_raw={"game:resource/a":b"a","game:resource/b":b"b"})
            self.assertEqual(verify.call_count,2)
            self.assertEqual(result["compiler"]["original_receipts"],[first,second])
            self.assertEqual(set(result["compiler"]["outputs"]),{"resource/a","resource/b"})
        with patch.object(m.ledger,"verify_compiler_receipt",side_effect=[first,{"outputs":{"resource/a":fp(b"wrong")}}]):
            with self.assertRaisesRegex(ValueError,"compiler_receipts_conflict"):
                m.verify_original_evidence(evidence,pins,target,[])

    def test_empty_or_unbounded_compiler_receipt_list_never_verifies_a_summary(self):
        for value in ([],[{}]*33,[True]):
            with self.assertRaisesRegex(ValueError,"original_compiler_receipt_list"):
                m.compiler_entries(value)

    def test_fresh_compiler_output_must_also_exist_as_exact_target_git_resource(self):
        pins={"game":"a"*40,"content":"b"*40,"operator":"c"*40}
        origins={**pins,"operator":"d"*40};name="panorama/scripts/a.vjs_c";raw=b"actual official output"
        proof={"outputs":{name:fp(raw)}};target=manifest({name:raw})
        evidence={key:{"source_revisions":origins} for key in ("compiler","protection","item_generator")}
        with patch.object(m.ledger,"verify_compiler_receipt",return_value=proof), \
             patch.object(m.ledger,"verify_protection_receipt",return_value={"protected_outputs":{},"production_overrides":{}}), \
             patch.object(m.ledger,"verify_item_generator_receipt",return_value={"outputs":{}}):
            for source in (None,{}, {"game:"+name:b"old committed output"}):
                with self.subTest(source=source),self.assertRaisesRegex(ValueError,"not_committed_target_git_resource"):
                    m.verify_original_evidence(evidence,pins,target,[],source_raw=source)
            result=m.verify_original_evidence(evidence,pins,target,[],source_raw={"game:"+name:raw})
            self.assertEqual(result["target_git_compiled_outputs"][name],{"target_commit":pins["game"],"output":fp(raw)})

    def test_changed_loaded_operator_is_rejected_before_key_use(self):
        with patch.object(m.pending,"_git",return_value=b"not the imported operator"), \
             patch.object(m.pack.protect_data,"sign_manifest",side_effect=AssertionError("no key")) as sign:
            with self.assertRaisesRegex(ValueError,"loaded_package_operator_not_exact"):
                m.verify_operator("a"*40)
            sign.assert_not_called()

    def test_dual_git_batch_checks_actual_objects_and_resolved_lfs_without_checkout_fallback(self):
        pins={"game":"a"*40,"content":"b"*40,"operator":"c"*40}
        value=b"exact resolved source";digest=hashlib.sha256(value).hexdigest()
        pointer=(f"version https://git-lfs.github.com/spec/v1\noid sha256:{digest}\nsize {len(value)}\n").encode()
        oid=hashlib.sha1(b"blob "+str(len(pointer)).encode()+b"\0"+pointer).hexdigest()
        key="game:panorama/images/a.vtex_c"
        facts={key:{"commit":pins["game"],"git_oid":oid,**fp(value),"lfs":True,"lfs_content_verified":True}}
        batch=oid.encode()+b" blob "+str(len(pointer)).encode()+b"\n"+pointer+b"\n"
        with patch.object(m.subprocess,"run",return_value=subprocess.CompletedProcess([],0,batch,b"")) as run:
            self.assertEqual(m._git_sources(pins,{key:value},facts),{key:digest})
            self.assertEqual(run.call_count,1)
            self.assertIn(b"a"*40+b":panorama/images/a.vtex_c",run.call_args.kwargs["input"])
            with self.assertRaisesRegex(ValueError,"resolved_lfs_source_proof"):
                m._git_sources(pins,{key:value+b"changed"},facts)
            bad=deepcopy(facts);bad[key]["git_oid"]="0"*40
            with self.assertRaisesRegex(ValueError,"immutable_git_object"):
                m._git_sources(pins,{key:value},bad)

    def test_lobby_admission_keeps_five_accounts_four_players_https_and_restores_old_validator(self):
        approved=["7656119800000000"+str(i) for i in range(1,6)]
        main,client=b"reviewed server lobby and native handoff",b"reviewed lobby init, original entry suffix"
        info={"addoninfo":{"maps":"ws4_entry","isplayable":"1","enablepickrules":"0",
                           "ws4_entry":{"maxplayers":"4"},"template_map":{"maxplayers":"4"},
                           "ws4_lobby":{"maxplayers":"1"}}}
        with tempfile.TemporaryDirectory(prefix="complete-lobby-policy-") as directory:
            root=Path(directory).resolve()
            content={"scripts/vscripts/addon_game_mode.lua":main,"scripts/vscripts/addon_game_mode_client.lua":client,
                     "scripts/vscripts/config/release_profile.lua":b'return {channel="production",native_cloud_roster_required=true}',
                     "scripts/vscripts/config/player_web_auth.lua":b'return {enabled=true,base_url="https://pay.xiaofengnet.com/ws4-web"}',
                     "scripts/vscripts/config/session_multiplayer_test.lua":b'return {enabled=false,expected_map="template_map"}',
                     "scripts/vscripts/config/commerce_payment_access.lua":b'return {enabled=true,connection_helper=false,expected_map="template_map",base_url="https://pay.xiaofengnet.com/ws4-web"}',
                     "scripts/vscripts/config/test_access.lua":('return {enabled=true,allowed_steamids={'+','.join('"'+v+'"' for v in approved)+'}}').encode(),
                     "maps/ws4_entry.vpk":b"entry","maps/template_map.vpk":b"gameplay"}
            for name,raw in content.items():
                path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
            original=m.pack.handoff.require_native_cloud_entry
            with m.admission_adapter(root,approved,info,client,main,set()):
                m.pack.handoff.require_native_cloud_entry(root,info)
                bad=deepcopy(info);bad["addoninfo"]["ws4_entry"]["maxplayers"]="5"
                with self.assertRaisesRegex(ValueError,"entry4_template4"):
                    m.pack.handoff.require_native_cloud_entry(root,bad)
                path=root/"scripts/vscripts/config/player_web_auth.lua"
                path.write_bytes(content["scripts/vscripts/config/player_web_auth.lua"].replace(b"https:",b"http:"))
                with self.assertRaisesRegex(ValueError,"https_auth_origin"):
                    m.pack.handoff.require_native_cloud_entry(root,info)
            self.assertIs(m.pack.handoff.require_native_cloud_entry,original)


if __name__ == "__main__":
    unittest.main()
