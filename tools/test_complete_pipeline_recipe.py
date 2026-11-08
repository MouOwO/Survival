"""Security boundaries of the complete canonical recipe (no SDK/sign/key)."""
from __future__ import annotations
import ast
from collections import Counter
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from complete_delivery_release_20261103 import pipeline_recipe as r, publication_validator as v, ledger

G, C, OP, COLLECTOR = "1"*40, "2"*40, "3"*40, "4"*40
PINS = {"game": G, "content": C}


class RecipeTests(unittest.TestCase):
    def test_prior_candidate_controls_are_rejected_before_any_source_or_package_read(self):
        from complete_delivery_release_20261103 import build_release, production_plan
        self.assertEqual(r.SEQUENCE,2026110804)
        self.assertEqual((build_release.SEQUENCE,production_plan.SEQUENCE),(r.SEQUENCE,r.SEQUENCE))
        self.assertEqual(build_release.REPORT,r.REPORT)
        for previous in ("complete_delivery_release_20261103", "complete_delivery_release_20261103_v02",
                         "complete_delivery_release_20261103_v03", "complete_delivery_release_20261105_v01",
                         "complete_delivery_release_20261105_v02", "complete_delivery_release_20261105_v03",
                         "complete_delivery_release_20261106_v01", "complete_delivery_release_20261106_v02",
                         "complete_delivery_release_20261106_v03", "complete_delivery_release_20261106_v04", "complete_delivery_release_20261107_v01", "complete_delivery_release_20261107_v02", "complete_delivery_release_20261107_v03", "complete_delivery_release_20261107_v04", "complete_delivery_release_20261107_v05", "complete_delivery_release_20261108_v01", "complete_delivery_release_20261108_v02"):
            with self.subTest(previous=previous), patch.object(r,"context") as context:
                with self.assertRaisesRegex(ValueError,"fixed_canonical_report_directory_required"):
                    r.main(["--source-revision",G,"--content-source-revision",C,
                            "--operator-revision",OP,"--report",str(r.ROOT/"output"/previous)])
                context.assert_not_called()

    def dependencies(self, collect=None):
        return SimpleNamespace(ledger=ledger, build=SimpleNamespace(MAX_DOCUMENT=16*1024*1024,
            _plain=lambda p, **kw: Path(p).resolve()),
            package=SimpleNamespace(verify_operator=lambda op: None),
            collect=SimpleNamespace(collect=collect or (lambda req: self.collection())))

    def configuration(self):
        return {"source_revisions": PINS, "package_operator_revision": OP,
            "collection_request": {"path":"request", "sha256":"a"*64},
            "projection": {"path":"projection", "sha256":"b"*64},
            "baseline_package": {"path":"baseline", "sha256":"c"*64},
            "unsigned_review": {"path":"unsigned-review", "sha256":"d"*64},
            "parent_root":"/parent", "parent_vpk":"/parent-pkg/3824360109.vpk",
            "unsigned_root":"/unsigned", "candidate":{k:"/external/"+k for k in ("view","trusted","output","overlay")}}

    def collection(self):
        return {"status":"COMPLETE_IMMUTABLE_INPUTS_COLLECTED_NOT_SIGNED", "diagnostic_only":False,
            "blockers":[], "projection_raw":b"projection", "projection": {"source_revisions":{**PINS,"operator":COLLECTOR}},
            "inputs":{}, "source_raw":{}, "source_facts":{}, "semantic_evidence":{"producer_operator":G}}

    def controls(self, request=None):
        req = request or {"source_revisions":{**PINS,"operator":COLLECTOR}}
        return {"request":(req,b"request"),"projection":({},b"projection"),
                "baseline":({},b"baseline"),"unsigned-review":({},b"unsigned-review")}

    def context_with(self, request=None, collect=None, operator=OP):
        cfg=self.configuration()
        with patch.object(r,"dependencies",return_value=self.dependencies(collect)), \
             patch.object(r,"config",return_value=(cfg,b"config")), \
             patch.object(r,"verify_facade_operator",return_value={"verified":True}), \
             patch.object(r,"checked_json",side_effect=lambda spec, **kw:self.controls(request)[spec["path"]]):
            return r.context(operator)

    def test_collection_and_package_operators_remain_distinct(self):
        ctx=self.context_with()
        self.assertEqual(ctx.operator_revision,OP)
        self.assertEqual(ctx.collection_request["source_revisions"]["operator"],COLLECTOR)
        self.assertEqual(ctx.semantic_evidence,{"producer_operator":G})

    def test_diagnostic_collection_rejected_before_collector(self):
        calls=[]
        with self.assertRaisesRegex(ValueError,"diagnostic_collection"):
            self.context_with({"source_revisions":{**PINS,"operator":COLLECTOR},
                "allow_uncommitted_collector_diagnostic":True}, lambda req:calls.append(req))
        self.assertEqual(calls,[])

    def test_runtime_source_substitution_rejected(self):
        with self.assertRaisesRegex(ValueError,"runtime_source_mismatch"):
            self.context_with({"source_revisions":{"game":"9"*40,"content":C,"operator":COLLECTOR}})

    def test_package_operator_substitution_rejected(self):
        with self.assertRaisesRegex(ValueError,"package_operator_mismatch"):
            self.context_with(operator="9"*40)

    def test_collector_failed_status_cannot_reach_signing(self):
        with self.assertRaisesRegex(ValueError,"strict_collection_required"):
            self.context_with(collect=lambda req:{**self.collection(),"blockers":["unbound_resource"]})

    def test_recomputed_projection_must_equal_exact_reviewed_bytes(self):
        with self.assertRaisesRegex(ValueError,"reviewed_projection"):
            self.context_with(collect=lambda req:{**self.collection(),"projection_raw":b"changed"})

    def test_changed_raw_control_pin_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/"control.json";p.write_bytes(b'{"value":1}\n')
            with patch.object(r,"dependencies",return_value=self.dependencies()):
                with self.assertRaisesRegex(ValueError,"pin_changed"):
                    r.checked_json({"path":str(p),"sha256":"0"*64})

    def test_parent_journal_must_be_successful_exact_package(self):
        report={"package_files":[{"name":"x","sha256":"a"*64}],"vpk_sha256":"b"*64}
        good=dict(uploaded=True,status="SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST",
            workshop_id=r.ITEM,owner=r.OWNER,app_id=r.APP,visibility_requested=3,
            release_sequence=r.BASE_SEQUENCE,content_sha256=r.BASE_CONTENT,
            package_files=report["package_files"],vpk_sha256=report["vpk_sha256"],legal_agreement_required=False)
        r.require_parent_journal(good,report)
        for key,value in (("uploaded",False),("content_sha256","c"*64),("release_sequence",2026110301),
                          ("package_files",[]),("legal_agreement_required",True)):
            with self.subTest(key=key),self.assertRaisesRegex(ValueError,"canonical_journal"):
                r.require_parent_journal({**good,key:value},report)

    def test_operator_closure_uses_one_batch_and_checks_actual_executed_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); (root/"tools").mkdir()
            raw=b"x = 1\r\n"; gitraw=b"x = 1\n"
            (root/"tools/a.py").write_bytes(raw)
            pin=hashlib.sha256(gitraw).hexdigest()
            oid=hashlib.sha1(b"blob "+str(len(gitraw)).encode()+b"\0"+gitraw).hexdigest()
            answer=oid.encode()+b" blob "+str(len(gitraw)).encode()+b"\n"+gitraw+b"\n"
            dep=self.dependencies()
            with patch.object(r,"ROOT",root),patch.object(r,"dependencies",return_value=dep), \
                 patch.object(subprocess,"run",return_value=SimpleNamespace(returncode=0,stdout=answer)) as run:
                proof=r.verify_operator_paths({"tools/a.py":pin},OP)
                self.assertEqual(proof["git_batch_calls"],1)
                self.assertEqual(proof["bindings"]["tools/a.py"]["git_oid"],oid)
                self.assertEqual(run.call_count,1)
                (root/"tools/a.py").write_bytes(b"x = 2\n")
                with self.assertRaisesRegex(ValueError,"changed_after_execution"):
                    r.verify_operator_paths({"tools/a.py":pin},OP)

    def test_operator_closure_rejects_changed_git_even_matching_worktree(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/"tools").mkdir(); raw=b"current\n";(root/"tools/a.py").write_bytes(raw)
            old=b"previous\n"; answer=b"0"*40+b" blob "+str(len(old)).encode()+b"\n"+old+b"\n"
            with patch.object(r,"ROOT",root),patch.object(r,"dependencies",return_value=self.dependencies()), \
                 patch.object(subprocess,"run",return_value=SimpleNamespace(returncode=0,stdout=answer)):
                with self.assertRaisesRegex(ValueError,"not_declared_commit"):
                    r.verify_operator_paths({"tools/a.py":hashlib.sha256(raw).hexdigest()},OP)

    def test_operator_batch_budget_allows_exact_lf_crlf_normalization(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/"tools").mkdir();raw=b"x = 1\n"*1000
            (root/"tools/a.py").write_bytes(raw)
            gitraw=raw.replace(b"\n",b"\r\n")
            answer=b"0"*40+b" blob "+str(len(gitraw)).encode()+b"\n"+gitraw+b"\n"
            with patch.object(r,"ROOT",root),patch.object(r,"dependencies",return_value=self.dependencies()), \
                 patch.object(subprocess,"run",return_value=SimpleNamespace(returncode=0,stdout=answer)):
                value=r.verify_operator_paths({"tools/a.py":hashlib.sha256(raw).hexdigest()},OP)
                self.assertEqual(value["files"],1)

    def test_origins_keep_untouched_parent_and_remove_deleted_resource(self):
        parent={"files":[{"path":name} for name in ("a.lua","b.lua","c.lua")],"content_sha256":"5"*64}
        raw=r.canonical(parent)
        original={name:{"kind":"FROZEN_SIGNED_RESOURCE","resource_sha256":str(n)*64}
                  for n,name in enumerate(("a.lua","b.lua","c.lua"),1)}
        snap={"parent_manifest_sha256":r.sha(raw),"parent_content_sha256":parent["content_sha256"],
              "resource_origins":original,"resource_origins_sha256":r.sha(r.canonical(original))}
        bindings=[{"resource":name,"kind":"identity","sources":["game:"+name],"output":{"sha256":"7"*64,"bytes":12}}
                  for name in ("a.lua","d.lua")]
        ctx=SimpleNamespace(inputs={"parent_raw":raw,"parent_sha256":r.sha(raw)},config={"source_revisions":PINS},
            projection={"coverage_ledger":{"resource_bindings":bindings},"source_revisions":{**PINS,"operator":COLLECTOR},
                        "projection_sha256":"6"*64,"removed_runtime_paths":["b.lua"],
                        "changed_runtime_paths":["a.lua","d.lua"],"projected_rows":[{"path":n} for n in ("a.lua","c.lua","d.lua")]})
        dep=SimpleNamespace(ledger=ledger,package=SimpleNamespace(pending=SimpleNamespace(
            BASELINE="fixed",BASELINE_SHA256="fixed_sha",_read_json=lambda *args:snap)))
        with patch.object(r,"dependencies",return_value=dep):
            origins,old_sha,new_sha=r.resource_origins(ctx)
        self.assertEqual(set(origins),{"a.lua","c.lua","d.lua"})
        self.assertEqual(origins["c.lua"],original["c.lua"])
        self.assertEqual(set(original),{"a.lua","b.lua","c.lua"})
        self.assertEqual(origins["d.lua"]["binding"],bindings[1])
        self.assertEqual(origins["d.lua"]["resource_sha256"],"7"*64)
        self.assertEqual(origins["a.lua"]["collection_operator_revision"],COLLECTOR)
        self.assertEqual(old_sha,snap["resource_origins_sha256"])
        self.assertEqual(new_sha,r.sha(r.canonical(origins)))

    def test_report_scope_and_counts_cannot_shrink_native_acceptance(self):
        cfg=self.configuration()
        ctx=SimpleNamespace(config=cfg,operator_revision=OP,view=Path("/external/view"),
            trusted=Path("/external/trusted"),output=Path("/external/output"),
            inputs={"scope_sha256":"1"*64,"facts_sha256":"2"*64,"parent_sha256":"3"*64},
            projection={"changed_runtime_paths":["a.lua","b.lua"],"removed_runtime_paths":["old.lua"]})
        target={"file_count":7031,"bytes":3806249954,"content_sha256":"4"*64}
        good=dict(workshop_id=r.ITEM,app_id=r.APP,owner=r.OWNER,candidate=str(ctx.view),trusted_source=str(ctx.trusted),
            output=str(ctx.output/(r.ITEM+".vpk")),full_runtime_validator_passed=True,
            changed_runtime_paths=["a.lua","b.lua"],removed_runtime_paths=["old.lua"],
            files=7031,payload_bytes=3806249954,content_sha256="4"*64,manifest_sha256=r.sha(r.canonical(target)),
            source_revision=G,package_operator_revision=OP,scope_sha256="1"*64,facts_sha256="2"*64,
            unsigned_review_sha256=cfg["unsigned_review"]["sha256"],baseline_package_sha256=cfg["baseline_package"]["sha256"],
            authenticated_parent_manifest_sha256="3"*64,authenticated_parent_content_sha256=r.BASE_CONTENT)
        r.verify_report_projection(good,ctx,target)
        for key,value in (("changed_runtime_paths",["a.lua"]),("removed_runtime_paths",[]),
                          ("files",1),("payload_bytes",1),("content_sha256","0"*64),("source_revision",OP)):
            with self.subTest(field=key),self.assertRaisesRegex(ValueError,"projection_field_changed:"+key):
                r.verify_report_projection({**good,key:value},ctx,target)

    def test_external_trusted_sources_must_match_operator_key_and_immutable_gate(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/"operator";trusted=Path(temp)/"trusted";trusted.mkdir()
            files={"scripts/vscripts/reviewed_gate.lua":b"immutable_gate\n",
                "tools/release_security/protection_policy.json":b'{"trusted":"production"}\n',
                "tools/release_security/trusted_public_key.pem":b"reviewed_public_key\n"}
            for name,raw in files.items():
                path=trusted/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
                if name.startswith("tools/"):
                    op=root/name;op.parent.mkdir(parents=True,exist_ok=True);op.write_bytes(raw)
            (trusted/"package_transcript.json").write_bytes(b"{}\n")
            dep=self.dependencies()
            dep.package.inc=SimpleNamespace(all_files=lambda p:{x.relative_to(p).as_posix() for x in p.rglob("*") if x.is_file()})
            expected={"scripts/vscripts/reviewed_gate.lua":files["scripts/vscripts/reviewed_gate.lua"]}
            with patch.object(r,"ROOT",root),patch.object(r,"dependencies",return_value=dep):
                ctx=SimpleNamespace(trusted=trusted)
                r.verify_trusted_sources(ctx,expected)
                for name,raw in files.items():
                    with self.subTest(file=name):
                        (trusted/name).write_bytes(b"different_trust_or_gate\n")
                        with self.assertRaisesRegex(ValueError,"not_exact_reviewed"):
                            r.verify_trusted_sources(ctx,expected)
                        (trusted/name).write_bytes(raw)
                (trusted/"old_file.lua").write_bytes(b"old\n")
                with self.assertRaisesRegex(ValueError,"exact_file_set"):
                    r.verify_trusted_sources(ctx,expected)


class ValidatorTests(unittest.TestCase):
    def test_exact_online_test_authorization_cannot_move_to_other_package_or_native_pass(self):
        policy = dict(schema=1, kind="EXPLICIT_CURRENT_USER_UNLISTED_ONLINE_TEST_AUTHORIZATION",
            user_authorization="授权按线上测试版先上传，实机验收待测",
            authorization_scope="UPLOAD_THIS_EXACT_SIGNED_PACKAGE_AND_VERIFY_OFFICIAL_DOWNLOAD",
            workshop_id=r.ITEM, visibility="unlisted", release_sequence=2026110804,
            ordinary_production_acceptance=False, native_acceptance_status="PENDING_USER_ONLINE_TEST",
            source_revisions=PINS, signed_manifest_sha256="5"*64, content_sha256="7"*64,
            report_sha256="c"*64, parent_journal_sha256="d"*64, generation=1)
        request = {**policy, "publication_mode":v.ONLINE_TEST_MODE}
        report = {key:policy[key] for key in ("release_sequence","source_revisions","signed_manifest_sha256","content_sha256")}
        v.validate_online_test_document(policy,request,report)
        for key,bad in (("visibility","public"),("release_sequence",2026110803),
                        ("ordinary_production_acceptance",True),("native_acceptance_status","PASS"),
                        ("report_sha256","0"*64),("parent_journal_sha256","0"*64),
                        ("generation",2),("user_authorization","historical approval")):
            with self.subTest(key=key),self.assertRaises(ValueError):
                v.validate_online_test_document({**policy,key:bad},request,report)
        with self.assertRaises(ValueError):
            v.validate_online_test_document(policy,{**request,"production_evidence_path":"fake"},report)

    def test_test_mode_result_preserves_native_pending(self):
        with tempfile.TemporaryDirectory() as temp,self.mocked(temp,{}) as (report,request,load,journal):
            request["publication_mode"] = v.ONLINE_TEST_MODE
            with patch.object(v,"online_test_admission",return_value=dict(
                    ordinary_production_acceptance=False,online_test_release_authorized=True,
                    publication_mode=v.ONLINE_TEST_MODE)),patch.object(v,"_native_policy") as native:
                result=v.validate_release(request)
            self.assertFalse(result["ordinary_production_acceptance"])
            self.assertTrue(result["online_test_release_authorized"])
            native.assert_not_called()

    def fixture(self, temp):
        root=Path(temp);journal=root/"journal.json";cfgpath=root/"pipeline_inputs.json"
        journal.write_bytes(b'{"published":true}\n'); cfgpath.write_bytes(b"config")
        report={"operator_revision":OP, "pipeline_inputs_sha256":r.sha(b"config"),"source_revisions":PINS,
            "signed_manifest_sha256":"5"*64,"plan_sha256":"6"*64, "plan_path":str(root/"plan.json"),
            "release_sequence":r.SEQUENCE,"content_sha256":"7"*64,
            "authenticated_parent_content_sha256":"8"*64,"authenticated_parent_manifest_sha256":"9"*64,
            "parent_resource_origins_sha256":"a"*64,"resource_origins_sha256":"b"*64}
        request={"release_sequence":r.SEQUENCE,"generation":1,"parent_journal_sha256":r.sha(journal.read_bytes()),
            "signed_manifest_sha256":report["signed_manifest_sha256"],"report_sha256":"c"*64,
            "plan_sha256":report["plan_sha256"],"source_revisions":PINS}
        manifest={"content_sha256":report["content_sha256"]}; signed={"release_sequence":r.SEQUENCE}
        cfg={"candidate":{"output":str(root/"package")}}
        return journal,cfgpath,report,request,manifest,signed,cfg

    @contextmanager
    def mocked(self,temp,evidence):
        journal,cfgpath,report,request,manifest,signed,cfg=self.fixture(temp)
        with patch.object(r,"JOURNAL",journal),patch.object(r,"INPUT_FILE",cfgpath), \
             patch.object(r,"dependencies",return_value=SimpleNamespace(ledger=ledger)), \
             patch.object(r,"load_package",return_value=(report,manifest,signed)) as load, \
             patch.object(r,"config",return_value=(cfg,b"config")), \
             patch.object(r,"baseline",return_value=({},{})),patch.object(r,"require_parent_journal"), \
             patch.object(v,"_operator_file"),patch.object(v,"_native_policy",return_value=SimpleNamespace(
                validate_native_release=lambda *args:evidence)):
            yield report,request,load,journal

    def test_missing_real_native_acceptance_cannot_grant_release(self):
        with tempfile.TemporaryDirectory() as temp,self.mocked(temp,{}) as (report,request,load,journal):
            with self.assertRaisesRegex(ValueError,"same_signed_ordinary"):
                v.validate_release(request)
            load.assert_called_once_with(request["report_sha256"],full=True)

    def test_native_evidence_for_other_candidate_rejected(self):
        with tempfile.TemporaryDirectory() as temp,self.mocked(temp,
             {"ordinary_production_acceptance":True,"content_sha256":"0"*64}) as (report,request,load,journal):
            with self.assertRaisesRegex(ValueError,"same_signed_ordinary"):
                v.validate_release(request)

    def test_native_success_returns_only_dual_runtime_source_tuple_to_guard(self):
        with tempfile.TemporaryDirectory() as temp,self.mocked(temp,
             {"ordinary_production_acceptance":True,"content_sha256":"7"*64}) as (report,request,load,journal):
            actual=v.validate_release(request)
            self.assertEqual(actual["source_revisions"],PINS)
            self.assertEqual(actual["operator_revision"],OP)
            self.assertTrue(actual["ordinary_production_acceptance"])

    def test_native_ready_cannot_override_wrong_request_source(self):
        with tempfile.TemporaryDirectory() as temp,self.mocked(temp,
             {"ordinary_production_acceptance":True,"content_sha256":"7"*64}) as (report,request,load,journal):
            request["source_revisions"]={**PINS,"operator":OP}
            with self.assertRaisesRegex(ValueError,"source_and_package_binding"):
                v.validate_release(request)


class RealSdkAdmissionContextTests(unittest.TestCase):
    def test_private_builder_and_actual_sdk_pack_restore_after_failure(self):
        try:
            import cryptography
        except ImportError:
            self.skipTest("actual signing environment provides cryptography")
        d=r.dependencies()
        actual=__import__("stream_workshop_vpk")
        apis=(d.package.pack,actual)
        saved=[(api.handoff.ROOT,api.handoff.steamids,api.handoff.require_native_cloud_entry,
                api.runtime.SCENE_MAPS) for api in apis]
        approved=[str(76561190000000000+n) for n in range(5)]
        with tempfile.TemporaryDirectory() as temp:
            ctx=SimpleNamespace(trusted=Path(temp))
            values=(approved,{"addoninfo":{}},b"reviewed_client",b"reviewed_main",{"maps/actual_scene.vpk"},{})
            with patch.object(r,"_admission_values",return_value=values),patch.object(r,"controls_unchanged"), \
                 patch.object(r,"verify_trusted_sources"):
                with self.assertRaisesRegex(RuntimeError,"sdk_probe_failure"):
                    with r.scene_maps(ctx):
                        for api in apis:
                            self.assertEqual(api.handoff.ROOT,ctx.trusted)
                            self.assertEqual(api.handoff.steamids(approved),approved)
                            self.assertEqual(api.runtime.SCENE_MAPS,{"maps/actual_scene.vpk"})
                            with self.assertRaisesRegex(ValueError,"original_five_accounts"):
                                api.handoff.steamids(approved[:4])
                        raise RuntimeError("sdk_probe_failure")
        for api,old in zip(apis,saved):
            self.assertEqual((api.handoff.ROOT,api.handoff.steamids,api.handoff.require_native_cloud_entry,
                              api.runtime.SCENE_MAPS),old)


class ActualGitPinIntegrationTests(unittest.TestCase):
    """Use the real repository/Git reader; no returned Git bytes are mocked."""
    @classmethod
    def setUpClass(cls):
        try:
            import cryptography
        except ImportError:
            raise unittest.SkipTest("actual signing environment provides cryptography")
        cls.d=r.dependencies()
        cls.head=cls.d.package.pending._git(r.ROOT,"rev-parse","HEAD",counts=Counter()).decode().strip()

    def test_actual_publication_operator_pin_and_tampered_bytes(self):
        name="tools/release_pending_inventory.py"
        physical=(r.ROOT/name).read_bytes()
        declared=self.d.package.pending._git(r.ROOT,"show",self.head+":"+name,counts=Counter())
        self.assertEqual(v._operator_file(name,physical,self.head),r.sha(declared))
        with self.assertRaisesRegex(ValueError,"not_in_declared_operator"):
            v._operator_file(name,physical+b"\n# changed",self.head)

    def test_actual_facade_pin_passes_only_when_committed_bytes_match(self):
        physical=Path(r.__file__).read_bytes().replace(b"\r\n",b"\n")
        declared=self.d.package.pending._git(r.ROOT,"show",self.head+":"+r.TOOL,counts=Counter())
        if declared.replace(b"\r\n",b"\n")==physical:
            proof=r.verify_facade_operator(self.head)
            self.assertEqual(proof["git_sha256"],r.sha(declared))
        else:
            with self.assertRaisesRegex(ValueError,"recipe_not_in_immutable_package_operator"):
                r.verify_facade_operator(self.head)

    def test_actual_package_operator_reader_reaches_source_identity_check(self):
        module=self.d.package
        committed=self.d.package.pending._git(r.ROOT,"show",self.head+":"+module.TOOL,counts=Counter())
        if committed.replace(b"\r\n",b"\n")==Path(module.__file__).read_bytes().replace(b"\r\n",b"\n"):
            proof=module.verify_operator(self.head)
            self.assertTrue(proof)
            self.assertEqual({row["revision"] for row in proof},{self.head})
        else:
            with self.assertRaisesRegex(ValueError,"loaded_package_operator_not_exact_commit"):
                module.verify_operator(self.head)

    def test_actual_original_producer_tools_are_bound_to_git(self):
        name="tools/release_pending_inventory.py"
        raw=(r.ROOT/name).read_bytes()
        proof={"source_revisions":{"operator":self.head},"operator_tools":{name:raw}}
        evidence={"compiler":[proof],"protection":proof,
                  "item_generator":{"source_revisions":{"operator":self.head},"operator_bytes":{name:raw}}}
        actual=self.d.package.verify_producer_operators(evidence)
        self.assertEqual(len(actual),3)
        self.assertEqual({row["revision"] for row in actual},{self.head})
        bad={**evidence,"compiler":[{**proof,"operator_tools":{name:raw+b"\n# changed"}}]}
        with self.assertRaisesRegex(ValueError,"original_producer_operator_bytes_not_git_commit"):
            self.d.package.verify_producer_operators(bad)


class FamilyGitApiTests(unittest.TestCase):
    def test_every_family_git_reader_supplies_keyword_only_counts(self):
        family=Path(r.__file__).parent
        calls=[]
        for path in sorted(family.glob("*.py")):
            for node in ast.walk(ast.parse(path.read_bytes(),filename=str(path))):
                if isinstance(node,ast.Call) and isinstance(node.func,ast.Attribute) and node.func.attr=="_git":
                    calls.append((path.name,node.lineno))
                    self.assertIn("counts",{arg.arg for arg in node.keywords},str((path.name,node.lineno)))
        self.assertGreaterEqual(len(calls),4)


if __name__=="__main__":
    unittest.main()
