"""Explicit owned signed-production smoke tools; default plan has no effects.

No signing, publication, login, rewards, gameplay fixture or UI automation.
Production intentionally refuses offline_logic_test. A development equivalent
requires a separate entry and cannot become signed-production gameplay proof.
"""
from pathlib import Path
from datetime import datetime,timezone
import argparse
import importlib.util
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time

sys.dont_write_bytecode=True
_path=Path(__file__).with_name('publish.py')
_spec=importlib.util.spec_from_file_location('portrait1101_native_admission',_path)
p=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(p)
b,validated_package=p.b,p.validated_package
ADDON,PORT,PROTECTED_PID=b.NATIVE_ADDON,29026,28324
GAME=b.ROOT.parents[1]
EXE=GAME/'bin/win64/dota2.exe'
HANDOFF=b.REPORT/'native_handoff.json'
HIDDEN=getattr(subprocess,'CREATE_NO_WINDOW',0)

# Read-only OS inventory. Other client command lines are never emitted or saved.
SNAPSHOT_PS="""$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$d=@(Get-CimInstance Win32_Process -Filter "name='dota2.exe'" | ForEach-Object {
 [ordered]@{pid=[int]$_.ProcessId;created_utc=$_.CreationDate.ToUniversalTime().ToString('o');executable=$_.ExecutablePath;command_line=$_.CommandLine}})
$s=@(Get-CimInstance Win32_Process -Filter "name='steam.exe'")
$l=@(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object {$_.LocalPort -eq 29026} | ForEach-Object {
 [ordered]@{port=[int]$_.LocalPort;pid=[int]$_.OwningProcess;address=$_.LocalAddress}})
[ordered]@{dota=$d;steam_running=($s.Count -gt 0);listeners=$l}|ConvertTo-Json -Depth 5 -Compress
"""

# Existing reviewed framing/history/barrier implementation, console_send only.
# A fresh OS identity/port guard runs inside this child after its console
# handshake and immediately before the fixed cvar batch or graceful quit.
CONSOLE_JS=r"""'use strict';
const cp=require('node:child_process'),crypto=require('node:crypto');
const {ConsoleSession}=require(process.argv[1]);
const wanted=JSON.parse(process.argv[2]),operation=process.argv[3],nonce=process.argv[4],inspect=process.argv[5];
if(!['query','close'].includes(operation)||!/^AP1101_[a-f0-9]{32}$/.test(nonce))throw Error('fixed_operation_required');
function guard(){
 const r=cp.spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',inspect],{windowsHide:true,encoding:'utf8',timeout:15000,maxBuffer:1048576});
 if(r.status!==0)throw Error('owned_os_guard_failed');
 const s=JSON.parse(r.stdout.replace(/^\uFEFF/,'')),a=s.dota.filter(x=>x.pid===wanted.pid);
 if(a.length!==1||a[0].pid===28324||a[0].created_utc!==wanted.created_utc||
  a[0].executable.toLowerCase()!==wanted.executable.toLowerCase()||
  crypto.createHash('sha256').update(a[0].command_line,'utf8').digest('hex')!==wanted.command_line_sha256||
  !s.listeners.length||s.listeners.some(x=>x.port!==29026||x.pid!==wanted.pid)||
  (operation!=='close'&&s.dota.some(x=>x.pid!==wanted.pid)))throw Error('owned_process_generation_or_port_changed');
 return {pid:a[0].pid,created_utc:a[0].created_utc};
}
(async()=>{
 guard();const s=new ConsoleSession({port:29026,timeoutMs:5000,historyTimeoutMs:10000,
   retainOutput:false,maxPendingOutputChars:65536});
 const barrier=s.requestBarrier.bind(s);s.requestBarrier=()=>{guard();return barrier();};
 try{
  await s.connect();const before=guard();
  let answer;
  if(operation==='query')answer=await s.send([{name:'console_send',arguments:{commands:
    'sv_cheats\nsurvival_archive_http_enabled\necho '+nonce}}],nonce,100);
  else{
   try{answer=await s.send([{name:'console_send',arguments:{commands:'quit'}}],'',0);}
   catch(e){if(!(e.sent>=1))throw e;answer={sent:e.sent,peer_closed_after_send:true};}
  }
  if(answer.output_truncated)throw Error('native_query_output_truncated');
  console.log(JSON.stringify({before,...answer}));
 }finally{await s.close();}
})().catch(()=>{process.stderr.write('owned_native_console_refused\n');process.exitCode=1});
"""


