"""Explicit nontransactional native serializer probe, isolated from Workshop.

Launches the official base dota map in Tools, never an addon or player API.
The small temporary script emits eight cw/d messages; net_showmsg reports the
engine's own received message lengths. These are transport evidence only, not
production gameplay, ordinary-client acceptance or a frame-rate benchmark.
"""
from pathlib import Path
import argparse,ctypes,hashlib,json,subprocess,sys
from datetime import datetime,timezone

ROOT=Path(__file__).resolve().parents[1]
GAME=ROOT.parents[1]
STORE=Path('D:/Survival_本地排演/network50_probe_20261103/run01')
EXE=GAME/'bin/win64/dota2.exe'
SCRIPT=GAME/'dota/scripts/vscripts/net50_probe_20261103.lua'
CFG=GAME/'dota/cfg/net50_probe_20261103.cfg'
LUA='''-- Isolated base-map packet sizing only; no persistence/rewards/HTTP.
if not IsServer() or not IsInToolsMode() or GetMapName()~="dota" then
    print("[N50_NATIVE_PROBE] REFUSED_ENVIRONMENT")
    return
end
local started=Time()
GameRules:GetGameModeEntity():SetContextThink("net50_probe_20261103",function()
    if Time()-started>30 then print("[N50_NATIVE_PROBE] NO_LOCAL_PLAYER");return nil end
    local player=PlayerResource:GetPlayer(0)
    if not player then return 0.1 end
    print("[N50_NATIVE_PROBE] BEGIN event=cw key=d native_lengths_required")
    for _,n in ipairs({0,1,8,16,24,28,32,40}) do
        print("[N50_NATIVE_PROBE] SEND value_ascii_bytes="..n)
        CustomGameEventManager:Send_ServerToPlayer(player,"cw",{d=string.rep("A",n)})
    end
    print("[N50_NATIVE_PROBE] END sends=8 transactions=0")
    return nil
end,0)
'''
CONFIG='net_showmsg CUserMsg_CustomGameEvent\nnet_restrict_showmsg_socket client\nscript_execute net50_probe_20261103\n'

def sha(raw):return hashlib.sha256(raw).hexdigest()
def write_new(path,raw):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('xb') as stream:stream.write(raw)
def ps(script):
    # CIM errors are normally non-terminating in Windows PowerShell. An access
    # failure must never become an empty process list and authorize retirement.
    strict="$ErrorActionPreference='Stop'; "+script
    done=subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',strict],capture_output=True,check=True,encoding='utf8')
    return json.loads(done.stdout or 'null')
def clients():
    observed=ps("$probeProcesses=@(Get-CimInstance Win32_Process -Filter \"name='dota2.exe'\" -ErrorAction Stop|ForEach-Object {[ordered]@{pid=[int]$_.ProcessId;created=$_.CreationDate.ToUniversalTime().ToString('o')}}); ConvertTo-Json -InputObject $probeProcesses -Compress")
    if not isinstance(observed,list):raise ValueError('process_query_must_return_explicit_array')
    for row in observed:
        if not isinstance(row,dict) or type(row.get('pid'))is not int or row['pid']<1 or not isinstance(row.get('created'),str) or not row['created']:
            raise ValueError('process_query_identity_invalid')
    return observed
def launch():
    if clients():raise ValueError('existing_dota_client_preserved')
    if STORE.exists():raise ValueError('fresh_single_probe_paths_required')
    for path,expected in ((SCRIPT,LUA.encode()),(CFG,CONFIG.encode())):
        if path.exists() and path.read_bytes()!=expected:raise ValueError('existing_probe_source_changed_preserve')
    STORE.mkdir(parents=True)
    write_new(STORE/'probe.lua',LUA.encode());write_new(STORE/'probe.cfg',CONFIG.encode())
    if not SCRIPT.exists():write_new(SCRIPT,LUA.encode())
    if not CFG.exists():write_new(CFG,CONFIG.encode())
    log=ROOT/'output/network50_native_probe_20261103'/STORE.name/'engine.log';log.parent.mkdir(parents=True,exist_ok=True)
    args=['-steam','-tools','-noassetbrowser','-dev','-novid','-console','-vconsole','-vconport','29068',
        '-condebug','-con_logfile',str(log),'+sv_cheats','1',
        '+map','dota','+exec','net50_probe_20261103']
    process=subprocess.Popen([str(EXE),*args],cwd=GAME/'dota',creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    observed=clients();rows=observed if isinstance(observed,list) else [observed]
    identity=next((x for x in rows if x and x['pid']==process.pid),None)
    if not identity:raise ValueError('owned_process_identity_not_observed_preserve_files')
    receipt=dict(status='BASE_MAP_NATIVE_TRANSPORT_PROBE_STARTED',**identity,argv=args,
        observed_utc=datetime.now(timezone.utc).isoformat(),script_sha256=sha(LUA.encode()),cfg_sha256=sha(CONFIG.encode()),
        workshop_install_written=False,sdk_initialized=False,transactions=0,ordinary_client_acceptance=False)
    write_new(STORE/'process.json',(json.dumps(receipt,indent=2)+'\n').encode())
    return receipt
def close():
    record=json.loads((STORE/'process.json').read_bytes())
    rows=clients();rows=rows if isinstance(rows,list) else [rows]
    if not any(x and x['pid']==record['pid'] and x['created']==record['created'] for x in rows):
        return dict(status='OWNED_NATIVE_PROBE_ALREADY_EXITED',force_stop=False)
    api=ctypes.WinDLL('user32',use_last_error=True);found=[]
    callback=ctypes.WINFUNCTYPE(ctypes.c_bool,ctypes.c_void_p,ctypes.c_void_p)
    def visit(hwnd,_):
        pid=ctypes.c_ulong();api.GetWindowThreadProcessId(ctypes.c_void_p(hwnd),ctypes.byref(pid))
        if pid.value==record['pid'] and api.IsWindowVisible(ctypes.c_void_p(hwnd)):found.append(hwnd)
        return True
    api.EnumWindows(callback(visit),None)
    if not found:raise ValueError('owned_visible_window_required_no_force_stop')
    for hwnd in found:
        if not api.PostMessageW(ctypes.c_void_p(hwnd),0x0010,0,0):raise ValueError('normal_close_not_queued')
    return dict(status='OWNED_NATIVE_PROBE_NORMAL_CLOSE_QUEUED',windows=len(found),force_stop=False)
def status():
    return dict(status='READONLY_NATIVE_PROBE_STATUS',clients=clients(),log_exists=(STORE/'engine.log').exists(),
        workshop_install_written=False,transactions=0)
def main():
    global STORE
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=('plan','launch','status','close'))
    parser.add_argument('--run-id',choices=('run01','run02'),default='run01')
    args=parser.parse_args()
    STORE=STORE.parent/args.run_id
    result=dict(status='STATIC_NATIVE_PACKET_SIZING_PROBE_NO_ACTIONS',store=str(STORE),value_lengths=[0,1,8,16,24,28,32,40])if args.action=='plan' else globals()[args.action]()
    print(json.dumps(result,ensure_ascii=True))
if __name__=='__main__':main()
