-- Inert Tools-only native acquisition candidate. This is not a production
-- optimization. enable() affects NEW formal MONSTER_SPAWNED notifications only.
-- No existing-unit scan, Stop, attack order, combat stat or movement mutation.
-- Idle-acquire has no trusted original-state reader: stop() removes the hook;
-- changed units retain the candidate settings until the map is reloaded.
local M={}
local KEY='SURVIVAL_WAVE_ACQUISITION_PROBE'
local function tools()
    assert(IsServer and IsServer() and IsInToolsMode and IsInToolsMode(),'Tools server only')
    assert(GetMapName()=='template_map','template_map only')
end
local function shallow_copy(t)
    if type(t)~='table' then return t end
    local result={};for k,v in pairs(t) do result[k]=shallow_copy(v) end;return result
end
local function matches(s)
    local setup=require('systems/match_setup_service')
    return _G[KEY]==s and s.mode==GameRules:GetGameModeEntity()
        and s.guard==_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION and s.guard.mode==s.mode
        and s.fixture==_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF and s.fixture.mode==s.mode
        and s.fixture.guard==s.guard and s.fixture.status=='ready'
        and setup.get_mode()==s.match_mode and setup.get_session_id()==s.session
end
local function count_reason(s,kind,reason)
    s[kind]=s[kind]+1
    local counts=s[kind..'_reasons'];counts[reason]=(counts[reason] or 0)+1
end
local function eligible(unit,payload)
    if not unit or unit:IsNull() or not unit:IsAlive() then return false,'invalid_or_dead_unit' end
    if payload.monster_source~='wave' or unit.survival_is_wave_monster~=true then return false,'not_formal_wave' end
    if unit:GetTeamNumber()~=DOTA_TEAM_BADGUYS then return false,'not_enemy_team' end
    if unit:IsRealHero() or unit:GetClassname()~='npc_dota_creature' then return false,'hero_or_noncreature' end
    if (unit.IsIllusion and unit:IsIllusion()) or unit.survival_hero_id~=nil or unit.survival_training_id~=nil
        or unit.survival_is_challenge_monster==true or unit.survival_visual_only==true
        or unit.survival_is_summon==true or unit.survival_monkey_king_clone==true
        or unit.survival_blademaster_clone==true or unit.survival_drow_companion==true then
        return false,'excluded_gameplay_role'
    end
    local ai=unit:FindModifierByName('modifier_enemy_wall_ai')
    if not ai or ai:IsNull() or ai:GetParent()~=unit then return false,'no_authoritative_wall_ai' end
    local contract=require('systems/wave_native_attack_cap')
    if not contract.is_bare_creature(unit:GetUnitName()) then return false,'unknown_native_unit_contract' end
    local amount=unit:GetAbilityCount()
    if type(amount)~='number' or amount<0 or amount>64 or amount~=math.floor(amount) then return false,'ability_count_invalid' end
    for slot=0,amount-1 do
        local ability=unit:GetAbilityByIndex(slot)
        if ability and not ability:IsNull() and not contract.is_inert_native_warp(ability,slot) then
            return false,'unknown_native_ability'
        end
    end
    return true
end
local function read_acquisition(unit)
    if type(unit.GetAcquisitionRange)~='function' then return nil,'getter_unavailable' end
    local ok,value=pcall(unit.GetAcquisitionRange,unit)
    if not ok then return nil,tostring(value):sub(1,160) end
    if type(value)~='number' or value~=value or math.abs(value)==math.huge then return nil,'nonfinite_value' end
    return value
