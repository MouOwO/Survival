-- Default-off Tools native ranged template. No production cfg/spawn changes.
-- Adopt only an exact root-owned official NPC; path comes from native readback.
-- A bounded real launch+land test replaces gesture-only approval.
local M = {}
local KEY = 'SURVIVAL_NATIVE_RANGED_VISUAL_PROBE'
local ROOT_KEY = 'SURVIVAL_RANGED_NATIVE_PREVIEW'
local OBSERVER = 'modifier_native_ranged_preview_observer'
local OFFICIAL = 'npc_dota_creep_badguys_ranged'
-- Verified by native readback, not a guessed asset_catalog mapping.
local OFFICIAL_MODEL = 'models/creeps/lane_creeps/creep_bad_ranged/lane_dire_ranged.vmdl'
local function copy(t) if type(t) ~= 'table' then return t end local r={};for k,v in pairs(t) do r[k]=copy(v) end;return r end
local function tools() assert(IsServer() and IsInToolsMode() and GetMapName()=='template_map','Tools template_map only') end
local function valid(u) local ok,v=pcall(function() return u and not u:IsNull() and u:IsAlive() end);return ok and v==true end
local function exists(u) local ok,v=pcall(function() return u and not u:IsNull() end);return ok and v==true end
local function current(s)
    local ok,v=pcall(function()
        local setup=require('systems/match_setup_service')
        return _G[KEY]==s and not s.stopped and GameRules:GetGameModeEntity()==s.world
            and _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION==s.guard and s.guard.mode==s.world
            and _G.SURVIVAL_FOUR_PLAYER_LIVE_PERF==s.fixture and s.fixture.mode==s.world
            and s.fixture.guard==s.guard and s.fixture.status=='ready'
            and s.bus==require('core/event_bus') and s.bus_generation==s.bus.get_generation()
            and setup.get_session_id()==s.session and setup.get_mode()==s.match_mode
    end);return ok and v==true
end
local function owned_demo(s, include_dead)
    local ok,v=pcall(function() return (include_dead and exists(s.demo) or valid(s.demo)) and s.root.unit==s.demo and s.root.world==s.world and s.root.guard==s.guard
        and _G[ROOT_KEY]==s.root and s.root.token==s.root_token
        and s.demo.survival_ranged_native_preview_token==s.root_token
        and s.demo.survival_native_ranged_probe_token==s.token and s.demo:entindex()==s.demo_id end)
    return ok and v==true
end
local function owned_target(s)
    local ok,v=pcall(function() return exists(s.target) and s.target.survival_native_ranged_target_token==s.target_token
        and s.target:entindex()==s.target_id end);return ok and v==true
end
local function target_visible(s)
    if not owned_demo(s) or not owned_target(s) or not valid(s.target)
        or type(s.demo.CanEntityBeSeenByMyTeam)~='function' then return false end
    local ok,seen=pcall(s.demo.CanEntityBeSeenByMyTeam,s.demo,s.target)
    return ok and seen==true
end
local function disable(s, reason)
    s.enabled=false;s.error=reason
    if s.subscription then s.bus.unsubscribe(s.subscription);s.subscription=nil end
end
local function attachment(u)
    if type(u.ScriptLookupAttachment)~='function' then return nil end
    local ok,n=pcall(u.ScriptLookupAttachment,u,'attach_attack1')
    if not ok or type(n)~='number' or n~=n or math.abs(n)==math.huge or n<1 or n~=math.floor(n) then return nil end
    return n
end
local function state()
    tools();local s=assert(_G[KEY],'Adopt exact root preview first');assert(current(s),'Current isolated world required');return s
end
local function stop_demo(s)
    if owned_demo(s) and type(s.demo.Stop)=='function' then pcall(s.demo.Stop,s.demo) end
end
local function detach_observer(s)
    if not s.observer then return end
    local read,owned=pcall(function() return not s.observer:IsNull() and s.observer:GetParent()==s.demo
        and s.observer.survival_native_ranged_observer_token==s.token end)
    if read and owned then
        local removed=pcall(s.observer.Destroy,s.observer);s.observer_destroyed=removed
        if removed then s.observer=nil end
    elseif read and s.observer:IsNull() then s.observer=nil end
