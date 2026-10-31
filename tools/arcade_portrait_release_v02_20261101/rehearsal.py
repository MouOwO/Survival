"""Owned local signed-candidate rehearsal, never publication or official download.

Default is a static plan. Explicit actions authenticate the completed signed
package first. The five original Workshop files are the only install mutations;
all backups, staging, intents and receipts live in a NEW external transaction.
launch stays running to hold read-only, deny-write/delete file handles. Keep that
terminal alive; close is a separate, fixed graceful-quit action, never a kill.
No synthetic profile, Lua injection, login approval, reward, UGC or ACF mutation.
"""
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
import argparse
import ctypes as C
import hashlib
import importlib.util
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('portrait_v02_rehearsal_checks', HERE/'release_checks.py')
c = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(c)
b, need = c.b, c.b.need
GAME = b.ROOT.parents[1]
EXE = GAME/'bin/win64/dota2.exe'
INSTALLED = b.ROOT.parents[4]/'workshop/content/570/3824360109'
ACF = b.ROOT.parents[4]/'workshop/appworkshop_570.acf'
STORE = Path('D:/Survival_本地排演/20261101_ws4_portrait_perf_teleport_v02')
PORT = 29028
NAMES = (b.ITEM+'.vpk', *(b.ITEM+'_%03d.vpk' % i for i in range(4)))
ORDER = (*NAMES[1:], NAMES[0])  # Both forward and restoration commit index last.
CHUNK, RESERVE = 4*1024*1024, 512*1024*1024
HIDDEN = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
KIND = 'LOCAL_SIGNED_CANDIDATE_REHEARSAL'
TRANSPORT = b.ROOT/'tools/map_c6/console-session.cjs'
FRAMING = b.ROOT/'tools/map_c6/console.cjs'


def digest(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as stream:
        while block := stream.read(CHUNK): result.update(block)
    return result.hexdigest()


def regular(path, *, exists=True, single_link=False):
    path = Path(path).absolute()
    for part in (path, *path.parents):
        try: info = part.lstat()
        except FileNotFoundError: continue
        need(not stat.S_ISLNK(info.st_mode) and not getattr(info, 'st_file_attributes', 0)&0x400,
             'Reparse/link path forbidden')
    need(not exists or path.exists(), 'Required rehearsal path missing')
    if path.exists() and path.is_file() and single_link:
        need(path.stat().st_nlink == 1, 'Mutable/backup/staged hardlinks forbidden')
    return path


def json_read(path, maximum=1024*1024):
    path = regular(path, single_link=True)
    need(path.is_file() and path.stat().st_size <= maximum, 'Bounded regular JSON required')
    def pairs(rows):
        result = {}
        for key, value in rows:
            need(key not in result, 'Duplicate JSON key'); result[key] = value
        return result
    return json.loads(path.read_bytes().decode('utf-8-sig'), object_pairs_hook=pairs)


def write_new(path, value):
    path = regular(path, exists=False)
    raw = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2)+'\n').encode('utf-8')
    with path.open('xb') as stream: stream.write(raw); stream.flush(); os.fsync(stream.fileno())
    return hashlib.sha256(raw).hexdigest()


def row(path, name=None):
    path = regular(path, single_link=True)
    need(path.is_file(), 'Regular VPK required')
    return dict(name=name or path.name, bytes=path.stat().st_size, sha256=digest(path))


def exact_members(folder):
    folder = regular(folder)
    need(folder.is_dir() and {p.name for p in folder.iterdir()} == set(NAMES), 'Exact five VPK files required')
    for name in NAMES: regular(folder/name, single_link=True)


def inventory(folder):
    exact_members(folder)
    return [row(folder/name) for name in NAMES]


def require_rows(folder, expected):
    need(inventory(folder) == expected, 'Full five VPK hash/size mismatch')


def copy_new(source, target, expected):
    source, target = regular(source), regular(target, exists=False)
    # Input package volumes may intentionally be immutable shared hardlinks.
    # Destination is always a physical NEW file, never copy metadata or a link.
    with source.open('rb') as read, target.open('xb') as write:
        while block := read.read(CHUNK): write.write(block)
        write.flush(); os.fsync(write.fileno())
    need(row(target, expected['name']) == expected, 'Physical copy failed hash verification')


def fixed_paths():
    need(INSTALLED == b.ROOT.parents[4]/'workshop/content/570/3824360109'
         and STORE == Path('D:/Survival_本地排演/20261101_ws4_portrait_perf_teleport_v02'), 'Fixed rehearsal paths changed')
    regular(INSTALLED); regular(STORE, exists=False)
    need(INSTALLED.anchor.casefold() == STORE.anchor.casefold(), 'Same-volume atomic replacement required')
    b.inc.disjoint([INSTALLED, STORE, b.VIEW, b.OUTPUT, b.BASE, *b.FROZEN_V01_OUTPUTS])


def safe_id(value):
    need(re.fullmatch(r'[a-z][a-z0-9_]{0,39}', value or '') is not None, 'Explicit safe NEW transaction/label required')
    return value


def directory(identifier): return regular(STORE/safe_id(identifier), exists=False)


def stamp(): return datetime.now(timezone.utc).isoformat()


