package.path = 'scripts/vscripts/?.lua;' .. package.path
local probe = require('tests/manual_wave_low_model_probe')
assert(_G.SURVIVAL_WAVE_LOW_MODEL_PROBE == nil and not probe.preview().enabled and not probe.enable().enabled)
local mode, session, time, tasks = {}, 'low_model_test', 0, {}
IsServer = function() return true end; IsInToolsMode = function() return true end
GetMapName = function() return 'template_map' end
GameRules = {GetGameModeEntity = function() return mode end, GetGameTime = function() return time end}
Vector = function(x,y,z) return {x=x,y=y,z=z} end
DOTA_TEAM_BADGUYS = 3; DOTA_TEAM_NEUTRALS = 4; DOTA_UNIT_ORDER_MOVE_TO_POSITION = 1; ACT_DOTA_ATTACK = 1500
package.loaded['systems/match_setup_service'] = {get_mode = function() return 'standard' end, get_session_id = function() return session end}
package.loaded['systems/player_context_service'] = {owner_player_id = function(u) return u.survival_player_id end, is_defeated = function() return false end}
package.loaded['core/logger'] = {info=function() end,warn=function() end}
package.loaded['core/scheduler'] = {after=function(_,cb,id) tasks[id]=cb end,cancel=function(id) tasks[id]=nil end}
local bus, events = require('core/event_bus'), require('core/events')
local guard = {mode=mode}; _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = guard
_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF = {mode=mode,guard=guard,status='ready',ids={0,1,2,3}}
local status, callback, async_calls, native_creates, serial, removed = 'not_requested', nil, 0, 0, 0, {}
PrecacheUnitByNameAsync = function(name,cb)
    assert(name=='asset_proxy_wave_vis_ogre_frostmage'); async_calls=async_calls+1; callback=cb
