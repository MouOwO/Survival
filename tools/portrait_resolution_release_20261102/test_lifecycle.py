"""Synthetic package lifecycle; no real release report, crypto, SDK or Git calls."""
from contextlib import ExitStack,nullcontext
from pathlib import Path
from unittest.mock import patch
import copy,importlib.util,json,tempfile,unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('lifecycle_release_authority',HERE/'validator.py')
v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
c,b=v.c,v.c.b


class CandidateFixture:
    def __init__(self,root):
        self.root=Path(root).resolve();self.report_dir=self.root/'reports';self.report_dir.mkdir()
        self.journal=self.root/'journal.json'
        recipe=self.root/'tools/recipe.py';recipe.parent.mkdir();recipe.write_bytes(b'reviewed immutable recipe\n')
        self.values={name:('scoped runtime '+name).encode() for name in b.PAYLOADS}
        rows={name:dict(path=name,**b.checks(b'historical runtime'))for name in b.PAYLOADS if name not in b.ADDED_RUNTIME_PATHS}
        for name in b.ADMISSION_PATHS:rows[name]=dict(path=name,**b.checks(b'official five accounts'))
        for i in range(6917-len(rows)):
            name='materials/frozen/%04d.vtex_c'%i;rows[name]=dict(path=name,**b.checks(b'frozen signed resource'))
        self.old=dict(schema=2,kind='runtime_release_allowlist',hash_algorithms=['md5','sha256'],
            files=[rows[name]for name in sorted(rows)],file_count=6917,bytes=sum(row['bytes']for row in rows.values()),content_sha256='b'*64)
        self.manifest,self.changed=b.projected(self.old,self.values)
        self.sources={'game':'a'*40,'content':'b'*40}
        self.lineage=dict(source_revisions=self.sources,actual_parent_manifest_sha256='c'*64,
            parent_resource_origins_sha256='d'*64,resource_origins_sha256='e'*64)
        self.bindings={pin['source']:{'reviewed':True}for pin in b.COMPILED.values()}
        self.recipe_pins={'tools/recipe.py':b.checks(recipe.read_bytes())}
        self.operator_bindings={'tools/recipe.py':{'exact_reviewed_binding':True}}
        self.report=dict(status='BUILT_SIGNED_PENDING_NATIVE_PERF_ACCEPTANCE',release_sequence=b.SEQUENCE,
            signature_valid=True,full_runtime_validator_passed=True,dry_run=False,payload_changed=False,
            workshop_upload_performed=False,workshop_id=b.ITEM,files=6919,protected_modules_preserved=184,
            all_difficulties_unlocked=False,archive_bundle_hash=b.EXPECTED_BUNDLE,changed_runtime_paths=sorted(b.PAYLOADS),
            added_runtime_paths=list(b.ADDED_RUNTIME_PATHS),removed_runtime_paths=[],auxiliary_input_pins=self.recipe_pins,
            operator_revision='c'*40,operator_source_bindings=self.operator_bindings,source_revision='a'*40,
            source_revisions=self.sources,git_runtime_lineage=self.lineage,
            authenticated_parent_manifest_sha256='c'*64,parent_resource_origins_sha256='d'*64,resource_origins_sha256='e'*64,
            source_artifact_pins=self.bindings,trusted_review_pins={},archive_source_review={'ui_wire_only':True},
            target_pins={name:b.checks(raw)for name,raw in sorted(self.changed.items())},
            preserved_admission_rows=b.preserved_admission(self.old,self.manifest),max_players=4,
            approved_steamids64=list(b.APPROVED),content_sha256=self.manifest['content_sha256'],signature_sha256='f'*64,
            package_files=[{'name':'3824360109.vpk','bytes':1,'sha256':'7'*64}])
        self.parent_report=dict(package_files=copy.deepcopy(self.report['package_files']),vpk_sha256='7'*64)
        self.journal.write_text(json.dumps(dict(release_sequence=b.SEQUENCE,content_sha256=self.manifest['content_sha256'],
            uploaded=True,status='SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST',workshop_id=b.ITEM,
            owner='76561198845461206',app_id=570,visibility_requested=3,legal_agreement_required=False,
            package_files=self.parent_report['package_files'],vpk_sha256='7'*64,vpk_bytes=1)))
        self.signed=dict(release_sequence=b.SEQUENCE,signature_valid=True)
        self.plan_path=self.report_dir/'plan.json';self.plan_path.write_text(json.dumps(dict(status='PLAN_ONLY_NOT_SIGNED',dry_run=True,signature_valid=False)))
        self.report_sha='1'*64;self.plan_sha='2'*64;self.manifest_sha='3'*64
        self.parent_checks=[]

    def baseline(self,*,full=False,require_current_journal=True):
        self.parent_checks.append((full,require_current_journal))
        if require_current_journal:b.require_parent_journal(json.loads(self.journal.read_bytes()),self.parent_report)
        return self.parent_report,self.old

    def load(self,path):
        if path==self.report_dir/'package.json':return self.report
        if path==self.plan_path:return json.loads(self.plan_path.read_bytes())
        if path==self.journal:raise AssertionError('Pure package authentication must not read current canonical state')
        return {}

    def digest(self,path):
        if path==self.journal:raise AssertionError('Pure package authentication must not hash current canonical state')
        if path==self.plan_path:return self.plan_sha
        if path==self.report_dir/'package.json':return self.report_sha
        if path==b.VIEW/b.pack.handoff.MANIFEST:return self.manifest_sha
        if path==b.VIEW/b.pack.handoff.SIGNATURE:return self.report['signature_sha256']
        raise AssertionError('Unexpected immutable digest path')

    def payloads(self,revision,*,source_bindings):
        source_bindings.update(copy.deepcopy(self.bindings));return revision,self.values

    def patches(self):
        return [patch.object(b,'ROOT',self.root),patch.object(b,'REPORT',self.report_dir),patch.object(b,'JOURNAL',self.journal),
            patch.object(b,'AUXILIARY_INPUTS',tuple(self.recipe_pins)),patch.object(b,'load',side_effect=self.load),
            patch.object(b,'operator_inputs',return_value=('c'*40,self.recipe_pins,self.operator_bindings)),
            patch.object(b,'baseline',side_effect=self.baseline),patch.object(b,'payloads',side_effect=self.payloads),
            patch.object(b,'source_lineage',return_value=self.lineage),patch.object(b,'trusted_review',return_value={}),
            patch.object(b,'archive_review',return_value=self.report['archive_source_review']),
            patch.object(b,'scene_maps',return_value=nullcontext()),patch.object(b.inc,'trusted_source',return_value=nullcontext()),
            patch.object(b.inc,'metadata',return_value=(self.manifest,{},{})),patch.object(b.pack.runtime,'digest',side_effect=self.digest),
            patch.object(b.pack.handoff,'trusted_policy',return_value=({'integrity':{'minimum_release_sequence':1,'trusted_key_id':'reviewed'}},Path('public.pem'))),
            patch.object(b.pack,'verify_signed_snapshot',return_value=self.signed),
            patch.object(b.pack,'authenticate',return_value=(b.VIEW,self.manifest,self.signed,{})),
            patch.object(b.pack.handoff,'configured_ids',return_value=sorted(b.APPROVED)),
            patch.object(b.parent.parent.previous.base.protection,'selected_files',return_value=[]),
            patch.object(b.pack,'package_inventory',return_value=self.report['package_files']),patch.object(b.pack,'verify_vpk'),
            patch.object(b,'immutable_revision',side_effect=lambda value:value)]


