"""Local operator refusal tests. No SSH, database, service or pointer operations."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent


def load(name,file):
    spec=importlib.util.spec_from_file_location(name,HERE/file)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


driver=load('mode_driver_test','mode_release_operator.py')
remote=load('mode_remote_test','mode_release_remote.py')


class ModeReleaseOperatorTests(unittest.TestCase):
    def test_invalid_archive_paths_refused(self):
        for name in ('','.', '..','../x','/x','a/../b','C:/x','a\\b','a//b','a/./b','a\0b'):
            with self.subTest(name=name),self.assertRaises(RuntimeError):driver.safe_name(name)
        self.assertEqual(driver.safe_name('archive/backend/service.py').as_posix(),'archive/backend/service.py')

    def test_tar_duplicate_and_symlink_refused(self):
        for duplicate in (True,False):
            output=io.BytesIO()
            with tarfile.open(fileobj=output,mode='w:gz') as stream:
                first=tarfile.TarInfo('one');first.size=1;stream.addfile(first,io.BytesIO(b'a'))
                item=tarfile.TarInfo('one' if duplicate else 'link')
                if duplicate:item.size=1;stream.addfile(item,io.BytesIO(b'b'))
                else:item.type=tarfile.SYMTYPE;item.linkname='/etc/passwd';stream.addfile(item)
            with self.assertRaises(RuntimeError):driver.unpack(output.getvalue())

    def test_canonical_sql_outer_transaction_only(self):
        files,_,_=driver.sealed_candidate()
        for name,expected in driver.SQL.items():
            raw=files['overlay/database/'+name]
            self.assertEqual(driver.sha(raw),expected)
            body=remote.sql_body(raw)
            self.assertIn('CREATE OR REPLACE FUNCTION public.match_profile_login',body)
            self.assertIn('BEGIN',body)
            self.assertNotIn('\r',body)
            self.assertFalse(body.rstrip().upper().endswith('COMMIT;'))
        with self.assertRaises(RuntimeError):remote.sql_body(b'SELECT 1;')

    def test_lost_commit_never_guessed(self):
        before={'ledger':{},'config':{},'sync':'old'}
        after={'ledger':{'002':'digest'},'config':{'candidate':'digest'},'sync':'new'}
        self.assertEqual(remote.outcome(before,before,after),'NOT_COMMITTED')
        self.assertEqual(remote.outcome(after,before,after),'COMMITTED')
        self.assertEqual(remote.outcome({**before,'sync':'new'},before,after),'UNKNOWN')

    def test_sealed_candidate_is_exact_incremental_mode_scope(self):
        files,review,report=driver.sealed_candidate()
        self.assertEqual(review['bundle'],driver.BUNDLE)
        self.assertEqual(set(review['changed_backend_files']),driver.BACKEND)
        self.assertEqual(set(review['changed_lua_sources']),driver.CHANGED_LUA)
        self.assertEqual({n for n in files if n.startswith('overlay/database/')},{'overlay/database/'+n for n in driver.SQL})
        self.assertTrue(report['cluster_stopped'])
        self.assertEqual(review['applied_003_sha256'],'522891724d0d1df7e105f5da4f508a87e4cdd53c4ea21768a1022f26895ce9b2')

    def check_fixture(self):
        return ({'sha256':'a'*64},{'mode_migrations':[{'id':'target/'+name} for name in driver.SQL],
            'files':{'baseline_pins.json':'b'*64}},b'')

    def test_default_check_makes_no_remote_call(self):
        with mock.patch.object(sys,'argv',['operator']),mock.patch.object(driver,'checked_plan',return_value=self.check_fixture()),mock.patch.object(driver,'transport',side_effect=AssertionError('SSH forbidden')),contextlib.redirect_stdout(io.StringIO()) as out:
            driver.main()
        self.assertFalse(json.loads(out.getvalue())['remote_executed'])

    def test_mutation_requires_exact_review_token(self):
        for action in ('upload','backup','prepare','validate','activate','rollback'):
            with self.subTest(action=action),mock.patch.object(sys,'argv',['operator',action]),mock.patch.object(driver,'checked_plan',return_value=self.check_fixture()),mock.patch.object(driver,'transport',side_effect=AssertionError('SSH forbidden')):
                with self.assertRaisesRegex(RuntimeError,'explicit_reviewed_plan_sha_required'):driver.main()

    def test_mutation_requires_fresh_matching_preflight(self):
        with tempfile.TemporaryDirectory() as folder:
            for state in ({'status':'TRANSPORT_UNAVAILABLE'}, {'status':'PASS','baseline_sha256':'wrong'}):
                Path(folder,'preflight_status.json').write_text(json.dumps(state))
                with self.subTest(state=state),mock.patch.object(sys,'argv',['operator','activate','--execute-reviewed-plan','a'*64]),mock.patch.object(driver,'OUT',Path(folder)),mock.patch.object(driver,'checked_plan',return_value=self.check_fixture()),mock.patch.object(driver,'transport',side_effect=AssertionError('SSH forbidden')):
                    with self.assertRaisesRegex(RuntimeError,'latest_live_preflight_required_or_baseline_drifted'):driver.main()

    def test_expected_state_adds_only004_and_preserves_daily(self):
        operator=remote.Operator.__new__(remote.Operator)
        old={'target/202610200002_archive_match_modes.sql':'old002','target/202610200003_archive_daily_limits.sql':'old003'}
        operator.pins={'functions':{remote.LOGIN:{'sha256':'oldlogin'},remote.SYNC:{'sha256':'oldsync'},'public.daily_rpc()':{'sha256':'daily'}},'constraints':{'mode':'same','daily':'same'}}
        operator.p={'old_ledger':old,'old_config_rows':{'parent':'config'},'bundle':'new','configuration_sha256':'newconfig',
            'mode_migrations':[{'id':'target/202610200004_mode_unlock_chain.sql','sha256':'new004'}],
            'new_function_hashes':{remote.LOGIN:'newlogin',remote.SYNC:'newsync'}}
        after=operator.expected_state(True)
        self.assertEqual(after['ledger'],{**old,'target/202610200004_mode_unlock_chain.sql':'new004'})
        self.assertEqual(after['constraints'],operator.pins['constraints'])
        self.assertEqual(after['functions']['public.daily_rpc()'],'daily')
        self.assertEqual(after['configs'],{'parent':'config','new':'newconfig'})

    def test_empty_ssh_records_is_transport_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            def fail(source,label,timeout):
                module.OUT.mkdir(parents=True)
                (module.OUT/(label+'.json')).write_text(json.dumps({'ssh_exit':255,'records':[]}))
                raise SystemExit(255)
            module=SimpleNamespace(execute=fail)
            spec=SimpleNamespace(loader=SimpleNamespace(exec_module=lambda _:None))
            with mock.patch.object(driver,'OUT',Path(folder)),mock.patch.object(driver.importlib.util,'spec_from_file_location',return_value=spec),mock.patch.object(driver.importlib.util,'module_from_spec',return_value=module):
                with self.assertRaisesRegex(RuntimeError,'ssh_transport_failure_255'):driver.transport('readonly','preflight')

    def test_actual_driver_and_ssh_wrapper_compile_for_all_remote_phases(self):
        # Capture the real legacy SSH transport input after driver STAGE/MODE
        # assembly and outer try-wrapper, without executing SSH or its body.
        # Import-only tests miss future imports rejected by this composition.
        captured=[]
        def subprocess_fixture(args,**kwargs):
            self.assertEqual(args[0],'ssh.exe')
            script=kwargs['input'].decode('utf-8')
            compile(script,'actual_mode_ssh_stdin','exec')
            captured.append(script)
            return SimpleNamespace(returncode=0,stdout=b'{"status":"COMPILE_ONLY_NOT_EXECUTED"}\n')
        with tempfile.TemporaryDirectory() as folder:
            Path(folder,'preflight_status.json').write_text(json.dumps({'status':'PASS','baseline_sha256':'b'*64}))
            for action in ('backup','prepare','validate','activate','verify','rollback'):
                args=['operator',action,'--execute-reviewed-plan','a'*64]
                with self.subTest(action=action),mock.patch.object(sys,'argv',args),mock.patch.object(driver,'OUT',Path(folder)),mock.patch.object(driver,'checked_plan',return_value=self.check_fixture()),mock.patch.object(subprocess,'run',side_effect=subprocess_fixture),contextlib.redirect_stdout(io.StringIO()) as output:
                    driver.main()
                    self.assertEqual(json.loads(output.getvalue())['status'],'COMPILE_ONLY_NOT_EXECUTED')
                    self.assertIn(" MODE='"+action+"'\n",captured[-1])
                    self.assertIn(' class Operator:',captured[-1])
            self.assertEqual(len(captured),6)

    def test_verify_does_not_write_remote_stage(self):
        operator=remote.Operator.__new__(remote.Operator)
        operator.p={'bundle':driver.BUNDLE};operator.new=Path('/release');operator.pay=Path('/payment')
        operator.pointers=mock.Mock();operator.candidate=mock.Mock();operator.health=mock.Mock()
        conn=mock.MagicMock();manager=mock.MagicMock();manager.__enter__.return_value=conn
        operator.connection=lambda:manager
        operator.db_state=lambda _:{'ledger':'checked'}
        operator.expected_state=lambda _:{'ledger':'checked'}
        operator.privileges=mock.Mock()
        operator.save=mock.Mock(side_effect=AssertionError('Remote stage write forbidden'))
        result=operator.verify(save=False)
        self.assertEqual(result['status'],'MODE_RELEASE_VERIFIED')
        operator.save.assert_not_called()
        conn.rollback.assert_called_once()

    def http_opener(self,ready=True,bundle='candidate'):
        calls=[]
        def opener(request,timeout):
            calls.append((request.full_url,request.get_method(),request.data))
            self.assertEqual(request.get_header('Authorization'),'Bearer fixture_token')
            if request.full_url.endswith('/ready'):
                value={'ok':ready,'database':'ready' if ready else 'unavailable'}
            else:
                self.assertTrue(request.full_url.endswith('/v1/archive/config'))
                self.assertEqual(request.data,b'{}')
                value={'ok':True,'config_hash':bundle}
            stream=io.BytesIO(json.dumps(value).encode());stream.status=200 if ready else 503
            return stream
        return opener,calls

    def test_loaded_bundle_must_match_not_just_health_ok(self):
        opener,_=self.http_opener(bundle='old_bundle')
        with self.assertRaisesRegex(RuntimeError,'archive_loaded_bundle_mismatch'):
            remote.archive_http_probe('fixture_token','candidate',opener)

    def test_database_readiness_must_pass_before_config(self):
        opener,calls=self.http_opener(ready=False)
        with self.assertRaisesRegex(RuntimeError,'archive_database_not_ready'):
            remote.archive_http_probe('fixture_token','candidate',opener)
        self.assertEqual(len(calls),1)

    def test_runtime_http_probe_has_no_account_or_token_output(self):
        opener,calls=self.http_opener()
        result=remote.archive_http_probe('fixture_token','candidate',opener)
        self.assertEqual(result,{'database_ready':True,'loaded_bundle':'candidate'})
        self.assertEqual([c[1] for c in calls],['GET','POST'])
        self.assertNotIn('fixture_token',json.dumps(result))
        directory=Path('/opt/goufayu/releases/20261020-archive-caps-v1')
        def runner(args,**kwargs):
            self.assertEqual(args,['systemctl','show','goufayu-api.service','--property=MainPID','--value'])
            return SimpleNamespace(returncode=0,stdout='14689\n')
        def resolver(path):
            self.assertEqual(path,Path('/proc/14689/cwd'))
            return directory
        self.assertTrue(remote.running_release_probe(directory,runner,resolver))
        for wrong in (directory/'backend',Path('/opt/goufayu/releases/old-release')):
            with self.subTest(wrong=wrong),self.assertRaisesRegex(RuntimeError,'archive_running_wrong_release'):
                remote.running_release_probe(directory,runner,lambda _:wrong)


if __name__=='__main__':unittest.main()
