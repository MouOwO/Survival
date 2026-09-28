local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local routes = require("config/tower_route_config")
local context = require("systems/player_context_service")
local M = {}
local jobs, dependencies = {}, nil
local players = {}
local queue_player
local function player_task(player, suffix)
    return "tower_auto_upgrade_player_" .. tostring(player) .. suffix
end
local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
        and unit.survival_building_destroyed ~= true
end
local function stop(index)
    local job = jobs[index]
    if not job then return end
    jobs[index] = nil
    local bucket = players[job.player_id]
    if bucket then
        bucket.jobs[index] = nil
        if not next(bucket.jobs) then
            players[job.player_id] = nil
            scheduler.cancel(player_task(job.player_id, "_check"))
            scheduler.cancel(player_task(job.player_id, "_fallback"))
        end
    end
    if valid(job.unit) then
        job.unit.survival_tower_auto_upgrade = nil
        local state = dependencies.query(job.unit)
        if state then dependencies.publish(state, "tower_auto_upgrade_stopped") end
    end
end
local function current(job)
    if not valid(job.unit) or context.is_defeated(job.player_id) then return nil end
    local state = dependencies.query(job.unit)
    if not state or state.unit ~= job.unit or state.building_id ~= "arrow_tower"
        or state.player_id ~= job.player_id or state.tower_class ~= job.tower_class then return nil end
    local row = routes.current(state)
    local next_row = routes.row_at_level(state, state.level + 1)
    if not state.tower_class or not row or not next_row then return nil end
    return state
end
local function step(index)
    local job = jobs[index]
    if not job then return false end
    local state = current(job)
    if not state then stop(index); return false end
    if job.unit.survival_upgrade_in_progress
        or job.unit:HasModifier("modifier_building_under_construction") then return true end
    if job.cost_level ~= state.level or job.cost_population ~= state.population_occupied then
        job.cost = routes.cost_to(state, state.level + 1)
        job.cost_level, job.cost_population = state.level, state.population_occupied
    end
    -- Cached route cost, live wallet/population/free-upgrade eligibility. Failed
    -- preflight never enters the full upgrade lifecycle or publishes UI state.
    if not job.cost or not dependencies.can_upgrade(state, job.cost) then return true end
    -- Use the same authoritative cost, population and upgrade lifecycle as a click.
    -- Keep the selected route through stage transitions; never choose a route.
    local result = dependencies.upgrade({building = job.unit, upgrade_mode = "one",
        silent_notification = true, player_id = job.player_id})
    if jobs[index] ~= job then return false end
    if not current(job) then stop(index); return false end
    job.waiting = job.unit.survival_upgrade_in_progress == true
    if result and result.ok and not job.waiting then queue_player(job.player_id) end
    return true
end