def utc_ticks(value):
    # Preserve the seventh fractional digit; datetime alone truncates it.
    found = re.fullmatch(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,7}))?(?:Z|\+00:00)', value or '')
    need(found is not None, 'Actual UTC process creation timestamp required')
    base = datetime.fromisoformat(found[1]).replace(tzinfo=timezone.utc)
    delta = base-datetime(1601,1,1,tzinfo=timezone.utc)
    return (delta.days*86400+delta.seconds)*10_000_000+int((found[2] or '').ljust(7,'0') or '0')


def powershell(script):
    need(os.name == 'nt', 'Windows native operation required')
    completed = subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-Command',
        "$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);"+script],
        capture_output=True, timeout=20, creationflags=HIDDEN)
    need(completed.returncode == 0 and len(completed.stdout) <= 1024*1024, 'Read-only CIM query failed')
    return json.loads(completed.stdout.decode('utf-8-sig'))


SNAPSHOT_PS = """$d=@(Get-CimInstance Win32_Process -Filter \"name='dota2.exe'\" | ForEach-Object {
 [ordered]@{pid=[int]$_.ProcessId;created_utc=$_.CreationDate.ToUniversalTime().ToString('o');executable=$_.ExecutablePath;command_line=$_.CommandLine}})
$s=@(Get-CimInstance Win32_Process -Filter \"name='steam.exe'\")
$l=@(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object {$_.LocalPort -eq 29028} | ForEach-Object {
 [ordered]@{port=[int]$_.LocalPort;pid=[int]$_.OwningProcess}})
[ordered]@{dota=$d;steam_running=($s.Count -gt 0);listeners=$l}|ConvertTo-Json -Depth 5 -Compress
"""


def snapshot():
    value = powershell(SNAPSHOT_PS)
    need(isinstance(value.get('dota'), list) and isinstance(value.get('listeners'), list)
         and type(value.get('steam_running')) is bool, 'Complete process/port inventory required')
    return value


def process_details(pid):
    need(type(pid) is int and 0 < pid < 2**31, 'Bound process PID required')
    return powershell("$p=Get-CimInstance Win32_Process -Filter 'ProcessId="+str(pid)+"';"
        "if(-not $p){'null';exit};[ordered]@{pid=[int]$p.ProcessId;created_utc=$p.CreationDate.ToUniversalTime().ToString('o');"
        "executable=$p.ExecutablePath;command_line=$p.CommandLine}|ConvertTo-Json -Compress")


def no_clients():
    value = snapshot()
    need(not value['dota'] and not value['listeners'], 'Close Dota clients first; occupied port is never stopped')
    return value


def steam_ready():
    # Read-only AppID/owner/BLoggedOn only. No UGC request, subscription or callback.
    if str(b.ROOT/'tools') not in sys.path: sys.path.insert(0,str(b.ROOT/'tools'))
    import steam_workshop_upload as sdk
    with sdk.Steam() as steam:
        return dict(app_id=sdk.APP, expected_owner_verified=True, logged_on=True)


def acf_item():
    path = regular(ACF)
    need(path.stat().st_size <= 4*1024*1024, 'Bounded existing Workshop ACF required')
    raw = path.read_bytes(); value = b.pack.handoff.kv(raw.decode('utf-8-sig'))['appworkshop']
    item = value['workshopitemsinstalled'][b.ITEM]
    need(value.get('appid') == '570' and item.get('manifest') == '2484609663754935010', 'Original3102 installed manifest required; never rewrite ACF')
    return dict(item=item, raw_sha256=hashlib.sha256(raw).hexdigest())


def package_auth(expected_sha, *, full=True):
    # Every real action, including restoration, requires actual completed signed
    # metadata. Unsigned review directories are never executable inputs.
    need(re.fullmatch(r'[a-f0-9]{64}', expected_sha or '') is not None, 'Explicit completed signed report SHA required')
    package, manifest, signed = c.validated_package(expected_sha, full=full)
    need(signed['signature_valid'] is True and signed['release_sequence'] == b.SEQUENCE, 'Signed production candidate required')
    need([r['name'] for r in package['package_files']] == list(NAMES)
         and package['source_revision'] and package['content_sha256'] == manifest['content_sha256'], 'Exact candidate identity required')
    return package, manifest


def full_vpk(folder, manifest):
    with b.scene_maps(): b.pack.verify_vpk(folder/NAMES[0], manifest)


def own_code_pins():
    return {str(path):digest(regular(path)) for path in (Path(__file__), TRANSPORT, FRAMING)}


@contextmanager
def operation_lock():
    # Local transaction serialization only, not a lock on Steam's updater.
    import msvcrt
    regular(STORE); lock = regular(STORE/'operation.lock',exists=False,single_link=True)
    with lock.open('a+b') as stream:
        if stream.seek(0,2) == 0: stream.write(b'0'); stream.flush()
        stream.seek(0); msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
        try: yield
        finally: stream.seek(0); msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)


def event(folder, status, **fields):
    events = regular(folder/'events')
    names = sorted(path.name for path in events.iterdir())
    need(len(names) < 128 and all(re.fullmatch(r'\d{3}\.json', name) for name in names), 'Bounded transaction event sequence required')
    need(names == ['%03d.json' % i for i in range(len(names))], 'Transaction event gap')
    return write_new(events/('%03d.json' % len(names)), dict(schema=1,status=status,observed_utc=stamp(),**fields))