def snapshot():
    b.need(os.name=='nt','Windows CIM identity required')
    result=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-Command',SNAPSHOT_PS],
        capture_output=True,timeout=20,creationflags=HIDDEN)
    b.need(result.returncode==0 and len(result.stdout)<=1024*1024,'Read-only OS process/port inventory failed')
    value=json.loads(result.stdout.decode('utf-8-sig'))
    b.need(isinstance(value.get('dota'),list) and isinstance(value.get('listeners'),list)
        and type(value.get('steam_running')) is bool,'Complete OS process/port inventory required')
    return value


def no_clients(observation):
    b.need(not observation['dota'],'Close existing Dota clients; never stop them automatically')
    b.need(not observation['listeners'],'Port29026 is occupied; do not reuse or stop its owner')
    b.need(observation['steam_running'] is True,'Normal Steam client must be running')


def steam_ready():
    # Read-only SDK app/owner/BLoggedOn checks; no UGC or cloud game operation.
    with p.sdk.Steam() as steam:return {'owner':steam.owner,'app_id':p.sdk.APP,'logged_on':True}


def run_directory(run_id):
    b.need(re.fullmatch(r'[a-z][a-z0-9_]{0,39}',run_id or '') is not None,'Explicit safe run-id required')
    return b.REPORT/('native_smoke_'+run_id)


def arguments(log):
    return ['-steam','-tools','-noassetbrowser','-addon',ADDON,'-dev','-novid','-vconport',str(PORT),
        '-condebug','-con_logfile',str(log),'+sv_cheats','0','+host_timescale','1',
        '+survival_archive_http_enabled','1','+dota_launch_custom_game',ADDON,'template_map']


def plan():
    return {'status':'SIGNED_NATIVE_PLAN_ONLY','addon':ADDON,'port':PORT,'protected_pid':PROTECTED_PID,
        'production_argv':arguments(b.REPORT/'native_smoke_NEW'/'engine.log'),
        'offline_status':'SIGNED_PRODUCTION_OFFLINE_NOT_SUPPORTED',
        'offline_reason':'production development_allowed=false; offline provider omitted/web auth enabled',
        'process_inventory':'NOT_RUN','steam_initialized':False,'files_written':0,'clients_started':0,
        'gameplay_verified':False,'online_fps_verified':False}


def install(digest):
    package,manifest,_=validated_package(digest,full=True)
    b.need(not HANDOFF.exists(),'NEW native handoff required; never replace an existing installation')
    no_clients(snapshot());steam=steam_ready();no_clients(snapshot())
    with b.scene_maps(),b.inc.trusted_source(b.TRUSTED):
        result=b.pack.handoff.prepare(b.VIEW,ADDON,b.pack.handoff.configured_ids(b.VIEW),'update',b.ITEM,apply=True)
    b.need(result['content_sha256']==manifest['content_sha256'] and result['release_sequence']==b.SEQUENCE
        and result['runtime_files']==6918 and result['signature_valid'] is True,'Installed signed identity differs')
    result=dict(result,native_package_report_sha256=digest,steam_readonly=steam)
    b.inc.write_new(HANDOFF,(json.dumps(result,ensure_ascii=False,indent=2)+'\n').encode())
    return {'status':result['status'],'addon':ADDON,'files':6918,'workshop_upload_performed':False}