end
local function remember_observation(s)
    s.observation_history=s.observation_history or {}
    local attempt=s.observation_attempt or 1
    if s.observation_history[#s.observation_history] and s.observation_history[#s.observation_history].attempt==attempt then return end
    if #s.observation_history>=8 then table.remove(s.observation_history,1) end
    local order_sent=s.order_sent;if order_sent==nil then order_sent='unknown_legacy_v1' end
    s.observation_history[#s.observation_history+1]={attempt=attempt,reason=s.observation_reason,
        launched=s.launched,landed=s.landed,started=s.observation_started,finished=GameRules:GetGameTime(),
        target_health_before=s.target_health_before,target_health_after=s.target_health_after,
        order_sent=order_sent,order_sent_at=s.order_sent_at,visibility_checks=s.visibility_checks or 0,
        passed=s.shots_passed==true}
end
local function finish(s, reason)
    if not s.observing then return end
    s.observing=false;s.observation_reason=reason
    stop_demo(s)
    detach_observer(s)
    if s.watchdog then require('core/scheduler').cancel(s.watchdog) end
    if s.stop_task then require('core/scheduler').cancel(s.stop_task) end
    if s.visibility_task then require('core/scheduler').cancel(s.visibility_task) end
    if owned_target(s) then local ok,hp=pcall(s.target.GetHealth,s.target);if ok then s.target_health_after=hp end end
    s.shots_passed=reason=='three_launches_and_lands' and s.launched>=3 and s.landed>=3
        and s.target_health_after==s.target_health_before and attachment(s.demo)~=nil
    remember_observation(s)
end
local function begin_observation(s,timeout,retry)
    assert(s.observer==nil,'Old observer must be detached before retry')
    s.observation_attempt=(s.observation_attempt or 0)+1
    local attempt=s.observation_attempt
    s.launched=0;s.landed=0;s.records={};s.record_count=0;s.unknown_records=0;s.foreign_events=0
    s.shots_passed=false;s.validated=false;s.observation_reason=nil;s.observer_destroyed=false
    s.order_sent=false;s.order_sent_at=nil;s.visibility_checks=0;s.visibility_wait_exhausted=false
    s.target_health_after=nil;s.target_health_before=s.target:GetHealth()
    s.observing=true;s.observation_started=GameRules:GetGameTime()
    s.observer=s.demo:AddNewModifier(s.demo,nil,OBSERVER,{})
    assert(s.observer and not s.observer:IsNull(),'Bounded native observer creation failed')
    s.observer.survival_native_ranged_observer_token=s.token
    s.watchdog='native_ranged_preview_watchdog';s.stop_task='native_ranged_preview_stop_after_launch'
    s.visibility_task='native_ranged_preview_visibility_check'
    local scheduler=require('core/scheduler')
    scheduler.after(timeout,function()
        if s.observing and s.observation_attempt==attempt then finish(s,'shot_test_timeout') end
    end,s.watchdog)
    local deadline=s.observation_started+1
    local function send_when_visible()
        if not s.observing or s.observation_attempt~=attempt then return end
        if not current(s) or not owned_demo(s) or not owned_target(s) or not valid(s.target) then
            finish(s,'world_preview_or_target_changed');return
        end
        if not retry and GameRules:GetGameTime()>deadline then s.visibility_wait_exhausted=true;return end
        s.visibility_checks=s.visibility_checks+1
        if target_visible(s) then
            if s.order_sent then return end
            s.order_sent=true;s.order_sent_at=GameRules:GetGameTime()
            local ordered=pcall(ExecuteOrderFromTable,{UnitIndex=s.demo_id,OrderType=DOTA_UNIT_ORDER_ATTACK_TARGET,TargetIndex=s.target_id,Queue=false})
            if not ordered then finish(s,'native_order_call_failed') end
        elseif not retry and GameRules:GetGameTime()<deadline then
            scheduler.after(.1,send_when_visible,s.visibility_task)
        else s.visibility_wait_exhausted=true end
    end
    -- Native FOW/team visibility may not exist in the target creation frame.
    -- A retry also rechecks visibility after this delay; it never trusts an
    -- earlier read or issues an immediate/same-frame native order.
    scheduler.after(.1,send_when_visible,s.visibility_task)
end
function M.adopt_root_preview(options)
    options=options or {};if options.enabled~=true then return {default_off=true,enabled=false} end
    tools();local old=_G[KEY];assert(not old or old.stopped,'Stop previous owned probe before adoption')
    local world=GameRules:GetGameModeEntity();local guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    local fixture=_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF;local root=assert(_G[ROOT_KEY],'Root preview absent')
    assert(guard and guard.mode==world and fixture and fixture.mode==world and fixture.guard==guard and fixture.status=='ready','Current isolated ready fixture required')
    local u=root.unit
    assert(root.world==world and root.guard==guard and root.token~=nil and valid(u)
        and u.survival_ranged_native_preview_token==root.token and u:entindex()==options.demo_entindex
        and u:GetUnitName()==OFFICIAL and u.survival_is_wave_monster~=true and u.survival_hero_id==nil,'Exact exclusive official root preview required')
    local model=u:GetModelName();assert(model==OFFICIAL_MODEL and attachment(u)
        and u:GetAttackCapability()==DOTA_UNIT_CAP_RANGED_ATTACK,'Native model+positive ranged attachment readback required')
    local setup,bus=require('systems/match_setup_service'),require('core/event_bus')
    local s={world=world,guard=guard,fixture=fixture,bus=bus,bus_generation=bus.get_generation(),
        session=setup.get_session_id(),match_mode=setup.get_mode(),root=root,root_token=root.token,token={},
        demo=u,demo_id=u:entindex(),model_path=model,attachment_index=attachment(u),enabled=false,
        validated=false,observing=false,launched=0,landed=0,records={},unknown_records=0,foreign_events=0,
        modified=0,failed=0,skipped=0,duplicates=0,visual_write_attempts=0,retired_parts=0,samples={},
        observation_attempt=0,observation_history={},seen=setmetatable({},{__mode='k'})}
    u.survival_native_ranged_probe_token=s.token;u.survival_visual_only=true
    _G[KEY]=s;return M.snapshot()
end
function M.start_shot_test(options)
    local s=state();options=options or {};assert(owned_demo(s) and attachment(s.demo),'Own attached demo required')
    assert(not s.observing and not s.target,'Only one owned short shot test allowed')
    local pos=assert(options.target_position,'Explicit nearby target position required')
    for _,k in ipairs({'x','y','z'}) do assert(type(pos[k])=='number' and pos[k]==pos[k] and math.abs(pos[k])<20000,'Finite bounded position required') end
    local timeout=tonumber(options.timeout_seconds) or 8;assert(timeout>=3 and timeout<=10,'Short 3..10s observation only')
    assert(type(LinkLuaModifier)=='function','Native modifier binding required')
    LinkLuaModifier(OBSERVER,'tests/modifier_native_ranged_preview_observer',LUA_MODIFIER_MOTION_NONE)
    local u=CreateUnitByName('npc_survival_wave_monster',Vector(pos.x,pos.y,pos.z),false,nil,nil,DOTA_TEAM_GOODGUYS)
    assert(valid(u),'Owned target creation failed')
    s.target=u;s.target_id=u:entindex();s.target_token={};u.survival_native_ranged_target_token=s.target_token
    local ready=pcall(function()
        u.survival_visual_only=true;u.survival_is_visual_carrier=true
        u:RemoveModifierByName('modifier_single_health_bar')
        u:SetBaseMaxHealth(1000000);u:SetMaxHealth(1000000);u:SetHealth(1000000)
        u:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK);u:SetIdleAcquire(false);u:SetAcquisitionRange(0)
        assert(not u:IsInvulnerable(),'Target must remain attackable; no INVULNERABLE flag')
        s.demo:SetBaseDamageMin(0);s.demo:SetBaseDamageMax(0);s.demo:SetIdleAcquire(false);s.demo:SetAcquisitionRange(0)
        begin_observation(s,timeout,false)
    end)
    if not ready then
        finish(s,'shot_test_setup_failed')
        if owned_target(s) then UTIL_Remove(s.target);s.target_removed=true end
        s.observation_reason='shot_test_setup_failed';s.shots_passed=false
        return M.snapshot()
    end
    return M.snapshot()