def load_transaction(identifier, report_sha, *, full=False):
    package, manifest = package_auth(report_sha, full=full)
    fixed_paths(); folder = directory(identifier)
    record = json_read(folder/'transaction.json')
    need(record.get('kind') == KIND and record.get('schema') == 1
         and record.get('transaction_id') == identifier and record.get('package_report_sha256') == report_sha
         and record.get('release_sequence') == b.SEQUENCE and record.get('content_sha256') == package['content_sha256']
         and record.get('source_revision') == package['source_revision']
         and record.get('candidate_files') == package['package_files'] and record.get('installed') == str(INSTALLED)
         and record.get('code_pins') == own_code_pins(), 'Transaction signed identity/code binding changed')
    need(record['original_files'] == b.load(b.BASE_REPORT)['package_files'], 'Original3102 backup binding changed')
    return folder, record, package, manifest


def stage(identifier, report_sha):
    package, manifest = package_auth(report_sha, full=True)
    fixed_paths(); no_clients(); steam = steam_ready(); no_clients()
    old, old_manifest = b.baseline(full=True, require_current_journal=False)
    require_rows(INSTALLED, old['package_files']); full_vpk(INSTALLED, old_manifest)
    before_acf = acf_item()
    folder = directory(identifier); need(not folder.exists(), 'NEW external rehearsal transaction required')
    regular(STORE, exists=False).mkdir(parents=True, exist_ok=True)
    with operation_lock():
        need(not folder.exists(), 'NEW external transaction required')
        no_clients(); require_rows(INSTALLED, old['package_files'])
        need(acf_item() == before_acf, 'Steam ACF changed before staging')
        required = sum(r['bytes'] for r in old['package_files'])+sum(r['bytes'] for r in package['package_files'])+max(
            r['bytes'] for r in (*old['package_files'],*package['package_files']))+RESERVE
        need(shutil.disk_usage(STORE).free >= required, 'Full backups/staging/restore temporary space required')
        folder.mkdir(exist_ok=False)
        for name in ('backup','candidate','work','events','inspections'): (folder/name).mkdir()
        record = dict(schema=1,kind=KIND,transaction_id=identifier,installed=str(INSTALLED),
            package_report_sha256=report_sha,release_sequence=b.SEQUENCE,content_sha256=package['content_sha256'],
            source_revision=package['source_revision'],candidate_files=package['package_files'],original_files=old['package_files'],
            original_content_sha256=b.BASE_CONTENT,original_release_sequence=b.BASE_SEQUENCE,acf=before_acf,
            code_pins=own_code_pins(),official_download=False,uploaded=False,steam_readonly=steam)
        write_new(folder/'transaction.json',record)
        try:
            for rows, source, destination in ((old['package_files'],INSTALLED,folder/'backup'),
                    (package['package_files'],b.OUTPUT,folder/'candidate')):
                for item in rows:
                    no_clients(); copy_new(source/item['name'],destination/item['name'],item)
            require_rows(folder/'backup',old['package_files']); full_vpk(folder/'backup',old_manifest)
            require_rows(folder/'candidate',package['package_files']); full_vpk(folder/'candidate',manifest)
            need(acf_item() == before_acf, 'Steam ACF changed during backup/staging')
            event(folder,'BACKUPS_AND_CANDIDATE_FULLY_VERIFIED')
            transition(folder,record,to_original=False)
            require_rows(INSTALLED,package['package_files']); full_vpk(INSTALLED,manifest)
            need(acf_item() == before_acf, 'Steam ACF changed during local installation')
            event(folder,'STAGED_CANDIDATE_NOT_YET_RUN')
            return dict(status='LOCAL_SIGNED_CANDIDATE_STAGED_NOT_OFFICIAL_DOWNLOAD',transaction_id=identifier,
                content_sha256=package['content_sha256'],official_download=False,game_started=False,ready_for_upload=False)
        except BaseException:
            event(folder,'RECOVERY_REQUIRED_NO_AUTOMATIC_RESTORE',automatic_retry=False)
            raise


def known_images(record):
    exact_members(INSTALLED)
    old = {r['name']:r for r in record['original_files']}; new = {r['name']:r for r in record['candidate_files']}
    actual = {}
    # Check ALL five before changing any. Unknown Steam bytes are never accepted.
    for name in NAMES:
        actual[name] = row(INSTALLED/name)
        need(actual[name] in (old[name],new[name]), 'Unknown current VPK; preserve files and backup for recovery')
    return actual


def transition(folder, record, *, to_original):
    actual = known_images(record)
    desired = {r['name']:r for r in record['original_files' if to_original else 'candidate_files']}
    source = folder/('backup' if to_original else 'candidate')
    require_rows(source,list(desired.values()))
    for index,name in enumerate(ORDER):
        if actual[name] == desired[name]: continue
        no_clients()
        need(row(INSTALLED/name) == actual[name], 'Optimistic compare-and-swap conflict; no overwrite')
        temp = folder/'work'/('%s_%02d_%s' % ('restore' if to_original else 'forward',index,secrets.token_hex(8)))
        copy_new(source/name,temp,desired[name])
        no_clients(); need(row(INSTALLED/name) == actual[name], 'Compare-and-swap conflict after temporary copy')
        need(acf_item()['item'] == record['acf']['item'], 'Original-item ACF changed before file replacement')
        event(folder,'CAS_INTENT',name=name,before=actual[name],after=desired[name],restoration=to_original)
        os.replace(temp,INSTALLED/name)  # Same-volume rename; Steam has no shared transaction lock.
        need(row(INSTALLED/name) == desired[name], 'Postimage changed; recovery required')
        event(folder,'CAS_POSTIMAGE_VERIFIED',name=name,restoration=to_original)


