"""Ordinary-client adapter over the immutable reviewed rehearsal implementation.

Default is static; real actions still require the exact completed signed14
candidate. No installation, launch, SDK or UI action is performed on import.
An absent VConsole listener is valid for ordinary Dota. close only requests one
WM_CLOSE for the exact owned main window; the inherited keeper proves exit.
"""
from pathlib import Path
import ctypes as C
import hashlib
import importlib.util
import json
import os
import sys

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
PARENT=HERE.parent/'arcade_portrait_release_v02_20261101/rehearsal.py'
PARENT_SHA='b15122de3441a12d283e5d3c7f0998558b2b4fbd90058fb9beb5df928f181cd7'
RUNTIME_SOURCE_REVISION=None


def require_source_revision():
    need(isinstance(RUNTIME_SOURCE_REVISION,str) and p.re.fullmatch(r'[a-f0-9]{40}',RUNTIME_SOURCE_REVISION) is not None,
        'PENDING_IMMUTABLE_V03_RUNTIME_SOURCE: final root source commit required')



def require_parent():
    if hashlib.sha256(PARENT.read_bytes()).hexdigest()!=PARENT_SHA:
        raise ValueError('Frozen rehearsal parent changed; do not retarget this adapter')


require_parent()
_spec=importlib.util.spec_from_file_location('ordinary_rehearsal_v03_private_parent',PARENT)
p=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(p)
need=p.need
_spec=importlib.util.spec_from_file_location('ordinary_rehearsal_v03_checks',HERE/'release_checks.py')
c=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(c)
p.c=c;p.b=c.b;p.need=c.b.need;need=p.need
p.STORE=Path('D:/Survival_本地排演/20261101_ws4_portrait_perf_teleport_snapshot_v03')
p.PORT=29038
p.SNAPSHOT_PS=p.SNAPSHOT_PS.replace('29028','29038')


def fixed_paths():
    need(p.INSTALLED==p.b.ROOT.parents[4]/'workshop/content/570/3824360109'
        and p.STORE==Path('D:/Survival_本地排演/20261101_ws4_portrait_perf_teleport_snapshot_v03'),
        'Fixed v03 rehearsal paths changed')
    p.regular(p.INSTALLED);p.regular(p.STORE,exists=False)
    need(p.INSTALLED.anchor.casefold()==p.STORE.anchor.casefold(),'Same-volume atomic replacement required')
    p.b.inc.disjoint([p.INSTALLED,p.STORE,p.b.VIEW,p.b.OUTPUT,p.b.BASE,
        *p.b.FROZEN_V01_OUTPUTS,*p.b.FROZEN_V02_OUTPUTS])


p.fixed_paths=fixed_paths
_owned,_pins,_auth,_plan=p.owned,p.own_code_pins,p.package_auth,p.static_plan


def own_code_pins():
    require_parent()
    return {**_pins(),str(Path(__file__).resolve()):p.digest(Path(__file__))}


def package_auth(expected_sha,*,full=True):
    require_parent()
    require_source_revision()
    package,manifest=_auth(expected_sha,full=full)
    need(package['source_revision']==RUNTIME_SOURCE_REVISION,'Exact frozen v03 runtime source required; operation tool is separately pinned')
    return package,manifest


def owned(observation,record,*,listener=False):
    # Preserve every PID/CIM/exe/full-argv/native-generation check. The old
    # implementation still rejects ANY listener belonging to another process
    # or port. Only its requirement that a listener must exist is disabled.
    return _owned(observation,record,listener=False)


class RECT(C.Structure):
    _fields_=[('left',C.c_int32),('top',C.c_int32),('right',C.c_int32),('bottom',C.c_int32)]