end
function M.retry_visible_target(options)
    options=options or {};if options.enabled~=true then return {enabled=false,default_off=true} end
    local s=state();local timeout=tonumber(options.timeout_seconds) or 8
    assert(timeout>=3 and timeout<=10,'Short 3..10s observation only')
    assert(not s.observing and s.observer==nil and s.observation_reason=='shot_test_timeout'
        and s.launched==0 and s.landed==0 and owned_demo(s) and attachment(s.demo)
        and s.demo:GetModelName()==s.model_path and owned_target(s) and valid(s.target)
        and not s.target:IsInvulnerable() and target_visible(s),'Exact visible untouched zero-launch timeout required')
    -- v1 native timeout snapshots predate the attempt/history fields. Preserve
    -- that actual failure before starting a new observer on the same objects.
    if not s.observation_attempt or s.observation_attempt<1 then s.observation_attempt=1 end
    remember_observation(s)
    LinkLuaModifier(OBSERVER,'tests/modifier_native_ranged_preview_observer',LUA_MODIFIER_MOTION_NONE)
    local ready=pcall(begin_observation,s,timeout,true)
    if not ready then finish(s,'shot_test_setup_failed');s.observation_reason='shot_test_setup_failed' end
    return M.snapshot()
end
function M.on_native_event(observer, kind, p)
    local s=_G[KEY];if not s or not s.observing then return end
    if not current(s) or not owned_demo(s) then finish(s,'world_or_preview_changed');return end
    if type(p)~='table' then s.foreign_events=s.foreign_events+1;return end
    if observer~=s.observer or observer:GetParent()~=s.demo or p.attacker~=s.demo then s.foreign_events=s.foreign_events+1;return end
    local record=p.record
    if type(record)~='number' or record<0 or record~=math.floor(record) or math.abs(record)==math.huge then s.unknown_records=s.unknown_records+1;return end
    if kind~='destroy' and (p.target~=s.target or not valid(s.target)
        or s.target.survival_native_ranged_target_token~=s.target_token) then s.foreign_events=s.foreign_events+1;return end
    local r=s.records[record]
    if kind=='record' then
        if not r and s.record_count~=nil and s.record_count>=8 then finish(s,'record_limit');return end
        if not r then s.records[record]={record=true,record_at=GameRules:GetGameTime()};s.record_count=(s.record_count or 0)+1 end
    elseif kind=='launch' then
        if not r or not r.record then s.unknown_records=s.unknown_records+1;return end
        if not r.launch then r.launch=true;r.launch_at=GameRules:GetGameTime();s.launched=s.launched+1 end
        if s.launched>=3 then
            require('core/scheduler').after(0.01,function() if current(s) then stop_demo(s) end end,s.stop_task)
        end
    elseif kind=='landed' then
        if not r or not r.launch then s.unknown_records=s.unknown_records+1;return end
        if not r.landed then r.landed=true;r.landed_at=GameRules:GetGameTime();s.landed=s.landed+1 end
        if s.landed>=3 and s.launched>=3 then finish(s,'three_launches_and_lands') end
    elseif kind=='destroy' and r then r.destroy=true;r.destroy_at=GameRules:GetGameTime() end
