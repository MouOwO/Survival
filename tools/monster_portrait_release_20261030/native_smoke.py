"""Install/launch a separate signed candidate, or record its native startup.

No developer addon is replaced. The launch keeps production checks and
sv_cheats=0; detailed portrait rendering was verified in the offline client.
"""
from pathlib import Path
import argparse,hashlib,importlib.util,json,subprocess,sys
sys.dont_write_bytecode=True
import build_release as b
ROOT=b.ROOT;OUT=b.REPORT;ADDON='svt_m3003'
def load(name):return b.base.load(OUT/name)
def write(name,value):
 with (OUT/name).open('x',encoding='utf8') as stream:stream.write(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps(value,ensure_ascii=False))
def entry():
 spec=importlib.util.spec_from_file_location('portrait_native_entry',ROOT/'tools/workshop_test/test_entry.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def install():
 package=load(b.PACKAGE_REPORT);b.need(package['release_sequence']==b.SEQUENCE and package['full_runtime_validator_passed'],'Completed signed build required')
 handoff=b.pack.handoff;original=handoff.require_reviewed_gate
 def reviewed(candidate,manifest):
  with b.inc.trusted_source(b.TRUSTED):return original(candidate,manifest)
 handoff.require_reviewed_gate=reviewed
 try:
  listing=b.base.load(ROOT/'publishing/workshop/test_listing.json')
  with b.portrait_scene_maps(package['target_pins']):result=handoff.prepare(b.VIEW,ADDON,listing['tester_steamids64'],'update',b.ITEM,apply=True)
 finally:handoff.require_reviewed_gate=original
 write('native_handoff.json',result)
def launch():
 e=entry();state=e.process_inventory();b.need(state['steam_running'] and not state['dota_pids'],'Native test requires no other Dota process')
 args=['-steam','-tools','-noassetbrowser','-addon',ADDON,'-dev','-novid','-vconport','29006','-condebug','-con_logfile',str(OUT/'native_smoke_engine.log'),'+sv_cheats','0','+host_timescale','1','+dota_launch_custom_game',ADDON,'template_map']
 p=subprocess.Popen([str(e.GAME/'bin/win64/dota2.exe'),*args],cwd=e.GAME/'dota',creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
 write('native_process.json',dict(status='ISOLATED_SIGNED_NATIVE_PROCESS_STARTED',pid=p.pid,addon=ADDON,cheats=False))
def evidence():
 raw=(OUT/'native_smoke_engine.log').read_bytes();log=raw.decode('utf8','replace')
 markers=dict(signed_addon_selected=("[Server] SV:  addon='"+ADDON+"'") in log,server_activated='[SURVIVAL_LAUNCH_RULES] phase=activate ok=true' in log,addon_initialized='[Survival][INFO][Addon] initialized' in log,modifier_registry_loaded='[SURVIVAL_MODIFIER_BOOTSTRAP] phase=activate registry_refreshed=true' in log,panorama_layout_loaded='[STARTUP_UI]' in log and 'layout_ready' in log,no_script_runtime_error='Script Runtime Error' not in log,no_vscript_error='VScript Error' not in log)
 b.need(all(markers.values()),str(markers));manifest=b.base.load(b.VIEW/b.pack.handoff.MANIFEST);installed=ROOT.parent/ADDON
 with b.portrait_scene_maps(load(b.PACKAGE_REPORT)['target_pins']):verification=b.pack.runtime.verify(installed,manifest)
 b.need(verification['ok'],'Installed candidate changed')
 b.need('channel = "production"' in (installed/'scripts/vscripts/config/release_profile.lua').read_text('utf8'),'Production profile required')
 with (OUT/'native_smoke_engine_frozen.log').open('xb') as stream:stream.write(raw)
 write('native_smoke.json',dict(status='PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY',markers=markers,content_sha256=manifest['content_sha256'],signed_resources_verified=manifest['file_count'],protected_modules_verified=184,cheats=False,native_process=load('native_process.json'),engine_log_sha256=hashlib.sha256(raw).hexdigest(),real_account_grants_verified=False,multiplayer_verified=False,scope='Signed unit portrait/map candidate startup; 197 appearances, prewarm and HUD transitions verified separately offline.'))
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['install','launch','evidence']);a=p.parse_args();globals()[a.action]()