def installed(digest):
    package,manifest,_=validated_package(digest)
    record=b.load(HANDOFF)
    target=b.pack.handoff.INSTALL/'game/dota_addons'/ADDON
    receipt=b.ROOT/'output/release_test_handoff'/ADDON
    b.need(record.get('native_package_report_sha256')==digest and record.get('addon_name')==ADDON
        and record.get('content_sha256')==package['content_sha256'] and record.get('release_sequence')==b.SEQUENCE
        and record.get('signature_valid') is True and record.get('dry_run') is False
        and Path(record['game_addon']).resolve()==target.resolve()
        and Path(record['receipt_directory']).resolve()==receipt.resolve(),'Exact owned signed installation required')
    for name in (b.pack.handoff.MANIFEST,b.pack.handoff.SIGNATURE):
        b.need(b.pack.handoff.regular_path(receipt/name).read_bytes()==(b.VIEW/name).read_bytes(),'Installed signed metadata changed')
    with b.scene_maps():checked=b.pack.runtime.verify(b.pack.handoff.regular_path(target),manifest)
    b.need(checked['ok'] and checked['expected_files']==6918,'Installed runtime failed full6918 hash verification')
    return package,manifest,target


def owned(observation,record,*,listener=True,allow_others=False):
    b.need(record.get('schema')==1 and record.get('kind')=='OWNED_SIGNED_NATIVE_PROCESS'
        and type(record.get('pid')) is int and record['pid']>0 and record['pid']!=PROTECTED_PID
        and record.get('addon')==ADDON and record.get('port')==PORT and record.get('mode')=='production_smoke',
        'Only this tool-owned production process may be controlled')
    rows=[row for row in observation['dota'] if row['pid']==record['pid']]
    b.need(len(rows)==1 and p.same_process(rows[0],record)
        and rows[0]['created_utc']==record['created_utc']
        and Path(rows[0]['executable']).resolve()==EXE.resolve()
        and b.sha(rows[0]['command_line'].encode())==record['command_line_sha256'],
        'Owned PID/actual CIM creation/executable/arguments changed')
    # The receipt also binds the exact fixed launch arguments, not just a PID.
    b.need(record['argv']==arguments(Path(record['log_file'])) and record.get('executable')==str(EXE)
        and '+survival_offline_logic_test' not in record['argv']
        and rows[0]['command_line']==subprocess.list2cmdline([str(EXE),*record['argv']]),'Owned launch contract changed')
    b.need(allow_others or len(observation['dota'])==1,'Another Dota client is running; no console operation admitted')
    b.need(all(row['pid']==record['pid'] and row['port']==PORT for row in observation['listeners'])
        and (bool(observation['listeners']) or not listener),'Owned port29026 listener required')
    return rows[0]


def launch_smoke(digest,run_id):
    package,manifest,_=installed(digest)
    directory=run_directory(run_id);b.need(not directory.exists(),'NEW native run directory required')
    no_clients(snapshot());steam_ready();no_clients(snapshot())
    log=directory/'engine.log';argv=arguments(log);started=datetime.now(timezone.utc).isoformat()
    directory.mkdir(parents=True,exist_ok=False)
    intent={'schema':1,'addon':ADDON,'port':PORT,'mode':'production_smoke','argv':argv,'log_file':str(log),
        'launch_requested_utc':started,'package_report_sha256':digest,'content_sha256':manifest['content_sha256']}
    b.inc.write_new(directory/'launch_intent.json',(json.dumps(intent,indent=2)+'\n').encode())
    process=subprocess.Popen([str(EXE),*argv],cwd=GAME/'dota',creationflags=HIDDEN)
    try:
        observation=snapshot();rows=[row for row in observation['dota'] if row['pid']==process.pid]
        b.need(len(rows)==1,'New Popen PID missing from actual CIM; ownership not established')
        observed=rows[0]
        b.need(p.timestamp(observed['created_utc'])>=p.timestamp(started),'Popen PID predates this launch intent')
        record={**intent,'schema':1,'kind':'OWNED_SIGNED_NATIVE_PROCESS','status':'SIGNED_PRODUCTION_SMOKE_STARTED',
            'pid':process.pid,'created_utc':observed['created_utc'],'started_utc':started,'executable':str(EXE),
            'command_line_sha256':b.sha(observed['command_line'].encode()),'release_sequence':b.SEQUENCE,
            'cheats':False,'http_enabled':True,'offline_logic_requested':False,
            'gameplay_verified':False,'online_fps_verified':False}
        owned(observation,record,listener=False)
        b.inc.write_new(directory/'process.json',(json.dumps(record,indent=2)+'\n').encode())
    except Exception:
        b.inc.write_new(directory/'launch_ownership_failed.json',(json.dumps({'status':'OWNERSHIP_NOT_ESTABLISHED',
            'popen_pid':process.pid,'clients_force_stopped':0,'automatic_retry':False})+'\n').encode())
        raise
    return {'status':record['status'],'pid':record['pid'],'created_utc':record['created_utc'],
        'process_receipt':str(directory/'process.json'),'gameplay_verified':False}


