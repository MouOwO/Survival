"""Real file/phase binding and frozen verifier control flow, no Steam/native.

The tiny files are synthetic VPK fixtures; crypto/CRC callbacks are modeled.
The real frozen verify_installed performs actual membership and byte hashes.
These tests cannot create actual SDK, native or official-download evidence.
"""
from contextlib import ExitStack,nullcontext
from copy import deepcopy
import hashlib,json
from pathlib import Path
import sys,tempfile,unittest
from types import SimpleNamespace
from unittest.mock import Mock,patch

sys.path.insert(0,str(Path(__file__).resolve().parent))
from complete_delivery_release_20261103 import native_admission as n,complete_baseline as baseline,rehearsal as ops
from test_release_delivery_state import fixture as delivery_fixture
import verify_workshop_download as frozen


def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def rows(folder):
    return [dict(name=p.name,bytes=p.stat().st_size,sha256=digest(p)) for p in sorted(Path(folder).iterdir())]
def dump(path,value):
    path.parent.mkdir(parents=True,exist_ok=True);raw=json.dumps(value,sort_keys=True).encode();path.write_bytes(raw);return raw


class Fixture:
    def __init__(self):
        self.temp=tempfile.TemporaryDirectory(prefix="goufayu_post_download_phase_")
        self.root=Path(self.temp.name).resolve()
        assert self.root.parent==Path(tempfile.gettempdir()).resolve()
        assert not self.root.is_relative_to(n.ROOT.parents[2])
        self.installed=self.root/"installed";self.transaction=self.root/"native_transaction"
        self.parent_folder=self.transaction/"backup";self.retained=self.transaction/"retained_candidate"
        for folder,label in ((self.installed,b"0402"),(self.parent_folder,b"0104"),(self.retained,b"0402")):
            folder.mkdir(parents=True)
            (folder/"3824360109.vpk").write_bytes(label+b"-index")
            (folder/"3824360109_000.vpk").write_bytes(label+b"-volume")
        self.new_rows,self.old_rows=rows(self.installed),rows(self.parent_folder)
        self.parent=dict(package_files=self.old_rows);self.parent_manifest=dict(phase="0104")
        data=delivery_fixture();self.report=data["local_package"];self.journal=data["journal"];self.receipt=data["download_receipt"]
        self.manifest=dict(files=data["local_resources"],phase="0402")
        for value in (self.report,self.journal,self.receipt):
            value.update(release_sequence=2026110402,vpk_sha256=self.new_rows[0]["sha256"])
        self.report.update(package_files=self.new_rows,operator_revision="a"*40,protected_modules_verified=186,
            app_id=570,owner=123,signed_manifest_sha256="f"*64,resource_origins_sha256="9"*64)
        self.report["collection_source_revisions"]=dict(self.report["source_revisions"],operator="a"*40)
        self.journal.update(owner=123,package_files=deepcopy(self.new_rows),vpk_bytes=self.new_rows[0]["bytes"])
        self.report_dir=self.root/"report";self.report_raw=dump(self.report_dir/"package.json",self.report)
        self.report_sha=hashlib.sha256(self.report_raw).hexdigest()
        self.journal_path=self.root/"journal.json";self.journal_raw=dump(self.journal_path,self.journal)
        self.lineage_path=self.root/"lineage.json"
        self.lineage=dict(schema=1,generation=1,pending=None,head=dict(sequence=2026110402,
            canonical_journal_sha256=hashlib.sha256(self.journal_raw).hexdigest(),content_sha256=self.report["content_sha256"],
            manifest_sha256=self.report["signed_manifest_sha256"],resource_origins_sha256=self.report["resource_origins_sha256"],
            source_revisions=self.report["source_revisions"]))
        dump(self.lineage_path,self.lineage)
        self.request=dict(generation=1,report_sha256=self.report_sha,signed_manifest_sha256=self.report["signed_manifest_sha256"],
            source_revisions=self.report["source_revisions"])
        total=sum(v["bytes"] for v in self.new_rows)
        self.receipt.update(package_report_sha256=self.report_sha,canonical_journal_sha256=hashlib.sha256(self.journal_raw).hexdigest(),protected_modules_verified=186)
        self.receipt["pre_query"]["total_files_bytes"]=self.receipt["post_query"]["total_files_bytes"]=total
        self.receipt["download"].update(install_folder=str(self.installed))
        self.receipt["download"]["callback"]["callback_id"]=3406
        self.receipt["verification"].update(vpk_sha256=self.new_rows[0]["sha256"],package_files=deepcopy(self.new_rows),
            size_on_disk=total,expected_size_on_disk=total,callback=deepcopy(self.receipt["download"]["callback"]))
        self.checks=tuple(k for k in self.receipt["verification"]["verification"] if k.endswith("verified"))
        self.receipt["verification"]["verification"]["archive_count"]=1
        self.acf_row=dict(manifest=self.receipt["steam_manifest"],size=str(total),timeupdated="123")
        self.receipt["acf_installed_entry"]=deepcopy(self.acf_row)
        self.receipt_path=self.report_dir/"download_evidence/run01/verification.json"
        self.save_receipt();self.acf=self.root/"test.acf";dump(self.acf,self.acf_row)
        self.candidate=self.root/"candidate";dump(self.candidate/"_release_manifest.json",self.manifest)
        dump(self.candidate/"_release_signature.json",{"synthetic_crypto_fixture":True})
        self.frozen_calls=[]
        fake_pack=SimpleNamespace(handoff=SimpleNamespace(regular_path=lambda p:p.resolve(),MANIFEST="_release_manifest.json",SIGNATURE="_release_signature.json",
            trusted_policy=lambda:({"integrity":{"minimum_release_sequence":0,"trusted_key_id":"synthetic"}},self.root/"not-a-production-key")),
            package_paths=lambda p:[self.installed/v["name"] for v in self.new_rows],
            verify_signed_snapshot=lambda *a:dict(content_sha256=self.report["content_sha256"]),
            runtime=SimpleNamespace(digest=digest),package_inventory=lambda p:rows(self.installed),verify_vpk=self.synthetic_crc,
            MAX_MANIFEST=32*1024*1024,read_metadata=lambda p,*a:Path(p).read_bytes())
        self.fake_api=SimpleNamespace(pack=fake_pack,load=lambda p:json.loads(Path(p).read_bytes()))
        self.protocol=SimpleNamespace(INSTALLED=self.installed,ACF=self.acf,api=self.fake_api,
            callbacks=SimpleNamespace(CHECKS=self.checks),verify=SimpleNamespace(verify_installed=frozen.verify_installed),
            unchanged=self.unchanged,acf_manifest=lambda raw,*a:(json.loads(raw)["manifest"],json.loads(raw)))
        self.auth=SimpleNamespace(digest="8"*64,policy=dict(canonical_journal=str(self.journal_path),lineage_state=str(self.lineage_path),
            app_id=570,owner=123,workshop_id="3824360109",baseline_completion_sha256="1"*64,download_sha256="2"*64))
        self.b=SimpleNamespace(REPORT=self.report_dir,VIEW=self.candidate,TRUSTED=self.root/"trusted",
            checked_json=self.checked_json,verify_operator_paths=Mock(),scene_maps=lambda:nullcontext(),inc=SimpleNamespace(trusted_source=lambda p:nullcontext()))
        self.p=SimpleNamespace(INSTALLED=self.installed,regular=lambda p:Path(p).resolve(),row=lambda p:dict(name=Path(p).name,bytes=Path(p).stat().st_size,sha256=digest(p)))
        self.native_calls=0
        self.ops=SimpleNamespace(require_rows=ops.require_rows,full_vpk=self.lifecycle_vpk)
        self.downloaded=SimpleNamespace(configure=lambda r:None,protocol=lambda:self.protocol,_PROTOCOL_EXECUTED_PINS={})
        self.toolchain={"tools/release_pipeline.py":SimpleNamespace(authority=lambda:self.auth),
            "tools/complete_delivery_release_20261103/complete_baseline.py":SimpleNamespace(checked_authority=lambda a:a,current_head=baseline.current_head,verified_delivery=baseline.verified_delivery),
            "tools/complete_delivery_release_20261103/verify_download.py":self.downloaded}
    def save_receipt(self):
        raw=dump(self.receipt_path,self.receipt);self.ref=dict(path=str(self.receipt_path),sha256=hashlib.sha256(raw).hexdigest())
    def checked_json(self,ref,**kwargs):
        raw=Path(ref["path"]).read_bytes();assert len(raw)<kwargs["limit"]
        n.need(hashlib.sha256(raw).hexdigest()==ref["sha256"],"actual_receipt_raw_sha_mismatch")
        return json.loads(raw),raw
    def unchanged(self,snapshots):
        for path,raw in snapshots.items():n.need(Path(path).read_bytes()==raw,"official_controls_changed")
    def synthetic_crc(self,index,manifest):
        self.frozen_calls.append(index)
        return dict(files=self.report["files"],archive_count=1,**dict.fromkeys(self.checks,True))
    def lifecycle_vpk(self,folder,manifest):
        expected=self.old_rows if manifest["phase"]=="0104" else self.new_rows
        n.need(rows(folder)==expected,"actual_lifecycle_vpk_bytes_changed")
    def ordinary(self,request,report,manifest,signed,*,official=None):
        self.native_calls+=1
        n._lifecycle_packages(self.transaction,report,manifest,self.parent,self.parent_manifest,self.report_sha,self.ops,self.p,official)
        return dict(ordinary_production_acceptance=True)
    def context(self):
        stack=ExitStack()
        stack.enter_context(patch.object(n,"environment",return_value=(self.b,self.ops,self.p)))
        stack.enter_context(patch.object(ops,"environment",return_value=(None,self.p,None)))
        stack.enter_context(patch.object(n,"_post_download_operator",side_effect=lambda relative,*a:self.toolchain[relative]))
        stack.enter_context(patch.object(frozen,"api",self.fake_api))
        stack.enter_context(patch.object(n,"_validate_native_release",side_effect=self.ordinary))
        return stack
    def post(self):return n.validate_post_download_native_release(self.request,self.report,self.manifest,{},receipt_ref=self.ref)
    def close(self):
        assert self.root.parent==Path(tempfile.gettempdir()).resolve() and self.root.name.startswith("goufayu_post_download_phase_")
        self.temp.cleanup()


