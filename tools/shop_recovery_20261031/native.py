"""Install/launch/collect only an owned signed3102 startup test; never approve login."""
from datetime import datetime,timezone
from pathlib import Path
import argparse,importlib.util,json,re,subprocess
from release_checks import validated_package,build as b

ADDON='svt_s3102'


def load_entry():
    spec=importlib.util.spec_from_file_location('shop_native_entry',b.ROOT/'tools/workshop_test/test_entry.py')
    entry=importlib.util.module_from_spec(spec);spec.loader.exec_module(entry);return entry


def install(digest):
    report,manifest,_=validated_package(digest,full=True)
    inventory=load_entry().process_inventory();b.need(not inventory['dota_pids'],'Dota must be closed')
    target=b.REPORT/'native_handoff.json';b.need(not target.exists(),'NEW handoff required')
    with b.parent.scene_maps(),b.inc.trusted_source(b.TRUSTED):
        testers=b.pack.handoff.configured_ids(b.VIEW)
        result=b.pack.handoff.prepare(b.VIEW,ADDON,testers,'update',b.ITEM,apply=True)
    b.need(result['content_sha256']==manifest['content_sha256'] and result['runtime_files']==6917,'Installed identity differs')
    b.inc.write_new(target,(json.dumps(result,ensure_ascii=False,indent=2)+'\n').encode())
    print(json.dumps({'status':result['status'],'addon':ADDON,'files':6917,'workshop_upload_performed':False}))


def launch():
    target=b.REPORT/'native_process.json';b.need(not target.exists(),'NEW process receipt required')
    handoff=b.load(b.REPORT/'native_handoff.json');b.need(handoff['addon_name']==ADDON,'Wrong native addon')
    manifest=b.load(Path(handoff['receipt_directory'])/b.pack.handoff.MANIFEST)
    with b.parent.scene_maps():verified=b.pack.runtime.verify(Path(handoff['game_addon']),manifest)
    b.need(verified['ok'],'Installed bytes changed')
    inventory=load_entry().process_inventory();b.need(not inventory['dota_pids'] and inventory['steam_running'],'Dota must be closed and Steam online')
    log=b.REPORT/'native_smoke_engine.log';b.need(not log.exists(),'NEW native log required')
    game=b.ROOT.parents[1]
    argv=['-steam','-tools','-noassetbrowser','-addon',ADDON,'-dev','-novid','-vconport','29006',
        '-condebug','-con_logfile',str(log),'+sv_cheats','0','+host_timescale','1','+dota_launch_custom_game',ADDON,'template_map']
    process=subprocess.Popen([str(game/'bin/win64/dota2.exe'),*argv],cwd=game/'dota',creationflags=subprocess.CREATE_NO_WINDOW)
    result={'status':'ISOLATED_SIGNED_NATIVE_PROCESS_STARTED','pid':process.pid,'addon':ADDON,'port':29006,'cheats':False,
        'started_utc':datetime.now(timezone.utc).isoformat(),'log_file':str(log),'argv':argv,
        'content_sha256':manifest['content_sha256'],'signed_resources_verified':6917,'cloud_account_operations_performed':False}
    b.inc.write_new(target,(json.dumps(result,ensure_ascii=False,indent=2)+'\n').encode())
    print(json.dumps({key:result[key] for key in ('status','pid','addon','content_sha256')}))


def collect():
    target=b.REPORT/'native_smoke.json';b.need(not target.exists(),'NEW native smoke receipt required')
    owned=b.load(b.REPORT/'native_process.json');query=b.load(b.REPORT/'native_cvar_query.json')
    b.need(query['pid']==owned['pid'] and query['addon']==ADDON and query['marker_received']
        and query['script_injection'] is False and query['commands']==['sv_cheats','survival_archive_http_enabled'],'Exact readonly query required')
    raw=query['raw_output'];b.need(b.sha(raw.encode())==query['raw_output_sha256'],'Native query changed')
    b.need(len(re.findall(r'\bsv_cheats\b["\s]*[:=]["\s]*(?:0|false)\b',raw,re.I))==1,'Native cheats must be false')
    b.need(re.search(r'\bsurvival_archive_http_enabled\b["\s]*[:=]["\s]*1\b',raw),'Native archive HTTP must be enabled')
    log=Path(owned['log_file']).read_bytes();text=log.decode('utf8','replace')
    markers={'signed_addon':("addon='"+ADDON+"'") in text,
        'server_activated':'[SURVIVAL_LAUNCH_RULES] phase=activate ok=true deferred=false error=nil' in text,
        'initialized':'[Survival][INFO][Addon] initialized' in text,
        'layout_ready':'[STARTUP_UI]' in text and '"stage":"layout_ready"' in text,
        'no_script_error':re.search(r'Script Runtime Error|VScript Error|SCRIPT ERROR|ScriptException|stack traceback:',text,re.I) is None}
    b.need(all(markers.values()),'Native startup marker failed: '+json.dumps(markers))
    handoff=b.load(b.REPORT/'native_handoff.json');root=Path(handoff['game_addon'])
    manifest=b.load(Path(handoff['receipt_directory'])/b.pack.handoff.MANIFEST)
    with b.parent.scene_maps():verified=b.pack.runtime.verify(root,manifest)
    b.need(verified['ok'] and verified['expected_files']==6917,'Installed bytes changed during startup')
    mode=(root/b.MODE).read_bytes();b.need(re.search(rb'(?m)^M\.all_difficulties_unlocked\s*=\s*false\s*$',mode),'Installed normal default differs')
    b.need(b'BlackLionMarketRedeem' in (root/b.PAYLOADS[2]).read_bytes(),'Redemption UI missing')
    frozen=b.REPORT/'native_smoke_engine_frozen.log';b.inc.write_new(frozen,log)
    result={'schema':1,'status':'PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY','release_sequence':b.SEQUENCE,
        'content_sha256':manifest['content_sha256'],'signed_resources_verified':6917,'protected_modules_verified':184,
        'cheats':False,'markers':markers,'normal_default_verified':True,'redemption_resources_verified':True,
        'engine_log_sha256':b.sha(log),'native_query_sha256':b.pack.runtime.digest(b.REPORT/'native_cvar_query.json'),
        'native_process':{key:owned[key] for key in ('pid','addon','port','started_utc')},
        'real_account_grants_verified':False,'multiplayer_verified':False,'cloud_login_approved':False}
    b.inc.write_new(target,(json.dumps(result,ensure_ascii=False,indent=2)+'\n').encode())
    print(json.dumps({'status':result['status'],'files':6917,'cheats':False,'proof_sha256':b.pack.runtime.digest(target)}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['install','launch','collect']);parser.add_argument('--report-sha256')
    args=parser.parse_args()
    if args.action=='install':install(args.report_sha256)
    elif args.action=='launch':launch()
    else:collect()