end
function M.validate_preview(options)
    local s=state();options=options or {}
    assert(options.approved==true and options.demo_entindex==s.demo_id and owned_demo(s)
        and s.shots_passed and not s.observing and s.observer==nil and attachment(s.demo)
        and s.demo:GetModelName()==s.model_path,'Exact native attached three-shot preview approval required')
    s.validated=true;return M.snapshot()
end
-- Numeric actual native false-argument getters; no configured BAT substitute.
local GETTERS={health='GetHealth',max_health='GetMaxHealth',speed='GetBaseMoveSpeed',hull='GetHullRadius',
    cap='GetAttackCapability',BAT='GetBaseAttackTime',AS='GetAttackSpeed',SPA='GetSecondsPerAttack',APS='GetAttacksPerSecond',
    point='GetAttackAnimationPoint',acquisition='GetAcquisitionRange'}
local BOOLEAN={BAT=true,AS=true,SPA=true,APS=true,point=true,acquisition=true}
local function capture(u)
    local r={unit=u,id=u:entindex(),name=u:GetUnitName(),ai=u:FindModifierByName('modifier_enemy_wall_ai'),
        attack_cap=u:FindModifierByName('modifier_debug_attack_cap'),cap_flag=u.survival_wave_native_attack_cap,
        attack_speed=u.survival_attack_speed,owner=u.survival_player_id,target=u:GetAttackTarget()}
    if not r.ai then return nil,'ai_missing' end
    r.ai_state=r.ai.ai_state;r.wall=r.ai.wall_entindex;r.ai_owner=r.ai.wall_target_player_id
    local range_getter=u.Script_GetAttackRange or u.GetAttackRange
    if type(range_getter)~='function' then return nil,'getter_missing:attack_range' end
    local range_ok,range=pcall(range_getter,u)
    if not range_ok or type(range)~='number' or range~=range or math.abs(range)==math.huge or range<0 then
        return nil,'getter_failed:attack_range'
    end
    r.attack_range=range
    for key,getter in pairs(GETTERS) do
        if type(u[getter])~='function' then return nil,'getter_missing:'..getter end
        local ok,v;if BOOLEAN[key] then
            ok,v=pcall(u[getter],u,false)
            if not ok and type(v)=='string' and v:find(getter..' called with 2 arguments - expected 1',1,true) then ok,v=pcall(u[getter],u) end
        else ok,v=pcall(u[getter],u) end
        if not ok or type(v)~='number' or v~=v or math.abs(v)==math.huge then return nil,'getter_failed:'..getter end
        r[key]=v
    end
    if r.BAT<=0 or r.AS<=0 or r.SPA<=0 or r.APS<=0 or math.abs(r.SPA*r.APS-1)>.0001 then return nil,'cadence_invalid' end
    return r
