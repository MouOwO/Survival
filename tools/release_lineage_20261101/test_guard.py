"""Meaningful isolated lineage/delta/OS-lock tests; no SDK/network/project Git."""
from contextlib import ExitStack
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from release_lineage_20261101 import guard as g


class Fixture:
    def __init__(self, folder):
        self.root = Path(folder)
        self.journal = self.root/'canonical.json'
        self.state = self.root/'lineage.json'
        self.parent = dict(owner='synthetic-owner',app_id=570,workshop_id='42',
            uploaded=True,status='SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST',
            release_sequence=104,content_sha256='a'*64,vpk_sha256='b'*64,
            package_files=[{'name':'42.vpk','sha256':'b'*64}],
            previous_release={'release_sequence':103,'preserve_unknown':'value'},
            release_history=[{'synthetic':n} for n in range(20)])
        self.journal.write_bytes(g.canonical(self.parent))
        self.parent_sha = g.sha(self.journal.read_bytes())
        self.request = dict(parent_journal_sha256=self.parent_sha,generation=1,release_sequence=106,
            source_revisions={'game':'c'*40,'content':'d'*40},
            signed_manifest_sha256='e'*64,report_sha256='f'*64,plan_sha256='1'*64)
        self.validated = dict(self.request,owner='synthetic-owner',app_id=570,workshop_id='42',
            content_sha256='2'*64,authenticated_parent_content_sha256='a'*64,
            authenticated_parent_manifest_sha256='3'*64,parent_resource_origins_sha256='4'*64,
            resource_origins_sha256='5'*64,package_dir=str(self.root/'vpk'))
        self.bootstrap = dict(canonical_journal_sha256=self.parent_sha,release_sequence=104,
            content_sha256='a'*64,source_revisions={'game':'a'*40,'content':'b'*40},
            parent_manifest_sha256='3'*64,resource_origins_sha256='4'*64,
            source_anchor_is_full_published_tree=False)
        validator = self.root/'trusted_validator.py'
        validator.write_text('RELEASE = '+repr(self.validated)+'\nBOOTSTRAP = '+repr(self.bootstrap)+
            '\ndef validate_release(request): return RELEASE\ndef validate_bootstrap(request): return BOOTSTRAP\n',encoding='utf8')
        self.policy = dict(schema=1,canonical_journal=str(self.journal),lineage_state=str(self.state),
            publication_lock=str(self.journal)+'.lock',validator_path=str(validator),
            validator_sha256=g.sha(validator.read_bytes()),app_id=570,workshop_id='42',owner='synthetic-owner',
            repositories={'game':str(self.root/'game'),'content':str(self.root/'content')},
            required_feature_ancestors={'game':['9'*40]})
        self.policy_path = self.root/'authority.json'
        self.policy_path.write_bytes(g.canonical(self.policy))
        self.authority = g.load_authority(self.policy_path,g.sha(self.policy_path.read_bytes()))
        self.pin = self.authority.digest

    def seed(self):
        g.bootstrap_lineage(self.authority,{})

    def transition(self):
        value = dict(self.parent,release_sequence=106,content_sha256='2'*64,uploaded=False,status='UPLOAD_PENDING')
        value['previous_release'] = copy.deepcopy(self.parent)
        value['release_history'] = self.parent['release_history'] + [self.parent['previous_release']]
        return value

    def write_owned(self, value):
        g.before_journal_write(self.journal,value,authority_sha256=self.pin)
        # Exercise the same indented atomic-JSON representation the SDK uses.
        self.journal.write_text(json.dumps(value,indent=2)+'\n',encoding='utf8')
        g.after_journal_write(self.journal,g.sha(self.journal.read_bytes()),authority_sha256=self.pin)

    def call(self, suffix, args, result):
        permit = g.require_sdk_mutation(suffix,args,authority_sha256=self.pin)
        permit.observe_result(result)
        return permit


class LeaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.f = Fixture(self.tmp.name)
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.ancestor = self.stack.enter_context(patch.object(g,'require_ancestor'))
        self.stack.enter_context(patch.object(g,'CANONICAL_JOURNAL',self.f.journal))

    def test_old_sdk_paths_and_ready_json_cannot_mutate_or_clobber_canonical(self):
        before = self.f.journal.read_bytes()
        for name in g.MUTATIONS:
            with self.subTest(name=name),self.assertRaises(g.Refused):
                g.require_sdk_mutation(name,(570,42),authority_sha256=self.f.pin)
        with self.assertRaises(g.Refused):
            g.before_journal_write(self.f.journal,{'READY':True},authority_sha256=self.f.pin)
        self.assertEqual(before,self.f.journal.read_bytes())
        self.assertIsNone(g.require_sdk_mutation('DownloadItem',(),authority_sha256=None))
        self.assertIsNone(g.require_sdk_mutation('GetQueryUGCResult',(),authority_sha256=None))
        self.assertFalse(g.before_journal_write(self.f.root/'other_report.json',{'ok':True}))
        for unknown in ('SetItemFutureMetadata','AddItemKeyValueTag','RemoveDependency'):
            with self.subTest(unknown=unknown),self.assertRaisesRegex(g.Refused,'before_native'):
                g.require_sdk_mutation(unknown,(),authority_sha256=self.f.pin)

    def test_bootstrap_does_not_call_a_git_label_a_full_published_tree(self):
        self.f.seed()
        state,_=g.read_json(self.f.state)
        self.assertEqual(state['head']['manifest_sha256'],'3'*64)
        self.assertEqual(state['head']['resource_origins_sha256'],'4'*64)
        self.assertEqual(state['generation'],0)
        with self.assertRaisesRegex(g.Refused,'already_bootstrapped'):self.f.seed()

    def test_preflight_has_full_admission_but_no_intent_active_capability_or_writes(self):
        self.f.seed()
        before_state=self.f.state.read_bytes();before_journal=self.f.journal.read_bytes()
        with patch.object(g,'atomic_json',side_effect=AssertionError('preflight wrote JSON')):
            result=g.preflight_release(self.f.authority,self.f.request)
            with g.release_lease(self.f.authority,self.f.request,preflight=True):
                self.assertIsNone(g._ACTIVE.get())
                with self.assertRaises(g.Refused):
                    g.require_sdk_mutation('StartItemUpdate',(570,42),authority_sha256=self.f.pin)
        result['source_revisions']['game']='0'*40
        self.assertEqual(self.f.validated['source_revisions']['game'],'c'*40)
        self.assertEqual(self.f.state.read_bytes(),before_state)
        self.assertEqual(self.f.journal.read_bytes(),before_journal)
        with self.assertRaises(g.Refused):
            g.preflight_release(self.f.authority,dict(self.f.request,generation=99))
        # A read-only pass cannot stand in for a later publication admission.
        self.f.policy_path.write_bytes(b'{}')
        with self.assertRaises(g.Refused):
            with g.release_lease(self.f.authority,self.f.request):pass
        self.assertEqual(self.f.state.read_bytes(),before_state)

    def test_policy_rejects_a_different_lock_from_the_legacy_sdk_canonical_lock(self):
        policy=dict(self.f.policy,publication_lock=str(self.f.root/'other.lock'))
        self.f.policy_path.write_bytes(g.canonical(policy))
        with self.assertRaisesRegex(g.Refused,'canonical_sdk_publication_lock'):
            g.load_authority(self.f.policy_path,g.sha(self.f.policy_path.read_bytes()))

    def test_success_crosses_pending_once_preserves_parent_and_all_history(self):
        self.f.seed()
        with g.release_lease(self.f.authority,self.f.request) as lease:
            state,_=g.read_json(self.f.state)
            self.assertEqual(state['pending']['generation'],1)
            self.f.call('StartItemUpdate',(570,42),789)
            value=self.f.transition();self.f.write_owned(value)
            self.f.call('SetItemContent',(789,str(self.f.root/'vpk').encode()),True)
            self.f.call('SetItemPreview',(789,b'synthetic-cover'),True)
            self.f.call('SubmitItemUpdate',(789,b''),987)
            self.f.write_owned(dict(value,uploaded=True,status='SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST'))
            lease.mark_submitted(json.loads(self.f.journal.read_bytes()))
        state,_=g.read_json(self.f.state)
        self.assertEqual(state['generation'],1);self.assertIsNone(state['pending'])
        self.assertEqual(state['head']['source_revisions'],self.f.request['source_revisions'])
        self.assertEqual(len(json.loads(self.f.journal.read_bytes())['release_history']),21)
        self.assertTrue(any(call.args[1]=='9'*40 for call in self.ancestor.call_args_list))

    def test_unknown_submit_failure_is_pending_and_not_replayed(self):
        self.f.seed()
        with self.assertRaisesRegex(RuntimeError,'synthetic unknown'):
            with g.release_lease(self.f.authority,self.f.request):
                self.f.call('StartItemUpdate',(570,42),789)
                g.require_sdk_mutation('SubmitItemUpdate',(789,b''),authority_sha256=self.f.pin)
                raise RuntimeError('synthetic unknown')
        self.assertIsNotNone(g.read_json(self.f.state)[0]['pending'])
        with self.assertRaisesRegex(g.Refused,'reconciliation'):
            with g.release_lease(self.f.authority,self.f.request):pass

    def test_stale_source_sequence_parent_generation_and_policy_fail_before_native(self):
        self.f.seed()
        for key,value in [('parent_journal_sha256','0'*64),('generation',3),('release_sequence',104),
                ('signed_manifest_sha256','9'*64),('source_revisions',{'game':'f'*40,'content':'d'*40})]:
            with self.subTest(key=key),self.assertRaises(g.Refused):
                with g.release_lease(self.f.authority,dict(self.f.request,**{key:value})):pass
            self.assertIsNone(g.read_json(self.f.state)[0]['pending'])
        self.f.policy_path.write_bytes(b'{}')
        with self.assertRaises(g.Refused):
            with g.release_lease(self.f.authority,self.f.request):pass

    def test_foreign_handle_wrong_item_wrong_content_and_failed_setter_refuse(self):
        self.f.seed()
        with self.assertRaisesRegex(g.Refused,'not_completed'):
            with g.release_lease(self.f.authority,self.f.request):
                with self.assertRaises(g.Refused):self.f.call('StartItemUpdate',(570,99),789)
                self.f.call('StartItemUpdate',(570,42),789)
                with self.assertRaises(g.Refused):self.f.call('SetItemTitle',(888,b'bad'),True)
                with self.assertRaises(g.Refused):self.f.call('SetItemContent',(789,b'wrong-directory'),True)
                with self.assertRaises(g.Refused):self.f.call('SetItemVisibility',(789,0),True)
                with self.assertRaises(g.Refused):self.f.call('SetItemTitle',(789,b'bad'),False)
                with self.assertRaises(g.Refused):self.f.call('SetItemTitle',(789,b'again'),True)

    def test_unobserved_native_call_and_expired_permit_never_reenter(self):
        self.f.seed();permit=None
        with self.assertRaises(g.Refused):
            with g.release_lease(self.f.authority,self.f.request):
                permit=g.require_sdk_mutation('StartItemUpdate',(570,42),authority_sha256=self.f.pin)
                with self.assertRaisesRegex(g.Refused,'outcome_unknown'):
                    g.require_sdk_mutation('StartItemUpdate',(570,42),authority_sha256=self.f.pin)
        with self.assertRaises(g.Refused):permit.observe_result(789)

    def test_canonical_external_change_and_history_drop_are_not_accepted_as_owned_writes(self):
        self.f.seed()
        with self.assertRaises(g.Refused):
            with g.release_lease(self.f.authority,self.f.request):
                value=self.f.transition();value['release_history']=[]
                with self.assertRaisesRegex(g.Refused,'history'):
                    self.f.write_owned(value)
                self.f.journal.write_bytes(b'{}')
                self.f.call('StartItemUpdate',(570,42),789)

    def test_shared_lock_is_cross_process_not_a_caller_chosen_journal_lock(self):
        lock=self.f.policy['publication_lock']
        script="import sys;sys.path.insert(0,sys.argv[1]);from release_lineage_20261101.guard import exclusive_lock,Refused\ntry:\n with exclusive_lock(sys.argv[2]):sys.exit(9)\nexcept Refused:sys.exit(0)\n"
        with g.exclusive_lock(lock):
            result=subprocess.run([sys.executable,'-B','-c',script,str(HERE.parent),lock],capture_output=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
        with g.exclusive_lock(lock):pass

    def test_real_child_holds_lock_second_child_refuses_then_normal_or_exception_exit_releases(self):
        # No mocks of msvcrt/fcntl. Test exact disposable files, not a real journal.
        lock=str(self.f.root/'separate-real-os.lock')
        hold=("import sys;sys.path.insert(0,sys.argv[1]);from release_lineage_20261101.guard import exclusive_lock\n"
              "with exclusive_lock(sys.argv[2]):\n print('HELD',flush=True)\n sys.stdin.readline()\n"
              " if sys.argv[3]=='exception':raise RuntimeError('isolated expected failure')\n")
        attempt=("import sys;sys.path.insert(0,sys.argv[1]);from release_lineage_20261101.guard import exclusive_lock,Refused\n"
                 "try:\n with exclusive_lock(sys.argv[2]):sys.exit(9)\nexcept Refused:sys.exit(0)\n")
        Path(lock).touch()  # Existing empty/stale lock is not ownership.
        for mode in ('normal','exception'):
            with self.subTest(mode=mode):
                child=subprocess.Popen([sys.executable,'-B','-c',hold,str(HERE.parent),lock,mode],
                    stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                try:
                    self.assertEqual(child.stdout.readline().strip(),'HELD')
                    second=subprocess.run([sys.executable,'-B','-c',attempt,str(HERE.parent),lock],
                        capture_output=True,timeout=15)
                    self.assertEqual(second.returncode,0,second.stderr.decode(errors='replace'))
                    _,stderr=child.communicate('\n',timeout=15)
                    self.assertEqual(child.returncode,0 if mode=='normal' else 1,stderr)
                    with g.exclusive_lock(lock):pass
                finally:
                    if child.poll() is None:
                        child.kill();child.wait(timeout=15)  # Only this exact self-created test helper.

    def test_validator_is_once_per_lease_not_per_setter_or_journal_cas(self):
        self.f.seed()
        real=g._validator
        with patch.object(g,'_validator',wraps=real) as validator,self.assertRaises(g.Refused):
            with g.release_lease(self.f.authority,self.f.request):
                self.f.call('StartItemUpdate',(570,42),789)
                for index in range(8):self.f.call('SetItemTitle',(789,b'synthetic'),True)
                self.assertEqual(validator.call_count,1)
        self.assertEqual(validator.call_count,1)


class ProjectionTests(unittest.TestCase):
    def test_git_commands_disable_replace_objects_and_do_not_invoke_a_shell(self):
        from types import SimpleNamespace
        with patch.object(g.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout=b'blob')) as run:
            self.assertEqual(g._git('/synthetic/game','show','a'*40+':path'),b'blob')
        self.assertEqual(run.call_args.args[0][:2],['git','--no-replace-objects'])
        self.assertIn('safe.directory='+Path('/synthetic/game').resolve().as_posix(),run.call_args.args[0])
        self.assertNotIn('shell',run.call_args.kwargs)

    def fixture(self):
        rows=[dict(path='scripts/old14.lua',bytes=3,sha256=g.sha(b'old'),unknown={'preserve':1}),
              dict(path='scripts/protected.lua',bytes=6,sha256=g.sha(b'frozen'),protected=True)]
        parent={'files':rows,'unknown_header':'preserved by caller manifest builder'}
        origins={r['path']:dict(kind='frozen_signed_resource',resource_sha256=r['sha256']) for r in rows}
        repos={name:dict(path='/synthetic/'+name,parent='a'*40,target='b'*40) for name in ['game','content']}
        binding=dict(resource='scripts/old14.lua',inputs=[{'repo':'game','path':'scripts/old14.lua'}],
            output={'repo':'game','path':'scripts/old14.lua'},kind='identity',
            source_pins={'game:scripts/old14.lua':g.sha(b'new')},artifact_sha256=g.sha(b'new'))
        return parent,origins,repos,binding

    def test_no_git_diff_still_carries_unpublished_resource_relative_to_signed_parent(self):
        parent,origins,repos,binding=self.fixture()
        with patch.object(g,'git_changes',return_value=[]),patch.object(g,'_git',return_value=b'new'):
            result=g.derive_payload_plan(parent,repos,[binding],parent_origins=origins,parent_manifest_sha256='1'*64)
        self.assertEqual(set(result['changed_resources']),{'scripts/old14.lua'})
        indexed={r['path']:r for r in result['projected_rows']}
        self.assertEqual(indexed['scripts/protected.lua'],parent['files'][1])
        self.assertEqual(indexed['scripts/old14.lua']['unknown'],{'preserve':1})
        self.assertEqual(indexed['scripts/old14.lua']['md5'],hashlib.md5(b'new').hexdigest())
        self.assertEqual(parent['files'][0]['sha256'],g.sha(b'old'),'parent never mutated')

    def test_unknown_source_change_and_forged_parent_origins_fail_closed(self):
        parent,origins,repos,binding=self.fixture()
        with patch.object(g,'git_changes',return_value=[{'path':'scripts/new_unmapped.lua','kind':'A'}]),self.assertRaisesRegex(g.Refused,'unmapped'):
            g.derive_payload_plan(parent,repos,[binding],parent_origins=origins,parent_manifest_sha256='1'*64)
        origins['scripts/protected.lua']['resource_sha256']='f'*64
        with self.assertRaisesRegex(g.Refused,'origin'):
            g.derive_payload_plan(parent,repos,[binding],parent_origins=origins,parent_manifest_sha256='1'*64)

    def test_compiled_input_and_output_pins_are_both_from_immutable_git(self):
        parent,origins,repos,binding=self.fixture()
        binding.update(kind='compiled',inputs=[dict(repo='content',path='panorama/source.js')],
            source_pins={'content:panorama/source.js':g.sha(b'new source')})
        def blob(repo,*args):return b'new source' if args[-1].endswith('panorama/source.js') else b'new'
        with patch.object(g,'git_changes',return_value=[]),patch.object(g,'_git',side_effect=blob):
            result=g.derive_payload_plan(parent,repos,[binding],parent_origins=origins,parent_manifest_sha256='1'*64)
        self.assertEqual(result['source_pins'],{'content:panorama/source.js':g.sha(b'new source')})
        binding['source_pins']['content:panorama/source.js']='f'*64
        with patch.object(g,'git_changes',return_value=[]),patch.object(g,'_git',side_effect=blob),self.assertRaisesRegex(g.Refused,'source_binding'):
            g.derive_payload_plan(parent,repos,[binding],parent_origins=origins,parent_manifest_sha256='1'*64)

    def test_resource_deletion_is_never_silent(self):
        parent,origins,repos,binding=self.fixture()
        def changes(repo,*args):return [{'path':'scripts/old14.lua','kind':'D'}] if repo.endswith('game') else []
        with patch.object(g,'git_changes',side_effect=changes),self.assertRaisesRegex(g.Refused,'removal'):
            g.derive_payload_plan(parent,repos,[binding],parent_origins=origins,parent_manifest_sha256='1'*64)


if __name__=='__main__':unittest.main()