class FILETIME(C.Structure): _fields_ = [('low',C.c_uint32),('high',C.c_uint32)]
class FILE_INFO(C.Structure):
    _fields_ = [('attributes',C.c_uint32),('created',FILETIME),('access',FILETIME),('written',FILETIME),
        ('volume',C.c_uint32),('size_high',C.c_uint32),('size_low',C.c_uint32),('links',C.c_uint32),
        ('index_high',C.c_uint32),('index_low',C.c_uint32)]
class RM_UNIQUE_PROCESS(C.Structure): _fields_ = [('pid',C.c_uint32),('start',FILETIME)]
class RM_PROCESS_INFO(C.Structure):
    _fields_ = [('process',RM_UNIQUE_PROCESS),('app_name',C.c_uint16*256),('service_name',C.c_uint16*64),
        ('app_type',C.c_uint32),('status',C.c_uint32),('session',C.c_uint32),('restartable',C.c_int32)]


class FiveHolds:
    """Read handles only: no WRITE/DELETE sharing, no inherited handles."""
    def __init__(self, folder): self.folder, self.handles, self.identities = folder, [], []
    def __enter__(self):
        need(os.name == 'nt', 'Win32 read-only file holds required')
        self.api = C.WinDLL('kernel32',use_last_error=True)
        self.api.CreateFileW.argtypes = [C.c_wchar_p,C.c_uint32,C.c_uint32,C.c_void_p,C.c_uint32,C.c_uint32,C.c_void_p]
        self.api.CreateFileW.restype = C.c_void_p
        self.api.CloseHandle.argtypes = [C.c_void_p]; self.api.CloseHandle.restype = C.c_int32
        self.api.GetFileInformationByHandle.argtypes = [C.c_void_p,C.POINTER(FILE_INFO)]
        self.api.GetFileInformationByHandle.restype = C.c_int32
        self.api.GetFinalPathNameByHandleW.argtypes = [C.c_void_p,C.c_wchar_p,C.c_uint32,C.c_uint32]
        self.api.GetFinalPathNameByHandleW.restype = C.c_uint32
        try:
            exact_members(self.folder)
            for name in NAMES:
                path = regular(self.folder/name,single_link=True)
                handle = self.api.CreateFileW(str(path),0x80000000,1,None,3,0x80,None)
                need(handle not in (None,C.c_void_p(-1).value), 'Read-only deny-write/delete hold failed; do not weaken sharing')
                self.handles.append(handle)
                info, final = FILE_INFO(), C.create_unicode_buffer(32768)
                need(self.api.GetFileInformationByHandle(handle,C.byref(info)) != 0, 'FileID query failed')
                count = self.api.GetFinalPathNameByHandleW(handle,final,len(final),0)
                need(0 < count < len(final) and info.links == 1 and not info.attributes&0x400, 'Held file identity invalid')
                actual = final.value[4:] if final.value.startswith('\\\\?\\') else final.value
                # Do not resolve the expected name again: a concurrent junction
                # must not redirect both sides of this identity comparison.
                need(Path(actual).absolute() == path.absolute(), 'Held handle path differs from fixed target')
                self.identities.append(dict(name=name,path=str(path),volume_serial=info.volume,
                    file_index=(info.index_high<<32)|info.index_low,bytes=(info.size_high<<32)|info.size_low))
            need(len({(r['volume_serial'],r['file_index']) for r in self.identities}) == 5, 'Distinct held files required')
            return self
        except BaseException: self.__exit__(None,None,None); raise
    def __exit__(self,*unused):
        failed = False
        for handle in reversed(self.handles): failed |= self.api.CloseHandle(handle) == 0
        self.handles.clear()
        need(not failed,'Native handle close failed')


