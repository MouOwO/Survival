-- Bounded Workshop diagnostic. It observes the existing worker AI decision,
-- native harvest callback and actual internal-order call site; it never
-- suppresses/reissues an order or changes any attack/harvest property.
local M = {}
local FLAG = "SURVIVAL_WORKER_ORDER_PROBE"
local MAX_WORKERS, MAX_SAMPLES = 512, 32
local state
local function finite(value)
    value=tonumber(value)
    return value and value==value and math.abs(value)<math.huge and value or nil
end
local function now()
    return GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0
end
local function current_world()
    return GameRules and GameRules.GetGameModeEntity and GameRules:GetGameModeEntity()
end
local function read(unit,name,...)
    if not unit or type(unit[name])~="function" then return nil end
    local ok,value=pcall(unit[name],unit,...)
    if ok then return value end
end
local function finish(reason,t)
    if state and state.active then
        state.active=false
        state.status=reason
        state.finished_at=t
    end
    _G[FLAG]=false
end
local function active_time()
    if _G[FLAG]~=true or not state or not state.active then return nil end
    local t=now()
    if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode()
        or current_world()~=state.world then finish("world_or_mode_changed",t);return nil end
    if t>=state.deadline then finish("complete",state.deadline);return nil end
    return t
end
function M.start(options)
    options=options or {}
    if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode()
        or not current_world() then return false,"requires Workshop server world" end
    local duration=finite(options.duration_seconds) or 20
    local recent=finite(options.recent_landed_seconds) or 1
    if duration<=0 or duration>20 or recent<=0 or recent>20 then
        return false,"duration/recent window must be positive and at most 20 seconds"
    end
    local t=now()
    state={active=true,status="running",world=current_world(),started_at=t,deadline=t+duration,
        duration_seconds=duration,recent_landed_seconds=recent,records={},by_unit={},
        totals={},workers_dropped=0,workers_seen=0}
    _G[FLAG]=true
    return true
end
function M.stop()
    if state and state.active then finish("stopped",now()) else _G[FLAG]=false end
    return true
end
local function count(record,key)
    record.counts[key]=(record.counts[key] or 0)+1
    state.totals[key]=(state.totals[key] or 0)+1
