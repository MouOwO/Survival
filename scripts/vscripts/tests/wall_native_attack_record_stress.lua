-- Explicit isolated Tools test only. No gameplay bootstrap/HTTP/account calls.
-- Counts actual native attack record events across repeated safe cleanup, so
-- restarting an engine and testing fewer remaining profiles cannot hide a
-- cumulative native pool leak. Never uses PerformAttack or fabricated records.
local lifecycle=require('tests/wall_native_attack_record_lifecycle')
local json=require('core/json_encoder')
local M={}
local state
local TIMER='survival_isolated_native_attack_record_stress'
local function valid(unit) return unit and not unit:IsNull() end
local function now() return GameRules:GetGameTime() end
local function integer(value,default,minimum,maximum)
    value=tonumber(value) or default
    assert(value%1==0 and value>=minimum and value<=maximum,'invalid native stress integer option')
    return value
end
local function error_once(s,message)
    if not s.error_set[message] then s.error_set[message]=true;s.errors[#s.errors+1]=message end
end
local function result(s)
    local current=s.ledger and s.ledger:summary() or nil
    return {ok=false,active=state==s,phase=s.phase,reason=s.reason,
        elapsed=now()-s.started,target_records=s.target_records,population=s.population,
        records_per_batch=s.records_per_batch,created=s.created+(current and current.created or 0),
        destroyed=s.destroyed+(current and current.destroyed or 0),pending=current and current.pending or 0,
        batches=s.batches,ranged_pending_batches=s.ranged_pending_batches,errors=s.errors,
        attack_records=current,completed_batches=s.completed_batches,cleanup_blocked=s.cleanup_blocked==true}
end
local function final_result(s)
    local value=result(s)
    value.active=false;value.cleaned=true
    value.ok=#s.errors==0 and s.reason=='complete' and s.created>=s.target_records
        and s.created==s.destroyed and s.ranged_pending_batches>0
    M.last_result=value;state=nil
    GameRules:GetGameModeEntity():SetContextThink(TIMER,nil,0)
    print('[WALL_NATIVE_ATTACK_RECORD_STRESS_RESULT] '..json.encode(value))
    return value
end
local function begin_drain(s,reason)
    if s.phase=='draining' then return end
    s.reason=reason;s.phase='draining'
    s.ledger:begin_drain()
    local audit=s.ledger:summary();local ranged_pending=0
    for _,row in ipairs(audit.units) do
        if row.attack_capability==DOTA_UNIT_CAP_RANGED_ATTACK then ranged_pending=ranged_pending+row.pending end
    end
    s.batch_ranged_pending=ranged_pending
    if ranged_pending>0 then s.ranged_pending_batches=s.ranged_pending_batches+1 end
    print('[WALL_NATIVE_ATTACK_RECORD_STRESS_DRAIN] '..json.encode({batch=s.batches+1,
        created=audit.created,pending=audit.pending,ranged_pending=ranged_pending,reason=reason}))
end
local function remove_drained_batch(s)
    local audit=s.ledger:summary()
    assert(audit.pending==0,'never delete native attackers/target while records remain pending')
    if not audit.passed or audit.created~=audit.destroyed then error_once(s,'batch_record_audit_failed') end
    local count=#s.actors
    -- Observers stay attached until every attacker in the batch has drained.
    -- Delete attackers before their target, retaining no live native orders.
    for _,unit in ipairs(s.actors) do
        assert(s.ledger:detach(unit),'record audit refuses unsafe actor deletion')
        if valid(unit) then UTIL_Remove(unit) end
    end
    if valid(s.target) then UTIL_Remove(s.target) end
    s.created=s.created+audit.created;s.destroyed=s.destroyed+audit.destroyed;s.batches=s.batches+1
    s.completed_batches[#s.completed_batches+1]={batch=s.batches,created=audit.created,destroyed=audit.destroyed,
        pending=audit.pending,pending_at_stop=audit.pending_at_drain_start,
        ranged_pending_at_stop=s.batch_ranged_pending,drain_created=audit.drain_created,
        drain_seconds=audit.elapsed,passed=audit.passed,actors=count,errors=audit.errors}
    s.actors={};s.target=nil;s.ledger=nil
end
local function create_batch(s)
    s.phase='spawning';s.ledger=lifecycle.new({timeout=s.attack_record_timeout})
    local at=Vector(s.origin.x,s.origin.y,GetGroundHeight(s.origin,nil))
    s.target=assert(CreateUnitByName('building_wall',at,false,nil,nil,DOTA_TEAM_GOODGUYS),
        'isolated native record stress target creation failed')
    s.target:SetHullRadius(32);s.target:SetAcquisitionRange(0)
    s.target:SetMaxHealth(1000000000);s.target:SetHealth(1000000000);s.target:SetBaseHealthRegen(0)
    s.target:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
    s.target:RemoveModifierByName('modifier_invulnerable')
    for index=1,s.population do
        local angle=(index-1)*math.pi*2/s.population
        local position=Vector(at.x+math.cos(angle)*s.radius,at.y+math.sin(angle)*s.radius,at.z)
        position.z=GetGroundHeight(position,nil)
        local ranged=index%2==0
        local name=ranged and 'npc_survival_wave_named_flying_red_gargoyle' or 'npc_survival_wave_monster'
        local unit=assert(CreateUnitByName(name,position,false,nil,nil,DOTA_TEAM_BADGUYS),
            'isolated native record stress actor creation failed')
        s.actors[#s.actors+1]=unit
        unit:SetHullRadius(32);unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_GROUND)
        unit:SetAttackCapability(ranged and DOTA_UNIT_CAP_RANGED_ATTACK or DOTA_UNIT_CAP_MELEE_ATTACK)
        unit:SetAcquisitionRange(0);unit:SetMinimumGoldBounty(0);unit:SetMaximumGoldBounty(0);unit:SetDeathXP(0)
        unit:SetBaseDamageMin(1);unit:SetBaseDamageMax(1);unit:SetBaseAttackTime(s.attack_time)
        assert(s.ledger:attach(unit),'native attack record audit attachment failed')
        local row=unit.survival_native_attack_record_lifecycle
        row.test_attack_range=s.radius+256;row.modifier:SetStackCount(2);row.modifier:ForceRefresh()
    end
    -- npc_dota_building can receive its native protection on the next frame.
    -- Arm on the following real server think and verify an attackable target.
    s.phase='arming'
end
local function arm_batch(s)
    assert(valid(s.target) and s.target:IsAlive(),'native stress target lost before arming')
    s.target:RemoveModifierByName('modifier_invulnerable')
    assert(not s.target:IsInvulnerable(),'native stress target remains invulnerable')
    for _,unit in ipairs(s.actors) do
        unit:SetForceAttackTarget(s.target)
        ExecuteOrderFromTable({UnitIndex=unit:entindex(),OrderType=DOTA_UNIT_ORDER_ATTACK_TARGET,
            TargetIndex=s.target:entindex(),Queue=false})
    end
    s.phase='attacking';s.batch_started=now()
end
local function tick(s)
    if state~=s then return nil end
    if s.phase=='arming' then arm_batch(s);return .03 end
    if s.phase=='attacking' then
        if now()-s.started>=s.timeout then error_once(s,'campaign_timeout');begin_drain(s,'timeout')
        elseif not valid(s.target) or not s.target:IsAlive() then error_once(s,'target_lost');begin_drain(s,'target_lost')
        elseif s.ledger.error_count>0 then error_once(s,'record_observer_failed');begin_drain(s,'record_observer_failed')
        elseif s.ledger.created>=s.records_per_batch or s.created+s.ledger.created>=s.target_records then
            begin_drain(s,s.created+s.ledger.created>=s.target_records and 'complete' or 'batch_complete')
        end
        return .03
    end
    if s.phase=='draining' then
        local status=s.ledger:poll();local audit=s.ledger:summary()
        if status=='pending' or (status=='failed' and audit.pending>0 and not audit.timed_out) then return .03 end
        if audit.pending>0 then
            s.cleanup_blocked=true;s.phase='cleanup_blocked';error_once(s,'native_record_cleanup_blocked')
            M.last_result=result(s)
            print('[WALL_NATIVE_ATTACK_RECORD_STRESS_BLOCKED] '..json.encode(M.last_result))
            if PauseGame then PauseGame(true) end
            return nil
        end
        remove_drained_batch(s)
        if #s.errors>0 or s.reason~='batch_complete' then final_result(s);return nil end
        s.phase='next_batch';return .03
    end
    if s.phase=='next_batch' then
        local ok,message=pcall(create_batch,s)
        if not ok then error_once(s,'batch_setup_failed: '..tostring(message));begin_drain(s,'setup_failed') end
        return .03
    end
    return nil
end
function M.start(options)
    assert(IsServer() and IsInToolsMode(),'native attack-record stress is Tools server only')
    assert(_G.SURVIVAL_SOLID_ISOLATED_RECORD_TEST==true,'explicit isolated no-account scene opt-in required')
    assert(not state,'native record stress already active or retained unsafe cleanup exists')
    options=options or {};assert(options.origin and tonumber(options.origin.x) and tonumber(options.origin.y),
        'explicit isolated empty native test origin required')
    local population=integer(options.population,64,4,96)
    local s={origin=options.origin,population=population,target_records=integer(options.target_records,30000,1,1000000),
        records_per_batch=integer(options.records_per_batch,1500,1,5000),
        timeout=math.max(10,math.min(1800,tonumber(options.timeout) or 600)),
        attack_record_timeout=math.max(.15,math.min(10,tonumber(options.attack_record_timeout) or 5)),
        attack_time=math.max(.1,math.min(1,tonumber(options.attack_time) or .2)),
        radius=math.max(population*88/(math.pi*2),tonumber(options.radius) or 900),
        actors={},created=0,destroyed=0,batches=0,ranged_pending_batches=0,
        completed_batches={},errors={},error_set={},started=now(),phase='next_batch'}
    state=s
    LinkLuaModifier(lifecycle.modifier_name,'tests/modifier_wall_native_attack_record_audit',LUA_MODIFIER_MOTION_NONE)
    GameRules:GetGameModeEntity():SetContextThink(TIMER,function()
        local ok,value=pcall(tick,s)
        if ok then return value end
        error_once(s,'stress_runtime_error: '..tostring(value))
        if s.ledger then begin_drain(s,'runtime_error');return .03 end
        final_result(s);return nil
    end,.03)
    print('[WALL_NATIVE_ATTACK_RECORD_STRESS_START] '..json.encode({population=s.population,
        target_records=s.target_records,records_per_batch=s.records_per_batch,radius=s.radius}))
    return true
end
function M.stop(reason)
    if not state then return M.last_result end
    local s=state;error_once(s,reason or 'external_stop')
    if s.ledger then begin_drain(s,reason or 'external_stop') else return final_result(s) end
end
function M.retry_cleanup()
    assert(state and state.cleanup_blocked,'no retained native record stress cleanup')
    local s=state;s.phase='draining'
    GameRules:GetGameModeEntity():SetContextThink(TIMER,function() return tick(s) end,.03)
end
function M.is_active() return state~=nil end
function M.snapshot() return state and result(state) or M.last_result end
return M
