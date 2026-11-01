"""Isolated1105 contracts: no real native, SDK, installation or game action."""
from pathlib import Path
from contextlib import nullcontext,redirect_stdout
from unittest.mock import Mock,patch
import ctypes as C
import importlib.util
import io
import json
import tempfile
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('isolated1105_rehearsal',HERE/'rehearsal.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
p,b=r.p,r.b


class FakeKernel:
    def __init__(self,source):
        self.created=p.utc_ticks(source['created_utc'])+7;self.exited=False
        self.OpenProcess=Mock(return_value=0x1234);self.CloseHandle=Mock(return_value=1)
        self.GetProcessTimes=Mock(side_effect=self.times)
        self.QueryFullProcessImageNameW=Mock(side_effect=self.image)
        self.WaitForSingleObject=Mock(side_effect=self.wait)
    def times(self,handle,creation,exited,kernel,user):
        for pointer,value in ((creation,self.created),(exited,self.created+10000000 if self.exited else 0),(kernel,1),(user,1)):
            target=C.cast(pointer,C.POINTER(p.FILETIME)).contents;target.low=value&0xffffffff;target.high=value>>32
        return 1
    def image(self,handle,flags,buffer,size):
        if self.exited:raise AssertionError('No image query after exit')
        buffer.value=str(p.EXE);C.cast(size,C.POINTER(C.c_uint32)).contents.value=len(buffer.value);return 1
    def wait(self,handle,ms):
        if ms==0:return 0 if self.exited else 258
        assert ms==2000;self.exited=True;return 0


class RehearsalTests(unittest.TestCase):
    def test_default_plan_zero_effects_and_correct_five_account_parent(self):
        with patch.object(p,'snapshot',side_effect=AssertionError('No OS')),patch.object(p,'steam_ready',side_effect=AssertionError('No SDK')),\
                patch.object(p,'write_new',side_effect=AssertionError('No write')),redirect_stdout(io.StringIO()) as out:r.main([])
        value=json.loads(out.getvalue())
        self.assertEqual((value['release_sequence'],value['original_release_sequence'],value['approved_accounts']),(2026110105,2026110104,5))
        self.assertEqual((value['files_written'],value['os_queries'],value['clients_started']),(0,0,0))
        self.assertIsNone(value['expected_runtime_source_revision']);self.assertFalse(value['ready_for_upload'])
        self.assertEqual(value['restoration_status'],'ORIGINAL0104_FIVE_FILES_FULLY_RESTORED')

    def test_unset_source_rejects_all_actions_before_package_or_native(self):
        with patch.object(r,'RUNTIME_SOURCE_REVISION',None),patch.object(r.c,'validated_package',side_effect=AssertionError('No package')),\
                patch.object(p,'snapshot',side_effect=AssertionError('No native')),patch.object(p,'steam_ready',side_effect=AssertionError('No SDK')):
            for action in ('stage','launch','inspect','close','restore'):
                argv=[action,'--transaction','run01_candidate14','--report-sha256','a'*64]
                if action=='inspect':argv+=['--label','before01']
                with self.subTest(action=action),self.assertRaisesRegex(ValueError,'PENDING_IMMUTABLE_V05'):r.main(argv)

    def test_fixed_paths_and_log_route_are_new_and_disjoint(self):
        folder=r.STORE/'run01_candidate14'
        self.assertEqual(r.expected_log_path(folder),r.LOG_ROOT/'run01_candidate14/engine.log')
        self.assertEqual((p.PORT,b.SEQUENCE,b.BASE_SEQUENCE),(29058,2026110105,2026110104))
        self.assertEqual(p.arguments(r.expected_log_path(folder))[6:8],['-con_logfile',str(r.expected_log_path(folder))])
        with patch.object(p,'regular',side_effect=lambda path,**unused:path):r.fixed_paths()
        for path in (r.STORE.parent/'old/run01_candidate14',r.STORE/'invalid.name'):
            with self.subTest(path=path),self.assertRaises(ValueError):r.expected_log_path(path)

    def test_acf_only_official0104_manifest_no_write(self):
        with tempfile.TemporaryDirectory() as temp:
            file=Path(temp)/'acf'
            for manifest in (r.BASE_MANIFEST,'2484609663754935010','foreign'):
                file.write_text('"AppWorkshop" { "appid" "570" "WorkshopItemsInstalled" { "3824360109" { "manifest" "'+manifest+'" "size" "1" } } }',encoding='utf8')
                with patch.object(p,'ACF',file),patch.object(p,'regular',side_effect=lambda path,**unused:path):
                    if manifest==r.BASE_MANIFEST:self.assertEqual(r.acf_item()['item']['manifest'],manifest)
                    else:
                        with self.assertRaisesRegex(ValueError,'Official five-account0104'):r.acf_item()

    def test_new_signed_identity_and_source_are_required(self):
        package=dict(source_revision='a'*40,package_files=[{'name':name}for name in p.NAMES],content_sha256='b'*64)
        manifest=dict(content_sha256='b'*64);signed=dict(signature_valid=True,release_sequence=2026110105)
        with patch.object(r,'RUNTIME_SOURCE_REVISION','a'*40),patch.object(r.c,'validated_package',return_value=(package,manifest,signed)):
            self.assertEqual(r.package_auth('c'*64),(package,manifest))
            with patch.dict(package,source_revision='d'*40),self.assertRaisesRegex(ValueError,'Exact signed1105'):r.package_auth('c'*64)
            with patch.dict(signed,release_sequence=2026110103),self.assertRaisesRegex(ValueError,'Signed production1105'):r.package_auth('c'*64)

    def test_same_retained_handle_exit_is_native_and_not_image_requeried(self):
        record=dict(pid=1234,created_utc='2026-11-01T08:00:00.1234560Z',executable=str(p.EXE))
        api=FakeKernel(record)
        with patch.object(C,'WinDLL',return_value=api):
            with r.OwnedLifetime(record) as lifetime:
                record['native_created_filetime']=lifetime.native_created_filetime
                self.assertTrue(lifetime.wait_exited());proof=lifetime.verify()
                self.assertTrue(proof['exit_observed']);self.assertEqual(proof['created_filetime'],record['native_created_filetime'])
                self.assertEqual(proof['exit_identity_method'],'SAME_RETAINED_HANDLE_GETPROCESSTIMES')
                self.assertEqual(api.QueryFullProcessImageNameW.call_count,1)
        api.OpenProcess.assert_called_once_with(0x00101000,False,1234);api.CloseHandle.assert_called_once_with(0x1234)

    def test_real_inherited_close_resolves_v05_pins_and_queues_one_owned_message(self):
        # Execute the actual frozen close function, including its module-global
        # lookup. Only native/transaction dependencies are isolated.
        self.assertIs(p.close.__globals__,r.v4.r.__dict__)
        self.assertIs(p.close.__globals__['own_code_pins'],r.own_code_pins)
        pins=r.own_code_pins()
        self.assertIn(str(Path(r.__file__).resolve()),pins)
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp)
            live=dict(pid=1234,created_utc='2026-11-01T08:00:00.1234560Z',native_created_filetime=123,
                code_pins=pins)
            window=dict(hwnd=5678,pid=1234,title='Dota 2',client_width=1600,client_height=900)
            api=Mock();api.main_window.return_value=window;api.request_close.return_value=dict(queued=True,win32_error=0)
            lifetime=Mock();writes=[]
            with patch.object(p,'load_transaction',return_value=(folder,{},None,None)),patch.object(p,'operation_lock',return_value=nullcontext()),\
                    patch.object(p,'live_record',return_value=live),patch.object(p,'snapshot',return_value={}),\
                    patch.object(r.v4.r,'owned'),patch.object(p,'OwnedLifetime',return_value=nullcontext(lifetime)),\
                    patch.object(r.v4.r,'CloseWindowApi',return_value=api),\
                    patch.object(p,'write_new',side_effect=lambda path,value:writes.append((path,value))):
                result=p.close('run01_candidate14','a'*64)
            self.assertEqual(result['status'],'WM_CLOSE_REQUESTED_NOT_EXIT_VERIFIED')
            self.assertFalse(result['force_stop']);self.assertEqual(result['console_connections'],0)
            api.request_close.assert_called_once_with(window)
            self.assertEqual(api.main_window.call_count,2);lifetime.verify.assert_called_once()
            self.assertEqual([path.name for path,value in writes],['close_intent.json','close_requested.json'])
            self.assertEqual(writes[0][1]['code_pins'],pins)

    def exercise_restore(self,*,wrong_parent=False,changed_acf=False):
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp);original=[dict(name=name,bytes=1,sha256='a'*64)for name in p.NAMES]
            record=dict(original_files=original,original_content_sha256=b.BASE_CONTENT,
                original_release_sequence=b.BASE_SEQUENCE,acf=dict(item=dict(manifest=r.BASE_MANIFEST)))
            if wrong_parent:record['original_release_sequence']=2026103102
            writes=[];transition=Mock();no_clients=Mock()
            with patch.object(p,'load_transaction',return_value=(folder,record,{},{})),patch.object(p,'operation_lock',return_value=nullcontext()),\
                    patch.object(p,'no_clients',no_clients),patch.object(r,'acf_item',return_value=dict(item=dict(manifest='changed' if changed_acf else r.BASE_MANIFEST))),\
                    patch.object(p,'require_rows'),patch.object(b,'baseline',return_value=(dict(package_files=original),{})),\
                    patch.object(p,'full_vpk'),patch.object(p,'known_images'),patch.object(p,'transition',transition),\
                    patch.object(p,'write_new',side_effect=lambda path,value:writes.append((path,value))),patch.object(p,'event'):
                if wrong_parent or changed_acf:
                    with self.assertRaises(ValueError):r.restore('run01_candidate14','b'*64)
                    transition.assert_not_called();self.assertEqual(writes,[])
                else:
                    result=r.restore('run01_candidate14','b'*64)
                    self.assertEqual(result['status'],'ORIGINAL0104_FIVE_FILES_FULLY_RESTORED')
                    transition.assert_called_once_with(folder,record,to_original=True)
                    receipt=writes[0][1];self.assertEqual(receipt['original_release_sequence'],2026110104)
                    self.assertEqual(receipt['original_steam_manifest'],r.BASE_MANIFEST)
                    self.assertFalse(receipt['acf_written']);self.assertFalse(receipt['canonical_journal_written'])
                    self.assertEqual(no_clients.call_count,2)

    def test_restore_reports_only_full_official0104(self):self.exercise_restore()
    def test_old_parent_cannot_restore_or_mutate(self):self.exercise_restore(wrong_parent=True)
    def test_acf_changed_before_restore_never_mutates(self):self.exercise_restore(changed_acf=True)


if __name__=='__main__':unittest.main()
