"""Ordinary adapter contracts, entirely mocked. Zero OS/SDK/UI/game actions."""
from contextlib import nullcontext,redirect_stdout
from pathlib import Path
from unittest.mock import Mock,patch
import copy
import ctypes as C
import importlib.util
import io
import json
import tempfile
import types
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('isolated_ordinary_rehearsal_adapter',HERE/'rehearsal_v02.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
p=r.p


def process_fixture():
    log=Path('D:/synthetic/engine.log');argv=p.arguments(log)
    observed=dict(pid=1234,created_utc='2026-11-01T00:00:00.1234560Z',executable=str(p.EXE),
        command_line=p.subprocess.list2cmdline([str(p.EXE),*argv]))
    live=dict(kind=p.KIND,**p.identity(observed),port=p.PORT,workshop_id=p.b.ITEM,argv=argv,log_file=str(log),
        tools=False,offline_logic_requested=False,native_created_filetime=p.utc_ticks(observed['created_utc'])+7)
    return observed,live,dict(dota=[observed],listeners=[],steam_running=True)


def window(hwnd=103,pid=1234):
    return dict(hwnd=hwnd,pid=pid,title='Dota 2',client_width=1600,client_height=900,visible=True,iconic=False,hung=False)


class AdapterTests(unittest.TestCase):
    def test_static_default_never_queries_os_sdk_network_writes_or_window_api(self):
        with patch.object(p,'snapshot',side_effect=AssertionError('No OS')),\
                patch.object(p,'steam_ready',side_effect=AssertionError('No SDK')),\
                patch.object(p,'write_new',side_effect=AssertionError('No writes')),\
                patch.object(r,'CloseWindowApi',side_effect=AssertionError('No UI')),redirect_stdout(io.StringIO()) as out:
            r.main([])
        proof=json.loads(out.getvalue())
        self.assertEqual(proof['status'],'STATIC_ORDINARY_REHEARSAL_V02_PLAN_NO_EFFECTS')
        self.assertEqual(proof['expected_runtime_source_revision'],r.RUNTIME_SOURCE_REVISION)
        self.assertEqual((proof['files_written'],proof['os_queries'],proof['console_connections']),(0,0,0))
        self.assertFalse(proof['ready_for_upload'])

    def test_absent_listener_is_allowed_but_foreign_listener_and_pid_reuse_are_not(self):
        observed,live,snap=process_fixture();r.owned(snap,live)
        for rows in ([dict(port=p.PORT,pid=9999)],[dict(port=p.PORT+1,pid=live['pid'])]):
            with self.subTest(rows=rows),self.assertRaisesRegex(ValueError,'port owner changed'):
                r.owned(dict(snap,listeners=rows),live)
        altered=copy.deepcopy(snap);altered['dota'][0]['created_utc']='2026-11-01T00:00:01.1234560Z'
        with self.assertRaisesRegex(ValueError,'PID/actual creation'):r.owned(altered,live)
        r.owned(dict(snap,listeners=[dict(port=p.PORT,pid=live['pid'])]),live)

    def test_runtime_revision_and_operation_code_are_separately_bound(self):
        with patch.object(r,'_auth',return_value=(dict(source_revision='f'*40),{})):
            with self.assertRaisesRegex(ValueError,'frozen048'):r.package_auth('a'*64)
        with patch.object(r,'_auth',return_value=(dict(source_revision=r.RUNTIME_SOURCE_REVISION),{})):
            r.package_auth('a'*64)
        pins=r.own_code_pins()
        self.assertEqual(pins[str(r.PARENT)],r.PARENT_SHA)
        self.assertIn(str(Path(r.__file__).resolve()),pins)

    def test_each_action_without_completed_signed_report_refuses_before_os_or_ui(self):
        for name in ('stage','launch','inspect','close','restore'):
            with self.subTest(name=name),patch.object(p,'snapshot') as os_query,\
                    patch.object(p,'write_new') as write,patch.object(r,'CloseWindowApi') as api:
                with self.assertRaisesRegex(ValueError,'signed report SHA'):
                    getattr(p,name)('trial',None,*(['one'] if name=='inspect' else []))
                os_query.assert_not_called();write.assert_not_called();api.assert_not_called()

    def fake_api(self,rows):
        api=types.SimpleNamespace()
        def enumerate_windows(callback,unused):
            for hwnd in list(rows):
                if not callback(hwnd,None):return 0
            return 1
        def owner(hwnd,pointer):
            if hwnd not in rows:return 0
            C.cast(pointer,C.POINTER(C.c_uint32)).contents.value=rows[hwnd]['pid'];return 700
        def title(hwnd,buffer,size):buffer.value=rows[hwnd].get('title','');return len(buffer.value)
        def rect(hwnd,pointer):
            result=C.cast(pointer,C.POINTER(r.RECT)).contents
            result.right=rows[hwnd].get('width',0);result.bottom=rows[hwnd].get('height',0);return 1
        api.EnumWindows=Mock(side_effect=enumerate_windows);api.GetWindowThreadProcessId=Mock(side_effect=owner)
        api.IsWindow=Mock(side_effect=lambda hwnd:hwnd in rows)
        api.IsWindowVisible=Mock(side_effect=lambda hwnd:rows[hwnd].get('visible',True))
        api.IsIconic=Mock(side_effect=lambda hwnd:rows[hwnd].get('iconic',False))
        api.IsHungAppWindow=Mock(side_effect=lambda hwnd:rows[hwnd].get('hung',False))
        api.GetWindowTextW=Mock(side_effect=title);api.GetClientRect=Mock(side_effect=rect)
        api.PostMessageW=Mock(return_value=1)
        return api

    def base_windows(self):
        return {101:dict(pid=9999,title='PRIVATE OTHER APP',width=1600,height=900),
                102:dict(pid=1234,title='',width=0,height=0),
                103:dict(pid=1234,title='Dota 2',width=1600,height=900)}

    def test_actual_window_logic_skips_aux_and_foreign_windows_and_posts_only_wm_close(self):
        rows=self.base_windows();api=self.fake_api(rows)
        with patch.object(r.C,'WinDLL',return_value=api):
            native=r.CloseWindowApi();selected=native.main_window(1234)
            self.assertEqual(selected,window())
            result=native.request_close(selected)
        self.assertEqual(result,dict(queued=True,win32_error=0))
        self.assertNotIn(101,[call.args[0] for call in api.GetWindowTextW.call_args_list])
        api.PostMessageW.assert_called_once_with(103,0x0010,0,0)

    def test_ambiguous_or_hung_main_window_is_refused_without_message(self):
        for mode in ('ambiguous','hung','zero_size','minimized'):
            rows=self.base_windows()
            if mode=='ambiguous':rows[104]=dict(rows[103])
            if mode=='hung':rows[103]['hung']=True
            if mode=='zero_size':rows[103]['width']=0
            if mode=='minimized':rows[103]['iconic']=True
            api=self.fake_api(rows)
            with self.subTest(mode=mode),patch.object(r.C,'WinDLL',return_value=api),self.assertRaises(ValueError):
                r.CloseWindowApi().main_window(1234)
            api.PostMessageW.assert_not_called()

    def test_last_moment_owner_change_or_broadcast_target_never_posts(self):
        rows=self.base_windows();api=self.fake_api(rows)
        with patch.object(r.C,'WinDLL',return_value=api):
            native=r.CloseWindowApi();selected=native.main_window(1234)
            rows[103]['pid']=9999
            with self.assertRaisesRegex(ValueError,'identity/response changed'):native.request_close(selected)
            for hwnd in (0,0xffff):
                with self.assertRaises(ValueError):native.request_close(dict(selected,hwnd=hwnd))
        api.PostMessageW.assert_not_called()

    def close_scope(self,folder,*,changed_window=False,queued=True):
        observed,live,snap=process_fixture();live['code_pins']={'SYNTHETIC':'pin'}
        api=Mock();api.main_window.side_effect=[window(),window(104) if changed_window else window()]
        api.request_close.return_value=dict(queued=queued,win32_error=0 if queued else 5)
        patches=[patch.object(p,'load_transaction',return_value=(folder,{}, {},{})),
            patch.object(p,'live_record',return_value=live),patch.object(p,'snapshot',return_value=snap),
            patch.object(p,'operation_lock',side_effect=lambda:nullcontext()),
            patch.object(r,'own_code_pins',return_value={'SYNTHETIC':'pin'}),
            patch.object(p,'OwnedLifetime'),patch.object(r,'CloseWindowApi',return_value=api),
            patch.object(p.subprocess,'run',side_effect=AssertionError('No Node/C6/console subprocess')),
            patch.object(p.subprocess,'Popen',side_effect=AssertionError('No process creation'))]
        return patches,api,live

    def test_close_is_one_request_without_listener_and_never_claims_exit(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary);patches,api,live=self.close_scope(folder)
            for item in patches:item.start();self.addCleanup(item.stop)
            result=r.close('trial','a'*64)
            self.assertEqual(result['status'],'WM_CLOSE_REQUESTED_NOT_EXIT_VERIFIED')
            self.assertFalse(result['exit_verified']);self.assertFalse(result['force_stop'])
            self.assertEqual(result['console_connections'],0)
            receipt=p.json_read(folder/'close_requested.json')
            self.assertTrue(receipt['root_confirm_exit_required']);self.assertFalse(receipt['exit_verified'])
            self.assertIsNone(receipt['keeper_still_owns_file_holds'])
            self.assertTrue(receipt['keeper_exit_required_before_restore'])
            with self.assertRaisesRegex(ValueError,'Close already requested'):r.close('trial','a'*64)
            api.request_close.assert_called_once_with(window())
            p.OwnedLifetime.assert_called_with(live)

    def test_close_does_not_claim_file_holds_when_keeper_has_already_exited(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary);patches,api,live=self.close_scope(folder)
            try:
                for item in patches:item.start()
                # The Dota process is still valid; the keeper can independently
                # have exited. close does not observe it and must say unknown.
                with patch.object(p,'process_details',return_value=None):
                    result=r.close('trial','a'*64)
                self.assertIsNone(result['keeper_still_owns_file_holds'])
                receipt=p.json_read(folder/'close_requested.json')
                self.assertIsNone(receipt['keeper_still_owns_file_holds'])
                self.assertEqual(receipt['keeper_observation'],'UNKNOWN_NOT_OBSERVED_BY_CLOSE')
                self.assertTrue(receipt['keeper_exit_required_before_restore'])
            finally:
                for item in reversed(patches):item.stop()

    def test_changed_main_window_and_failed_queue_never_retry_or_force(self):
        for changed,queued in ((True,True),(False,False)):
            with self.subTest(changed=changed,queued=queued),tempfile.TemporaryDirectory() as temporary:
                folder=Path(temporary);patches,api,live=self.close_scope(folder,changed_window=changed,queued=queued)
                try:
                    for item in patches:item.start()
                    with self.assertRaises(ValueError):r.close('trial','a'*64)
                    if changed:api.request_close.assert_not_called()
                    else:
                        api.request_close.assert_called_once()
                        self.assertTrue((folder/'close_failed.json').exists())
                        with self.assertRaisesRegex(ValueError,'Close already requested'):r.close('trial','a'*64)
                        api.request_close.assert_called_once()
                finally:
                    for item in reversed(patches):item.stop()

    def test_adapter_has_no_force_focus_console_or_broadcast_fallback(self):
        source=Path(r.__file__).read_text(encoding='utf8')
        for forbidden in ('TerminateProcess','Stop-Process','taskkill','SetForegroundWindow','socket','console_send'):
            self.assertNotIn(forbidden,source)
        self.assertEqual(C.sizeof(r.RECT),16)


if __name__=='__main__':unittest.main()
