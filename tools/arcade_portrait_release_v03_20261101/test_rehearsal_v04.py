"""v04 isolated contracts. Zero real SDK, Win32, process launch or input."""
from pathlib import Path
from contextlib import redirect_stdout
from unittest.mock import Mock,patch
import ctypes as C
import importlib.util
import io
import json
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('isolated_rehearsal_v04',HERE/'rehearsal_v04.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
p=r.p


def record():
    return dict(pid=1234,created_utc='2026-11-01T06:20:00.1234560Z',executable=str(p.EXE))


class FakeKernel:
    def __init__(self,source,*,created=None,exit_time=None,image=None):
        self.created=p.utc_ticks(source['created_utc'])+7 if created is None else created
        self.exit_time=self.created+10000000 if exit_time is None else exit_time
        self.image=str(p.EXE) if image is None else image
        self.exited=False;self.wait_results=[258,0]
        self.OpenProcess=Mock(return_value=0x1234);self.CloseHandle=Mock(return_value=1)
        self.GetProcessTimes=Mock(side_effect=self.times)
        self.QueryFullProcessImageNameW=Mock(side_effect=self.query_image)
        self.WaitForSingleObject=Mock(side_effect=self.wait)
    def times(self,handle,creation,exited,kernel,user):
        for pointer,value in ((creation,self.created),(exited,self.exit_time if self.exited else 0),(kernel,10),(user,10)):
            target=C.cast(pointer,C.POINTER(p.FILETIME)).contents
            target.low=value&0xffffffff;target.high=value>>32
        return 1
    def query_image(self,handle,flags,buffer,size):
        if self.exited:raise AssertionError('Must not query image on an exited process')
        buffer.value=self.image;C.cast(size,C.POINTER(C.c_uint32)).contents.value=len(self.image);return 1
    def wait(self,handle,millis):
        if millis==0:return 0 if self.exited else 258
        assert millis==2000
        result=self.wait_results.pop(0)
        if result==0:self.exited=True
        return result


class V04Tests(unittest.TestCase):
    def test_static_zero_native_or_sdk_or_writes(self):
        with patch.object(p,'snapshot',side_effect=AssertionError('No OS')),patch.object(p,'steam_ready',side_effect=AssertionError('No SDK')),\
                patch.object(p,'write_new',side_effect=AssertionError('No writes')),redirect_stdout(io.StringIO()) as out:
            r.main([])
        result=json.loads(out.getvalue());self.assertEqual(result['operation_tool_version'],4)
        self.assertEqual((result['files_written'],result['os_queries'],result['clients_started']),(0,0,0))
        self.assertFalse(result['ready_for_upload']);self.assertFalse(result['log_copied'])

    def test_exact_mounted_log_route_and_real_configuration(self):
        folder=r.STORE/'run02_candidate14'
        log=r.expected_log_path(folder)
        self.assertEqual(log,r.LOG_ROOT/'run02_candidate14/engine.log')
        self.assertTrue(log.is_relative_to(p.b.ROOT/'output'));self.assertFalse(log.is_relative_to(r.STORE))
        self.assertEqual(p.PORT,29048);self.assertEqual(p.b.SEQUENCE,2026110103)
        self.assertEqual(p.arguments(log)[6:8],['-con_logfile',str(log)])
        with patch.object(p,'regular',side_effect=lambda path,**kwargs:path):r.fixed_paths()
        for wrong in (r.STORE.parent/'old/run02_candidate14',r.STORE/'invalid.name'):
            with self.subTest(wrong=wrong),self.assertRaises(ValueError):r.expected_log_path(wrong)

    def test_v04_retains_exact_signed_runtime_and_reviewed_parent(self):
        self.assertEqual(r.RUNTIME_SOURCE_REVISION,'ceede161d3a009ef5034a5965a1a6c5393930bc2')
        self.assertEqual(r.p.b.PAYLOADS[-1],'scripts/vscripts/systems/archive_service.lua')
        self.assertEqual(len(r.p.b.PAYLOADS),14)
        self.assertEqual(r.p.b.ARCHIVE_SOURCE_SHA256,'6a50c80d15ba98374d8a7df31aa664112070a8ffb4e8b71867a0fd1ae2cddec4')
        pins=r.own_code_pins();self.assertEqual(pins[str(r.PARENT)],r.PARENT_SHA)
        self.assertIn(str(Path(r.__file__).resolve()),pins)

    def test_live_record_requires_native_log_origin_not_a_copied_external_log(self):
        folder=r.STORE/'run02_candidate14';transaction=dict(package_report_sha256='a'*64,content_sha256='b'*64,
            source_revision=r.RUNTIME_SOURCE_REVISION,code_pins={'synthetic':'c'})
        live=dict(transaction,log_file=str(r.expected_log_path(folder)),log_origin='DIRECT_NATIVE_CON_LOGFILE_MOUNTED_OUTPUT',
            native_created_filetime=123,keeper={'native_created_filetime':456})
        with patch.object(p,'json_read',return_value=live):self.assertEqual(r.live_record(folder,transaction),live)
        for changed in (dict(log_file=str(folder/'engine.log')),dict(log_origin='COPIED'),dict(native_created_filetime=None)):
            with self.subTest(changed=changed),patch.object(p,'json_read',return_value=dict(live,**changed)),self.assertRaises(ValueError):r.live_record(folder,transaction)

    def test_lifetime_abi_retains_handle_and_does_not_query_exited_image(self):
        source=record();api=FakeKernel(source)
        with patch.object(r.C,'WinDLL',return_value=api):
            with r.OwnedLifetime(source) as lifetime:
                self.assertFalse(lifetime.wait_exited())
                # Stable timeout does not run extra identity or CIM calls.
                self.assertEqual(api.GetProcessTimes.call_count,1)
                self.assertEqual(api.QueryFullProcessImageNameW.call_count,1)
                self.assertTrue(lifetime.wait_exited());proof=lifetime.verify()
                self.assertEqual(proof['created_filetime'],api.created)
                self.assertTrue(proof['exit_observed']);self.assertTrue(proof['executable_verified_while_alive'])
                self.assertEqual(proof['exit_filetime'],api.exit_time)
                self.assertEqual(api.QueryFullProcessImageNameW.call_count,1)
                self.assertEqual(api.OpenProcess.argtypes,[C.c_uint32,C.c_int32,C.c_uint32])
                self.assertIs(api.OpenProcess.restype,C.c_void_p)
        api.OpenProcess.assert_called_once_with(0x00101000,False,1234)
        api.CloseHandle.assert_called_once_with(0x1234)
        self.assertEqual(C.sizeof(p.FILETIME),8)
        self.assertEqual([c.args[1] for c in api.WaitForSingleObject.call_args_list if c.args[1]!=0],[2000,2000])

    def test_mismatched_creation_executable_and_native_100ns_pin_are_rejected_alive(self):
        for mode in ('cim_creation','image','exact_pin'):
            source=record();api=FakeKernel(source)
            if mode=='cim_creation':api.created+=10
            if mode=='image':api.image=str(p.EXE.parent/'foreign.exe')
            if mode=='exact_pin':source['native_created_filetime']=api.created+1
            with self.subTest(mode=mode),patch.object(r.C,'WinDLL',return_value=api),self.assertRaises(ValueError):
                with r.OwnedLifetime(source):pass
            api.CloseHandle.assert_called_once()

    def test_never_binds_an_already_exited_initial_process(self):
        api=FakeKernel(record());api.exited=True
        with patch.object(r.C,'WinDLL',return_value=api),self.assertRaisesRegex(ValueError,'Alive process'):
            with r.OwnedLifetime(record()):pass
        api.QueryFullProcessImageNameW.assert_not_called();api.CloseHandle.assert_called_once()

    def test_exited_process_creation_changed_or_exit_time_zero_refuses(self):
        for mode in ('changed_creation','zero_exit','times_unavailable','wait_failed'):
            api=FakeKernel(record())
            with self.subTest(mode=mode),patch.object(r.C,'WinDLL',return_value=api):
                with r.OwnedLifetime(record()) as lifetime:
                    if mode=='changed_creation':api.created+=1
                    if mode=='zero_exit':api.exit_time=0
                    if mode=='times_unavailable':api.GetProcessTimes.return_value=0;api.GetProcessTimes.side_effect=None
                    api.wait_results=[0xffffffff if mode=='wait_failed' else 0]
                    with self.assertRaises(ValueError):lifetime.wait_exited()
            api.CloseHandle.assert_called_once()

    def test_no_new_endpoint_cim_or_force_close_after_owned_signal(self):
        text=Path(r.__file__).read_text(encoding='utf8')
        after=text[text.index('while not lifetime.wait_exited()'):text.index('completed=True')]
        self.assertNotIn('no_clients(',after);self.assertNotIn('snapshot(',after);self.assertNotIn('process_details(',after)
        self.assertIn('end_no_dota_check_deferred_to_restore=True',after)
        self.assertNotIn('TerminateProcess',text);self.assertNotIn('Stop-Process',text)


if __name__=='__main__':unittest.main()