end
local function transform(s,u,p)
    if not s.enabled or not current(s) then return false end
    local allowed= require('tests/manual_wave_cosmetic_probe').check_ordinary_wave_unit(u,p)
    if not allowed or u:GetAttackCapability()~=DOTA_UNIT_CAP_RANGED_ATTACK then s.skipped=s.skipped+1;return false end
    if s.seen[u] then s.duplicates=s.duplicates+1;return false end
    local read_ok,before,why=pcall(capture,u)
    if not read_ok or not before then s.failed=s.failed+1;disable(s,why or 'native_snapshot_read_failed');return false end
    local parts_before=require('visual/model_appearance_service')._count_for_test(u)
    s.seen[u]=true
    local visual={visual_id='tools_native_dire_ranged',model_path=s.model_path,model_scale=1,
        components={},effects={},ornaments={},activity_modifiers={},model_skin=0}
    s.visual_write_attempts=s.visual_write_attempts+1
    local ok,applied=pcall(require('visual/endless_monster_visual_service').apply,u,visual)
    local after_ok,after=pcall(capture,u);if not after_ok then after=nil end;local same=after~=nil
    if after then for k,v in pairs(before) do if after[k]~=v then same=false end end;for k,v in pairs(after) do if before[k]~=v then same=false end end end
    local parts_after=require('visual/model_appearance_service')._count_for_test(u)
    local success=ok and applied==true and same and attachment(u)~=nil and u:GetModelName()==s.model_path and parts_after==0
    local sample={id=before.id,owner=before.owner,success=success,attachment_index=attachment(u),numeric_invariants_equal=same,
        model=u:GetModelName(),native_launch_landed_preview=s.shots_passed,
        owned_parts_before=parts_before,owned_parts_after=parts_after,
        BAT_before=before.BAT,BAT_after=after and after.BAT,attack_speed_before=before.AS,attack_speed_after=after and after.AS,
        seconds_per_attack_before=before.SPA,seconds_per_attack_after=after and after.SPA,
        attacks_per_second_before=before.APS,attacks_per_second_after=after and after.APS,
        animation_point_before=before.point,animation_point_after=after and after.point,
        acquisition_before=before.acquisition,acquisition_after=after and after.acquisition}
    sample.attack_range_before=before.attack_range;sample.attack_range_after=after and after.attack_range
    if success then s.modified=s.modified+1;s.retired_parts=s.retired_parts+parts_before else s.failed=s.failed+1;disable(s,'native_model_or_combat_invariant_failed') end
    if #s.samples<32 then s.samples[#s.samples+1]=sample end
    return success