class OwnedLifetime:
    """Pin the original process object; stable waiting never forks/query-lists."""
    def __init__(self,record,*,expected_exe=EXE):
        self.record,self.handle,self.expected_exe=record,None,Path(expected_exe)
        self.native_created_filetime=None
    def __enter__(self):
        need(os.name == 'nt','Read-only Win32 process lifetime required')
        self.api=C.WinDLL('kernel32',use_last_error=True)
        self.api.OpenProcess.argtypes=[C.c_uint32,C.c_int32,C.c_uint32];self.api.OpenProcess.restype=C.c_void_p
        self.api.CloseHandle.argtypes=[C.c_void_p];self.api.CloseHandle.restype=C.c_int32
        self.api.GetProcessTimes.argtypes=[C.c_void_p,*([C.POINTER(FILETIME)]*4)];self.api.GetProcessTimes.restype=C.c_int32
        self.api.QueryFullProcessImageNameW.argtypes=[C.c_void_p,C.c_uint32,C.c_wchar_p,C.POINTER(C.c_uint32)]
        self.api.QueryFullProcessImageNameW.restype=C.c_int32
        self.api.WaitForSingleObject.argtypes=[C.c_void_p,C.c_uint32];self.api.WaitForSingleObject.restype=C.c_uint32
        self.handle=self.api.OpenProcess(0x00101000,False,self.record['pid']) # SYNCHRONIZE|QUERY_LIMITED_INFORMATION only.
        need(self.handle not in (None,C.c_void_p(-1).value),'Read-only owned process handle unavailable')
        try: self.verify();return self
        except BaseException:self.__exit__(None,None,None);raise
    def verify(self):
        times=[FILETIME() for i in range(4)]
        need(self.api.GetProcessTimes(self.handle,*(C.byref(value) for value in times)) != 0,'Owned process creation query failed')
        created=(times[0].high<<32)|times[0].low
        image,size=C.create_unicode_buffer(32768),C.c_uint32(32768)
        need(self.api.QueryFullProcessImageNameW(self.handle,0,image,C.byref(size)) != 0
             and 0 < size.value < len(image),'Owned process image query failed')
        # Win32_Process.CreationDate comes through CIM_DATETIME (microseconds),
        # even though ToString('o') pads a seventh zero. Never fabricate its
        # missing 100ns digit. Capture the kernel value once and pin it exactly.
        cim=utc_ticks(self.record['created_utc'])
        need(cim%10 == 0 and created//10 == cim//10
             and Path(image.value).resolve() == self.expected_exe.resolve() == Path(self.record['executable']).resolve(),
             'Read-only process handle creation/executable mismatch')
        expected=self.record.get('native_created_filetime',self.native_created_filetime)
        need(expected is None or type(expected) is int and created == expected,'Exact native process creation pin changed')
        self.native_created_filetime=created
        return dict(pid=self.record['pid'],created_filetime=created,executable=str(self.expected_exe))
    def wait_exited(self):
        result=self.api.WaitForSingleObject(self.handle,2000)
        need(result in (0,258),'Owned process wait failed; no PID replacement adopted')
        if result == 0:self.verify();return True
        return False
    def __exit__(self,*unused):
        if self.handle is not None:
            handle,self.handle=self.handle,None
            need(self.api.CloseHandle(handle) != 0,'Read-only process handle close failed')


def restart_manager_users(path):
    """One exact file per session. Only four non-destructive RM APIs exist here."""
    need(os.name == 'nt' and path in [INSTALLED/name for name in NAMES], 'Fixed single VPK RM path required')
    api = C.WinDLL('rstrtmgr',use_last_error=True)
    api.RmStartSession.argtypes = [C.POINTER(C.c_uint32),C.c_uint32,C.c_wchar_p]; api.RmStartSession.restype=C.c_uint32
    api.RmRegisterResources.argtypes = [C.c_uint32,C.c_uint32,C.POINTER(C.c_wchar_p),C.c_uint32,C.POINTER(RM_UNIQUE_PROCESS),C.c_uint32,C.POINTER(C.c_wchar_p)]
    api.RmRegisterResources.restype=C.c_uint32
    api.RmGetList.argtypes = [C.c_uint32,C.POINTER(C.c_uint32),C.POINTER(C.c_uint32),C.POINTER(RM_PROCESS_INFO),C.POINTER(C.c_uint32)]
    api.RmGetList.restype=C.c_uint32
    api.RmEndSession.argtypes = [C.c_uint32]; api.RmEndSession.restype=C.c_uint32
    session,key = C.c_uint32(),C.create_unicode_buffer(33)
    need(api.RmStartSession(C.byref(session),0,key) == 0,'Read-only RestartManager session failed')
    try:
        paths=(C.c_wchar_p*1)(str(regular(path)))
        need(api.RmRegisterResources(session,1,paths,0,None,0,None) == 0,'Single fixed VPK registration failed')
        needed,count,reasons = C.c_uint32(),C.c_uint32(),C.c_uint32()
        answer=api.RmGetList(session,C.byref(needed),C.byref(count),None,C.byref(reasons))
        if answer == 0 and count.value == 0: return []
        need(answer == 234 and 0 < needed.value <= 64,'Bounded RestartManager list unavailable')
        for attempt in range(2):
            rows=(RM_PROCESS_INFO*needed.value)(); count.value=len(rows)
            answer=api.RmGetList(session,C.byref(needed),C.byref(count),rows,C.byref(reasons))
            if answer == 0:
                need(count.value <= len(rows),'RestartManager count exceeded buffer')
                return [dict(pid=r.process.pid,created_filetime=(r.process.start.high<<32)|r.process.start.low)
                    for r in rows[:count.value]]
            need(answer == 234 and 0 < needed.value <= 64,'RestartManager retry refused')
        raise ValueError('RestartManager list unstable; file use remains unproven')
    finally: need(api.RmEndSession(session) == 0,'RestartManager session close failed')


def arguments(log):
    return ['-steam','-novid','-console','-vconport',str(PORT),'-condebug','-con_logfile',str(log),
        '+sv_cheats','0','+survival_archive_http_enabled','1','+dota_launch_custom_game',b.ITEM,'ws4_entry']


def identity(value):
    need(isinstance(value,dict) and type(value.get('pid')) is int and value['pid'] > 0
         and isinstance(value.get('command_line'),str) and 0 < len(value['command_line']) <= 32767
         and isinstance(value.get('executable'),str) and value['executable'],'Actual process identity unavailable')
    utc_ticks(value['created_utc'])
    return dict(pid=value['pid'],created_utc=value['created_utc'],executable=value['executable'],
        command_line_sha256=hashlib.sha256(value['command_line'].encode()).hexdigest())


def same_identity(observed, expected):
    return type(expected.get('pid')) is int and observed is not None and identity(observed) == {key:expected[key] for key in
        ('pid','created_utc','executable','command_line_sha256')}


