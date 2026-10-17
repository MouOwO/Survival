package.path='scripts/vscripts/?.lua;'..package.path
local probe=require('tests/manual_native_ranged_visual_probe')
assert(_G.SURVIVAL_NATIVE_RANGED_VISUAL_PROBE==nil and not probe.enable().enabled and not probe.adopt_root_preview().enabled and not probe.retry_visible_target().enabled)
local mode,session,time,tasks={},'native_ranged_test',0,{}
IsServer=function() return true end;IsInToolsMode=function() return true end
GetMapName=function() return 'template_map' end
GameRules={GetGameModeEntity=function() return mode end,GetGameTime=function() return time end}
Vector=function(x,y,z) return {x=x,y=y,z=z} end
class=function(t) return t end
DOTA_TEAM_BADGUYS=3;DOTA_TEAM_GOODGUYS=2;DOTA_UNIT_CAP_RANGED_ATTACK=2;DOTA_UNIT_CAP_NO_ATTACK=0
DOTA_UNIT_ORDER_ATTACK_TARGET=4;LUA_MODIFIER_MOTION_NONE=0
MODIFIER_EVENT_ON_ATTACK_RECORD=1;MODIFIER_EVENT_ON_ATTACK=2;MODIFIER_EVENT_ON_ATTACK_LANDED=3;MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY=4
package.loaded['systems/match_setup_service']={get_mode=function() return 'standard' end,get_session_id=function() return session end}
package.loaded['systems/player_context_service']={owner_player_id=function(u) return u.survival_player_id end,is_defeated=function() return false end}
package.loaded['core/logger']={info=function() end,warn=function() end}
package.loaded['core/scheduler']={after=function(_,cb,id) tasks[id]=cb end,cancel=function(id) tasks[id]=nil end}
local bus,events=require('core/event_bus'),require('core/events')
local guard={mode=mode};_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=guard
_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF={mode=mode,guard=guard,status='ready',ids={0,1,2,3}}
local official='models/creeps/lane_creeps/creep_bad_ranged/lane_dire_ranged.vmdl'
local observer_class=require('tests/modifier_native_ranged_preview_observer')
assert(#observer_class:DeclareFunctions()==4,'Declaration is stable even before creation')
local serial,created,links,orders,removed=0,0,0,{},{}
local function unit(kind)
    serial=serial+1
    local u={index=serial,class=kind or 'npc_dota_creature',name='npc_survival_wave_named_dwarf_white_rifle',
        model='original_model',health=1000,max=1000,BAT=.714,speed=400,hull=32,cap=2,team=3,
        survival_is_wave_monster=true,survival_monster_role='normal',survival_player_id=0,
        survival_attack_speed=1.4,survival_wave_native_attack_cap=true,target={index=900}}
    u.ai={ai_state='attack',wall_entindex=900,wall_target_player_id=0,IsNull=function() return false end,GetParent=function() return u end}
    u.attack_cap={}
    function u:IsNull() return self.removed==true end;function u:IsAlive() return self.health>0 end
    function u:entindex() return self.index end;function u:GetUnitName() return self.name end
    function u:GetModelName() return self.model end
    function u:SetModel(path) self.model=path;if self.bad_model_health then self.health=999 end end
    function u:SetOriginalModel(path) self.original_model=path end;function u:SetModelScale(v) self.scale=v end
    function u:GetHealth() return self.health end;function u:GetMaxHealth() return self.max end
    function u:GetBaseAttackTime(flag) assert(flag==false,'GetBaseAttackTime called with 1 arguments - expected 2');return self.BAT end
    function u:GetAttackSpeed(flag) assert(flag==false,'GetAttackSpeed called with 1 arguments - expected 2');return 1 end
    function u:GetSecondsPerAttack(flag) assert(flag==false,'GetSecondsPerAttack called with 1 arguments - expected 2');return self.BAT end
    function u:GetAttacksPerSecond(flag) assert(flag==false,'GetAttacksPerSecond called with 1 arguments - expected 2');return 1/self.BAT end
    function u:GetAttackAnimationPoint(flag) assert(flag==false);return .3 end
    function u:GetAcquisitionRange(...) if select('#',...)>0 then error('GetAcquisitionRange called with 2 arguments - expected 1') end;return 700 end
    function u:GetBaseMoveSpeed() return self.speed end;function u:GetHullRadius() return self.hull end
    function u:GetAttackCapability() return self.cap end;function u:GetAttackTarget() return self.target end
    function u:Script_GetAttackRange() return 600 end
    function u:GetTeamNumber() return self.team end;function u:GetClassname() return self.class end
    function u:GetPlayerOwnerID() return -1 end;function u:IsRealHero() return self.hero==true end;function u:IsHero() return self.hero==true end
    function u:IsIllusion() return false end
    function u:FindModifierByName(name) return name=='modifier_enemy_wall_ai' and self.ai or (name=='modifier_debug_attack_cap' and self.attack_cap or nil) end
    function u:ScriptLookupAttachment(name) assert(name=='attach_attack1');if self.missing_attachment then return 0 end;return self.model==official and 1 or 2 end
    function u:CanEntityBeSeenByMyTeam(target) return self.visible~=false and target.hidden~=true end
    function u:SetOwner(v) self.owner=v end;function u:SetParent(v) self.parent=v end;function u:FollowEntity(v) self.parent=v end
    function u:SetSolid() end;function u:SetSkin(v) self.skin=v end;function u:ResetSequenceInfo() end;function u:SetPlaybackRate(v) self.playback=v end
    function u:SetBaseDamageMin(v) assert(self.survival_visual_only and v==0);self.min_damage=v end
    function u:SetBaseDamageMax(v) assert(self.survival_visual_only and v==0);self.max_damage=v end
    function u:SetBaseMaxHealth(v) assert(self.survival_visual_only);self.base_max=v end
    function u:SetMaxHealth(v) assert(self.survival_visual_only);self.max=v end
    function u:SetHealth(v) assert(self.survival_visual_only);self.health=v end
    function u:SetAttackCapability(v) assert(self.survival_visual_only);self.cap=v end
    function u:SetIdleAcquire(v) assert(self.survival_visual_only and v==false) end
    function u:SetAcquisitionRange(v) assert(self.survival_visual_only and v==0) end
    function u:RemoveModifierByName(name) assert(self.survival_visual_only and name=='modifier_single_health_bar') end
    function u:IsInvulnerable() return self.invulnerable==true end
    function u:Stop() self.stopped=(self.stopped or 0)+1 end
    function u:AddNewModifier(_,_,name)
        assert(self.survival_visual_only and name=='modifier_native_ranged_preview_observer','No invulnerable modifier on target')
        if self.fail_observer then return nil end
        local m=setmetatable({parent=self},{__index=observer_class})
        function m:IsNull() return self.destroyed==true end;function m:GetParent() return self.parent end
        function m:Destroy() if self.fail_destroy then error('native destruction failed') end;self.destroyed=true end
        self.observer=m;return m
    end
    return u
end
IsValidEntity=function(u) return not u.removed end
UTIL_Remove=function(u) u.removed=true;removed[#removed+1]=u end
SpawnEntityFromTableSynchronous=function(kind,data) local u=unit(kind);u.model=data.model;return u end
CreateUnitByName=function(name,_,_,_,_,team)
    assert(name=='npc_survival_wave_monster' and team==DOTA_TEAM_GOODGUYS)
    created=created+1;local u=unit();u.name=name;u.team=team;u.ai=nil;u.attack_cap=nil
    u.survival_is_wave_monster=nil;u.survival_monster_role=nil;u.survival_player_id=nil
    return u
end
LinkLuaModifier=function(name,path,motion) assert(name=='modifier_native_ranged_preview_observer' and path=='tests/modifier_native_ranged_preview_observer' and motion==0);links=links+1 end
ExecuteOrderFromTable=function(o) orders[#orders+1]=o end
Entities={FindAllByClassname=function() error('No implicit scan') end}
local appearance=require('visual/model_appearance_service')
local outfit={asset_id='original_outfit',components={{component_id='weapon',model_path='weapon',attach_mode='bone_merge'},{component_id='head',model_path='head',attach_mode='bone_merge'}}}
local function source() local u=unit();assert(appearance.Apply(u,outfit,{fresh_unit=true}));return u end
local function root_demo()
    local u=unit();u.name='npc_dota_creep_badguys_ranged';u.model=official;u.invulnerable=true
    u.survival_is_wave_monster=nil;u.survival_player_id=nil;u.survival_monster_role=nil
    local root={unit=u,world=mode,guard=guard,token={}};u.survival_ranged_native_preview_token=root.token
    _G.SURVIVAL_RANGED_NATIVE_PREVIEW=root;return u,root
end
local function adopt()
    local d=root_demo();probe.adopt_root_preview({enabled=true,demo_entindex=d.index});return d
end
local function shot_test(d)
    local before=#orders
    probe.start_shot_test({target_position={x=120,y=100,z=384},timeout_seconds=8})
    local s=_G.SURVIVAL_NATIVE_RANGED_VISUAL_PROBE
    assert(s.target.health==1000000 and not s.target.invulnerable and s.demo.min_damage==0 and s.demo.max_damage==0)
    assert(#orders==before and not s.order_sent,'Creation frame cannot issue native attack order')
    time=time+.1;local wait=tasks.native_ranged_preview_visibility_check;tasks.native_ranged_preview_visibility_check=nil;wait()
    assert(orders[#orders].UnitIndex==d.index and orders[#orders].TargetIndex==s.target.index and orders[#orders].OrderType==4)
    return s,s.observer,s.target
end
local function three(m,d,t)
    for r=1,3 do local p={attacker=d,target=t,record=r};m:OnAttackRecord(p);m:OnAttack(p);m:OnAttackLanded(p);m:OnAttackRecordDestroy(p) end
end
local function candidate()
    local d=adopt();local _,m,t=shot_test(d);three(m,d,t)
    probe.validate_preview({approved=true,demo_entindex=d.index});probe.enable({enabled=true,validated_preview=true})
    return d
end
local d,r=root_demo();r.unit.model='not_native_model'
assert(not pcall(probe.adopt_root_preview,{enabled=true,demo_entindex=d.index}) and _G.SURVIVAL_NATIVE_RANGED_VISUAL_PROBE==nil)
d.model=official;d.missing_attachment=true;assert(not pcall(probe.adopt_root_preview,{enabled=true,demo_entindex=d.index}))
d.missing_attachment=nil;assert(not pcall(probe.adopt_root_preview,{enabled=true,demo_entindex=d.index+1}))
d.name='npc_other_creep';assert(not pcall(probe.adopt_root_preview,{enabled=true,demo_entindex=d.index}));d.name='npc_dota_creep_badguys_ranged'
r.world={};assert(not pcall(probe.adopt_root_preview,{enabled=true,demo_entindex=d.index}));r.world=mode
d.survival_ranged_native_preview_token={};assert(not pcall(probe.adopt_root_preview,{enabled=true,demo_entindex=d.index}))
d=adopt();assert(not pcall(probe.validate_preview,{approved=true,demo_entindex=d.index}),'Attachment/gesture alone cannot pass')
local s,m,t=shot_test(d)
m:OnAttack({attacker=d,target=t,record=99});m:OnAttackRecord({attacker=unit(),target=t,record=100})
m:OnAttackRecord({attacker=d,target=unit(),record=101})
assert(s.unknown_records==1 and s.foreign_events==2 and s.launched==0)
for rec=1,2 do local p={attacker=d,target=t,record=rec};m:OnAttackRecord(p);m:OnAttack(p);m:OnAttack(p);m:OnAttackLanded(p);m:OnAttackLanded(p) end
assert(s.launched==2 and s.landed==2 and s.observing and not s.validated)
local p={attacker=d,target=t,record=3};m:OnAttackRecord(p);m:OnAttack(p);m:OnAttackRecordDestroy(p);m:OnAttackLanded(p)
assert(s.shots_passed and not s.observing and m.destroyed and not tasks.native_ranged_preview_watchdog
    and not tasks.native_ranged_preview_stop_after_launch,'Real observed third landing detaches native fanout')
m:OnAttack(p);assert(s.launched==3,'Late native callbacks cannot increment after observation')
probe.validate_preview({approved=true,demo_entindex=d.index});probe.enable({enabled=true,validated_preview=true})
local u=source();local target,ai,cap=u.target,u.ai,u.attack_cap
local boss,leader,hero,challenge,melee,wrong=source(),source(),source(),source(),source(),source()
boss.survival_is_boss=true;leader.survival_monster_role='wave_leader';hero.hero=true;challenge.survival_is_challenge_monster=true;melee.cap=1
wrong.survival_player_id=2;wrong.ai.wall_target_player_id=1
Entities.FindAllByClassname=function(_,kind) assert(kind=='npc_dota_creature');return {u,boss,leader,hero,challenge,melee,wrong,d,t} end
local scan=probe.apply_existing()
assert(scan.complete and scan.modified_delta==1 and u.model==official and u.scale==1 and appearance._count_for_test(u)==0)
assert(u.target==target and u.ai==ai and u.attack_cap==cap and u.health==1000 and u.max==1000
    and u.BAT==.714 and u.speed==400 and u.hull==32 and u.cap==2 and u.survival_attack_speed==1.4)
assert(s.samples[1].BAT_before==.714 and s.samples[1].BAT_after==.714 and s.samples[1].acquisition_after==700
    and s.samples[1].attachment_index==1 and s.retired_parts==2)
for _,v in ipairs({boss,leader,hero,challenge,melee,wrong}) do assert(v.model=='original_model' and appearance._count_for_test(v)==2 and not v.removed) end
assert(probe.apply_existing().modified_delta==0 and s.modified==1)
local newborn=source();bus.emit(events.MONSTER_SPAWNED,{unit=newborn,monster_source='wave',member_role='normal',player_id=0})
assert(s.modified==2 and newborn.model==official and s.observer==nil)
probe.stop('candidate_done');assert(d.removed and t.removed and not u.removed and not newborn.removed)
d=adopt();s,m,t=shot_test(d);local timeout=tasks.native_ranged_preview_watchdog;timeout()
assert(m.destroyed and not s.shots_passed and s.observation_reason=='shot_test_timeout' and not pcall(probe.validate_preview,{approved=true,demo_entindex=d.index}))
local timed_out_demo,timed_out_target,created_before=d,t,created
-- Retain the old module's actual timeout state across an exact Tools reload.
s.observation_history=nil;s.observation_attempt=nil;s.order_sent=nil
package.loaded['tests/manual_native_ranged_visual_probe']=nil;probe=require('tests/manual_native_ranged_visual_probe')
local old_history_reason=s.observation_reason;d.visible=false
assert(not pcall(probe.retry_visible_target,{enabled=true}) and s.observation_reason==old_history_reason and s.observer==nil)
d.visible=true;local token=t.survival_native_ranged_target_token;t.survival_native_ranged_target_token={}
assert(not pcall(probe.retry_visible_target,{enabled=true}));t.survival_native_ranged_target_token=token
local before_retry=#orders
probe.retry_visible_target({enabled=true,timeout_seconds=8})
local retry_observer=s.observer;local retry_visibility=tasks.native_ranged_preview_visibility_check
assert(#orders==before_retry and d==timed_out_demo and t==timed_out_target and created==created_before
    and s.observation_attempt==2 and s.observation_history[1].reason=='shot_test_timeout'
    and s.observation_history[1].order_sent=='unknown_legacy_v1')
timeout();assert(s.observing,'An old captured-attempt watchdog cannot end the new retry')
time=time+.1;retry_visibility();retry_visibility()
assert(#orders==before_retry+1 and s.order_sent,'Visible retry issues exactly one delayed native command')
three(retry_observer,d,t);assert(s.shots_passed and s.observation_history[1].reason=='shot_test_timeout'
    and s.observation_history[2].reason=='three_launches_and_lands' and s.observer==nil)
assert(not pcall(probe.retry_visible_target,{enabled=true}),'Completed shots are never retryable')
probe.stop('timeout_done')
d=adopt();d.visible=false;local invisible_before=#orders
probe.start_shot_test({target_position={x=100,y=100,z=384}});s=_G.SURVIVAL_NATIVE_RANGED_VISUAL_PROBE;m=s.observer;t=s.target
for _=1,12 do
    local cb=tasks.native_ranged_preview_visibility_check
    if cb then tasks.native_ranged_preview_visibility_check=nil;time=time+.1;cb() end
end
assert(#orders==invisible_before and s.observing and s.visibility_wait_exhausted and not s.order_sent,
    'Invisible target cannot receive an order; first wait is bounded to one second')
tasks.native_ranged_preview_watchdog();assert(not s.observing and s.observation_reason=='shot_test_timeout')
d.visible=true;probe.retry_visible_target({enabled=true});local delayed=tasks.native_ranged_preview_visibility_check
d.visible=false;time=time+.1;delayed()
assert(#orders==invisible_before and s.observing and s.visibility_wait_exhausted,
    'Retry must recheck actual visibility after delay, not trust the request-time read')
probe.stop('invisible_done');delayed();assert(#orders==invisible_before,'Late callback after stop cannot issue orders')
d=adopt();d.visible=false;probe.start_shot_test({target_position={x=100,y=100,z=384}})
s=_G.SURVIVAL_NATIVE_RANGED_VISUAL_PROBE;m=s.observer;local delayed_scope=tasks.native_ranged_preview_visibility_check
local before_scope=#orders;guard.mode={};time=time+.1;delayed_scope()
assert(#orders==before_scope and not s.observing and m.destroyed and s.observation_reason=='world_preview_or_target_changed')
guard.mode=mode;probe.stop('delayed_scope_done')
d=adopt();d.fail_observer=true;local setup=probe.start_shot_test({target_position={x=100,y=100,z=384}})
assert(setup.observation_reason=='shot_test_setup_failed' and setup.target_removed and not setup.observer_present)
probe.stop('setup_done')
d=adopt();s,m,t=shot_test(d);guard.mode={};m:OnAttackRecord({attacker=d,target=t,record=1})
assert(m.destroyed and not s.shots_passed and s.observation_reason=='world_or_preview_changed')
guard.mode=mode;probe.stop('scope_done')
d=adopt();s,m,t=shot_test(d)
for rec=1,9 do m:OnAttackRecord({attacker=d,target=t,record=rec}) end
assert(s.record_count==8 and m.destroyed and s.observation_reason=='record_limit' and not s.shots_passed,'Native record retention bounded')
probe.stop('record_limit_done')
d=adopt();s,m,t=shot_test(d);m.fail_destroy=true;three(m,d,t)
assert(s.observer==m and not pcall(probe.enable,{enabled=true,validated_preview=true}), 'Failed native detach cannot assert fanout absent')
m.fail_destroy=nil;probe.stop('detach_retry');assert(m.destroyed and t.removed and d.removed)
d=candidate();s=_G.SURVIVAL_NATIVE_RANGED_VISUAL_PROBE
local unread=source();local attempts=0;unread.GetBaseAttackTime=function(_,flag) assert(flag==false);attempts=attempts+1;error('native invalid handle') end
Entities.FindAllByClassname=function() return {unread} end;probe.apply_existing()
assert(s.failed==1 and not s.enabled and not s.seen[unread] and s.visual_write_attempts==0 and attempts==1
    and unread.model=='original_model' and s.subscription==nil,'No arbitrary fallback, pre-read seen poisoning, or silent active hook')
assert(not pcall(probe.enable,{enabled=true,validated_preview=true}),'Failure cannot silently resume')
probe.stop('read_failure')
d=candidate();s=_G.SURVIVAL_NATIVE_RANGED_VISUAL_PROBE
local loss=source();loss.missing_attachment=true
bus.emit(events.MONSTER_SPAWNED,{unit=loss,monster_source='wave',member_role='normal',player_id=0})
assert(s.failed==1 and not s.enabled and s.visual_write_attempts==1 and not loss.removed and loss.health==1000)
probe.stop('attachment_failure')
d=candidate();s=_G.SURVIVAL_NATIVE_RANGED_VISUAL_PROBE
local changed=source();changed.bad_model_health=true
bus.emit(events.MONSTER_SPAWNED,{unit=changed,monster_source='wave',member_role='normal',player_id=0})
assert(s.failed==1 and not s.enabled and changed.health==999 and not changed.removed,'No fake combat rollback/source removal')
probe.stop('combat_failure')
d=candidate();s=_G.SURVIVAL_NATIVE_RANGED_VISUAL_PROBE
local guard_source=source();local original_guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode}
bus.emit(events.MONSTER_SPAWNED,{unit=guard_source,monster_source='wave',member_role='normal',player_id=0})
assert(not s.enabled and s.subscription==nil and guard_source.model=='original_model' and s.visual_write_attempts==0)
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=original_guard;probe.stop('changed_guard')
d=adopt();s,m,t=shot_test(d);t.health=999999;three(m,d,t)
assert(not s.shots_passed,'Attack test with changed real HP cannot pass')
t.health=0;probe.stop('dead_owned_target');assert(t.removed,'Dead owned dummy still retires')
print('NATIVE_RANGED_VISUAL_PROBE_PASS: inert/default-off; exact native root adoption/model/attachment; real callback record/launch/land; no fake completion; bounded observer; delayed actual visibility check; no same-frame order; exact zero-launch timeout retry/history; invisible/late/current-scope safety; attackable zero-damage dummy; original appearance; numeric cadence/range/animation/acquisition/AI/target/handle preservation; ranged-only eligibility; exclusive cleanup')