end
function M.enable(options)
    options=options or {};if options.enabled~=true then return {enabled=false,default_off=true} end
    local s=state();assert(options.validated_preview==true and s.validated and s.shots_passed and owned_demo(s),'Validated three-shot native profile required')
    assert(s.observer==nil and not s.observing,'No native observation fanout may remain during candidate')
    assert(not s.error,'Stopped failure requires a fresh probe/map; cannot silently resume partial changes')
    if not s.enabled then s.enabled=true;s.subscription=s.bus.subscribe(require('core/events').MONSTER_SPAWNED,function(p)
        if not current(s) then disable(s,'world_guard_fixture_or_bus_changed');return end
        if type(p)=='table' then transform(s,p.unit,p) end
    end) end
    return M.snapshot()
end
function M.apply_existing()
    local s=state();assert(s.enabled,'Enabled candidate required')
    local units=Entities:FindAllByClassname('npc_dota_creature');local n=0
    assert(type(units)=='table','Native dense collection required')
    for k in pairs(units) do assert(type(k)=='number' and k>=1 and k==math.floor(k),'Dense collection required');n=n+1 end
    assert(n==#units,'Complete collection required')
    local result={collected=n,examined=0,modified_before=s.modified,complete=false}
    for _,u in ipairs(units) do
        if not s.enabled or not current(s) then break end
        result.examined=result.examined+1
        transform(s,u,{unit=u,monster_source=u.survival_is_wave_monster==true and 'wave' or 'non_wave',
            member_role=u.survival_monster_role,player_id=u.survival_player_id,is_boss=u.survival_is_boss==true})
    end
    result.complete=result.examined==n and s.enabled and current(s);result.modified_delta=s.modified-result.modified_before
    result.failed=s.failed;s.last_existing=result;return copy(result)
end
function M.stop(reason)
    tools();local s=_G[KEY];if not s then return false end
    finish(s,reason or 'explicit_stop');detach_observer(s);s.enabled=false
    if s.subscription then s.bus.unsubscribe(s.subscription);s.subscription=nil end
    -- Ownership tokens and exact objects, never source NPCs or broad cleanup.
    if owned_target(s) then UTIL_Remove(s.target);s.target_removed=true end
    if owned_demo(s,true) then UTIL_Remove(s.demo);s.demo_removed=true end
    s.stopped=true;return M.snapshot()
end
function M.snapshot()
    tools();local s=_G[KEY];if not s then return {enabled=false,default_off=true} end
    local attacks={};for record,r in pairs(s.records) do attacks[#attacks+1]={record_id=record,record_observed=r.record==true,
        launch_observed=r.launch==true,landed_observed=r.landed==true,destroy_observed=r.destroy==true,
        record_at=r.record_at,launch_at=r.launch_at,landed_at=r.landed_at,destroy_at=r.destroy_at} end
    table.sort(attacks,function(a,b) return a.record_id<b.record_id end)
    return {default_off=true,current_scope=current(s),enabled=s.enabled and current(s),official_unit=OFFICIAL,
        model_path=s.model_path,demo_entindex=s.demo_id,attachment_index=s.attachment_index,
        observing=s.observing,observer_present=s.observer~=nil,observer_destroyed=s.observer_destroyed,
        observation_attempt=s.observation_attempt,observation_history=copy(s.observation_history),
        order_sent=s.order_sent,order_sent_at=s.order_sent_at,visibility_checks=s.visibility_checks,
        visibility_wait_exhausted=s.visibility_wait_exhausted,target_visible_now=target_visible(s),
        launched=s.launched,landed=s.landed,observed_attacks=attacks,observation_record_limit=8,
        unknown_records=s.unknown_records,foreign_events=s.foreign_events,
        target_health_before=s.target_health_before,target_health_after=s.target_health_after,shots_passed=s.shots_passed==true,
        observation_reason=s.observation_reason,validated=s.validated,modified=s.modified,skipped=s.skipped,
        failed=s.failed,duplicates=s.duplicates,visual_write_attempts=s.visual_write_attempts,retired_parts=s.retired_parts,error=s.error,samples=copy(s.samples),last_existing=copy(s.last_existing),
        demo_removed=s.demo_removed,target_removed=s.target_removed,no_global_observer_during_candidate=s.observer==nil,
        stop_restores_source_models=false,requires_fresh_map_to_restore_source_units=s.modified>0 or s.failed>0,
        native_mesh_triangle_or_fps_measurement=false}
end
return M
