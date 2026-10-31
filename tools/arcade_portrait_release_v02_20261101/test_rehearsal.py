"""Synthetic only: no Windows API, SDK, real install, process or UI operation."""
from contextlib import nullcontext, redirect_stdout
from pathlib import Path
from unittest.mock import Mock, patch
import copy
import ctypes as C
import importlib.util
import io
import json
import os
import tempfile
import types
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('isolated_v02_rehearsal',HERE/'rehearsal.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)


class Synthetic:
    def __init__(self, root):
        # Windows TEMP may itself be an 8.3 alias. Match the fixed production
        # roots, which are already canonical long paths before a native hold.
        self.root=Path(root).resolve(); self.install=self.root/'installed'; self.store=self.root/'transactions'
        self.package_folder=self.root/'package'; self.install.mkdir(); self.package_folder.mkdir()
        self.old=[]; self.new=[]
        for i,name in enumerate(r.NAMES):
            original=('original volume %d' % i).encode(); candidate=original if i in (2,3) else original+b' CANDIDATE'
            (self.install/name).write_bytes(original); (self.package_folder/name).write_bytes(candidate)
            self.old.append(r.row(self.install/name)); self.new.append(r.row(self.package_folder/name))
        self.package=dict(package_files=self.new,source_revision='a'*40,content_sha256='b'*64)
        self.manifest=dict(content_sha256='b'*64)
        self.report_sha='c'*64
        self.acf=dict(item={'manifest':'2484609663754935010','size':'synthetic'},raw_sha256='d'*64)

    def patches(self):
        return [patch.object(r,'INSTALLED',self.install),patch.object(r,'STORE',self.store),
            patch.object(r.b,'OUTPUT',self.package_folder),patch.object(r,'fixed_paths'),
            patch.object(r,'package_auth',return_value=(self.package,self.manifest)),
            patch.object(r.b,'baseline',return_value=(dict(package_files=self.old),dict(content_sha256='e'*64))),
            patch.object(r,'full_vpk'),patch.object(r,'no_clients',return_value={'dota':[]}),
            patch.object(r,'steam_ready',return_value={'logged_on':True}),
            patch.object(r,'acf_item',side_effect=lambda:copy.deepcopy(self.acf)),
            patch.object(r,'operation_lock',side_effect=lambda:nullcontext())]


class RehearsalTests(unittest.TestCase):
    def setUp(self): self.active=[]
    def tearDown(self):
        for item in reversed(self.active): item.stop()
    def setup_fixture(self,root):
        f=Synthetic(root)
        for p in f.patches(): p.start(); self.active.append(p)
        return f

    def test_default_plan_zero_os_sdk_files_or_launch(self):
        with patch.object(r,'snapshot',side_effect=AssertionError('No OS')),\
             patch.object(r,'package_auth',side_effect=AssertionError('No candidate reads')),\
             patch.object(r,'steam_ready',side_effect=AssertionError('No SDK')),\
             patch.object(r,'write_new',side_effect=AssertionError('No writes')),\
             patch.object(r.subprocess,'Popen',side_effect=AssertionError('No process')),redirect_stdout(io.StringIO()) as out:
            r.main([])
        proof=json.loads(out.getvalue()); self.assertEqual(proof['files_written'],0)
        self.assertEqual(proof['status'],'STATIC_REHEARSAL_PLAN_NO_EFFECTS')
        self.assertFalse(proof['ready_for_upload']); self.assertFalse(proof['official_download'])

    def test_every_real_action_without_signed_report_refuses_before_os_or_writes(self):
        for action in ('stage','launch','inspect','close','restore'):
            with self.subTest(action=action),patch.object(r,'snapshot') as os_query,\
                    patch.object(r,'write_new') as write,patch.object(r,'steam_ready') as sdk:
                with self.assertRaisesRegex(ValueError,'signed report SHA'):
                    getattr(r,action)('trial',None,*(['one'] if action=='inspect' else []))
                os_query.assert_not_called(); write.assert_not_called(); sdk.assert_not_called()

    def test_unsigned_or_wrong_sequence_never_admitted(self):
        for signed in ({'signature_valid':False,'release_sequence':r.b.SEQUENCE},
                       {'signature_valid':True,'release_sequence':r.b.SEQUENCE-1}):
            with patch.object(r.c,'validated_package',return_value=({}, {}, signed)):
                with self.assertRaisesRegex(ValueError,'Signed production candidate'):r.package_auth('a'*64)

    def test_full_physical_backup_stage_index_last_and_exact_restore(self):
        with tempfile.TemporaryDirectory() as temp:
            f=self.setup_fixture(temp)
            actual_replace=r.os.replace; seen=[]
            def replace(source,target):
                seen.append(Path(target).name); return actual_replace(source,target)
            with patch.object(r.os,'replace',side_effect=replace):
                result=r.stage('trial',f.report_sha)
            self.assertEqual(result['status'],'LOCAL_SIGNED_CANDIDATE_STAGED_NOT_OFFICIAL_DOWNLOAD')
            folder=f.store/'trial'; self.assertEqual(r.inventory(folder/'backup'),f.old)
            self.assertEqual(r.inventory(folder/'candidate'),f.new); self.assertEqual(r.inventory(f.install),f.new)
            self.assertEqual(seen[-1],r.NAMES[0])
            for name in r.NAMES:
                self.assertEqual((folder/'backup'/name).stat().st_nlink,1)
                self.assertNotEqual((folder/'backup'/name).stat().st_ino,(f.install/name).stat().st_ino)
            record=r.json_read(folder/'transaction.json'); seen.clear()
            with patch.object(r,'load_transaction',return_value=(folder,record,f.package,f.manifest)),\
                    patch.object(r.os,'replace',side_effect=replace):
                restored=r.restore('trial',f.report_sha)
            self.assertEqual(restored['status'],'ORIGINAL3102_FIVE_FILES_FULLY_RESTORED')
            self.assertEqual(seen[-1],r.NAMES[0]); self.assertEqual(r.inventory(f.install),f.old)
            self.assertEqual(r.inventory(folder/'backup'),f.old)
            self.assertFalse(restored['publication_performed'])

    def test_unknown_image_blocks_all_restore_before_first_mutation(self):
        with tempfile.TemporaryDirectory() as temp:
            f=self.setup_fixture(temp); r.stage('trial',f.report_sha)
            folder=f.store/'trial'; record=r.json_read(folder/'transaction.json')
            (f.install/r.NAMES[3]).write_bytes(b'STEAM FOREIGN BYTES')
            before=[(f.install/name).read_bytes() for name in r.NAMES]
            with patch.object(r,'load_transaction',return_value=(folder,record,f.package,f.manifest)),\
                    patch.object(r.os,'replace') as replace:
                with self.assertRaisesRegex(ValueError,'Unknown current VPK'):r.restore('trial',f.report_sha)
            replace.assert_not_called(); self.assertEqual(before,[(f.install/name).read_bytes() for name in r.NAMES])
            self.assertEqual(r.inventory(folder/'backup'),f.old)

    def test_changed_acf_blocks_restore_before_first_target_mutation(self):
        with tempfile.TemporaryDirectory() as temp:
            f=self.setup_fixture(temp);r.stage('trial',f.report_sha)
            folder=f.store/'trial';record=r.json_read(folder/'transaction.json')
            before=r.inventory(f.install);f.acf['item']['manifest']='FOREIGN'
            with patch.object(r,'load_transaction',return_value=(folder,record,f.package,f.manifest)),\
                    patch.object(r.os,'replace') as replace:
                with self.assertRaisesRegex(ValueError,'ACF changed before restoration'):r.restore('trial',f.report_sha)
            replace.assert_not_called();self.assertEqual(r.inventory(f.install),before)

    def test_space_guard_reserves_the_larger_candidate_temporary_too(self):
        with tempfile.TemporaryDirectory() as temp:
            f=self.setup_fixture(temp)
            insufficient=sum(x['bytes'] for x in f.old+f.new)+max(x['bytes'] for x in f.old)+r.RESERVE
            self.assertGreater(max(x['bytes'] for x in f.new),max(x['bytes'] for x in f.old))
            with patch.object(r.shutil,'disk_usage',return_value=types.SimpleNamespace(free=insufficient)),\
                    patch.object(r.os,'replace') as replace:
                with self.assertRaisesRegex(ValueError,'temporary space required'):r.stage('trial',f.report_sha)
            replace.assert_not_called();self.assertEqual(r.inventory(f.install),f.old)
            self.assertFalse((f.store/'trial').exists())

    def test_external_change_during_temp_copy_refuses_target_replace(self):
        with tempfile.TemporaryDirectory() as temp:
            f=self.setup_fixture(temp); r.stage('trial',f.report_sha)
            folder=f.store/'trial'; record=r.json_read(folder/'transaction.json')
            original_copy=r.copy_new
            def tamper(source,target,expected):
                original_copy(source,target,expected)
                (f.install/expected['name']).write_bytes(b'EXTERNAL UPDATE')
            with patch.object(r,'copy_new',side_effect=tamper),patch.object(r.os,'replace') as replace:
                with self.assertRaisesRegex(ValueError,'conflict after temporary copy'):
                    r.transition(folder,record,to_original=True)
            replace.assert_not_called()

    def test_partial_stage_failure_keeps_backup_and_explicit_recovery(self):
        with tempfile.TemporaryDirectory() as temp:
            f=self.setup_fixture(temp); original_replace=r.os.replace; calls=[]
            def fail_second(source,target):
                calls.append(Path(target).name)
                if len(calls)==2: raise OSError('synthetic failure')
                original_replace(source,target)
            with patch.object(r.os,'replace',side_effect=fail_second):
                with self.assertRaises(OSError):r.stage('trial',f.report_sha)
            folder=f.store/'trial'; self.assertEqual(r.inventory(folder/'backup'),f.old)
            events=[r.json_read(p) for p in sorted((folder/'events').iterdir())]
            self.assertEqual(events[-1]['status'],'RECOVERY_REQUIRED_NO_AUTOMATIC_RESTORE')
            self.assertNotEqual(r.inventory(f.install),f.old)
            self.assertEqual((f.install/r.NAMES[0]).read_bytes(),('original volume 0').encode())

    def test_unknown_extra_file_or_hardlink_is_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            f=self.setup_fixture(temp); (f.install/'foreign.tmp').write_bytes(b'x')
            with self.assertRaisesRegex(ValueError,'Exact five'):r.inventory(f.install)
            (f.install/'foreign.tmp').unlink()
            os.link(f.install/r.NAMES[0],f.root/'hardlinked')
            with self.assertRaisesRegex(ValueError,'hardlinks'):r.inventory(f.install)

    def test_launch_arguments_keep_original_item_non_tools_and_no_offline_flag(self):
        args=r.arguments(Path('D:/new/engine.log'))
        self.assertEqual(args[-3:],['+dota_launch_custom_game','3824360109','ws4_entry'])
        for forbidden in ('-tools','-dev','-addon','-insecure','+survival_offline_logic_test'):
            self.assertNotIn(forbidden,args)
        self.assertEqual(args[args.index('+sv_cheats')+1],'0')
        self.assertEqual(args[args.index('+survival_archive_http_enabled')+1],'1')

    def process_fixture(self):
        log=Path('D:/rehearsal/engine.log'); line=r.subprocess.list2cmdline([str(r.EXE),*r.arguments(log)])
        observed=dict(pid=1234,created_utc='2026-11-01T00:00:00.1234560Z',executable=str(r.EXE),command_line=line)
        live=dict(kind=r.KIND,**r.identity(observed),port=r.PORT,workshop_id=r.b.ITEM,argv=r.arguments(log),
            log_file=str(log),tools=False,offline_logic_requested=False,
            native_created_filetime=r.utc_ticks(observed['created_utc'])+7)
        snap=dict(dota=[observed],listeners=[dict(port=r.PORT,pid=1234)])
        return observed,live,snap

    def test_owned_rejects_pid_reuse_other_client_wrong_argv_or_port(self):
        observed,live,snap=self.process_fixture(); r.owned(snap,live)
        cases=[]
        q=copy.deepcopy(snap); q['dota'][0]['created_utc']='2026-11-01T00:00:00.1234568Z'; cases.append(q)
        q=copy.deepcopy(snap); q['dota'].append(dict(observed,pid=9999)); cases.append(q)
        q=copy.deepcopy(snap); q['listeners'][0]['port']=r.PORT+1; cases.append(q)
        q=copy.deepcopy(snap); q['dota'][0]['command_line']+=' -tools'; cases.append(q)
        for case in cases:
            with self.subTest(case=case),self.assertRaises(ValueError):r.owned(case,live)

    def test_restart_manager_filetime_preserves_100ns_and_never_accepts_old_pid(self):
        game=dict(pid=1234,created_utc='2026-11-01T00:00:00.1234560Z',native_created_filetime=r.utc_ticks('2026-11-01T00:00:00.1234567Z'))
        keeper=dict(pid=5678,created_utc='2026-11-01T00:00:01.0000000Z',native_created_filetime=r.utc_ticks('2026-11-01T00:00:01.0000003Z'))
        rows=[dict(pid=game['pid'],created_filetime=game['native_created_filetime']-1),
              dict(pid=keeper['pid'],created_filetime=keeper['native_created_filetime'])]
        self.assertEqual(r.file_use_result(rows,game,keeper),dict(owned_dota_uses_file=False,owned_keeper_uses_file=True))
        rows[0]['created_filetime']+=1
        self.assertTrue(r.file_use_result(rows,game,keeper)['owned_dota_uses_file'])
        self.assertEqual(game['native_created_filetime']-r.utc_ticks('2026-11-01T00:00:00.1234566Z'),1)
        self.assertFalse(r.file_use_result(rows,dict(pid=1234,created_utc=game['created_utc']),keeper)['owned_dota_uses_file'])

    def test_ctypes_abi_and_rm_has_only_four_non_destructive_apis(self):
        self.assertEqual((C.sizeof(r.FILETIME),C.sizeof(r.FILE_INFO),C.sizeof(r.RM_UNIQUE_PROCESS),C.sizeof(r.RM_PROCESS_INFO)),(8,52,12,668))
        source=Path(r.__file__).read_text(encoding='utf8')
        for destructive in ('RmShutdown','RmRestart','TerminateProcess','Stop-Process','taskkill','SetForegroundWindow'):
            self.assertNotIn(destructive,source)
        self.assertIn("CreateFileW(str(path),0x80000000,1,None,3,0x80,None)",source)
        self.assertIn("paths=(C.c_wchar_p*1)",source)

    def fake_file_api(self, fail_at=None):
        paths={}; api=types.SimpleNamespace()
        def create(path,access,sharing,security,creation,attributes,template):
            self.assertEqual((access,sharing,security,creation,attributes,template),(0x80000000,1,None,3,0x80,None))
            if fail_at is not None and len(paths)==fail_at:return C.c_void_p(-1).value
            handle=100+len(paths);paths[handle]=Path(path);return handle
        def information(handle,pointer):
            value=C.cast(pointer,C.POINTER(r.FILE_INFO)).contents
            value.links=1;value.volume=33;value.index_low=handle;value.size_low=paths[handle].stat().st_size
            return 1
        def final(handle,buffer,capacity,flags):
            buffer.value=str(paths[handle].resolve());return len(buffer.value)
        api.CreateFileW=Mock(side_effect=create);api.GetFileInformationByHandle=Mock(side_effect=information)
        api.GetFinalPathNameByHandleW=Mock(side_effect=final);api.CloseHandle=Mock(return_value=1)
        return api

    def test_real_hold_logic_uses_read_only_sharing_and_releases_all_on_partial_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            f=self.setup_fixture(temp);api=self.fake_file_api()
            with patch.object(r.C,'WinDLL',return_value=api):
                with r.FiveHolds(f.install) as held:self.assertEqual(len(held.identities),5)
            self.assertEqual(api.CloseHandle.call_count,5)
            api=self.fake_file_api(fail_at=2)
            with patch.object(r.C,'WinDLL',return_value=api):
                with self.assertRaisesRegex(ValueError,'hold failed'):
                    with r.FiveHolds(f.install):pass
            self.assertEqual([call.args[0] for call in api.CloseHandle.call_args_list],[101,100])

    def test_expected_path_is_not_resolved_again_to_follow_a_redirect(self):
        with tempfile.TemporaryDirectory() as temp:
            f=self.setup_fixture(temp);api=self.fake_file_api()
            # Simulate a new redirect that would make resolving BOTH names
            # produce the same other path. The original fixed path must win.
            with (patch.object(Path,'resolve',return_value=Path('D:/redirected')),
                  patch.object(r.C,'WinDLL',return_value=api)):
                with self.assertRaisesRegex(ValueError,'differs from fixed target'):
                    with r.FiveHolds(f.install):pass
            api.CloseHandle.assert_called_once_with(100)

    def fake_rm_api(self, *, oversized=False):
        api=types.SimpleNamespace()
        def start(pointer,flags,key):C.cast(pointer,C.POINTER(C.c_uint32)).contents.value=77;return 0
        def getlist(session,needed,count,rows,reasons):
            size=C.cast(needed,C.POINTER(C.c_uint32));filled=C.cast(count,C.POINTER(C.c_uint32))
            if rows is None:size.contents.value=65 if oversized else 1;return 234
            filled.contents.value=1;rows[0].process.pid=1234
            ticks=r.utc_ticks('2026-11-01T00:00:00.1234567Z')
            rows[0].process.start.low=ticks&0xffffffff;rows[0].process.start.high=ticks>>32
            return 0
        api.RmStartSession=Mock(side_effect=start);api.RmRegisterResources=Mock(return_value=0)
        api.RmGetList=Mock(side_effect=getlist);api.RmEndSession=Mock(return_value=0)
        return api

    def test_real_rm_logic_registers_only_one_fixed_file_and_always_ends_session(self):
        with tempfile.TemporaryDirectory() as temp:
            f=self.setup_fixture(temp);api=self.fake_rm_api();target=f.install/r.NAMES[0]
            with patch.object(r.C,'WinDLL',return_value=api): result=r.restart_manager_users(target)
            self.assertEqual(result,[dict(pid=1234,created_filetime=r.utc_ticks('2026-11-01T00:00:00.1234567Z'))])
            args=api.RmRegisterResources.call_args.args
            self.assertEqual(args[1],1);self.assertEqual(args[2][0],str(target))
            self.assertEqual(args[3:],(0,None,0,None));self.assertEqual(api.RmEndSession.call_count,1)
            self.assertEqual(api.RmGetList.call_count,2)
            api=self.fake_rm_api(oversized=True)
            with patch.object(r.C,'WinDLL',return_value=api),self.assertRaisesRegex(ValueError,'Bounded'):
                r.restart_manager_users(target)
            self.assertEqual(api.RmEndSession.call_count,1)

    def fake_lifetime_api(self,record,*,wrong_creation=False):
        api=types.SimpleNamespace(native_delta=-1 if wrong_creation else 7)
        def times(handle,created,exited,kernel,user):
            value=C.cast(created,C.POINTER(r.FILETIME)).contents
            ticks=r.utc_ticks(record['created_utc'])+api.native_delta
            value.low=ticks&0xffffffff;value.high=ticks>>32;return 1
        def image(handle,flags,buffer,size):
            buffer.value=str(r.EXE);C.cast(size,C.POINTER(C.c_uint32)).contents.value=len(buffer.value);return 1
        api.OpenProcess=Mock(return_value=500);api.CloseHandle=Mock(return_value=1)
        api.GetProcessTimes=Mock(side_effect=times);api.QueryFullProcessImageNameW=Mock(side_effect=image)
        api.WaitForSingleObject=Mock(side_effect=[258,0]);return api

    def test_owned_process_wait_uses_readonly_handle_without_stable_cim_or_hash(self):
        observed,live,snap=self.process_fixture();api=self.fake_lifetime_api(live)
        with patch.object(r.C,'WinDLL',return_value=api),\
                patch.object(r,'snapshot',side_effect=AssertionError('No stable CIM')) as query,\
                patch.object(r,'digest',side_effect=AssertionError('No stable hash')):
            with r.OwnedLifetime(live) as process:
                self.assertFalse(process.wait_exited());self.assertTrue(process.wait_exited())
        self.assertEqual(api.OpenProcess.call_args.args,(0x00101000,False,live['pid']))
        self.assertEqual([call.args for call in api.WaitForSingleObject.call_args_list],[(500,2000),(500,2000)])
        api.CloseHandle.assert_called_once_with(500);query.assert_not_called()

    def test_old_process_generation_cannot_be_adopted_by_lifetime_handle(self):
        observed,live,snap=self.process_fixture();api=self.fake_lifetime_api(live,wrong_creation=True)
        with patch.object(r.C,'WinDLL',return_value=api),self.assertRaisesRegex(ValueError,'creation/executable mismatch'):
            with r.OwnedLifetime(live):pass
        api.CloseHandle.assert_called_once_with(500);api.WaitForSingleObject.assert_not_called()

    def test_cim_microsecond_is_not_a_fake_native_100ns_pin(self):
        observed,live,snap=self.process_fixture();api=self.fake_lifetime_api(live)
        self.assertNotEqual(live['native_created_filetime'],r.utc_ticks(live['created_utc']))
        with patch.object(r.C,'WinDLL',return_value=api):
            with r.OwnedLifetime(live) as process:
                self.assertEqual(process.native_created_filetime,live['native_created_filetime'])
                api.native_delta=8
                with self.assertRaisesRegex(ValueError,'Exact native process creation pin changed'):process.verify()

    def test_one_file_use_never_becomes_five_file_or_gameplay_pass(self):
        with tempfile.TemporaryDirectory() as temp:
            f=self.setup_fixture(temp);r.stage('trial',f.report_sha)
            folder=f.store/'trial';record=r.json_read(folder/'transaction.json')
            observed,live,snap=self.process_fixture();keeper_observed=dict(pid=4321,
                created_utc='2026-11-01T00:00:01.0000000Z',executable='python.exe',command_line='SYNTHETIC')
            keeper=r.identity(keeper_observed);keeper['native_created_filetime']=r.utc_ticks(keeper['created_utc'])+3
            ids=[dict(name=name,file_index=i) for i,name in enumerate(r.NAMES)]
            live.update(package_report_sha256=f.report_sha,content_sha256=f.package['content_sha256'],
                source_revision=f.package['source_revision'],code_pins=record['code_pins'],keeper=keeper,
                held_files=ids,log_file=str(folder/'engine.log'))
            live['argv']=r.arguments(Path(live['log_file']))
            observed['command_line']=r.subprocess.list2cmdline([str(r.EXE),*live['argv']])
            live.update(r.identity(observed));snap['dota']=[observed]
            r.write_new(folder/'process.json',live);(folder/'engine.log').write_bytes(b'SYNTHETIC startup only')
            def rmusers(path):
                result=[dict(pid=keeper['pid'],created_filetime=keeper['native_created_filetime'])]
                if path.name==r.NAMES[0]:result.append(dict(pid=live['pid'],created_filetime=live['native_created_filetime']))
                return result
            with patch.object(r,'load_transaction',return_value=(folder,record,f.package,f.manifest)),\
                    patch.object(r,'snapshot',return_value=snap),patch.object(r,'process_details',return_value=keeper_observed),\
                    patch.object(r,'FiveHolds') as holds,patch.object(r,'restart_manager_users',side_effect=rmusers) as rm:
                holds.return_value.__enter__.return_value=types.SimpleNamespace(identities=ids)
                result=r.inspect('trial',f.report_sha,'one_file_only')
            self.assertEqual(rm.call_count,5);self.assertEqual(result['status'],'INCOMPLETE_NATIVE_FILE_USE_EVIDENCE')
            self.assertFalse(result['all_five_owned_dota_file_uses_observed'])
            self.assertFalse(result['all_five_open_verified']);self.assertTrue(result['index_owned_dota_use_observed'])
            self.assertFalse(result['production_gameplay_verified']);self.assertFalse(result['ready_for_upload'])

    def test_live_receipt_cannot_point_to_another_candidate_or_log(self):
        transaction=dict(package_report_sha256='a'*64,content_sha256='b'*64,source_revision='c'*40,code_pins={})
        folder=Path('D:/rehearsal/trial')
        live=dict(transaction,log_file=str(folder/'engine.log'),native_created_filetime=10,keeper={'native_created_filetime':20})
        with patch.object(r,'json_read',return_value=live):self.assertEqual(r.live_record(folder,transaction),live)
        for key in ('package_report_sha256','source_revision','log_file'):
            bad=dict(live);bad[key]='OTHER'
            with patch.object(r,'json_read',return_value=bad),self.assertRaisesRegex(ValueError,'another transaction'):
                r.live_record(folder,transaction)

    def test_wrong_fixed_target_and_path_traversal_ids_are_refused(self):
        with patch.object(r,'INSTALLED',Path('D:/wrong')):
            with self.assertRaisesRegex(ValueError,'Fixed rehearsal paths'):r.fixed_paths()
        for value in ('../escape','Upper','a/b','a\\b','',None):
            with self.subTest(value=value),self.assertRaises(ValueError):r.safe_id(value)


if __name__ == '__main__':unittest.main()
