local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local technology_definitions = require("config/generated/technology_definitions")
local technology_effects = require("config/technology_effect_config")
local technology_stat_manager = require("systems/technology_stat_manager")
local combat_stat_projection = require("ui/combat_stat_projection")
local hero_attack_cadence_projection = require("ui/hero_attack_cadence_projection")
local titan_aura_armor = require("systems/commerce_titan_aura_values")
local portrait_metadata = require("ui/portrait_metadata")

local portrait_metadata = require("ui/portrait_metadata")

local M = {}

local debug_state = {}
local hero_authority = {}
local subscriptions = {}

local function subscribe(event_name, callback)
    subscriptions[#subscriptions + 1] = event_bus.subscribe(event_name, callback)
end

local technology_names = {
    gold_mine_efficiency = "金矿采集效率",
    gold_mine_crit = "金矿暴击率",
    lumberjack_efficiency = "伐木效率",
    lumberjack_speed = "伐木速度",
    lumberjack_crit = "伐木暴击率",
    advanced_lumberjack_efficiency = "高级伐木效率",
    advanced_lumberjack_speed = "高级伐木速度",
    wall_health = "城墙强化",
    advanced_wall_health = "高级城墙强化",
    tower_attack = "防御塔强化",
    advanced_tower_attack = "高级防御塔强化",
    researcher_hero_attack = "英雄攻击",
    researcher_hero_final_damage = "英雄最终伤害",
    researcher_hero_armor_reduction = "英雄攻击减甲",
    researcher_lumberjack_attack_growth = "伐木工攻击成长",
    researcher_lumberjack_armor_reduction = "伐木工攻击减甲",
    researcher_super_tower_attack = "超级塔攻击",
    researcher_super_tower_crit = "超级塔暴击率",
    researcher_super_tower_range = "超级塔射程",
    researcher_super_wall_armor = "超级城墙护甲",
    researcher_super_wall_health = "超级城墙生命",
}

local definitions_by_group = {}

for _, row in ipairs(technology_definitions.rows or {}) do
    local group = tostring(row.technology_group or "")
    local level = tonumber(row.level) or 0
    if group ~= "" and level > 0 then
        definitions_by_group[group] = definitions_by_group[group] or {}
        definitions_by_group[group][level] = row
    end
end

local function number_text(value)
    local number = tonumber(value) or 0
    if math.abs(number - math.floor(number)) < 0.001 then
        return tostring(math.floor(number))
    end
    return string.format("%.2f", number):gsub("0+$", ""):gsub("%.$", "")
end

local function technology_effect_text(group, level, row)
    local effect_type = tostring(row and row.effect_type or "")
    local value = tonumber(row and row.effect_value) or 0
    if group == "advanced_lumberjack_speed" then
        value = technology_effects.accumulated_value(
            group, level, effect_type
        )
    end
    local formats = {
        mine_efficiency_percent = { "金矿收益 +", "%" },
        mine_crit_percent = { "金矿暴击率 +", "%" },
        lumberjack_wood_per_hit = { "每次伐木 +", " 木材" },
        lumberjack_wood_per_hit_advanced = { "每次伐木 +", " 木材" },
        lumberjack_attack_speed_pct = { "伐木攻速 +", "%" },
        lumberjack_attack_interval_flat = { "攻击间隔 -", " 秒" },
        lumberjack_critical_chance_pct = { "伐木暴击率 +", "%" },
        wall_health_pct = { "城墙生命 +", "%" },
        wall_health_pct_advanced = { "城墙生命 +", "%" },
        tower_attack_flat = { "防御塔攻击 +", "" },
        tower_attack_flat_advanced = { "防御塔攻击 +", "" },
        hero_attack_flat = { "英雄攻击 +", "" },
        hero_final_damage_pct = { "最终伤害 +", "%" },
        hero_attack_armor_reduction = { "攻击减甲 -", "" },
        lumberjack_attack_growth = { "每次伐木攻击 +", "" },
        lumberjack_attack_armor_reduction = { "伐木攻击减甲 -", "" },
        super_tower_attack_flat = { "超级塔攻击 +", "" },
        super_tower_crit_pct = { "超级塔暴击率 +", "%" },
        super_tower_attack_range = { "超级塔射程 +", "" },
        super_wall_armor_flat = { "超级墙护甲 +", "" },
        super_wall_health_pct = { "超级墙生命 +", "%" },
    }
    local format = formats[effect_type]
    if format then
        return format[1] .. number_text(value) .. format[2]
    end
    return "已激活（效果值 " .. number_text(value) .. "）"
end

local function technology_rows(levels)
    local result = {}
    for group, level_value in pairs(levels or {}) do
        local level = tonumber(level_value) or 0
        local row = definitions_by_group[group]
            and definitions_by_group[group][level]
        if level > 0 and row then
            local display_name = technology_names[group]
                or tostring(row.display_name or "")
            display_name = display_name:gsub("%s*Lv%.%d+$", "")
            if display_name == "" then display_name = group end
            result[#result + 1] = {
                group = group,
                name = display_name,
                level = level,
                effect = technology_effect_text(group, level, row),
                sort_order = tonumber(row.shop_sort_order) or 9999,
            }
        end
    end
    table.sort(result, function(left, right)
        return left.sort_order < right.sort_order
    end)
    for _, row in ipairs(result) do row.sort_order = nil end
    return result
end

local function debug_snapshot(player_id)
    local state = debug_state[player_id] or {}
    return {
        player_id = player_id,
        entindex = tonumber(state.entindex) or -1,
        total_damage = tonumber(state.total_damage) or 0,
        last_damage = tonumber(state.last_damage) or 0,
        hit_count = tonumber(state.hit_count) or 0,
        skill_total_damage = tonumber(state.skill_total_damage) or 0,
        skill_last_damage = tonumber(state.skill_last_damage) or 0,
        skill_hit_count = tonumber(state.skill_hit_count) or 0,
        skill_last_ability_name = tostring(state.skill_last_ability_name or ""),
        technologies = technology_rows(state.levels or {}),
        technology_stats = technology_stat_manager.get(player_id),
    }
end

local function publish_debug(player_id)
    CustomNetTables:SetTableValue(
        "survival_combat_debug",
        "player_" .. tostring(player_id),
        debug_snapshot(player_id)
    )
end

local function schedule_damage_publish(player_id)
    local state = debug_state[player_id]
    if not state or state.pending_publish then return end
    state.pending_publish = true
    scheduler.after(0.15, function()
        local current = debug_state[player_id]
        if current then current.pending_publish = false end
        publish_debug(player_id)
    end, "combat_debug_damage_" .. tostring(player_id))
end

local function on_hero_summoned(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil then return end
    local cached = hero_authority[player_id]
    -- The combat service can publish the new hero during this same summon
    -- dispatch, before this listener runs. Keep that hero's current snapshot.
    if cached and cached.unit ~= payload.unit then hero_authority[player_id] = nil end
    debug_state[player_id] = {
        unit = payload.unit,
        entindex = payload.unit and payload.unit:entindex() or -1,
        total_damage = 0,
        last_damage = 0,
        hit_count = 0,
        skill_total_damage = 0,
        skill_last_damage = 0,
        skill_hit_count = 0,
        skill_last_ability_name = "",
        levels = {},
    }
    local technology = event_bus.request(
        events.TECHNOLOGY_STATE_GET_REQUEST,
        { player_id = player_id }
    )
    debug_state[player_id].levels = technology and technology.levels or {}
    publish_debug(player_id)
end

local function on_damage(payload)
    local player_id = tonumber(payload.player_id)
    local state = debug_state[player_id]
    local damage = math.max(0, tonumber(payload.final_damage) or 0)
    if not state or damage <= 0
        or tonumber(payload.attacker_entindex) ~= tonumber(state.entindex) then
        return
    end
    local victim = payload.victim_entindex
        and EntIndexToHScript(tonumber(payload.victim_entindex)) or nil
    if victim and state.unit
        and victim:GetTeamNumber() == state.unit:GetTeamNumber() then
        return
    end
    state.total_damage = (state.total_damage or 0) + damage
    state.last_damage = damage
    state.hit_count = (state.hit_count or 0) + 1
    if payload.damage_kind == "ability" then
        state.skill_total_damage = (state.skill_total_damage or 0) + damage
        state.skill_last_damage = damage
        state.skill_hit_count = (state.skill_hit_count or 0) + 1
        state.skill_last_ability_name = tostring(payload.ability_name or "")
    end
    schedule_damage_publish(player_id)
end

local function on_technology_changed(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil then return end
    debug_state[player_id] = debug_state[player_id] or {
        entindex = -1,
        total_damage = 0,
        last_damage = 0,
        hit_count = 0,
    }
    debug_state[player_id].levels = payload.levels or {}
    publish_debug(player_id)
end

local function publish(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or not payload.snapshot then
        return
    end
    -- Both selected-unit responses and regular stat updates must carry the
    -- same portrait identity. Decorate only the projected copy, leaving the
    -- authoritative combat snapshot and its version untouched.
    local entindex = tonumber(payload.snapshot.entindex)
    local unit
    if entindex and entindex >= 0 and entindex < math.huge
        and entindex == math.floor(entindex) then
        local ok, resolved = pcall(function()
            local entity = EntIndexToHScript(entindex)
            if entity and not entity:IsNull() then return entity end
        end)
        if ok then unit = resolved end
    end
    -- Retain the raw service snapshot, never the already projected UI value:
    -- a later temporary-buff event must not multiply a previous slowdown again.
    hero_authority[player_id] = unit and {snapshot = payload.snapshot, unit = unit} or nil
    local projected = combat_stat_projection.for_ui(
        titan_aura_armor.for_ui(
            hero_attack_cadence_projection.for_ui(payload.snapshot, unit), unit)
    )
    portrait_metadata.apply(unit, projected)
    CustomNetTables:SetTableValue(
        "survival_combat_stats",
        "player_" .. tostring(player_id),
        projected
    )
    -- NetTable is the single regular synchronization path. Selected-unit
    -- requests still use their direct response event for immediate feedback.
end

local function on_unit_combat_stats_changed(payload)
    local entindex = tonumber(payload and payload.entindex)
    if not entindex then return end
    for player_id, cached in pairs(hero_authority) do
        if tonumber(cached.snapshot.entindex) == entindex
            and (not payload.unit or payload.unit == cached.unit) then
            -- Entity indices can be reused. Only refresh the precise cached
            -- hero handle, and avoid delayed buff updates after death/removal.
            local ok, current = pcall(function()
                local unit = EntIndexToHScript(entindex)
                if unit ~= cached.unit or unit:IsNull() then return false end
                if unit.IsAlive and not unit:IsAlive() then return false end
                if unit.GetPlayerOwnerID and unit:GetPlayerOwnerID() ~= player_id then return false end
                return true
            end)
            if ok and current then publish({player_id = player_id, snapshot = cached.snapshot}) end
        end
    end
end

local pending_growth = {}
local function publish_growth_debug(player_id)
    if pending_growth[player_id] then return end
    local token = {}
    pending_growth[player_id] = token
    scheduler.after(0.1, function()
        if pending_growth[player_id] ~= token then return end
        pending_growth[player_id] = nil
        publish_debug(player_id)
    end, "lumberjack_publish_growth_debug_" .. tostring(player_id))
end

function M.init()
    for _, subscription in ipairs(subscriptions) do event_bus.unsubscribe(subscription) end
    subscriptions = {}
    hero_authority = {}
    for player_id in pairs(pending_growth) do
        scheduler.cancel("lumberjack_publish_growth_debug_" .. tostring(player_id))
    end
    pending_growth = {}
    debug_state = {}
    subscribe(events.HERO_COMBAT_STATS_CHANGED, publish)
    subscribe(events.UNIT_COMBAT_STATS_CHANGED, on_unit_combat_stats_changed)
    subscribe(events.HERO_SUMMONED, on_hero_summoned)
    subscribe(events.HERO_REMOVED, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        local cached = player_id and hero_authority[player_id]
        if cached and cached.unit == payload.unit then hero_authority[player_id] = nil end
        local current = player_id and debug_state[player_id]
        if not current or current.unit ~= payload.unit then return end
        debug_state[player_id], pending_growth[player_id] = nil, nil
        scheduler.cancel("combat_debug_damage_" .. tostring(player_id))
        scheduler.cancel("lumberjack_publish_growth_debug_" .. tostring(player_id))
        publish_debug(player_id)
    end)
    subscribe(events.COMBAT_DAMAGE_RESOLVED, on_damage)
    subscribe(events.TECHNOLOGY_CHANGED, on_technology_changed)
    subscribe(events.TECHNOLOGY_STATS_CHANGED, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        if player_id == nil then return end
        debug_state[player_id] = debug_state[player_id] or {
            entindex = -1,
            total_damage = 0,
            last_damage = 0,
            hit_count = 0,
            skill_total_damage = 0,
            skill_last_damage = 0,
            skill_hit_count = 0,
            skill_last_ability_name = "",
            levels = {},
        }
        if payload.changed_section == "lumberjack" then
            publish_growth_debug(player_id)
        else
            publish_debug(player_id)
        end
    end)
end

return M