def owned(observation, record, *, listener=True):
    need(type(record.get('pid')) is int and record['pid'] > 0
         and record.get('kind') == KIND and record.get('port') == PORT and record.get('workshop_id') == b.ITEM
         and record.get('tools') is False and record.get('offline_logic_requested') is False
         and record.get('argv') == arguments(Path(record['log_file'])),'Owned non-Tools original-item receipt required')
    rows=[r for r in observation['dota'] if r['pid'] == record['pid']]
    need(len(rows) == 1 and len(observation['dota']) == 1 and same_identity(rows[0],record)
         and Path(rows[0]['executable']).resolve() == EXE.resolve()
         and rows[0]['command_line'] == subprocess.list2cmdline([str(EXE),*record['argv']]),
         'Owned Dota PID/actual creation/executable/argv changed')
    need(all(r['pid'] == record['pid'] and r['port'] == PORT for r in observation['listeners'])
         and (bool(observation['listeners']) or not listener),'Fixed console port owner changed')
    return rows[0]


def live_record(folder, transaction):
    live=json_read(folder/'process.json')
    need(live.get('package_report_sha256') == transaction['package_report_sha256']
         and live.get('content_sha256') == transaction['content_sha256']
         and live.get('source_revision') == transaction['source_revision']
         and live.get('log_file') == str(folder/'engine.log')
         and live.get('code_pins') == transaction['code_pins'], 'Native process belongs to another transaction/candidate')
    need(type(live.get('native_created_filetime')) is int
         and type(live.get('keeper',{}).get('native_created_filetime')) is int,'Exact native process creation pins required')
    return live


def launch(identifier, report_sha):
    folder, record, package, manifest = load_transaction(identifier,report_sha,full=True)
    with operation_lock():
        no_clients(); steam_ready(); no_clients()
        need(not (folder/'launch_intent.json').exists(),'Launch already attempted; no automatic replay')
        need(acf_item()['item'] == record['acf']['item'],'Original item ACF changed')
        require_rows(folder/'backup',record['original_files'])
        need(not (folder/'restored.json').exists(),'Restored transaction cannot be relaunched')
        write_new(folder/'launch_intent.json',dict(status='REQUESTED_NOT_YET_STARTED',requested_utc=stamp(),code_pins=own_code_pins()))
    completed = False
    try:
        with FiveHolds(INSTALLED) as held:
            require_rows(INSTALLED,record['candidate_files']); full_vpk(INSTALLED,manifest)
            no_clients(); started = stamp(); log = folder/'engine.log'
            need(not log.exists(),'NEW engine log required')
            keeper = identity(process_details(os.getpid()))
            with OwnedLifetime(keeper,expected_exe=Path(keeper['executable'])) as owner_lifetime:
                keeper['native_created_filetime']=owner_lifetime.native_created_filetime
            child = subprocess.Popen([str(EXE),*arguments(log)],cwd=GAME/'dota',creationflags=HIDDEN,
                env=dict(os.environ,SteamAppId='570',SteamGameId='570'))
            value=process_details(child.pid); game=identity(value)
            need(utc_ticks(game['created_utc']) >= utc_ticks(started),'Launched PID predates request')
            live=dict(schema=1,kind=KIND,**game,port=PORT,workshop_id=b.ITEM,argv=arguments(log),
                log_file=str(log),tools=False,offline_logic_requested=False,cheats_requested=False,http_requested=True,
                source_revision=package['source_revision'],content_sha256=package['content_sha256'],
                package_report_sha256=report_sha,keeper=keeper,held_files=held.identities,started_utc=started,
                file_hold_mode='GENERIC_READ_FILE_SHARE_READ_ONLY',code_pins=own_code_pins(),official_download=False)
            owned(snapshot(),live,listener=False)
            # Retain the same kernel process object across PID reuse. During
            # ETW there is only a 2s kernel wait: no PowerShell/CIM/hash/scan.
            with OwnedLifetime(live) as lifetime:
                live['native_created_filetime']=lifetime.native_created_filetime
                write_new(folder/'process.json',live)
                print(json.dumps(dict(status='OWNED_REHEARSAL_RUNNING_KEEP_THIS_TERMINAL_ALIVE',pid=game['pid'],
                    created_utc=game['created_utc'],transaction_id=identifier,normal_oauth_required=True,
                    production_gameplay_verified=False,ready_for_upload=False)),flush=True)
                while not lifetime.wait_exited(): pass
                no_clients()  # Endpoint CIM/port inventory, after the owned process exited.
                write_new(folder/'hold_end.json',dict(status='OWNED_DOTA_EXITED_HOLDS_COMPLETED',ended_utc=stamp(),
                    pid=game['pid'],created_utc=game['created_utc'],held_files=held.identities,
                    process_lifetime=lifetime.verify(),end_no_dota_verified=True,
                    stable_observer='READ_ONLY_PROCESS_HANDLE_WAIT_ONLY',
                    gameplay_verified=False,restoration_still_required=True))
            completed=True
    finally:
        if not completed and not (folder/'hold_failed.json').exists():
            write_new(folder/'hold_failed.json',dict(status='HOLD_OR_OWNERSHIP_FAILED_NO_FORCE_STOP',observed_utc=stamp(),
                evidence_complete=False,automatic_restore=False,automatic_retry=False))
    return dict(status='REHEARSAL_CLIENT_EXITED_RESTORE_REQUIRED',ready_for_upload=False)


