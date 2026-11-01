"""Explicit install/start/query/collect/close of one owned signed test addon.

No login approval, identity substitution, cloud grant or Workshop upload.
Install is one authenticated manifest copy/hash pass, never a game refresh.
"""
from datetime import datetime,timezone
from pathlib import Path
import argparse,json,os,re,subprocess
from release_checks import build as b,validated_package

def load_entry():return b.module('five_account_native_entry',b.ROOT/'tools/workshop_test/test_entry.py')
def encoded(value):return (json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode()
def new_report(name,value):b.inc.write_new(b.REPORT/name,encoded(value))

def corrected_handoff_receipt(dry_result):
 """The old helper's static4 receipt is used only as a read-only validator.

This new installer writes its own truthful5-account/4-player metadata; it never
executes or edits the old helper's installation or an immutable signed file.
"""
 result=dict(dry_result)
 result.update(kind='isolated_five_account_test_handoff',tester_count=5,max_players=4,
  limitations=['Five approved Steam accounts; maximum four players in one match.',
   'Workshop visibility does not replace server admission or Steam authentication.',
   'Signed startup and official Workshop download are separate evidence.'])
 return result

def install(digest):
 package,manifest,_=validated_package(digest,full=True)
 b.need(not load_entry().process_inventory()['dota_pids'],'Close Dota before isolated installation')
 b.need(not (b.REPORT/'native_handoff.json').exists(),'NEW native handoff required')
 values,_,_=b.payloads(package['source_revision'])
 with b.scene_maps(),b.admission_context(values),b.inc.trusted_source(b.TRUSTED):
  h=b.pack.handoff
  result=corrected_handoff_receipt(h.prepare(b.VIEW,b.ADDON,list(b.APPROVED),'update',b.ITEM,apply=False))
  b.need(result['content_sha256']==manifest['content_sha256'] and result['runtime_files']==6917,'Dry validation identity differs')
  game_target,content_target=Path(result['game_addon']),Path(result['content_addon'])
  receipt=b.TRUSTED/'output/release_test_handoff'/b.ADDON
  b.need(not receipt.exists(),'NEW installed receipt directory required')
  stage=game_target.with_name('.'+game_target.name+'.admission-staging')
  b.need(not stage.exists(),'NEW staging directory required');stage.mkdir(exist_ok=False)
  for row in manifest['files']:b.inc.copy_new(b.pack.protect_data.source_path(b.VIEW,row['path']),stage/row['path'],row)
  b.need(b.pack.runtime.verify(stage,manifest)['ok'] and b.pack.runtime.verify(b.VIEW,manifest)['ok'],'Copy/source inventory changed; preserve staging')
  h.require_single_map(stage);h.require_reviewed_gate(stage,manifest)
  b.need(h.configured_ids(stage)==sorted(b.APPROVED),'Copied whitelist differs')
  b.need(not game_target.exists() and not content_target.exists(),'Destination appeared during install')
  os.rename(stage,game_target);content_target.mkdir(exist_ok=False)
  b.need(b.pack.runtime.verify(game_target,manifest)['ok'],'Installed inventory differs')
  result.update(status='INSTALLED_FOR_NATIVE_TEST_ONLY',dry_run=False,receipt_directory=str(receipt))
  receipt.mkdir(parents=True,exist_ok=False)
  for name in (h.MANIFEST,h.SIGNATURE):b.inc.write_new(receipt/name,(b.VIEW/name).read_bytes())
  b.inc.write_new(receipt/'handoff.json',encoded(result))
 new_report('native_handoff.json',result)
 print(json.dumps({'status':result['status'],'addon':b.ADDON,'files':6917,'tester_count':5,'max_players':4}))

def os_identity(pid):
 script="$ErrorActionPreference='Stop';$p=Get-CimInstance Win32_Process -Filter 'ProcessId="+str(pid)+"';if($null -eq $p -or $p.Name -ne 'dota2.exe' -or $p.CommandLine -notmatch '-addon "+b.ADDON+"(?: |$)' -or $p.CommandLine -notmatch '(?:^| )-tools(?: |$)' -or $p.CommandLine -notmatch '-vconport 29006(?: |$)'){throw 'Owned signed process mismatch'};[ordered]@{pid=$p.ProcessId;process_started_os_utc=$p.CreationDate.ToUniversalTime().ToString('o')}|ConvertTo-Json -Compress"
 raw=subprocess.check_output(['powershell.exe','-NoProfile','-Command',script],stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
 return json.loads(raw.decode('utf-8-sig'))

def launch():
 b.need(not (b.REPORT/'native_process.json').exists(),'NEW native process receipt required')
 handoff=b.load(b.REPORT/'native_handoff.json')
 b.need(handoff['addon_name']==b.ADDON and handoff['tester_count']==5 and handoff['max_players']==4,'Wrong installed handoff')
 manifest=b.load(Path(handoff['receipt_directory'])/b.pack.handoff.MANIFEST)
 with b.scene_maps():b.need(b.pack.runtime.verify(Path(handoff['game_addon']),manifest)['ok'],'Installed bytes changed')
 inventory=load_entry().process_inventory();b.need(not inventory['dota_pids'] and inventory['steam_running'],'Dota must be closed and Steam online')
 log=b.REPORT/'native_smoke_engine.log';b.need(not log.exists(),'NEW native log required')
 game=b.ROOT.parents[1]
 argv=['-steam','-tools','-noassetbrowser','-addon',b.ADDON,'-dev','-novid','-vconport','29006','-condebug','-con_logfile',str(log),
  '+sv_cheats','0','+host_timescale','1','+dota_launch_custom_game',b.ADDON,'template_map']
 process=subprocess.Popen([str(game/'bin/win64/dota2.exe'),*argv],cwd=game/'dota',creationflags=subprocess.CREATE_NO_WINDOW)
 identity=os_identity(process.pid)
 record={'status':'OWNED_SIGNED_NATIVE_STARTED',**identity,'addon':b.ADDON,'port':29006,'cheats':False,
  'started_utc':datetime.now(timezone.utc).isoformat(),'log_file':str(log),'argv':argv,'content_sha256':manifest['content_sha256'],
  'cloud_account_operations_performed':False}
 new_report('native_process.json',record)
 print(json.dumps({k:record[k] for k in ('status','pid','addon','content_sha256')}))

def collect():
 b.need(not (b.REPORT/'native_smoke.json').exists(),'NEW native smoke receipt required')
 owned=b.load(b.REPORT/'native_process.json');query=b.load(b.REPORT/'native_cvar_query.json')
 b.need(os_identity(owned['pid'])['process_started_os_utc']==owned['process_started_os_utc'],'Owned native process changed')
 b.need(query['pid']==owned['pid'] and query['addon']==b.ADDON and query['marker_received'] is True
  and query['script_injection'] is False and query['commands']==['sv_cheats','survival_archive_http_enabled'],'Exact readonly native query required')
 raw=query['raw_output'];b.need(b.sha(raw.encode())==query['raw_output_sha256'],'Raw native query drift')
 b.need(len(re.findall(r'\bsv_cheats\b["\s]*[:=]["\s]*(?:0|false)\b',raw,re.I))==1,'Actual native cheats0 required')
 b.need(len(re.findall(r'\bsurvival_archive_http_enabled\b["\s]*[:=]["\s]*1\b',raw))==1,'Actual native archive HTTP enabled required')
 log=Path(owned['log_file']).read_bytes();text=log.decode('utf8','replace')
 markers={'signed_addon':("addon='"+b.ADDON+"'") in text,
  'server_activated':'[SURVIVAL_LAUNCH_RULES] phase=activate ok=true deferred=false error=nil' in text,
  'initialized':'[Survival][INFO][Addon] initialized' in text,
  'layout_ready':'[STARTUP_UI]' in text and '"stage":"layout_ready"' in text,
  'no_script_error':re.search(r'Script Runtime Error|VScript Error|SCRIPT ERROR|ScriptException|stack traceback:|SnapshotError|Failed to serialize|Serialization failed|CustomGameEvent[^\n]*(?:too large|overflow)',text,re.I) is None}
 b.need(all(markers.values()),'Signed native startup markers failed: '+json.dumps(markers))
 handoff=b.load(b.REPORT/'native_handoff.json');installed=Path(handoff['game_addon'])
 manifest=b.load(Path(handoff['receipt_directory'])/b.pack.handoff.MANIFEST)
 with b.scene_maps():verified=b.pack.runtime.verify(installed,manifest)
 b.need(verified['ok'] and verified['expected_files']==6917,'Installed bytes changed during native startup')
 b.need(b.parsed_ids(installed,b.APPROVED)==sorted(b.APPROVED),'Installed exact-five roster differs')
 b.need(re.search(rb'(?m)^M\.all_difficulties_unlocked\s*=\s*false\s*$',(installed/'scripts/vscripts/config/mode_release_config.lua').read_bytes()),'Normal online write/default policy changed')
 profile=b.pack.handoff.literal_flat_config(installed,b.pack.runtime.RELEASE_PROFILE)
 b.need(profile=={'channel':'production','native_cloud_roster_required':True},'Installed production profile differs')
 frozen=b.REPORT/'native_smoke_engine_frozen.log';b.inc.write_new(frozen,log)
 proof={'schema':1,'status':'PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY','release_sequence':b.SEQUENCE,
  'content_sha256':manifest['content_sha256'],'signed_resources_verified':6917,'protected_modules_verified':184,'cheats':False,
  'tester_count':5,'max_players':4,'normal_default_verified':True,'markers':markers,'native_process':owned,
  'engine_log':{'path':str(frozen),'sha256':b.sha(log)},'native_query':{'path':str(b.REPORT/'native_cvar_query.json'),'sha256':b.pack.runtime.digest(b.REPORT/'native_cvar_query.json')},
  'real_account_grants_verified':False,'multiplayer_verified':False,'cloud_login_approved':False,
  'scope':'Signed candidate startup, installed exact5 roster and real cvars only; no impersonation or real player login.'}
 new_report('native_smoke.json',proof)
 print(json.dumps({'status':proof['status'],'files':6917,'tester_count':5,'max_players':4,'cheats':False}))

def close():
 owned=b.load(b.REPORT/'native_process.json')
 b.need(os_identity(owned['pid'])['process_started_os_utc']==owned['process_started_os_utc'],'Owned process identity changed')
 script="$ErrorActionPreference='Stop';$p=Get-Process -Id "+str(owned['pid'])+";if(-not $p.CloseMainWindow()){throw 'Normal close not accepted'};if(-not $p.WaitForExit(20000)){throw 'Owned native did not close normally'}"
 subprocess.run(['powershell.exe','-NoProfile','-Command',script],check=True,creationflags=subprocess.CREATE_NO_WINDOW)
 new_report('native_closed.json',{'status':'OWNED_SIGNED_NATIVE_CLOSED','pid':owned['pid'],'forced':False,'closed_utc':datetime.now(timezone.utc).isoformat()})
 print(json.dumps({'status':'OWNED_SIGNED_NATIVE_CLOSED','pid':owned['pid'],'forced':False}))

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=('install','launch','query','collect','close'));p.add_argument('--report-sha256');a=p.parse_args()
 if a.action=='install':install(a.report_sha256)
 elif a.action=='query':subprocess.run(['C:/Program Files/nodejs/node.exe',str(Path(__file__).with_name('native_query.cjs'))],check=True)
 else:globals()[a.action]()

if __name__=='__main__':
 try:main()
 except Exception as error:print(json.dumps({'status':'NATIVE_ACTION_REFUSED','error':str(error)}));raise SystemExit(1)
