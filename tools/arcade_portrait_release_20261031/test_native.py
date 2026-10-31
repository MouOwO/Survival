"""Synthetic native entry ownership checks; no install, launch, UI or SDK."""
from contextlib import ExitStack,redirect_stdout
from datetime import datetime,timezone
from pathlib import Path
from unittest.mock import Mock,patch
import copy
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest

_spec=importlib.util.spec_from_file_location('portrait1101_test_native',Path(__file__).with_name('native.py'))
n=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(n)


class NativeEntryTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='native_entry_synthetic_');self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name).resolve();self.stack=ExitStack();self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(n.b,'REPORT',self.root))
        self.stack.enter_context(patch.object(n,'HANDOFF',self.root/'native_handoff.json'))
        self.snapshot=self.stack.enter_context(patch.object(n,'snapshot',side_effect=AssertionError('No actual CIM')))
        self.steam=self.stack.enter_context(patch.object(n,'steam_ready',side_effect=AssertionError('No actual SDK')))
        self.popen=self.stack.enter_context(patch.object(n.subprocess,'Popen',side_effect=AssertionError('No actual launch')))
        self.process_calls=self.stack.enter_context(patch.object(n.subprocess,'run',side_effect=AssertionError('No actual helper process')))
        self.validator=self.stack.enter_context(patch.object(n,'validated_package',side_effect=AssertionError('No actual package operation')))
        self.clean={'dota':[],'steam_running':True,'listeners':[]}
        self.path=n.run_directory('v01');log=self.path/'engine.log';argv=n.arguments(log)
        command=subprocess.list2cmdline([str(n.EXE),*argv])
        self.record=dict(schema=1,kind='OWNED_SIGNED_NATIVE_PROCESS',status='SIGNED_PRODUCTION_SMOKE_STARTED',
            pid=50000,created_utc='2026-11-01T00:00:01.0000000Z',started_utc='2026-11-01T00:00:00Z',
            addon=n.ADDON,port=n.PORT,mode='production_smoke',log_file=str(log),argv=argv,
            executable=str(n.EXE),command_line_sha256=n.b.sha(command.encode()),package_report_sha256='a'*64)
        self.observed={'dota':[dict(pid=50000,created_utc=self.record['created_utc'],executable=str(n.EXE),command_line=command)],
            'steam_running':True,'listeners':[{'port':29026,'pid':50000,'address':'127.0.0.1'}]}

    def save_process(self):
        self.path.mkdir(parents=True,exist_ok=True)
        (self.path/'process.json').write_text(json.dumps(self.record),encoding='utf8')

    def test_default_plan_is_pure_and_cannot_request_production_offline(self):
        with redirect_stdout(io.StringIO()) as output:self.assertEqual(n.main([]),0)
        result=json.loads(output.getvalue());self.assertEqual(result['status'],'SIGNED_NATIVE_PLAN_ONLY')
        self.assertEqual(result['port'],29026);self.assertEqual(result['addon'],'svt_ap1101')
        self.assertEqual(result['offline_status'],'SIGNED_PRODUCTION_OFFLINE_NOT_SUPPORTED')
        self.assertEqual(list(self.root.iterdir()),[])
        for call in (self.snapshot,self.steam,self.popen,self.process_calls,self.validator):call.assert_not_called()

    def test_launch_offline_refuses_before_package_process_or_network_actions(self):
        with self.assertRaisesRegex(ValueError,'SIGNED_PRODUCTION_OFFLINE_NOT_SUPPORTED'):n.launch_offline('a'*64,'v01')
        for call in (self.snapshot,self.steam,self.popen,self.process_calls,self.validator):call.assert_not_called()

    def test_signed_install_refuses_unsigned_before_any_external_action(self):
        self.validator.side_effect=ValueError('unsigned review refused')
        with self.assertRaisesRegex(ValueError,'unsigned'):n.install('a'*64)
        self.validator.assert_called_once_with('a'*64,full=True)
        self.snapshot.assert_not_called();self.steam.assert_not_called();self.popen.assert_not_called()

    def test_install_refuses_current_user_client_before_steam_or_copy(self):
        self.validator.side_effect=None;self.validator.return_value=({}, {}, {})
        self.snapshot.side_effect=None;self.snapshot.return_value=dict(self.clean,dota=[{'pid':28324}])
        with self.assertRaisesRegex(ValueError,'existing Dota'):n.install('a'*64)
        self.steam.assert_not_called();self.popen.assert_not_called()
        self.assertFalse(n.HANDOFF.exists())

    def test_busy_or_foreign_port_and_no_steam_refuse(self):
        for observation in [dict(self.clean,listeners=[{'port':29026,'pid':28324}]),dict(self.clean,steam_running=False)]:
            with self.subTest(observation=observation),self.assertRaises(ValueError):n.no_clients(observation)

    def test_same_owned_process_and_real_creation_is_required(self):
        self.assertEqual(n.owned(self.observed,self.record)['pid'],50000)
        for key,value in [('created_utc','2026-10-31T00:00:01.0000000Z'),('executable',str(self.root/'dota2.exe')),
                ('command_line','different')]:
            observation=copy.deepcopy(self.observed);observation['dota'][0][key]=value
            with self.subTest(key=key),self.assertRaisesRegex(ValueError,'actual CIM'):n.owned(observation,self.record)

    def test_protected_pid_wrong_addon_wrong_port_or_offline_receipt_refused(self):
        for key,value in [('pid',28324),('addon','survival'),('port',29006),('mode','offline')]:
            with self.subTest(key=key),self.assertRaisesRegex(ValueError,'tool-owned'):
                n.owned(self.observed,dict(self.record,**{key:value}))

    def test_command_line_cannot_be_rebound_to_different_launch(self):
        observation=copy.deepcopy(self.observed);record=copy.deepcopy(self.record)
        observation['dota'][0]['command_line']+=' +sv_cheats 1'
        record['command_line_sha256']=n.b.sha(observation['dota'][0]['command_line'].encode())
        with self.assertRaisesRegex(ValueError,'launch contract'):n.owned(observation,record)

    def test_console_requires_own_listener_and_no_other_client(self):
        for observation in [dict(self.observed,listeners=[]),
                dict(self.observed,listeners=[{'pid':28324,'port':29026}]),
                dict(self.observed,dota=self.observed['dota']+[{'pid':28324}])]:
            with self.subTest(observation=observation),self.assertRaises(ValueError):n.owned(observation,self.record)

    def test_launch_receipt_uses_cim_creation_not_python_timestamp(self):
        self.snapshot.side_effect=[self.clean,self.clean,self.observed]
        self.steam.side_effect=None;self.steam.return_value={}
        self.popen.side_effect=None;self.popen.return_value=Mock(pid=50000)
        now=datetime(2026,11,1,tzinfo=timezone.utc)
        with patch.object(n,'installed',return_value=({}, {'content_sha256':'b'*64},self.root)),\
                patch.object(n,'datetime') as clock:
            clock.now.return_value=now
            result=n.launch_smoke('a'*64,'v01')
        created=json.loads((self.path/'process.json').read_bytes())['created_utc']
        self.assertEqual(created,self.record['created_utc']);self.assertNotEqual(created,now.isoformat())
        self.assertEqual(result['pid'],50000);self.assertFalse(result['gameplay_verified'])
        argv=self.popen.call_args.args[0]
        self.assertEqual(argv[argv.index('-vconport')+1],'29026')
        self.assertEqual(argv[argv.index('+sv_cheats')+1],'0')
        self.assertNotIn('+survival_offline_logic_test',argv)

    def test_query_rejects_generation_change_without_writing_receipt(self):
        self.save_process();changed=copy.deepcopy(self.observed)
        changed['dota'][0]['created_utc']='2026-11-01T00:02:00Z'
        self.snapshot.side_effect=[self.observed,changed]
        with patch.object(n,'console',return_value={'expected_output_received':True,'sent':3,'output':'test'}):
            with self.assertRaisesRegex(ValueError,'actual CIM'):n.query('v01')
        self.assertFalse((self.path/'native_cvar_query.json').exists())

    def test_query_receipt_records_real_generation_and_readonly_commands(self):
        self.save_process();self.snapshot.side_effect=None;self.snapshot.return_value=self.observed
        output='sv_cheats = false\nsurvival_archive_http_enabled = 1\n'
        with patch.object(n,'console',return_value={'expected_output_received':True,'sent':3,'output':output}):
            n.query('v01')
        result=json.loads((self.path/'native_cvar_query.json').read_bytes())
        self.assertEqual(result['created_utc'],self.record['created_utc'])
        self.assertEqual(result['raw_output_sha256'],n.b.sha(output.encode()))
        self.assertEqual(result['commands'],['sv_cheats','survival_archive_http_enabled'])
        self.assertFalse(result['script_injection'])

    def test_close_never_touches_current_user_and_only_sends_graceful_quit(self):
        self.save_process();user={'pid':28324}
        self.snapshot.side_effect=[dict(self.observed,dota=self.observed['dota']+[user]),dict(self.clean,dota=[user])]
        with patch.object(n,'console',return_value={'sent':1}) as transport:
            result=n.close('v01')
        self.assertEqual(result['pid'],50000);self.assertFalse(result['force_stop_performed'])
        self.assertEqual(transport.call_args.args[1],'close')
        self.popen.assert_not_called();self.process_calls.assert_not_called()

    def test_close_pid_reuse_refuses_without_console_send(self):
        self.save_process();observation=copy.deepcopy(self.observed)
        observation['dota'][0]['created_utc']='2026-11-01T00:04:00Z'
        self.snapshot.side_effect=None;self.snapshot.return_value=observation
        with patch.object(n,'console') as transport:
            with self.assertRaisesRegex(ValueError,'actual CIM'):n.close('v01')
        transport.assert_not_called()


if __name__=='__main__':unittest.main()