end
package.loaded['systems/asset_preload_service'] = {
    queue_resources = function(resources)
        assert(#resources==1 and resources[1].async_unit_name=='asset_proxy_wave_vis_ogre_frostmage')
        if status~='ready' and status~='loading' then status='loading';PrecacheUnitByNameAsync(resources[1].async_unit_name,function() status='ready' end) end
        return true
    end,
    resource_status = function(kind,path) assert(kind=='model' and path:find('n_creep_ogre_med',1,true));return status end,
}
local function unit(class)
    serial=serial+1
    local u={index=serial,class=class or 'npc_dota_creature',name='npc_survival_wave_named_dwarf_white_rifle',
        model='original_model',health=1000,max=1000,BAT=.714,speed=400,hull=32,cap=2,team=3,
        survival_is_wave_monster=true,survival_monster_role='normal',survival_player_id=0,
        survival_attack_speed=1.4,survival_wave_native_attack_cap=true,target={index=900}}
    u.ai={ai_state='attack',wall_entindex=900,wall_target_player_id=0,IsNull=function() return false end,GetParent=function() return u end}
    u.attack_cap={}
    function u:IsNull() return self.removed==true end;function u:IsAlive() return self.health>0 end
    function u:entindex() return self.index end;function u:GetUnitName() return self.name end
    function u:GetModelName() return self.model end;function u:SetModel(path) self.model=path;if self.bad_model_health then self.health=999 end end
    function u:SetOriginalModel(path) self.original_model=path end;function u:SetModelScale(value) self.scale=value end
    function u:GetHealth() return self.health end;function u:GetMaxHealth() return self.max end
    function u:GetBaseAttackTime(flag) assert(flag==false,'GetBaseAttackTime called with 1 arguments - expected 2');return self.BAT end
    function u:GetAttackSpeed(flag) assert(flag==false,'GetAttackSpeed called with 1 arguments - expected 2');return 1 end
    function u:GetSecondsPerAttack(flag) assert(flag==false,'GetSecondsPerAttack called with 1 arguments - expected 2');return self.BAT end
    function u:GetAttacksPerSecond(flag) assert(flag==false,'GetAttacksPerSecond called with 1 arguments - expected 2');return 1/self.BAT end
    function u:GetAttackAnimationPoint(flag) assert(flag==false);return .3 end
    function u:GetAcquisitionRange(...) if select('#',...)>0 then error('GetAcquisitionRange called with 2 arguments - expected 1') end;return 700 end
    function u:GetBaseMoveSpeed() return self.speed end
    function u:GetHullRadius() return self.hull end;function u:GetAttackCapability() return self.cap end
    function u:GetAttackTarget() return self.target end;function u:GetTeamNumber() return self.team end
    function u:GetClassname() return self.class end;function u:GetPlayerOwnerID() return -1 end
    function u:IsRealHero() return self.hero==true end;function u:IsHero() return self.hero==true end
    function u:IsIllusion() return false end
    function u:FindModifierByName(name) return name=='modifier_enemy_wall_ai' and self.ai or (name=='modifier_debug_attack_cap' and self.attack_cap or nil) end
    function u:SetOwner(v) self.owner=v end;function u:SetParent(v) self.parent=v end;function u:FollowEntity(v) self.parent=v end
    function u:SetSolid() end;function u:SetSkin(value) self.skin=value end
    function u:ResetSequenceInfo() end;function u:SetPlaybackRate(value) self.playback=value end
    function u:SetBaseDamageMin(value) assert(self.survival_visual_only and value==0) end
    function u:SetBaseDamageMax(value) assert(self.survival_visual_only and value==0) end
    function u:SetBaseMoveSpeed(value) assert(self.survival_visual_only);self.speed=value end
    function u:SetIdleAcquire(value) assert(self.survival_visual_only and value==false) end
    function u:SetAcquisitionRange(value) assert(self.survival_visual_only and value==0) end
    function u:RemoveModifierByName(name) assert(self.survival_visual_only and name=='modifier_single_health_bar') end
    function u:AddNewModifier(_,_,name) assert(self.survival_visual_only and name=='modifier_invulnerable');return {} end
    function u:StartGestureWithPlaybackRate(activity,rate) assert(self.survival_visual_only and activity==ACT_DOTA_ATTACK and rate==1);self.gesture=true end
    return u
end
IsValidEntity=function(u) return not u.removed end
UTIL_Remove=function(u) u.removed=true;removed[#removed+1]=u end
SpawnEntityFromTableSynchronous=function(class,data) local u=unit(class);u.model=data.model;return u end
local appearance=require('visual/model_appearance_service')
local outfit={asset_id='original_outfit',components={{component_id='weapon',model_path='weapon',attach_mode='bone_merge'},{component_id='head',model_path='head',attach_mode='bone_merge'}}}
local function source() local u=unit();assert(appearance.Apply(u,outfit,{fresh_unit=true}));return u end
CreateUnitByName=function(name,position,_,_,_,team)
    assert(status=='ready','Never create before callback/readback');native_creates=native_creates+1
    local u=unit();u.team=team;u.survival_is_wave_monster=nil;u.survival_player_id=nil;return u
end
local orders={};ExecuteOrderFromTable=function(order) orders[#orders+1]=order end
Entities={FindAllByClassname=function() error('No implicit existing scan') end}
local started=probe.preview({enabled=true,position={x=100,y=100,z=384}})
assert(started.preview_status=='loading' and async_calls==1 and native_creates==0)
assert(not pcall(probe.enable,{enabled=true,validated_preview=true}),'Cannot enable before preview approval')
assert(not pcall(probe.validate_preview,{approved=true,demo_entindex=1,walk_seen=true,attack_gesture_seen=true}))
callback();tasks.wave_low_model_preview_ready()
local ready=probe.snapshot();assert(ready.preview_status=='ready' and ready.model_readback_confirmed and native_creates==1)
local demo=_G.SURVIVAL_WAVE_LOW_MODEL_PROBE.demo
probe.demo_walk({x=140,y=100,z=384});probe.demo_attack_gesture()
assert(#orders==1 and orders[1].UnitIndex==demo:entindex() and demo.gesture)
assert(not pcall(probe.validate_preview,{approved=true,demo_entindex=demo:entindex()+1,walk_seen=true,attack_gesture_seen=true}))
probe.validate_preview({approved=true,demo_entindex=demo:entindex(),walk_seen=true,attack_gesture_seen=true})
probe.enable({enabled=true,validated_preview=true})
local u=source();local target, ai, cap=u.target,u.ai,u.attack_cap
local boss,leader,hero,challenge=source(),source(),source(),source()
boss.survival_is_boss=true;leader.survival_monster_role='wave_leader';hero.hero=true;challenge.survival_is_challenge_monster=true
Entities.FindAllByClassname=function(_,class) assert(class=='npc_dota_creature');return {u,boss,leader,hero,challenge,demo} end
local existing=probe.apply_existing()
assert(existing.complete and existing.modified_delta==1 and probe.snapshot().retired_parts==2)
assert(u:GetModelName():find('n_creep_ogre_med',1,true) and u.scale==.88 and appearance._count_for_test(u)==0)
assert(u.target==target and u.ai==ai and u.attack_cap==cap and u.health==1000 and u.max==1000
    and u.BAT==.714 and u.speed==400 and u.hull==32 and u.cap==2 and u.survival_attack_speed==1.4)
for _,v in ipairs({boss,leader,hero,challenge}) do assert(v.model=='original_model' and appearance._count_for_test(v)==2 and not v.removed) end
assert(probe.apply_existing().modified_delta==0,'Duplicate scans cannot rebuild the same model')
local newborn=source();bus.emit(events.MONSTER_SPAWNED,{unit=newborn,monster_source='wave',member_role='normal',player_id=0})
assert(probe.snapshot().modified==2 and not newborn.removed)
local partial=source();partial.bad_model_health=true
bus.emit(events.MONSTER_SPAWNED,{unit=partial,monster_source='wave',member_role='normal',player_id=0})
assert(not probe.snapshot().enabled and probe.snapshot().failed==1 and partial.health==999 and not partial.removed,
    'Unexpected combat change aborts without fake health rollback or source-unit removal')
probe.stop('sample_done');assert(demo.removed and not u.removed and not newborn.removed and not partial.removed)
local before=native_creates;status='not_requested';probe.preview({enabled=true,position={x=100,y=100,z=384}})
local late=tasks.wave_low_model_preview_ready
probe.stop('cancel_loading');callback();late()
assert(native_creates==before,'Late asynchronous callback cannot create after stop')
local function approved_candidate()
    status='ready';probe.preview({enabled=true,position={x=100,y=100,z=384}})
    local d=_G.SURVIVAL_WAVE_LOW_MODEL_PROBE.demo
    probe.validate_preview({approved=true,demo_entindex=d:entindex(),walk_seen=true,attack_gesture_seen=true})
    probe.enable({enabled=true,validated_preview=true});return d
end
local retry_demo=approved_candidate()
local unreadable=source();local original_bat=unreadable.GetBaseAttackTime;local attempts=0
unreadable.GetBaseAttackTime=function(_,flag) attempts=attempts+1;assert(flag==false);error('native invalid handle') end
Entities.FindAllByClassname=function() return {unreadable} end
local refusal=probe.apply_existing()
local saved=_G.SURVIVAL_WAVE_LOW_MODEL_PROBE
assert(refusal.modified_delta==0 and saved.visual_write_attempts==0 and not saved.seen[unreadable]
    and attempts==1 and unreadable.model=='original_model','Non-arity failure cannot retry noarg, mutate visuals, or poison seen')
assert(not pcall(probe.retry_read_only_failure,{approved_existing_demo=true,demo_entindex=retry_demo:entindex()+1}))
unreadable.GetBaseAttackTime=original_bat
-- Tools module reload reuses exact isolated state/demo, not an engine class.
package.loaded['tests/manual_wave_low_model_probe']=nil;probe=require('tests/manual_wave_low_model_probe')
probe.retry_read_only_failure({approved_existing_demo=true,demo_entindex=retry_demo:entindex()})
assert(_G.SURVIVAL_WAVE_LOW_MODEL_PROBE==saved and saved.failed==1 and not retry_demo.removed)
probe.enable({enabled=true,validated_preview=true})
local retried=probe.apply_existing()
assert(retried.modified_delta==1 and retried.failed==1 and retried.failed_delta==0 and saved.pre_read_retry_count==1)
assert(saved.samples[1].native_base_BAT_read and saved.samples[1].BAT_before==.714
    and saved.samples[1].attacks_per_second_before==1/.714 and saved.samples[1].attack_animation_point_before==.3
    and saved.samples[1].acquisition_range_before==700)
assert(not pcall(probe.retry_read_only_failure,{approved_existing_demo=true,demo_entindex=retry_demo:entindex()}),
    'A source visual write must forbid zero-write recovery')
probe.stop('retry_test_done')
approved_candidate()
local inconsistent=source();inconsistent.GetAttacksPerSecond=function(_,flag) assert(flag==false);return 3 end
Entities.FindAllByClassname=function() return {inconsistent} end
probe.apply_existing()
assert(probe.snapshot().stop_reason=='native_cadence_reciprocity_failed'
    and _G.SURVIVAL_WAVE_LOW_MODEL_PROBE.visual_write_attempts==0 and inconsistent.model=='original_model',
    'Inconsistent genuine cadence cannot be replaced by configured/base BAT')
probe.stop('inconsistent_test_done')
approved_candidate()
local animation=source();local animation_model=animation.SetModel
animation.SetModel=function(self,path) animation_model(self,path);self.changed_animation=true end
animation.GetAttackAnimationPoint=function(self,flag) assert(flag==false);return self.changed_animation and .5 or .3 end
Entities.FindAllByClassname=function() return {animation} end
probe.apply_existing()
assert(not probe.snapshot().enabled and probe.snapshot().samples[1].changed_combat_field=='attack_animation_point'
    and not animation.removed,'Animation-point change aborts without source deletion or fake rollback')
probe.stop('animation_test_done')
print('WAVE_LOW_MODEL_PROBE_PASS: inert; async/readback/demo approval; shared eligibility; real appearance; handle/combat/AI preserved; explicit false BAT/AS/SPA/APS; arity-only legacy fallback; native cadence reciprocity; animation/acquisition checks; pre-read seen and exact zero-write retry; historical failure retained; source failure abort; owned demo cleanup; late callback guard')
