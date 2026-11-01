"""Isolated canonical-entry contracts; no SDK, project Git, signing or install."""
from contextlib import ExitStack, contextmanager, redirect_stdout, redirect_stderr
import copy
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import release_pipeline as p
from release_lineage_20261101 import guard as g
from release_lineage_20261101.test_guard import Fixture


@contextmanager
def no_effect_context(*unused):
    yield


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.f = Fixture(self.root)
        self.report = dict(content_sha256='2'*64, release_sequence=106,
                           vpk_sha256='8'*64, package_files=[{'name':'42.vpk','sha256':'8'*64}])
        self.reports = self.root/'reports'; self.reports.mkdir()
        report_raw=g.canonical(self.report)
        (self.reports/'package.json').write_bytes(report_raw)
        for value in (self.f.request, self.f.validated):value['report_sha256']=g.sha(report_raw)
        self.output = self.root/'vpk';self.output.mkdir()
        self.template = dict(workshop_id='42',visibility_requested='unlisted',
            title='Preserve reviewed title',description='Preserve reviewed description',
            tester_steamids64=['synthetic01','synthetic02','synthetic03','synthetic04','synthetic05'],
            map='ws4_entry',max_players=4,real_money_payments=True,
            cover='cover.jpg',cover_sha256=g.sha(b'synthetic-cover'),
            runtime_content_sha256='a'*64,release_sequence=104,unknown_reviewed_field='preserved')
        template_path=self.root/'listing_template.json'
        template_path.write_bytes(g.canonical(self.template))
        (self.root/'cover.jpg').write_bytes(b'synthetic-cover')
        self.f.policy.update(listing_template_path=str(template_path),listing_template_sha256=g.sha(template_path.read_bytes()))
        self._refresh_authority()
        self.stack=ExitStack();self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(g,'require_ancestor'))
        self.stack.enter_context(patch.object(g,'CANONICAL_JOURNAL',self.f.journal))
        self.builder=SimpleNamespace(REPORT=self.reports,OUTPUT=self.output,VIEW=self.root/'view',TRUSTED=self.root/'trusted',
            scene_maps=no_effect_context,inc=SimpleNamespace(trusted_source=no_effect_context,write_new=self.write_new),main=Mock(return_value=0))

    def _refresh_authority(self):
        validator=Path(self.f.policy['validator_path'])
        validator.write_text('RELEASE = '+repr(self.f.validated)+'\nBOOTSTRAP = '+repr(self.f.bootstrap)+
            '\ndef validate_release(request): return RELEASE\ndef validate_bootstrap(request): return BOOTSTRAP\n',encoding='utf8')
        self.f.policy['validator_sha256']=g.sha(validator.read_bytes())
        self.f.policy_path.write_bytes(g.canonical(self.f.policy))
        self.f.authority=g.load_authority(self.f.policy_path,g.sha(self.f.policy_path.read_bytes()))
        self.f.pin=self.f.authority.digest

    def write_new(self,path,raw):
        Path(path).parent.mkdir(parents=True,exist_ok=True)
        with Path(path).open('xb') as stream:stream.write(raw)

    def request_path(self):
        path=self.reports/'request.json';path.write_bytes(g.canonical(self.f.request))
        return path,g.sha(path.read_bytes())

    def test_default_and_status_are_static_without_policy_git_or_sdk(self):
        for args in ([],['status']):
            with patch.object(p,'authority',side_effect=AssertionError('policy touched')),patch.object(p,'_sdk',side_effect=AssertionError('SDK touched')),redirect_stdout(io.StringIO()) as out:
                self.assertEqual(p.main(args),0)
            self.assertEqual(json.loads(out.getvalue())['files_written'],0)

    def test_authority_comes_only_from_the_common_hook(self):
        with patch.object(p.hook,'AUTHORITY_FILE',self.f.policy_path),patch.object(p.hook,'AUTHORITY_SHA256',self.f.pin):
            self.assertEqual(p.authority().digest,self.f.pin)
        with redirect_stdout(io.StringIO()),redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
            p.main(['--authority',str(self.f.policy_path)])

    def test_pinned_module_executes_verified_bytes_and_rejects_drift(self):
        module_path=self.root/'recipe.py';module_path.write_bytes(b'VALUE=17\n')
        self.f.policy.update(recipe_path=str(module_path),recipe_sha256=g.sha(module_path.read_bytes()))
        self._refresh_authority()
        self.assertEqual(p.recipe(self.f.authority).VALUE,17)
        module_path.write_bytes(b'raise AssertionError("untrusted executed")\n')
        with self.assertRaisesRegex(g.Refused,'pinned_pipeline_input_changed'):p.recipe(self.f.authority)

    def test_request_is_bounded_hashed_and_scoped_to_recipe_report(self):
        path,pin=self.request_path()
        self.assertEqual(p.request_json(self.builder,path,pin),self.f.request)
        with self.assertRaises(g.Refused):p.request_json(self.builder,path,'0'*64)
        outside=self.root/'outside.json';outside.write_bytes(path.read_bytes())
        with self.assertRaises(g.Refused):p.request_json(self.builder,outside,pin)
        path.write_bytes(b' '*(p.MAX_REQUEST+1))
        with self.assertRaises(g.Refused):p.request_json(self.builder,path,pin)

    def test_recipe_actions_delegate_only_registered_arguments(self):
        common=['--source-revision','c'*40,'--content-source-revision','d'*40,'--operator-revision','9'*40,
                '--report',str(self.reports/'new.json')]
        for command in ('plan','prepare','build'):
            args=[command,*common]
            if command!='plan':args+=['--reviewed-plan',str(self.reports/'plan.json'),'--reviewed-plan-sha256','e'*64]
            if command=='build':args+=['--key',str(self.root/'synthetic-key-path')]
            with patch.object(p,'authority',return_value=self.f.authority),patch.object(p,'recipe',return_value=self.builder):
                self.assertEqual(p.main(args),0)
            delegated=self.builder.main.call_args.args[0]
            self.assertEqual(delegated[:1],['--source-revision'] if command=='plan' else ['--'+command])
            self.assertIn('--operator-revision',delegated)
        self.assertNotIn('--authority',delegated)

    def test_rehearsal_uses_its_pinned_module_not_arbitrary_entry(self):
        ops=SimpleNamespace(main=Mock(return_value=0))
        with patch.object(p,'authority',return_value=self.f.authority),patch.object(p,'pinned_module',return_value=ops) as loader:
            self.assertEqual(p.main(['rehearsal','inspect','--transaction','synthetic','--report-sha256','f'*64,'--label','sample']),0)
        loader.assert_called_once_with(self.f.authority,'rehearsal')
        self.assertEqual(ops.main.call_args.args[0],['inspect','--transaction','synthetic','--report-sha256','f'*64,'--label','sample'])

    def test_cli_preflight_has_no_sdk_no_generated_listing_and_no_state_write(self):
        self.f.seed();path,pin=self.request_path();before=self.f.state.read_bytes()
        with patch.object(p,'authority',return_value=self.f.authority),patch.object(p,'recipe',return_value=self.builder),patch.object(p,'_sdk',side_effect=AssertionError('SDK touched')),patch.object(g,'atomic_json',side_effect=AssertionError('JSON write')),redirect_stdout(io.StringIO()) as out:
            self.assertEqual(p.main(['preflight','--request',str(path),'--request-sha',pin]),0)
        self.assertEqual(json.loads(out.getvalue())['status'],'FULL_RELEASE_PREFLIGHT_PASS_NO_SDK_CAPABILITY')
        self.assertEqual(self.f.state.read_bytes(),before)
        self.assertFalse((self.reports/'pipeline_listing').exists())
        self.assertIsNone(g._ACTIVE.get())

    def test_cli_bootstrap_passes_exact_hashed_request_to_real_guard_without_sdk(self):
        path,pin=self.request_path()
        with patch.object(p,'authority',return_value=self.f.authority),patch.object(p,'recipe',return_value=self.builder),patch.object(p,'_sdk',side_effect=AssertionError('SDK touched')),redirect_stdout(io.StringIO()) as out:
            self.assertEqual(p.main(['bootstrap','--request',str(path),'--request-sha',pin]),0)
        self.assertEqual(json.loads(out.getvalue())['status'],'LINEAGE_BOOTSTRAPPED_FROM_AUTHENTICATED_PUBLISHED_PARENT')
        self.assertEqual(g.read_json(self.f.state)[0]['generation'],0)
        with patch.object(p,'authority',return_value=self.f.authority),patch.object(p,'recipe',return_value=self.builder),self.assertRaises(g.Refused):
            p.main(['bootstrap','--request',str(path),'--request-sha',pin])

    def fake_sdk(self, *, wrong_facts=False, unknown_submit=False):
        sdk=SimpleNamespace(publication_lock=Mock(side_effect=AssertionError('nested lock')))
        def validate(view,vpk,listing_path,report_path):
            self.assertIsNotNone(g._ACTIVE.get())
            listing=json.loads(listing_path.read_bytes())
            facts=copy.deepcopy(self.report)
            if wrong_facts:facts['vpk_sha256']='0'*64
            return listing,listing_path.parent/listing['cover'],facts
        @contextmanager
        def steam():
            self.assertIsNotNone(g._ACTIVE.get());yield 'synthetic-native-session'
        def publish(native,listing,cover,vpk,facts,state_path,**options):
            self.assertEqual(options,dict(apply=True,update_existing=True))
            self.f.call('StartItemUpdate',(570,42),789)
            value=self.f.transition();self.f.write_owned(value)
            self.f.call('SetItemContent',(789,str(self.output).encode()),True)
            self.f.call('SetItemVisibility',(789,3),True)
            self.f.call('SubmitItemUpdate',(789,b''),987)
            if unknown_submit:raise RuntimeError('synthetic unknown submit')
            result=dict(value,uploaded=True,status='SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST')
            self.f.write_owned(result);return result
        sdk.validate_upload=Mock(side_effect=validate);sdk.Steam=Mock(side_effect=steam);sdk.publish=Mock(side_effect=publish)
        return sdk

    def test_publish_uses_actual_sdk_result_and_advances_real_guard_only_once(self):
        self.f.seed();sdk=self.fake_sdk()
        with patch.object(p,'_sdk',return_value=sdk):result=p.publish(self.f.authority,self.builder,self.f.request)
        self.assertTrue(result['uploaded']);sdk.publication_lock.assert_not_called()
        self.assertEqual(g.read_json(self.f.state)[0]['generation'],1)
        listing=json.loads((self.reports/'pipeline_listing/listing.json').read_bytes())
        self.assertEqual(set(k for k in listing if listing[k]!=self.template[k]),{'runtime_content_sha256','release_sequence'})
        self.assertEqual((self.reports/'pipeline_listing/cover.jpg').read_bytes(),b'synthetic-cover')
        with patch.object(p,'_sdk',side_effect=AssertionError('SDK reentered')),self.assertRaises(g.Refused):
            p.publish(self.f.authority,self.builder,self.f.request)

    def test_sdk_facts_mismatch_and_unknown_submit_leave_pending_never_mark_pass(self):
        self.f.seed();sdk=self.fake_sdk(wrong_facts=True)
        with patch.object(p,'_sdk',return_value=sdk),self.assertRaisesRegex(g.Refused,'sdk_package_facts_differ'):
            p.publish(self.f.authority,self.builder,self.f.request)
        sdk.Steam.assert_not_called();self.assertIsNotNone(g.read_json(self.f.state)[0]['pending'])
        # An unknown outcome is a distinct synthetic fixture, never auto-cleared.
        state,_=g.read_json(self.f.state);state['pending']=None;g.atomic_json(self.f.state,state)
        sdk=self.fake_sdk(unknown_submit=True)
        with patch.object(p,'_sdk',return_value=sdk),self.assertRaises(RuntimeError):
            p.publish(self.f.authority,self.builder,self.f.request)
        self.assertEqual(g.read_json(self.f.state)[0]['generation'],0)
        self.assertIsNotNone(g.read_json(self.f.state)[0]['pending'])

    def test_stale_parent_refuses_before_derived_listing_or_sdk(self):
        self.f.seed()
        with patch.object(p,'listing_file',side_effect=AssertionError('listing touched')),patch.object(p,'_sdk',side_effect=AssertionError('SDK touched')),self.assertRaises(g.Refused):
            p.publish(self.f.authority,self.builder,dict(self.f.request,parent_journal_sha256='0'*64))
        self.assertIsNone(g.read_json(self.f.state)[0]['pending'])


if __name__=='__main__':unittest.main()