def file_use_result(users, game, keeper):
    def found(wanted):
        exact=wanted.get('native_created_filetime')
        return type(exact) is int and any(row.get('pid') == wanted['pid'] and row.get('created_filetime') == exact for row in users)
    return dict(owned_dota_uses_file=found(game),owned_keeper_uses_file=found(keeper))


def inspect(identifier, report_sha, label):
    folder, record, package, manifest = load_transaction(identifier,report_sha)
    safe_id(label)
    with operation_lock():
        target=folder/'inspections'/(label+'.json'); need(not target.exists(),'NEW inspection label required')
        live=live_record(folder,record); owned(snapshot(),live)
        need(live['code_pins'] == own_code_pins() and same_identity(process_details(live['keeper']['pid']),live['keeper'])
             and not (folder/'hold_end.json').exists() and not (folder/'hold_failed.json').exists(),'Continuous owned keeper no longer established')
        with FiveHolds(INSTALLED) as held:
            require_rows(INSTALLED,record['candidate_files'])
            need(held.identities == live['held_files'],'Candidate held FileID/path changed')
            rows=[]
            for name in NAMES:
                observed=restart_manager_users(INSTALLED/name)
                rows.append(dict(name=name,**file_use_result(observed,live,live['keeper'])))
            owned(snapshot(),live)
            need(same_identity(process_details(live['keeper']['pid']),live['keeper']),'Keeper changed during inspection')
            need(acf_item()['item'] == record['acf']['item'],'Steam original-item metadata changed')
        log=regular(Path(live['log_file']))
        need(log.stat().st_size <= 64*1024*1024,'Bounded native startup log required')
        raw=log.read_bytes(); text=raw.decode('utf-8','replace')
        markers=dict(entry_handoff_seen='[WS4-NATIVE-HANDOFF-01]' in text,
            server_activated='[SURVIVAL_LAUNCH_RULES] phase=activate ok=true deferred=false error=nil' in text,
            initialized='[Survival][INFO][Addon] initialized' in text,
            no_script_error=re.search(r'Script Runtime Error|VScript Error|SCRIPT ERROR|ScriptException|stack traceback:',text,re.I) is None)
        all_used=all(r['owned_dota_uses_file'] and r['owned_keeper_uses_file'] for r in rows)
        proof=dict(schema=1,kind=KIND,status='FILE_USE_OBSERVED_NOT_GAMEPLAY_ACCEPTANCE' if all_used else 'INCOMPLETE_NATIVE_FILE_USE_EVIDENCE',
            observed_utc=stamp(),release_sequence=b.SEQUENCE,content_sha256=package['content_sha256'],
            package_report_sha256=report_sha,source_revision=package['source_revision'],
            process={key:live[key] for key in ('pid','created_utc','command_line_sha256')},keeper=live['keeper'],
            candidate_files=record['candidate_files'],held_files=live['held_files'],file_use=rows,
            all_five_owned_dota_file_uses_observed=all_used,external_signed_manifest_binding=True,
            all_five_open_verified=all_used,index_owned_dota_use_observed=rows[0]['owned_dota_uses_file'],
            external_signed_resources_verified=6918,external_protected_modules_verified=184,
            external_auth_scope='FULL_AT_STAGE_LAUNCH_SIGNED_PIN_RECHECK_AT_INSPECT',
            all_gameplay_paths_verified=False,
            native_signed_manifest_sequence_hash_log_available=False,native_startup_markers=markers,
            engine_log_sha256=hashlib.sha256(raw).hexdigest(),official_download=False,uploaded=False,
            production_gameplay_verified=False,online_fps_verified=False,ready_for_upload=False,
            normal_oauth_approved_by_tool=False,cloud_writes_claimed_zero=False)
        write_new(target,proof)
        return dict(status=proof['status'],receipt=str(target),all_five_owned_dota_file_uses_observed=all_used,
            all_five_open_verified=all_used,index_owned_dota_use_observed=rows[0]['owned_dota_uses_file'],
            production_gameplay_verified=False,ready_for_upload=False)


CLOSE_JS = r"""'use strict';
const cp=require('node:child_process'),crypto=require('node:crypto');
const {ConsoleSession}=require(process.argv[1]);const w=JSON.parse(process.argv[2]),inspect=process.argv[3];
function guard(){const p=cp.spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',inspect],
 {windowsHide:true,encoding:'utf8',timeout:20000,maxBuffer:1048576});if(p.status!==0)throw Error('os_guard');
 const s=JSON.parse(p.stdout.replace(/^\uFEFF/,'')),r=s.dota.filter(x=>x.pid===w.pid);
 if(s.dota.length!==1||r.length!==1||r[0].created_utc!==w.created_utc||r[0].executable!==w.executable||
 crypto.createHash('sha256').update(r[0].command_line).digest('hex')!==w.command_line_sha256||
 !s.listeners.length||s.listeners.some(x=>x.port!==29028||x.pid!==w.pid))throw Error('owned_process_changed');}
(async()=>{guard();const s=new ConsoleSession({port:29028,timeoutMs:5000,historyTimeoutMs:10000,retainOutput:false,maxPendingOutputChars:4096});
 const barrier=s.requestBarrier.bind(s);s.requestBarrier=()=>{guard();return barrier();};
 try{await s.connect();guard();try{await s.send([{name:'console_send',arguments:{commands:'quit'}}],'',0);}
 catch(e){if(!(e.sent>=1))throw e;}process.stdout.write(JSON.stringify({quit_sent:true,force_stop:false}));}
 finally{await s.close();}})().catch(()=>{process.stderr.write('owned_quit_refused\n');process.exitCode=1;});
"""