-- One coalesced queue per owner, with at most eight towers checked per slice.
-- Events emitted synchronously by spending only queue a later pass.
queue_player = function(player)
    local bucket = players[player]
    if not bucket then return end
    if bucket.pending then
        if bucket.running then bucket.again = true end
        return
    end
    bucket.pending = true
    local indexes, cursor
    local function run()
        if players[player] ~= bucket then return end
        if not indexes then
            indexes = {}
            for index in pairs(bucket.jobs) do indexes[#indexes + 1] = index end
            table.sort(indexes)
            cursor = 1
        end
        bucket.running = true
        local last = math.min(#indexes, cursor + 7)
        while cursor <= last do
            step(indexes[cursor])
            cursor = cursor + 1
            if players[player] ~= bucket then return end
        end
        if cursor <= #indexes then
            scheduler.after(0.05, run, player_task(player, "_check"))
        else
            bucket.pending, bucket.running = false, false
            if bucket.again then
                bucket.again = false
                queue_player(player)
            end
        end
    end
    scheduler.after(0.2, run, player_task(player, "_check"))
end
local function add_job(index, job)
    jobs[index] = job
    local player = job.player_id
    local bucket = players[player]
    if not bucket then
        bucket = {jobs = {}}
        players[player] = bucket
        -- Recovers missed lifecycle/free-upgrade events; not the normal driver.
        scheduler.every(3, function()
            if players[player] ~= bucket then return false end
            queue_player(player)
            return true
        end, player_task(player, "_fallback"))
    end
    bucket.jobs[index] = true
    queue_player(player)
end
local function toggle(payload)
    payload = payload or {}
    local index, player = tonumber(payload.entindex), tonumber(payload.player_id)
    if not index or not player or context.is_defeated(player) then
        return {ok = false, error = "无法设置自动升级"}
    end
    local ok, unit = pcall(EntIndexToHScript, index)
    if not ok or not valid(unit) then return {ok = false, error = "箭塔不存在"} end
    local state = dependencies.query(unit)
    if not state or state.building_id ~= "arrow_tower" or state.player_id ~= player then
        return {ok = false, error = "只能设置自己的箭塔"}
    end
    if jobs[index] and jobs[index].unit == unit then
        stop(index)
        return {ok = true, enabled = false}
    end
    local row = routes.current(state)
    local next_row = routes.row_at_level(state, state.level + 1)
    if not state.tower_class then
        return {ok = false, error = "基础箭塔需要手动升级并选择路线"}
    end
    if not row or not next_row then return {ok = false, error = "箭塔已满级"} end
    if unit:HasModifier("modifier_building_under_construction") then
        return {ok = false, error = "请等待建造完成"}
    end
    local ability = unit:FindAbilityByName("ability_upgrade_tower_lv01")
        or unit:FindAbilityByName("ability_upgrade_tower")
    if not ability or ability:IsNull() or ability:IsHidden() then
        return {ok = false, error = "升级技能不可用"}
    end
    if jobs[index] then stop(index) end
    add_job(index, {unit = unit, player_id = player, tower_class = state.tower_class, level = state.level})
    unit.survival_tower_auto_upgrade = true
    dependencies.publish(state, "tower_auto_upgrade_started")
    return {ok = true, enabled = true}
end
function M.init(options)
    for player in pairs(players) do
        scheduler.cancel(player_task(player, "_check"))
        scheduler.cancel(player_task(player, "_fallback"))
    end
    for _, job in pairs(jobs) do
        if valid(job.unit) then job.unit.survival_tower_auto_upgrade = nil end
    end
    jobs, players, dependencies = {}, {}, options
    event_bus.handle_request(events.TOWER_AUTO_UPGRADE_TOGGLE_REQUEST, toggle)
    event_bus.subscribe(events.BUILDING_CHANGED, function(payload)
        local job = jobs[payload.entindex]
        if not job then return end
        -- Attack growth also publishes BUILDING_CHANGED: ignore it here.
        local reason = tostring(payload.reason or "")
        local changed = (payload.level ~= nil and payload.level ~= job.level)
            or (payload.tower_class ~= nil and payload.tower_class ~= job.tower_class)
            or (job.waiting and not job.unit.survival_upgrade_in_progress)
            or reason:find("upgraded", 1, true) or reason:find("upgrade_cancelled", 1, true)
        if not changed then return end
        local state = current(job)
        if not state then stop(payload.entindex); return end
        job.level, job.waiting = state.level, job.unit.survival_upgrade_in_progress == true
        queue_player(job.player_id)
    end)
    event_bus.subscribe(events.RESOURCE_CHANGED, function(payload)
        queue_player(tonumber(payload.player_id))
    end)
    event_bus.subscribe(events.BUILDING_DESTROYED, function(payload)
        local job = jobs[payload.entindex]
        if job and (not payload.unit or job.unit == payload.unit) then stop(payload.entindex) end
    end)
    event_bus.subscribe(events.PLAYER_DISCONNECTED, function(payload)
        if not payload.defeat_cleanup then return end
        local indexes = {}
        for index, job in pairs(jobs) do
            if job.player_id == tonumber(payload.player_id) then indexes[#indexes + 1] = index end
        end
        for _, index in ipairs(indexes) do stop(index) end
    end)
end
return M
