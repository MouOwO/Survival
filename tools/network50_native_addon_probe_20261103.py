"""Fresh isolated Lua-enabled transport LAB, no project or account service.

The LAB and its files live outside game/content. A fresh junction is only its
Tools mount point; the sole VPK is an unchanged normal maps/template_map.vpk.
No bare package/data volume or production install is created or replaced.
"""
from pathlib import Path
import hashlib,importlib.util,json,os,shutil,subprocess,sys,time

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('n50_base_probe',Path(__file__).with_name('network50_native_probe_20261103.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
STORE=p.STORE.parent/'run03';LAB=STORE/'addon';MOUNT=ROOT.parent/'svt_network50_lab'
SOURCE='''function Precache(context) end
function Activate()
    if not IsInToolsMode() or GetMapName()~="template_map" then return end
    local started=Time()
    GameRules:GetGameModeEntity():SetContextThink("n50_packet_probe",function()
        if Time()-started>60 then print("[N50_NATIVE_PROBE] NO_PLAYER");return nil end
        local player=PlayerResource:GetPlayer(0)
        if not player then return 0.1 end
        print("[N50_NATIVE_PROBE] BEGIN event=cw key=d")
        for _,n in ipairs({0,1,8,16,24,28,32,40}) do
            print("[N50_NATIVE_PROBE] SEND value_ascii_bytes="..n)
            CustomGameEventManager:Send_ServerToPlayer(player,"cw",{d=string.rep("A",n)})
        end
        print("[N50_NATIVE_PROBE] END sends=8 transactions=0")
        return nil
    end,0)
end
'''

# This second direction deliberately uses a fresh, minimal addon. Preparing it
# never launches/closes Dota, touches the production install, or calls an SDK.
C2S_STORE=p.STORE.parent/'run04'
C2S_GAME=C2S_STORE/'addon'
C2S_CONTENT=C2S_STORE/'content'
CONTENT_MOUNT=ROOT.parents[2]/'content/dota_addons/svt_network50_lab'
C2S_LUA='''function Precache(context) end
function Activate()
    if not IsInToolsMode() or GetMapName()~="template_map" then return end
    local received,announced=false,false
    CustomGameEventManager:RegisterListener("cw",function(source,payload)
        if received then print("[N50_C2S_PROBE] DUPLICATE_REFUSED");return end
        if type(payload)~="table" or type(payload.d)~="string" or #payload.d~=24
            or payload.d~=string.rep("A",24) then
            print("[N50_C2S_PROBE] INVALID_PAYLOAD");return
        end
        received=true
        local injected=tonumber(payload.PlayerID)
        local player=injected and PlayerResource:GetPlayer(injected) or nil
        local ok,actor=pcall(EntIndexToHScript,tonumber(source) or -1)
        local own_id=player and player:GetPlayerID() or -1
        local actor_id=-2
        if ok and actor and type(actor.GetPlayerID)=="function" then
            local safe,value=pcall(actor.GetPlayerID,actor)
            if safe then actor_id=value end
        end
        print("[N50_C2S_PROBE] RECEIVED value_ascii_bytes=24 source_index="..tostring(tonumber(source) or -1)
            .." entity_is_actual_player="..tostring(ok and actor==player and player~=nil)
            .." engine_player_id_matches="..tostring(actor_id==own_id and own_id>=0)
            .." injected_player_id_matches="..tostring(injected==own_id and own_id>=0))
        print("[N50_C2S_PROBE] END received=1 transactions=0")
    end)
    local started=Time()
    GameRules:GetGameModeEntity():SetContextThink("n50_c2s_ready",function()
        if received then return nil end
        if Time()-started>60 then print("[N50_C2S_PROBE] NO_PLAYER");return nil end
        local player=PlayerResource:GetPlayer(0)
        if not player then return 0.1 end
        if not announced then announced=true;print("[N50_C2S_PROBE] BEGIN event=cw key=d direction=client_to_server") end
        -- Empty cw is readiness only. The measured C2S frame is sent by the
        -- actual Panorama GameEvents bridge after this listener is installed.
        CustomGameEventManager:Send_ServerToPlayer(player,"cw",{d=""})
        return 1 -- Bounded readiness retry only; measured C2S still occurs once.
    end,0)
end
'''
C2S_JS='''(function(){
"use strict";
var sent=false,root=$.GetContextPanel();
GameEvents.Subscribe("cw",function(packet){
 if(sent||!packet||packet.d!==""||!root||root.IsValid&&!root.IsValid())return;
 sent=true;
 GameEvents.SendCustomGameEventToServer("cw",{d:"A".repeat(24)});
 $.Msg("[N50_C2S_PROBE_CLIENT] SENT event=cw key=d value_ascii_bytes=24 transactions=0");
});
}());
'''
C2S_MANIFEST='''<?xml version="1.0" encoding="utf-8"?>
<root><Panel hittest="false"><CustomUIElement type="Hud" layoutfile="file://{resources}/layout/custom_game/n50_c2s_probe.xml" /></Panel></root>
'''
C2S_XML='''<?xml version="1.0" encoding="utf-8"?>
<root><scripts><include src="file://{resources}/scripts/custom_game/n50_c2s_probe.js" /></scripts><Panel hittest="false" hittestchildren="false" /></root>
'''
C2S_FILES={
    'panorama/layout/custom_game/custom_ui_manifest.xml':C2S_MANIFEST.encode(),
    'panorama/layout/custom_game/n50_c2s_probe.xml':C2S_XML.encode(),
    'panorama/scripts/custom_game/n50_c2s_probe.js':C2S_JS.encode(),
}
C2S_EXT={'.xml':'.vxml_c','.js':'.vjs_c'}

def file_sha(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def c2s_plan():
    log=ROOT/'output/network50_native_probe_20261103'/C2S_STORE.name/'engine.log'
    return dict(status='ISOLATED_C2S_NATIVE_PROBE_PLAN_NO_ACTIONS',external_lab=str(C2S_GAME),
        external_content=str(C2S_CONTENT),game_mount=str(MOUNT),content_mount=str(CONTENT_MOUNT),
        log=str(log),event='cw',key='d',value_ascii_bytes=24,
        lua_sha256=p.sha(C2S_LUA.encode()),source_sha256={key:p.sha(raw) for key,raw in C2S_FILES.items()},
        native_proof_pending=True,actor_source_proof_pending=True,transactions=0,sdk_calls=0,
        launch_argv=[str(p.EXE),'-steam','-tools','-noassetbrowser','-dev','-addon',MOUNT.name,
            '-novid','-console','-vconsole','-vconport','29068','-condebug','-con_logfile',str(log),
            '+sv_cheats','1','+net_showmsg','1' if C2S_STORE.name=='run06' else 'CUserMsg_CustomGameEvent','+net_restrict_showmsg_socket','server',
            '+dota_launch_custom_game',MOUNT.name,'template_map'])

def _fresh_c2s_paths():
    external_parent=Path('D:/Survival_本地排演/network50_probe_20261103').resolve()
    if C2S_STORE.resolve().parent!=external_parent:raise ValueError('exact_external_run04_parent_required')
    if MOUNT.parent.resolve()!=ROOT.parent.resolve():raise ValueError('exact_game_addon_mount_parent_required')
    expected_content=ROOT.parents[2]/'content/dota_addons'
    if CONTENT_MOUNT.parent.resolve()!=expected_content.resolve():raise ValueError('exact_content_addon_mount_parent_required')
    for path in (C2S_STORE,MOUNT,CONTENT_MOUNT):
        if os.path.lexists(path):raise ValueError('fresh_c2s_lab_and_both_mounts_required:'+str(path))

def prepare_c2s():
    """Prepare and officially compile only. The root operator owns launch/exit."""
    if p.clients():raise ValueError('existing_dota_client_preserved_no_mount_changes')
    _fresh_c2s_paths()
    compiler=p.GAME/'bin/win64/resourcecompiler.exe'
    source_map=ROOT/'maps/template_map.vpk'
    if not compiler.is_file() or not source_map.is_file():raise ValueError('official_compiler_and_normal_template_map_required')
    C2S_GAME.mkdir(parents=True);C2S_CONTENT.mkdir()
    p.write_new(C2S_GAME/'addoninfo.txt',b'"AddonInfo"\n{\n "addon_title" "Native C2S actor probe"\n "addon_type" "1"\n "maps" "template_map"\n "max_players" "1"\n}\n')
    p.write_new(C2S_GAME/'scripts/vscripts/addon_game_mode.lua',C2S_LUA.encode())
    map_target=C2S_GAME/'maps/template_map.vpk';map_target.parent.mkdir()
    shutil.copyfile(source_map,map_target)
    map_digest=file_sha(source_map)
    if file_sha(map_target)!=map_digest:raise ValueError('normal_map_copy_digest_mismatch_preserve_lab')
    for relative,raw in C2S_FILES.items():p.write_new(C2S_CONTENT/relative,raw)
    for mount,target in ((MOUNT,C2S_GAME),(CONTENT_MOUNT,C2S_CONTENT)):
        subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',
            "New-Item -ItemType Junction -Path '"+str(mount)+"' -Target '"+str(target)+"' | Out-Null"],check=True)
        if mount.resolve()!=target.resolve():raise ValueError('isolated_junction_target_mismatch_preserve_lab')
    records=[]
    # Only three explicit inputs; no directory compile, source dependencies,
    # project asset imports, production pointer or external account runtime.
    for relative,raw in sorted(C2S_FILES.items(),key=lambda row:(2 if row[0].endswith('custom_ui_manifest.xml') else 0 if row[0].endswith('.js') else 1)):
        source=CONTENT_MOUNT/relative
        artifact=C2S_GAME/str(Path(relative).with_suffix(C2S_EXT[Path(relative).suffix]))
        if artifact.exists():raise ValueError('unexpected_existing_c2s_compiler_output')
        started=time.time();args=[str(compiler),'-i',str(source),'-game',str(p.GAME/'dota'),'-fshallow','-nop4']
        built=subprocess.run(args,capture_output=True,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        log=built.stdout+built.stderr
        p.write_new(C2S_STORE/'compile_logs'/(Path(relative).name+'.log'),log)
        if built.returncode!=0 or b'0 failed' not in log or not artifact.is_file() or artifact.stat().st_size<=0:
            raise ValueError('official_c2s_compile_failed_preserve_all_evidence:'+relative)
        if artifact.stat().st_mtime+2<started:raise ValueError('stale_c2s_compiler_artifact')
        if source.read_bytes()!=raw:raise ValueError('compiler_input_mutated')
        records.append(dict(source_relative=relative,source_sha256=p.sha(raw),source_bytes=len(raw),
            artifact_relative=artifact.relative_to(C2S_GAME).as_posix(),artifact_sha256=file_sha(artifact),
            artifact_bytes=artifact.stat().st_size,compiler_argv=args,compiler_exit_code=built.returncode))
    report=c2s_plan();report.update(status='ISOLATED_C2S_NATIVE_PROBE_PREPARED_NOT_LAUNCHED',
        normal_map_sha256=map_digest,compiler_sha256=file_sha(compiler),compiled_resources=records,
        workshop_install_written=False,production_gameplay_acceptance=False,backend_imports=False,
        processes_started=0,processes_closed=0,files_removed=0)
    p.write_new(C2S_STORE/'prepared.json',(json.dumps(report,indent=2)+'\n').encode())
    return report

def verify_c2s():
    report=json.loads((C2S_STORE/'prepared.json').read_bytes())
    if report.get('status')!='ISOLATED_C2S_NATIVE_PROBE_PREPARED_NOT_LAUNCHED':raise ValueError('prepared_c2s_receipt_required')
    if MOUNT.resolve()!=C2S_GAME.resolve() or CONTENT_MOUNT.resolve()!=C2S_CONTENT.resolve():raise ValueError('exact_prepared_c2s_mounts_required')
    if (C2S_GAME/'scripts/vscripts/addon_game_mode.lua').read_bytes()!=C2S_LUA.encode():raise ValueError('c2s_lua_source_drift')
    for row in report['compiled_resources']:
        source=C2S_CONTENT/row['source_relative'];artifact=C2S_GAME/row['artifact_relative']
        if file_sha(source)!=row['source_sha256'] or file_sha(artifact)!=row['artifact_sha256']:
            raise ValueError('prepared_c2s_source_or_artifact_drift')
    if file_sha(C2S_GAME/'maps/template_map.vpk')!=report['normal_map_sha256']:raise ValueError('prepared_normal_map_drift')
    return dict(status='ISOLATED_C2S_PREPARED_BYTES_VERIFIED_NOT_NATIVE_PROOF',resources=3,
        native_proof_pending=True,actor_source_proof_pending=True,transactions=0,processes_started=0)
def launch_c2s():
    verify_c2s()
    if p.clients():raise ValueError('existing_client_preserved')
    receipt=C2S_STORE/'process.json'
    if receipt.exists():raise ValueError('fresh_c2s_process_receipt_required')
    prepared=json.loads((C2S_STORE/'prepared.json').read_bytes())
    log=Path(prepared['log']);log.parent.mkdir(parents=True,exist_ok=True)
    if log.exists():raise ValueError('fresh_log_required_preserve_existing_native_evidence')
    child=subprocess.Popen(prepared['launch_argv'],cwd=p.GAME/'dota',
        creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    observed=p.clients();rows=observed if isinstance(observed,list) else [observed]
    identity=next((x for x in rows if x and x['pid']==child.pid),None)
    if not identity:raise ValueError('owned_c2s_process_identity_not_observed')
    result=dict(status='ISOLATED_C2S_NATIVE_PROBE_STARTED',**identity,
        argv=prepared['launch_argv'],external_lab=str(C2S_GAME),mount=str(MOUNT),
        workshop_install_written=False,production_gameplay_acceptance=False,transactions=0)
    p.write_new(receipt,(json.dumps(result,indent=2)+'\n').encode());return result
def close_c2s():
    prior=p.STORE
    try:
        p.STORE=C2S_STORE
        return p.close()
    finally:p.STORE=prior
def capture_c2s():
    import re
    if p.clients():raise ValueError('native_log_must_be_closed')
    prepared=json.loads((C2S_STORE/'prepared.json').read_bytes())
    raw=Path(prepared['log']).read_bytes()
    observed=re.findall(r'RECEIVED value_ascii_bytes=(\d+) source_index=(\d+) entity_is_actual_player=(true|false) engine_player_id_matches=(true|false) injected_player_id_matches=(true|false)',raw.decode('utf-8',errors='replace'))
    if not observed:raise ValueError('actual_panorama_send_required')
    p.write_new(C2S_STORE/'engine.log',raw)
    result=dict(status='REAL_C2S_ACTOR_OBSERVED_TOOLS_ONLY',source_log_sha256=p.sha(raw),
        source_log_path_was_reused=(C2S_STORE.name=='run05'),
        prior_failed_run04_log_overwritten=(C2S_STORE.name=='run05'),
        samples=[dict(value_ascii_bytes=int(n),source_index=int(source),entity_is_actual_player=a=='true',
            engine_player_id_matches=b=='true',injected_player_id_matches=c=='true')for n,source,a,b,c in observed],
        all_actor_checks_passed=all(a==b==c=='true'for _,_,a,b,c in observed),
        native_C2S_bytes_measured=False,ordinary_production_acceptance=False,transactions=0,
        workshop_install_written=False)
    p.write_new(C2S_STORE/'native_actor_proof.json',(json.dumps(result,indent=2)+'\n').encode());return result
def retire_c2s_mounts():
    verify_c2s()
    if p.clients():raise ValueError('client_still_running_preserve_mounts')
    # Verify both links and both exact external targets before touching either.
    for link,target in ((MOUNT,C2S_GAME),(CONTENT_MOUNT,C2S_CONTENT)):
        if not link.is_junction() or link.resolve()!=target.resolve():raise ValueError('exact_owned_junction_required')
    for link in (MOUNT,CONTENT_MOUNT):link.rmdir() # nonrecursive junction removal
    result=dict(status='ISOLATED_C2S_MOUNTS_RETIRED_FILES_PRESERVED',external_lab=str(C2S_GAME),transactions=0)
    p.write_new(C2S_STORE/'mounts_retired.json',(json.dumps(result,indent=2)+'\n').encode());return result
def game_c2s_namespace():
    global C2S_STORE,C2S_GAME,C2S_CONTENT,C2S_LUA
    C2S_STORE=p.STORE.parent/'run05';C2S_GAME=C2S_STORE/'addon';C2S_CONTENT=C2S_STORE/'content'
    bootstrap='''    GameRules:SetCustomGameSetupTimeout(1)
    GameRules:EnableCustomGameSetupAutoLaunch(true)
    GameRules:SetCustomGameSetupAutoLaunchDelay(0)
    GameRules:SetHeroSelectionTime(0)
    GameRules:SetStrategyTime(0)
    GameRules:SetShowcaseTime(0)
    GameRules:SetPreGameTime(0)
    GameRules:GetGameModeEntity():SetCustomGameForceHero("npc_dota_hero_axe")
'''
    C2S_LUA=C2S_LUA.replace('    local received,announced=false,false',bootstrap+'    local received,announced=false,false',1)
def measured_c2s_namespace():
    global C2S_STORE,C2S_GAME,C2S_CONTENT,C2S_LUA,C2S_JS,C2S_FILES
    game_c2s_namespace()
    C2S_STORE=p.STORE.parent/'run06';C2S_GAME=C2S_STORE/'addon';C2S_CONTENT=C2S_STORE/'content'
    C2S_LUA=C2S_LUA.replace('if received then print("[N50_C2S_PROBE] DUPLICATE_REFUSED");return end','',1)
    C2S_LUA=C2S_LUA.replace('or #payload.d~=24','or not ({[0]=true,[1]=true,[8]=true,[16]=true,[24]=true,[32]=true})[#payload.d]',1)
    C2S_LUA=C2S_LUA.replace('or payload.d~=string.rep("A",24)','or payload.d~=string.rep("A",#payload.d)',1)
    C2S_LUA=C2S_LUA.replace('RECEIVED value_ascii_bytes=24 source_index=', 'RECEIVED value_ascii_bytes="..#payload.d.." source_index=',1)
    C2S_JS=C2S_JS.replace('GameEvents.SendCustomGameEventToServer("cw",{d:"A".repeat(24)});',
        '[0,1,8,16,24,32].forEach(function(n){GameEvents.SendCustomGameEventToServer("cw",{d:"A".repeat(n)});});',1)
    C2S_FILES={'panorama/layout/custom_game/custom_ui_manifest.xml':C2S_MANIFEST.encode(),
        'panorama/layout/custom_game/n50_c2s_probe.xml':C2S_XML.encode(),
        'panorama/scripts/custom_game/n50_c2s_probe.js':C2S_JS.encode()}
def launch():
    if p.clients():raise ValueError('existing_client_preserved')
    if STORE.exists() or MOUNT.exists():raise ValueError('fresh_external_lab_and_mount_required')
    if MOUNT.parent.resolve()!=ROOT.parent.resolve():raise ValueError('exact_addon_mount_parent_required')
    LAB.mkdir(parents=True)
    p.write_new(LAB/'addoninfo.txt',b'"AddonInfo"\n{\n "addon_title" "Native packet probe"\n "addon_type" "1"\n "maps" "template_map"\n "max_players" "1"\n}\n')
    p.write_new(LAB/'scripts/vscripts/addon_game_mode.lua',SOURCE.encode())
    source=ROOT/'maps/template_map.vpk';target=LAB/'maps/template_map.vpk'
    raw=source.read_bytes();p.write_new(target,raw)
    subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',
        "New-Item -ItemType Junction -Path '"+str(MOUNT)+"' -Target '"+str(LAB)+"' | Out-Null"],check=True)
    log=ROOT/'output/network50_native_probe_20261103/run03/engine.log';log.parent.mkdir(parents=True)
    args=['-steam','-tools','-noassetbrowser','-dev','-addon',MOUNT.name,'-novid','-console','-vconsole',
        '-vconport','29068','-condebug','-con_logfile',str(log),'+sv_cheats','1',
        '+net_showmsg','CUserMsg_CustomGameEvent','+net_restrict_showmsg_socket','client',
        '+dota_launch_custom_game',MOUNT.name,'template_map']
    child=subprocess.Popen([str(p.EXE),*args],cwd=p.GAME/'dota',creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    observed=p.clients();rows=observed if isinstance(observed,list) else [observed]
    identity=next((x for x in rows if x and x['pid']==child.pid),None)
    if not identity:raise ValueError('owned_lab_process_identity_not_observed')
    report=dict(status='ISOLATED_NATIVE_SERIALIZER_LAB_STARTED',**identity,argv=args,external_lab=str(LAB),mount=str(MOUNT),
        normal_map_sha256=p.sha(raw),probe_script_sha256=p.sha(SOURCE.encode()),workshop_install_written=False,transactions=0,
        sdk_initialized=False,production_gameplay_acceptance=False)
    p.write_new(STORE/'process.json',(json.dumps(report,indent=2)+'\n').encode());return report
if __name__=='__main__':
    actions={'launch':launch,'plan-c2s':c2s_plan,'prepare-c2s':prepare_c2s,'verify-c2s':verify_c2s,
        'launch-c2s':launch_c2s,'close-c2s':close_c2s,'retire-c2s':retire_c2s_mounts,'capture-c2s':capture_c2s}
    action=sys.argv[1] if len(sys.argv)==2 else ''
    if action.endswith('-game'):
        game_c2s_namespace();action=action[:-5]
    elif action.endswith('-measured'):
        measured_c2s_namespace();action=action[:-9]
    if action not in actions:raise SystemExit('explicit known isolated probe action required')
    print(json.dumps(actions[action](),ensure_ascii=True))