class CandidateLifecycleTests(unittest.TestCase):
    def test_identical_signed_package_remains_purely_verifiable_after_canonical_advances(self):
        with tempfile.TemporaryDirectory()as temp,ExitStack()as stack:
            fixture=CandidateFixture(temp)
            for item in fixture.patches():stack.enter_context(item)
            report,manifest,signed=c.validated_package(fixture.report_sha,full=True)
            self.assertEqual(report,fixture.report);self.assertEqual(manifest,fixture.manifest);self.assertEqual(signed,fixture.signed)
            self.assertEqual(fixture.parent_checks,[(True,False)])
            b.pack.authenticate.assert_called_once();b.pack.verify_vpk.assert_called_once()
            self.assertEqual(json.loads(fixture.journal.read_bytes())['release_sequence'],b.SEQUENCE)

    def test_publication_authority_refuses_same_candidate_after_canonical_advances(self):
        with tempfile.TemporaryDirectory()as temp,ExitStack()as stack:
            fixture=CandidateFixture(temp)
            for item in fixture.patches():stack.enter_context(item)
            stack.enter_context(patch.object(v,'b',b))
            old_state=json.loads(fixture.journal.read_bytes());old_state.update(release_sequence=b.BASE_SEQUENCE,content_sha256=b.BASE_CONTENT)
            b.require_parent_journal(old_state,fixture.parent_report)  # Only advancement differs; all other parent fields are valid.
            request=dict(release_sequence=b.SEQUENCE,generation=1,source_revisions=fixture.sources,
                report_sha256=fixture.report_sha,plan_path=str(fixture.plan_path),plan_sha256=fixture.plan_sha,
                signed_manifest_sha256=fixture.manifest_sha)
            with self.assertRaisesRegex(ValueError,'successful0104 parent'):v.validate_release(request)
            self.assertEqual(fixture.parent_checks,[(True,False),(False,True)])


if __name__=='__main__':unittest.main()