def launch_offline(*unused):
    raise ValueError('SIGNED_PRODUCTION_OFFLINE_NOT_SUPPORTED: development_allowed is fail-closed; use separate development equivalence evidence')


def console(record,operation,nonce):
    b.need(operation in ('query','close') and re.fullmatch(r'AP1101_[a-f0-9]{32}',nonce) is not None,
        'Fixed native query/close operation required')
    owned(snapshot(),record,allow_others=operation=='close')
    node=shutil.which('node.exe') or shutil.which('node');b.need(node,'Existing Node console transport required')
    result=subprocess.run([node,'-e',CONSOLE_JS,str(b.ROOT/'tools/map_c6/console-session.cjs'),
        json.dumps(record),operation,nonce,SNAPSHOT_PS],capture_output=True,timeout=60,creationflags=HIDDEN)
    b.need(result.returncode==0 and len(result.stdout)<=128*1024,'Owned native console refused; no automatic replay')
    return json.loads(result.stdout.decode('utf-8-sig'))


def query(run_id):
    directory=run_directory(run_id);record=b.load(directory/'process.json');target=directory/'native_cvar_query.json'
    b.need(not target.exists(),'NEW native query required')
    before=owned(snapshot(),record);nonce='AP1101_'+secrets.token_hex(16)
    result=console(record,'query',nonce);after=owned(snapshot(),record)
    b.need(result.get('expected_output_received') is True and result.get('sent')==3,'Fresh exact native query echo required')
    raw=result['output']
    receipt={'pid':record['pid'],'created_utc':record['created_utc'],'addon':ADDON,'port':PORT,
        'commands':['sv_cheats','survival_archive_http_enabled'],'marker':nonce,'marker_received':True,
        'script_injection':False,'raw_output':raw,'raw_output_sha256':b.sha(raw.encode()),
        'before':{key:before[key] for key in ('pid','created_utc')},'after':{key:after[key] for key in ('pid','created_utc')}}
    b.inc.write_new(target,(json.dumps(receipt,indent=2)+'\n').encode())
    return {'status':'OWNED_NATIVE_CVAR_QUERY_CAPTURED','pid':record['pid'],'created_utc':record['created_utc'],'query':str(target)}