def close(identifier, report_sha):
    folder,record,package,manifest=load_transaction(identifier,report_sha)
    with operation_lock():
        live=live_record(folder,record); owned(snapshot(),live)
        need(live['code_pins'] == own_code_pins(),'Fixed close transport changed')
        write_new(folder/'close_intent.json',dict(status='ONE_GRACEFUL_QUIT_REQUEST',observed_utc=stamp(),
            pid=live['pid'],created_utc=live['created_utc'],automatic_retry=False))
        node=shutil.which('node.exe') or shutil.which('node'); need(node,'Existing Node transport required')
        with OwnedLifetime(live):  # Exact kernel generation stays pinned through the Node/CIM barriers.
            result=subprocess.run([node,'-e',CLOSE_JS,str(TRANSPORT),json.dumps(live),
                "$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);"+SNAPSHOT_PS],
                capture_output=True,timeout=60,creationflags=HIDDEN)
        need(result.returncode == 0 and json.loads(result.stdout).get('quit_sent') is True,
            'Graceful close failed/unknown; no retry or force-stop')
        write_new(folder/'close_sent.json',dict(status='GRACEFUL_QUIT_SENT_NOT_FORCE_STOPPED',observed_utc=stamp(),
            pid=live['pid'],created_utc=live['created_utc'],restore_requires_no_dota=True))
        return dict(status='GRACEFUL_QUIT_SENT_WAIT_FOR_KEEPER_EXIT',force_stop=False,ready_for_upload=False)


def restore(identifier, report_sha):
    folder,record,package,manifest=load_transaction(identifier,report_sha,full=True)
    with operation_lock():
        no_clients(); need(not (folder/'restored.json').exists(),'Already restored; never replay')
        need(acf_item()['item'] == record['acf']['item'],'Original-item ACF changed before restoration')
        if (folder/'process.json').exists():
            live=live_record(folder,record)
            need(not same_identity(process_details(live['keeper']['pid']),live['keeper']), 'Wait for owned keeper to exit and release read holds')
        require_rows(folder/'backup',record['original_files'])
        _,old_manifest=b.baseline(full=True,require_current_journal=False)
        full_vpk(folder/'backup',old_manifest)
        # Unknown images block the entire restore before its first mutation.
        known_images(record)
        try:
            transition(folder,record,to_original=True)
            no_clients(); require_rows(INSTALLED,record['original_files']); full_vpk(INSTALLED,old_manifest)
            need(acf_item()['item'] == record['acf']['item'],'Original-item ACF changed; do not rewrite it')
            write_new(folder/'restored.json',dict(schema=1,status='ORIGINAL3102_FIVE_FILES_FULLY_RESTORED',observed_utc=stamp(),
                original_files=record['original_files'],original_content_sha256=b.BASE_CONTENT,
                official_download_performed=False,canonical_journal_written=False,acf_written=False,
                backups_preserved=True,publication_performed=False))
            event(folder,'ORIGINAL3102_FIVE_FILES_FULLY_RESTORED')
            return dict(status='ORIGINAL3102_FIVE_FILES_FULLY_RESTORED',publication_performed=False)
        except BaseException:
            event(folder,'RESTORE_INCOMPLETE_PRESERVE_ALL_BACKUPS',automatic_retry=False); raise


def static_plan():
    return dict(status='STATIC_REHEARSAL_PLAN_NO_EFFECTS',kind=KIND,release_sequence=b.SEQUENCE,
        original_item=b.ITEM,port=PORT,install_target=str(INSTALLED),external_store=str(STORE),
        five_members=list(NAMES),commit_order=list(ORDER),actions=['stage','launch','inspect','close','restore'],
        signed_report_required=True,launch_requires_keepalive_terminal=True,steam_initialized=False,
        files_written=0,os_queries=0,clients_started=0,official_download=False,ready_for_upload=False,
        source_revision=None,production_gameplay_verified=False,online_fps_verified=False)


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',nargs='?',default='plan',choices=['plan','stage','launch','inspect','close','restore'])
    parser.add_argument('--transaction'); parser.add_argument('--report-sha256'); parser.add_argument('--label')
    args=parser.parse_args(argv)
    if args.action == 'plan':
        need(not any((args.transaction,args.report_sha256,args.label)),'Static plan takes no action inputs')
        result=static_plan()
    else:
        safe_id(args.transaction)
        need(args.action == 'inspect' or args.label is None,'Label is only for explicit inspection')
        function=globals()[args.action]
        result=function(args.transaction,args.report_sha256,*([safe_id(args.label)] if args.action == 'inspect' else []))
    # ASCII JSON avoids Windows console-codepage corruption of external paths.
    print(json.dumps(result,ensure_ascii=True),flush=True)
    return 0


if __name__ == '__main__':
    try: raise SystemExit(main())
    except Exception:
        print(json.dumps(dict(status='REFUSED_PRESERVE_TRANSACTION_AND_BACKUPS',automatic_retry=False,
            force_stop=False,canonical_journal_written=False,publication_performed=False)),flush=True)
        raise SystemExit(2)