end
local function register(owner,unit,t)
    if not owner or not unit then return nil end
    local record=state.by_unit[unit]
    if not record then
        if #state.records>=MAX_WORKERS then state.workers_dropped=state.workers_dropped+1;return nil end
        record={sequence=#state.records+1,unit=unit,owner=owner,player_id=tonumber(owner.player_id),
            tree_entindex=tonumber(owner.tree_entindex),first_observed_at=t,counts={}}
        state.records[#state.records+1]=record
        state.by_unit[unit]=record
        state.workers_seen=state.workers_seen+1
    elseif record.owner~=owner or record.tree_entindex~=tonumber(owner.tree_entindex) then
        count(record,"owner_or_tree_changes")
        record.owner,record.tree_entindex=owner,tonumber(owner.tree_entindex)
        record.last_landed_at,record.last_landed_target,record.last_landed_same_goal=nil,nil,nil
    end
    record.last_observed_at=t
    return record
end
local function recent_landed(record,t)
    return record.last_landed_at~=nil and t>=record.last_landed_at
        and t-record.last_landed_at<=state.recent_landed_seconds
end
function M.observe_getter(owner,unit,tree,target)
    local t=active_time();if not t then return end
    local record=register(owner,unit,t);if not record then return end
    count(record,"getter_reads")
    local kind=target==tree and "tree" or target==nil and "nil" or "foreign"
    local manual=owner.manual_control==true and "manual" or owner.manual_control==false and "automatic" or "unknown"
    record.last_getter_kind,record.last_getter_manual,record.last_getter_at=kind,manual,t
    count(record,"getter_"..kind)
    count(record,"getter_"..kind.."_"..manual)
    local recent=recent_landed(record,t)
    local same=recent and record.last_landed_same_goal==true and record.last_landed_target==tree
    record.last_getter_recent_landed,record.last_getter_recent_same_tree=recent,same
    if kind=="nil" and recent then
        count(record,"nil_with_recent_landed")
        if same then
            count(record,"nil_with_recent_same_tree_landed")
            count(record,"nil_with_recent_same_tree_landed_"..manual)
        else count(record,"nil_with_recent_foreign_tree_landed") end
    elseif kind=="foreign" and recent then count(record,"foreign_target_with_recent_landed") end
end
function M.observe_internal_order(unit,tree)
    local t=active_time();if not t then return end
    -- This point follows the existing getter observation in OnIntervalThink.
    -- No FindModifier/GetAttackTarget call or fallback order is introduced.
    local record=state.by_unit[unit]
    if not record then return end
    count(record,"internal_order_attempts")
    if record.last_getter_at==t then
        count(record,"internal_order_after_"..record.last_getter_kind)
        if record.last_getter_kind=="nil" and record.last_getter_recent_landed then
            count(record,"internal_order_after_nil_recent_landed")
            if record.last_getter_recent_same_tree then
                count(record,"internal_order_after_nil_recent_same_tree_landed_"..record.last_getter_manual)
            else count(record,"internal_order_after_nil_recent_foreign_tree_landed") end
        elseif record.last_getter_kind=="foreign" and record.last_getter_recent_landed then
            count(record,"internal_order_after_foreign_target_recent_landed")
        end
    else count(record,"internal_order_without_same_observation_time") end
end
function M.observe_landed(owner,unit,target,same_goal,record_id)
    local t=active_time();if not t then return end
    local record=register(owner,unit,t);if not record then return end
    count(record,"native_harvest_landed")
    count(record,same_goal and "landed_same_goal_tree" or "landed_foreign_tree")
    count(record,record_id~=nil and "landed_record_present" or "landed_record_missing")
    if record.last_landed_at then
        local gap=t-record.last_landed_at
        if gap>=0 then
            record.landed_gap_count=(record.landed_gap_count or 0)+1
            record.landed_gap_sum=(record.landed_gap_sum or 0)+gap
            record.landed_gap_max=math.max(record.landed_gap_max or 0,gap)
        end
    end
    record.last_landed_at,record.last_landed_target,record.last_landed_same_goal=t,target,same_goal
end
function M.snapshot(options)
    options=options or {}
    if state and state.active then active_time() end
    local result={schema="worker_order_probe_v1",active=state and state.active or false,
        status=state and state.status or "not_started",max_workers=MAX_WORKERS,max_native_samples=MAX_SAMPLES,
        attack_or_order_changes=false,order_acceptance_not_asserted=true,
        harvest_yield_not_asserted=true,native_timing_is_snapshot_not_full_window=true,
        recent_window_is_statistical_not_attack_readiness=true,
        workers_with_unknown_sampled_timing=0,totals={},workers={},native_samples={}}
    if not state then return result end
    local t=now()
    local elapsed=math.max(0,(state.finished_at or t)-state.started_at)
    result.started_at,result.finished_at,result.elapsed_game_seconds=state.started_at,state.finished_at,elapsed
    result.duration_seconds,result.recent_landed_seconds=state.duration_seconds,state.recent_landed_seconds
    result.workers_seen,result.worker_capacity_rejections=state.workers_seen,state.workers_dropped
    for key,value in pairs(state.totals) do result.totals[key]=value end
    result.totals.internal_orders_per_game_second=elapsed>0 and (state.totals.internal_order_attempts or 0)/elapsed or 0
    result.totals.landed_per_game_second=elapsed>0 and (state.totals.native_harvest_landed or 0)/elapsed or 0
    local sample_native=options.sample_native~=false
        and IsServer and IsServer() and IsInToolsMode and IsInToolsMode() and current_world()==state.world
    for i,record in ipairs(state.records) do
        local worker={sequence=record.sequence,player_id=record.player_id,tree_entindex=record.tree_entindex,
            first_observed_at=record.first_observed_at,last_observed_at=record.last_observed_at,
            last_getter_kind=record.last_getter_kind,last_getter_manual=record.last_getter_manual,
            last_landed_at=record.last_landed_at,counts={},native_attack_timing_sampled=false}
        local live_handle=sample_native and read(record.unit,"IsNull")==false
        if live_handle then worker.unit_entindex=read(record.unit,"entindex") end
        for key,value in pairs(record.counts) do worker.counts[key]=value end
        worker.internal_orders_per_game_second=elapsed>0 and (record.counts.internal_order_attempts or 0)/elapsed or 0
        worker.landed_per_game_second=elapsed>0 and (record.counts.native_harvest_landed or 0)/elapsed or 0
        if record.landed_gap_count and record.landed_gap_count>0 then
            worker.observed_landed_gap_average=record.landed_gap_sum/record.landed_gap_count
            worker.observed_landed_gap_max=record.landed_gap_max
        end
        if sample_native and i<=MAX_SAMPLES then
            -- Native timing is read only here, outside every AI/hit callback.
            local bat=live_handle and finite(read(record.unit,"GetBaseAttackTime")) or nil
            local rate=live_handle and finite(read(record.unit,"GetAttacksPerSecond",false)) or nil
            bat=bat and bat>0 and bat or nil
            rate=rate and rate>0 and rate or nil
            local interval=rate and 1/rate or nil
            if not bat or not rate then
                result.workers_with_unknown_sampled_timing=result.workers_with_unknown_sampled_timing+1
            end
            worker.native_attack_timing_sampled=true
            result.native_samples[#result.native_samples+1]={sequence=record.sequence,unit_entindex=worker.unit_entindex,
                sampled_at=t,base_attack_time_seconds=bat or "unknown",native_attacks_per_second=rate or "unknown",
                native_attack_interval_seconds=interval or "unknown",recent_landed_seconds=state.recent_landed_seconds,
                recent_window_to_sampled_interval_ratio=interval and state.recent_landed_seconds/interval or "unknown",
                sample_handle_valid=live_handle,
                sample_is_alive=live_handle and read(record.unit,"IsAlive") or false,
                last_getter_kind=record.last_getter_kind}
        end
        result.workers[#result.workers+1]=worker
    end
    result.workers_without_native_timing_sample=math.max(0,#state.records-#result.native_samples)
    return result
end
return M