class CloseWindowApi:
    """Two bounded top-level inventories, then one targeted WM_CLOSE. No input."""
    def __init__(self):
        need(os.name=='nt','Explicit Windows owned-window close required')
        self.api=C.WinDLL('user32',use_last_error=True)
        self.callback_type=getattr(C,'WINFUNCTYPE',C.CFUNCTYPE)(C.c_int32,C.c_void_p,C.c_void_p)
        specs={
            'EnumWindows':([self.callback_type,C.c_void_p],C.c_int32),
            'GetWindowThreadProcessId':([C.c_void_p,C.POINTER(C.c_uint32)],C.c_uint32),
            'IsWindow':([C.c_void_p],C.c_int32),'IsWindowVisible':([C.c_void_p],C.c_int32),
            'IsIconic':([C.c_void_p],C.c_int32),'IsHungAppWindow':([C.c_void_p],C.c_int32),
            'GetClientRect':([C.c_void_p,C.POINTER(RECT)],C.c_int32),
            'GetWindowTextW':([C.c_void_p,C.c_wchar_p,C.c_int32],C.c_int32),
            'PostMessageW':([C.c_void_p,C.c_uint32,C.c_size_t,C.c_ssize_t],C.c_int32),
        }
        for name,(arguments,result) in specs.items():
            function=getattr(self.api,name);function.argtypes=arguments;function.restype=result

    def main_window(self,pid):
        need(type(pid)is int and 0<pid<2**31,'Exact owned PID required for window inventory')
        rows,errors,visited=[],[],[0]
        def visit(hwnd,unused):
            # ctypes callback exceptions must not be swallowed by the FFI.
            try:
                visited[0]+=1;need(visited[0]<=4096,'Bounded desktop window inventory exceeded')
                owner=C.c_uint32()
                thread=self.api.GetWindowThreadProcessId(hwnd,C.byref(owner))
                if not thread or owner.value!=pid:return 1
                if not self.api.IsWindow(hwnd) or not self.api.IsWindowVisible(hwnd) or self.api.IsIconic(hwnd):return 1
                title=C.create_unicode_buffer(512)
                count=self.api.GetWindowTextW(hwnd,title,len(title))
                if count<=0 or title.value!='Dota 2':return 1
                rect=RECT();need(self.api.GetClientRect(hwnd,C.byref(rect))!=0,'Owned main-window geometry unavailable')
                width,height=rect.right-rect.left,rect.bottom-rect.top
                if width<640 or height<360:return 1
                rows.append(dict(hwnd=int(hwnd),pid=pid,title='Dota 2',client_width=width,client_height=height,
                    visible=True,iconic=False,hung=bool(self.api.IsHungAppWindow(hwnd))))
                return 1
            except Exception:errors.append(True);return 0
        callback=self.callback_type(visit)
        ok=self.api.EnumWindows(callback,None)
        need(ok!=0 and not errors,'Owned-window enumeration failed; no close requested')
        need(len(rows)==1,'Exactly one visible Dota 2 main window >=640x360 required')
        need(not rows[0]['hung'],'Owned main window is not responding; manual review required, no force-stop')
        need(rows[0]['hwnd'] not in (0,0xffff),'Specific main HWND required; broadcast forbidden')
        return rows[0]

    def request_close(self,window):
        hwnd=window['hwnd'];owner=C.c_uint32()
        need(type(hwnd)is int and hwnd not in (0,0xffff) and self.api.IsWindow(hwnd), 'Specific live owned main HWND required')
        thread=self.api.GetWindowThreadProcessId(hwnd,C.byref(owner))
        need(thread!=0 and owner.value==window['pid'] and self.api.IsWindowVisible(hwnd)
             and not self.api.IsIconic(hwnd) and not self.api.IsHungAppWindow(hwnd), 'Window identity/response changed before WM_CLOSE')
        title,rect=C.create_unicode_buffer(512),RECT()
        need(self.api.GetWindowTextW(hwnd,title,len(title))>0 and title.value==window['title']
             and self.api.GetClientRect(hwnd,C.byref(rect))!=0
             and (rect.right-rect.left,rect.bottom-rect.top)==(window['client_width'],window['client_height']),
             'Main window title/geometry changed before WM_CLOSE')
        queued=self.api.PostMessageW(hwnd,0x0010,0,0)!=0
        return dict(queued=queued,win32_error=0 if queued else C.get_last_error())


