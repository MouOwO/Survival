"""Pure isolated route contracts; no actual client, SDK, key, or process query."""
from pathlib import Path
from unittest.mock import patch
import copy,importlib.util,json,subprocess,tempfile,unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('resolution_route_contract',HERE/'rehearsal.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
p,b=r.p,r.b


class RouteContracts(unittest.TestCase):
    def test_lobby_only_omits_direct_entry_and_keeps_all_production_flags(self):
        log=r.expected_log_path(r.STORE/'run01_lobby')
        direct=r.arguments(log,'direct');lobby=r.arguments(log,'lobby')
        self.assertEqual(direct,lobby+['+dota_launch_custom_game','3824360109','ws4_entry'])
        self.assertEqual(lobby,['-steam','-novid','-console','-vconport','29060','-condebug',
            '-con_logfile',str(log),'+sv_cheats','0','+survival_archive_http_enabled','1'])

    def test_unknown_or_unbound_route_refuses(self):
        with patch.object(r,'_ROUTE_CONTEXT',None):
            for route in (None,'manual','adopt','lobby;quit'):
                with self.subTest(route=route),self.assertRaises(ValueError):r.arguments(Path('log'),route)

    def test_route_cannot_be_changed_in_same_operation_process(self):
        with patch.object(r,'_ROUTE_CONTEXT',None):
            r.bind_route('lobby');r.bind_route('lobby')
            with self.assertRaises(ValueError):r.bind_route('direct')

    def test_actual_inherited_owned_guard_accepts_lobby_and_rejects_borrowed_argv(self):
        log=r.expected_log_path(r.STORE/'run01_lobby');argv=r.arguments(log,'lobby')
        command=subprocess.list2cmdline([str(p.EXE),*argv])
        raw=dict(pid=1234,created_utc='2026-11-02T00:00:00.0000010Z',executable=str(p.EXE),command_line=command)
        record=dict(p.identity(raw),kind=p.KIND,port=p.PORT,workshop_id=b.ITEM,tools=False,
            offline_logic_requested=False,argv=argv,log_file=str(log))
        observation=dict(dota=[raw],listeners=[])
        with patch.object(r,'_ROUTE_CONTEXT','lobby'):
            self.assertEqual(p.owned(observation,record)['pid'],1234)
            changed=copy.deepcopy(record);changed['argv']=r.arguments(log,'direct')
            with self.assertRaises(ValueError):p.owned(observation,changed)
            foreign=copy.deepcopy(observation);foreign['listeners']=[dict(port=29060,pid=987)]
            with self.assertRaises(ValueError):p.owned(foreign,record)

    def test_process_receipt_routes_are_written_not_reconstructed_as_manual(self):
        writes=[]
        with patch.object(r,'_ROUTE_CONTEXT','lobby'),patch.object(r,'_write_new',side_effect=lambda path,value:writes.append(value)):
            r.write_new(Path('launch_intent.json'),{'status':'REQUESTED_NOT_YET_STARTED'})
            r.write_new(Path('process.json'),{'pid':1234})
        self.assertEqual(len(writes),2)
        for row in writes:
            self.assertEqual(row['launch_route'],'lobby');self.assertTrue(row['owned_launch'])
            self.assertFalse(row['direct_entry_requested']);self.assertFalse(row['lobby_creation_by_tool'])

    def test_main_cannot_apply_route_to_inspect_or_skip_it_on_launch(self):
        with patch.object(p,'load_transaction',side_effect=AssertionError('No actual package I/O')):
            for args in (['launch','--transaction','run01','--report-sha256','a'*64],
                ['inspect','--transaction','run01','--report-sha256','a'*64,'--label','after01','--route','lobby']):
                with self.subTest(args=args),self.assertRaises(ValueError):r.main(args)

    def test_missing_actual_compiler_pin_is_fail_closed(self):
        pins=copy.deepcopy(b.COMPILED);pins[b.PAYLOADS[12]]['compiled_sha256']=None
        with patch.object(b,'COMPILED',pins),patch.object(b,'immutable_revision',return_value='a'*40),\
            patch.object(b,'blob',side_effect=AssertionError('No Git payload before pin')):
            with self.assertRaisesRegex(ValueError,'PENDING_OFFICIAL_COMPILER_PROOF'):b.payloads('a'*40)


if __name__=='__main__':unittest.main()
