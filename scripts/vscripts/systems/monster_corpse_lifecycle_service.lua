local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local rules = require("config/generated/global_rules")

local M = {}

local TASK_ID = "monster_corpse_lifecycle"
local corpses = {}
local task_running = false

local function rule_value(rule_id, fallback, minimum)
    local row = rules.by_id and rules.by_id[rule_id] or nil
    local value = row and row.enabled ~= false and tonumber(row.value) or fallback
    return math.max(minimum or 0, value or fallback)
end

local HOLD_SECONDS = rule_value("monster_corpse_hold_seconds", 0.6, 0)
local SINK_SECONDS = rule_value("monster_corpse_sink_seconds", 0.8, 0.05)
local SINK_DEPTH = rule_value("monster_corpse_sink_depth", 160, 1)
local UPDATE_INTERVAL = rule_value("monster_corpse_update_interval", 0.05, 0.01)
local REMOVE_DELAY_SECONDS = rule_value(
    "monster_corpse_remove_delay_seconds", 0.05, 0
)

local function valid(unit)
    return unit and not unit:IsNull()
end

local function game_time()
    return GameRules:GetGameTime()
end

local function set_origin(unit, origin)
    if type(unit.SetAbsOrigin) ~= "function" then return end
    pcall(unit.SetAbsOrigin, unit, Vector(origin.x, origin.y, origin.z))
end

local function hide(unit)
    if type(unit.AddNoDraw) == "function" then
        pcall(unit.AddNoDraw, unit)
    end
end

local function remove(unit)
    if valid(unit) and UTIL_Remove then
        pcall(UTIL_Remove, unit)
    end
end

local function update_corpses()
    local now = game_time()
    local remaining = 0
    for unit, state in pairs(corpses) do
        if not valid(unit) then
            corpses[unit] = nil
        elseif state.hidden_at then
            if now - state.hidden_at >= REMOVE_DELAY_SECONDS then
                corpses[unit] = nil
                remove(unit)
            else
                remaining = remaining + 1
            end
        elseif now >= state.sink_at then
            local progress = math.min(1, (now - state.sink_at) / SINK_SECONDS)
            set_origin(unit, {
                x = state.origin.x,
                y = state.origin.y,
                z = state.origin.z - SINK_DEPTH * progress,
            })
            if progress >= 1 then
                hide(unit)
                state.hidden_at = now
            end
            remaining = remaining + 1
        else
            remaining = remaining + 1
        end
    end
    if remaining == 0 then
        task_running = false
        return false
    end
end

local function ensure_task()
    if task_running then return end
    task_running = true
    scheduler.every(UPDATE_INTERVAL, update_corpses, TASK_ID)
end

local function on_entity_killed(payload)
    local unit = payload and payload.victim or nil
    if not valid(unit) or unit.survival_monster_corpse ~= true
        or unit.survival_wave_cleanup == true
        or unit.survival_corpse_started == true then
        return
    end
    local origin = unit:GetAbsOrigin()
    unit.survival_corpse_started = true
    corpses[unit] = {
        origin = { x = origin.x, y = origin.y, z = origin.z },
        sink_at = game_time() + HOLD_SECONDS,
    }
    ensure_task()
end

function M.track(unit, source)
    if not valid(unit) then return false end
    unit.survival_monster_corpse = true
    unit.survival_monster_corpse_source = tostring(source or "monster")
    return true
end

function M.init()
    scheduler.cancel(TASK_ID)
    corpses = {}
    task_running = false
    event_bus.subscribe(events.MONSTER_SPAWNED, function(payload)
        M.track(payload and payload.unit, "monster_spawned")
    end)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
end

return M