def close(identifier,report_sha):
    folder,record,package,manifest=p.load_transaction(identifier,report_sha)
    with p.operation_lock():
        need(not (folder/'close_intent.json').exists(),'Close already requested; no replay or fallback')
        live=p.live_record(folder,record)
        owned(p.snapshot(),live)
        need(live['code_pins']==own_code_pins(),'Ordinary close code binding changed')
        # The precise native FILETIME stays pinned across both CIM/window
        # observations and the asynchronous message. No VCon is opened.
        with p.OwnedLifetime(live) as lifetime:
            windows=CloseWindowApi();before=windows.main_window(live['pid'])
            owned(p.snapshot(),live)
            after=windows.main_window(live['pid'])
            need(before==after,'Owned main HWND/geometry changed; no close requested')
            lifetime.verify()
            p.write_new(folder/'close_intent.json',dict(schema=2,status='ONE_OWNED_WM_CLOSE_INTENT',observed_utc=p.stamp(),
                pid=live['pid'],created_utc=live['created_utc'],native_created_filetime=live['native_created_filetime'],
                main_window=after,code_pins=own_code_pins(),automatic_retry=False,console_connections=0))
            result=windows.request_close(after)
            p.write_new(folder/('close_requested.json' if result['queued'] else 'close_failed.json'),dict(schema=2,
                status='WM_CLOSE_REQUESTED_NOT_EXIT_VERIFIED' if result['queued'] else 'WM_CLOSE_NOT_QUEUED_NO_FORCE_STOP',
                observed_utc=p.stamp(),pid=live['pid'],created_utc=live['created_utc'],main_window=after,**result,
                exit_verified=False,root_confirm_exit_required=True,keeper_still_owns_file_holds=None,
                keeper_observation='UNKNOWN_NOT_OBSERVED_BY_CLOSE',keeper_exit_required_before_restore=True,
                automatic_retry=False,force_stop=False,console_connections=0))
            need(result['queued'],'Owned WM_CLOSE could not be queued; no retry or force-stop')
            return dict(status='WM_CLOSE_REQUESTED_NOT_EXIT_VERIFIED',pid=live['pid'],hwnd=after['hwnd'],
                exit_verified=False,root_confirm_exit_required=True,keeper_still_owns_file_holds=None,
                keeper_exit_required_before_restore=True,force_stop=False,console_connections=0,ready_for_upload=False)


def static_plan():
    return dict(_plan(),status='STATIC_ORDINARY_REHEARSAL_V03_PLAN_NO_EFFECTS',operation_tool_version=3,
        frozen_parent_sha256=PARENT_SHA,expected_runtime_source_revision=RUNTIME_SOURCE_REVISION,
        operation_tool_bound_separately=True,listener_policy='ABSENT_ALLOWED_IF_PRESENT_MUST_BE_OWNED',
        close_method='ONE_OWNED_MAIN_WINDOW_WM_CLOSE_REQUEST_ONLY',console_connections=0)


# Only this private module instance is adapted. The immutable parent's bytes,
# other imports, builder/checks, release plan, unsigned view and journal remain.
p.owned=owned;p.own_code_pins=own_code_pins;p.package_auth=package_auth;p.close=close;p.static_plan=static_plan


def main(argv=None):return p.main(argv)


if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception:
        print(json.dumps(dict(status='REFUSED_ORDINARY_V03_PRESERVE_TRANSACTION_AND_BACKUPS',automatic_retry=False,
            force_stop=False,console_connections=0,canonical_journal_written=False,publication_performed=False)))
        raise SystemExit(2)
