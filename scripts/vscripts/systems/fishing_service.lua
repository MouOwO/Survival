local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local player_context = require("systems/player_context_service")
local rewards = require("config/generated/fishing_reward_definitions")
local rules = require("config/generated/fishing_system_rules")

local M = {}
local started_at = nil
local next_tick = 480
local effects_by_player = {}
local match_interval = 480
local RESOURCE_EFFECTS = {
    immediate_wood = true,
    immediate_gold = true,
    immediate_max_population = true,
    gold_per_second = true,
    wood_per_second = true,
}

local function number(value, fallback)
    local result = tonumber(value)
    return result ~= nil and result or (fallback or 0)
end

local function enabled_rows()
    local result = {}
    for _, row in ipairs(rewards.rows or {}) do
        if row.enabled ~= false and number(row.weight) > 0 then
            result[#result + 1] = row
        end
    end
    return result
end

local function choose(requested_id)
    if requested_id and requested_id ~= "" and requested_id ~= "random" then
        local row = rewards.by_id[requested_id]
        if not row or row.enabled == false then return nil, "reward_id_invalid" end
        return row
    end
    local rows = enabled_rows()
    local total = 0
    for _, row in ipairs(rows) do total = total + number(row.weight) end
    if total <= 0 then return nil, "reward_pool_empty" end
    local roll = RandomFloat(0, total)
    local cursor = 0
    for _, row in ipairs(rows) do
        cursor = cursor + number(row.weight)
        if roll <= cursor then return row end
    end
    return rows[#rows]
end

local function player_name(player_id)
    local player = PlayerResource and PlayerResource:GetPlayer(player_id) or nil
    if player and player.GetPlayerName then return player:GetPlayerName() end
    return "玩家" .. tostring(player_id)
end

local function apply_wall_health(player_id, amount)
    local result = event_bus.request(events.BUILDING_LIST_REQUEST, { player_id = player_id })
    local applied = false
    for _, item in ipairs(result and result.buildings or {}) do
        if item.building_id == "wall" and EntIndexToHScript then
            local unit = EntIndexToHScript(tonumber(item.entindex))
            if unit and not unit:IsNull() and unit:IsAlive() then
                local max_health = unit:GetMaxHealth() + amount
                unit:SetBaseMaxHealth(max_health)
                unit:SetMaxHealth(max_health)
                unit:SetHealth(math.min(unit:GetHealth() + amount, max_health))
                applied = true
            end
        end
    end
    return applied
end

local function add_wall_health(unit, amount)
    if not unit or unit:IsNull() or not unit:IsAlive() or amount <= 0 then return false end
    local max_health = unit:GetMaxHealth() + amount
    unit:SetBaseMaxHealth(max_health)
    unit:SetMaxHealth(max_health)
    unit:SetHealth(math.min(unit:GetHealth() + amount, max_health))
    return true
end

local function apply_row(player_id, row)
    local value = number(row.value_min)
    local team = PlayerResource:GetTeam(player_id)
    if RESOURCE_EFFECTS[row.effect_key] then
        local changes = { team = team, reason = "fishing:" .. row.reward_id }
        if row.effect_key == "immediate_wood" then changes.wood = value end
        if row.effect_key == "immediate_gold" then changes.gold = value end
        if row.effect_key == "immediate_max_population" then
            changes.max_population = value
        end
        if row.effect_key == "gold_per_second" or row.effect_key == "wood_per_second" then
            local state = effects_by_player[player_id] or {}
            state[row.effect_key] = number(state[row.effect_key]) + value
            effects_by_player[player_id] = state
            return true, value
        end
        local result = event_bus.request(events.RESOURCE_ADD_REQUEST, changes)
        return result and result.ok == true, value
    end
    if row.effect_key == "wall_health_flat" then
        local state = effects_by_player[player_id] or {}
        state.wall_health_flat = number(state.wall_health_flat) + value
        effects_by_player[player_id] = state
        apply_wall_health(player_id, value)
        return true, value
    end
    local result = event_bus.request(events.TECHNOLOGY_STATS_ROGUE_ADD_REQUEST, {
        player_id = player_id,
        effects = { { effect_type = row.effect_key, value = value } },
        reason = "fishing:" .. row.reward_id,
    })
    return result and result.ok == true, value
end


local function on_building_created(payload)
    if payload and payload.building_id == "wall" then
        local state = effects_by_player[tonumber(payload.player_id)] or {}
        local unit = EntIndexToHScript and EntIndexToHScript(tonumber(payload.entindex)) or nil
        add_wall_health(unit, number(state.wall_health_flat))
    end
end

local function announce(player_id, row, value)
    event_bus.emit(events.UI_NOTIFICATION, {
        audience = "all",
        player_id = player_id,
        message = string.format("%s 获得[%s] %s：%s", player_name(player_id),
            tostring(row.rarity or ""), tostring(row.display_name), tostring(row.notes or "")),
        level = "info",
    })
    event_bus.emit(events.FISHING_REWARD_GRANTED, {
        player_id = player_id,
        reward_id = row.reward_id,
        display_name = row.display_name,
        rarity = row.rarity,
        value = value,
    })
end

function M.grant(player_id, reward_id)
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 then return { ok = false, error = "player_id_invalid" } end
    local row, error_code = choose(reward_id)
    if not row then return { ok = false, error = error_code } end
    local ok, value = apply_row(player_id, row)
    if not ok then return { ok = false, error = "reward_apply_failed", reward_id = row.reward_id } end
    announce(player_id, row, value)
    return { ok = true, reward_id = row.reward_id, display_name = row.display_name, value = value }
end

local function tick_resources()
    for player_id, state in pairs(effects_by_player) do
        if PlayerResource and PlayerResource:GetPlayer(player_id) then
            event_bus.request(events.RESOURCE_ADD_REQUEST, {
                team = PlayerResource:GetTeam(player_id),
                gold = math.floor(number(state.gold_per_second)),
                wood = math.floor(number(state.wood_per_second)),
                reason = "fishing_per_second",
            })
        end
    end
    return 1
end

local function on_wave_changed(payload)
    local state = payload and (payload.state or payload) or nil
    if started_at ~= nil or not state or state.difficulty_selected ~= true then return end
    started_at = GameRules:GetGameTime()
    local rule = rules.by_id.default_fishing or {}
    next_tick = number(rule.match_reward_interval_seconds, 480)
    event_bus.emit(events.FISHING_STARTED, { started_at = started_at, interval = next_tick })
end

local function on_tick()
    if started_at == nil then return 1 end
    local elapsed = GameRules:GetGameTime() - started_at
    if elapsed >= next_tick then
        for _, player_id in ipairs(player_context.active_player_ids()) do
            M.grant(player_id, "random")
        end
        next_tick = next_tick + match_interval
    end
    return 1
end

function M.init()
    started_at = nil
    local rule = rules.by_id.default_fishing or {}
    match_interval = number(rule.match_reward_interval_seconds, 480)
    next_tick = match_interval
    effects_by_player = {}
    event_bus.subscribe(events.WAVE_CHANGED, on_wave_changed)
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    scheduler.every(1, on_tick, "fishing_reward_timer")
    scheduler.every(1, tick_resources, "fishing_resource_tick")
end

M._test = { choose = choose, on_wave_changed = on_wave_changed, on_tick = on_tick }
return M