class PostDownloadPhaseTests(unittest.TestCase):
    def setUp(self):self.f=Fixture();self.addCleanup(self.f.close)
    def test_old_preflight_rejects_current_target_even_with_user_phase_flag(self):
        f=self.f
        with f.context(),self.assertRaisesRegex(ValueError,"byte_mismatch"):
            n.validate_native_release(dict(f.request,post_download=True),f.report,f.manifest,{})
        self.assertEqual(f.frozen_calls,[])
    def test_post_download_real_bytes_pass_frozen_verifier_before_native_backup_recheck(self):
        f=self.f
        with f.context():value=f.post()
        self.assertEqual(f.native_calls,1);self.assertEqual(len(f.frozen_calls),1)
        self.assertTrue(value["official_full_installation_reverified"])
        self.assertEqual(value["official_receipt_sha256"],f.ref["sha256"])
    def test_full_checkpoint_collection_uses_closed_post_download_phase_after0402_install(self):
        # This reaches the real collect_verified branch, which formerly called
        # preflight native validation and rejected these physical0402 files.
        f=self.f
        from complete_delivery_release_20261103 import publication_validator as publication
        f.b.load_package=lambda *a,**k:(f.report,f.manifest,{"release_sequence":2026110402})
        f.b.INPUT_FILE=f.report_dir/"pipeline_inputs.json";f.b.INPUT_FILE.write_bytes(b"{}")
        ctx=SimpleNamespace(config={},config_raw=b"{}",inputs={"inventory_raw":b"{}"},projection={},projection_raw=b"{}")
        f.b.context=lambda *a:ctx
        fake_pending=SimpleNamespace(_read_json=lambda *a:{},BASELINE="unused",BASELINE_SHA256="0"*64)
        f.b.dependencies=lambda:SimpleNamespace(package=SimpleNamespace(pending=fake_pending))
        with f.context(),patch.object(baseline,"checked_authority",return_value=f.auth), \
                patch.object(publication,"_native_policy",return_value=n), \
                patch.object(baseline,"target_trees",return_value=({},{})), \
                patch.object(baseline,"advance",return_value={"fixture_only":True}) as assemble:
            baseline.collect_verified(f.auth,f.b,f.request,f.receipt_path,full=True)
        self.assertEqual((f.native_calls,len(f.frozen_calls)),(1,1))
        evidence=assemble.call_args.args[-1]
        self.assertTrue(evidence["ordinary_production_acceptance"])
        self.assertTrue(evidence["official_full_installation_reverified"])
    def test_arbitrary_bool_or_receipt_dict_cannot_replace_private_phase_capability(self):
        f=self.f
        for value in (True,{"verified":True}):
            with f.context(),self.subTest(value=value),self.assertRaisesRegex(ValueError,"verified_official_phase"):
                n._lifecycle_packages(f.transaction,f.report,f.manifest,f.parent,f.parent_manifest,f.report_sha,f.ops,f.p,value)
    def test_official_extra_or_changed_bytes_prevent_native_phase(self):
        f=self.f;(f.installed/"3824360109_000.vpk").write_bytes(b"corrupt")
        with f.context(),self.assertRaisesRegex(ValueError,"archives differ"):f.post()
        self.assertEqual(f.native_calls,0)
    def test_old_receipt_or_stale_sdk_lineage_prevents_native_phase(self):
        f=self.f;f.receipt["release_sequence"]=2026110104;f.save_receipt()
        with f.context(),self.assertRaisesRegex(ValueError,"same_target_real_sdk"):f.post()
        self.assertEqual(f.native_calls,0)
    def test_pending_sdk_state_cannot_be_certified(self):
        f=self.f;f.lineage["pending"]={"unknown":True};dump(f.lineage_path,f.lineage)
        with f.context(),self.assertRaisesRegex(ValueError,"pending_or_changed_generation"):f.post()
        self.assertEqual(f.native_calls,0)
    def test_backup0104_and_retained_target_are_still_required(self):
        f=self.f
        for folder in (f.parent_folder,f.retained):
            path=folder/"3824360109_000.vpk";original=path.read_bytes();path.write_bytes(b"damaged-copy")
            with self.subTest(folder=folder.name),f.context(),self.assertRaisesRegex(ValueError,"byte_mismatch"):f.post()
            path.write_bytes(original)
        self.assertEqual(len(f.frozen_calls),2)
    def test_signature_crc_and_acf_failure_cannot_create_an_official_phase(self):
        f=self.f
        original=f.fake_api.pack.verify_signed_snapshot
        f.fake_api.pack.verify_signed_snapshot=Mock(side_effect=ValueError("synthetic invalid signature"))
        with f.context(),self.assertRaisesRegex(ValueError,"invalid signature"):f.post()
        f.fake_api.pack.verify_signed_snapshot=original
        original=f.fake_api.pack.verify_vpk
        f.fake_api.pack.verify_vpk=lambda *args:dict(files=1,archive_count=1,**dict.fromkeys(f.checks,False))
        with f.context(),self.assertRaisesRegex(ValueError,"actual_official_installation_failed"):f.post()
        f.fake_api.pack.verify_vpk=original;dump(f.acf,dict(f.acf_row,manifest="wrong-manifest"))
        with f.context(),self.assertRaisesRegex(ValueError,"official_acf_changed"):f.post()
        self.assertEqual(f.native_calls,0)
    def test_actual_native_evidence_failure_remains_fatal_after_valid_official_bytes(self):
        f=self.f
        with f.context(),patch.object(n,"_validate_native_release",side_effect=ValueError("native close/restore missing")):
            with self.assertRaisesRegex(ValueError,"close/restore missing"):f.post()
        self.assertEqual(len(f.frozen_calls),1)
    def test_receipt_must_be_original_hashed_path_under_download_evidence(self):
        f=self.f;outside=f.root/"verification.json";dump(outside,f.receipt)
        f.ref.update(path=str(outside),sha256=digest(outside))
        with f.context(),self.assertRaisesRegex(ValueError,"original_official_receipt"):f.post()
        self.assertEqual(f.native_calls,0)


if __name__=="__main__":unittest.main()