end
local function on_spawn(s,payload)
    if not s.enabled then return end
    if not matches(s) then M.stop('fixture_or_session_changed');return end
    s.events=s.events+1;payload=payload or {}
    local unit=payload.unit
    local ok,allowed,why=pcall(eligible,unit,payload)
    if not ok then count_reason(s,'failed','eligibility_read_failed');return end
    if not allowed then count_reason(s,'skipped',why);return end
    if s.seen[unit] then count_reason(s,'skipped','duplicate_spawn_notification');return end
    s.seen[unit]=true
    local initial,initial_error=read_acquisition(unit)
    local sample={entindex=unit:entindex(),unit_name=unit:GetUnitName(),player_id=unit.survival_player_id,
        monster_source=payload.monster_source,game_time=GameRules:GetGameTime(),
        initial_acquisition=initial,initial_acquisition_known=initial~=nil,initial_read_error=initial_error,
        initial_idle_acquire_known=false,requested_idle_acquire=false,requested_zero_acquisition=s.zero_acquisition}
    if type(unit.SetIdleAcquire)~='function' then
        sample.success=false;sample.failure='idle_acquire_setter_unavailable';count_reason(s,'failed',sample.failure)
    else
        s.native_write_attempts=s.native_write_attempts+1
        local idle_ok,idle_error=pcall(unit.SetIdleAcquire,unit,false)
        if not idle_ok then
            sample.success=false;sample.failure='idle_acquire_set_failed';sample.error=tostring(idle_error):sub(1,160)
            count_reason(s,'failed',sample.failure)
        else
            s.modified=s.modified+1;sample.idle_acquire_false_set=true
            if s.zero_acquisition then
                if type(unit.SetAcquisitionRange)~='function' then
                    sample.success=false;sample.failure='acquisition_setter_unavailable';count_reason(s,'failed',sample.failure)
                else
                    s.native_write_attempts=s.native_write_attempts+1
                    local range_ok,range_error=pcall(unit.SetAcquisitionRange,unit,0)
                    if not range_ok then
                        sample.success=false;sample.failure='acquisition_set_failed';sample.error=tostring(range_error):sub(1,160)
                        count_reason(s,'failed',sample.failure)
                    else sample.zero_acquisition_set=true;sample.success=true end
                end
            else sample.success=true end
            if sample.success then s.processed=s.processed+1 end
        end
    end
    local after,after_error=read_acquisition(unit)
    sample.after_acquisition=after;sample.after_acquisition_known=after~=nil;sample.after_read_error=after_error
    if #s.samples<32 then s.samples[#s.samples+1]=sample end
end
function M.enable(options)
    tools();options=options or {}
    assert(options.zero_acquisition==nil or type(options.zero_acquisition)=='boolean','zero_acquisition must be boolean')
    local zero=options.zero_acquisition==true
    local previous=_G[KEY]
    if previous and previous.enabled then
        assert(matches(previous) and previous.zero_acquisition==zero,'Stop the old candidate before enabling different settings/world')
        return M.snapshot()
    end
    local mode=GameRules:GetGameModeEntity();local guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    local fixture=_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF
    assert(guard and guard.mode==mode and fixture and fixture.mode==mode and fixture.guard==guard and fixture.status=='ready',
        'Current ready four-owner fixture and match write isolation required')
    local setup=require('systems/match_setup_service')
    local s={mode=mode,guard=guard,fixture=fixture,match_mode=setup.get_mode(),session=setup.get_session_id(),
        enabled=true,zero_acquisition=zero,events=0,processed=0,modified=0,native_write_attempts=0,skipped=0,failed=0,
        skipped_reasons={},failed_reasons={},samples={},seen=setmetatable({},{__mode='k'})}
    _G[KEY]=s
    s.subscription=require('core/event_bus').subscribe(require('core/events').MONSTER_SPAWNED,function(p) on_spawn(s,p) end)
    return M.snapshot()
end
function M.stop(reason)
    local s=_G[KEY];if not s then return false end
    if s.subscription then require('core/event_bus').unsubscribe(s.subscription);s.subscription=nil end
    s.enabled=false;s.stop_reason=reason or 'explicit_stop'
    return true
end
function M.snapshot()
    tools();local s=_G[KEY]
    if not s then return {enabled=false,default_enabled=false,experimental_not_production=true,modified=0} end
    return {enabled=s.enabled and matches(s),current_fixture_and_guard=matches(s),default_enabled=false,
        experimental_not_production=true,zero_acquisition=s.zero_acquisition,events=s.events,
        processed=s.processed,modified=s.modified,native_write_attempts=s.native_write_attempts,skipped=s.skipped,failed=s.failed,
        skipped_reasons=shallow_copy(s.skipped_reasons),failed_reasons=shallow_copy(s.failed_reasons),
        samples=shallow_copy(s.samples),sample_limit=32,sample_policy='first_32_eligible_new_spawn_notifications',
        only_new_spawn_notifications_no_scan=true,initial_idle_acquire_readable=false,
        stop_reason=s.stop_reason,stop_restores_unit_parameters=false,
        requires_map_reload_to_restore_modified_units=s.native_write_attempts>0,
        attack_orders_stats_damage_and_collision_changed=false,
        scope='formal_wave_bare_creatures_with_authoritative_wall_ai_only'}
end
return M