def collect_smoke(digest,run_id):
    directory=run_directory(run_id);target=directory/'native_smoke.json'
    b.need(not target.exists(),'NEW signed startup receipt required')
    record=b.load(directory/'process.json');owned(snapshot(),record)
    b.need(record['package_report_sha256']==digest,'Startup package report differs')
    package,manifest,root=installed(digest);captured=b.load(directory/'native_cvar_query.json')
    raw=captured['raw_output']
    b.need(p.same_process(captured,record) and captured['addon']==ADDON and captured.get('marker_received') is True
        and captured.get('script_injection') is False and captured.get('commands')==['sv_cheats','survival_archive_http_enabled']
        and captured['raw_output_sha256']==b.sha(raw.encode())
        and re.search(r'(?m)^sv_cheats\s*=\s*false\s*$',raw)
        and re.search(r'(?m)^survival_archive_http_enabled\s*=\s*1\s*$',raw),'Actual same-generation production cvar query required')
    log=b.pack.read_metadata(b.pack.handoff.regular_path(Path(record['log_file'])),64*1024*1024)
    text=log.decode('utf8','replace')
    markers={'signed_addon':("addon='"+ADDON+"'") in text,
        'server_activated':'[SURVIVAL_LAUNCH_RULES] phase=activate ok=true deferred=false error=nil' in text,
        'initialized':'[Survival][INFO][Addon] initialized' in text,
        'layout_ready':'[STARTUP_UI]' in text and '"stage":"layout_ready"' in text,
        'no_script_error':re.search(r'Script Runtime Error|VScript Error|SCRIPT ERROR|ScriptException|stack traceback:',text,re.I) is None}
    b.need(all(markers.values()),'Production startup markers failed; no gameplay acceptance generated')
    b.need(re.search(rb'(?m)^M\.all_difficulties_unlocked\s*=\s*false\s*$',(root/b.MODE).read_bytes()),'Installed normal default differs')
    owned(snapshot(),record)
    b.inc.write_new(directory/'native_smoke_engine_frozen.log',log)
    proof={'schema':1,'status':'PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY','release_sequence':b.SEQUENCE,
        'content_sha256':manifest['content_sha256'],'package_report_sha256':digest,'signed_resources_verified':6918,
        'protected_modules_verified':184,'cheats':False,'markers':markers,'normal_default_verified':True,
        'engine_log_sha256':b.sha(log),'native_query_sha256':b.pack.runtime.digest(directory/'native_cvar_query.json'),
        'native_process':{key:record[key] for key in ('pid','created_utc','addon','port','started_utc')},
        'real_account_grants_verified':False,'multiplayer_verified':False,'cloud_login_approved':False,
        'full_package_gameplay_verified':False,'online_fps_verified':False}
    b.inc.write_new(target,(json.dumps(proof,indent=2)+'\n').encode())
    return {'status':proof['status'],'proof':str(target),'sha256':b.pack.runtime.digest(target),'gameplay_verified':False}


def close(run_id):
    directory=run_directory(run_id);record=b.load(directory/'process.json');target=directory/'closed.json'
    b.need(not target.exists(),'Close receipt already exists; do not replay')
    owned(snapshot(),record,allow_others=True)
    # Engine quit is a normal close, not terminate/kill/Stop-Process. No fallback.
    console(record,'close','AP1101_'+secrets.token_hex(16))
    deadline=time.monotonic()+8;gone=False
    for attempt in range(8):
        observed=snapshot();rows=[row for row in observed['dota'] if row['pid']==record['pid']]
        if not rows:gone=True;break
        b.need(len(rows)==1 and p.same_process(rows[0],record),'PID reused after graceful close; no further operation permitted')
        if time.monotonic()>=deadline:break
        time.sleep(.25)
    b.need(gone,'Owned client still running; no automatic force-stop or retry')
    b.inc.write_new(target,(json.dumps({'status':'OWNED_CLIENT_GRACEFULLY_CLOSED','pid':record['pid'],
        'created_utc':record['created_utc'],'force_stop_performed':False})+'\n').encode())
    return {'status':'OWNED_CLIENT_GRACEFULLY_CLOSED','pid':record['pid'],'force_stop_performed':False}


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',nargs='?',default='plan',choices=['plan','install','launch-smoke','launch-offline','query','collect-smoke','close'])
    parser.add_argument('--report-sha256');parser.add_argument('--run-id')
    args=parser.parse_args(argv)
    if args.action=='plan':result=plan()
    elif args.action=='install':result=install(args.report_sha256)
    elif args.action=='launch-smoke':result=launch_smoke(args.report_sha256,args.run_id)
    elif args.action=='launch-offline':result=launch_offline()
    elif args.action=='query':result=query(args.run_id)
    elif args.action=='collect-smoke':result=collect_smoke(args.report_sha256,args.run_id)
    else:result=close(args.run_id)
    print(json.dumps(result,ensure_ascii=False));return 0


if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception as error:
        print(json.dumps({'status':'NATIVE_ACTION_REFUSED_NO_AUTOMATIC_RETRY','reason':str(error),
            'force_stops':0,'updates_submitted':0}));raise SystemExit(1)
