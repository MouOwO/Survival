local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local technology_definitions = require("config/generated/technology_definitions")
local technology_effects = require("config/technology_effect_config")
local technology_stat_manager = require("systems/technology_stat_manager")
local combat_stat_projection = require("ui/combat_stat_projection")

local M = {}

local debug_state = {}

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
    CustomNetTables:SetTableValue(
        "survival_combat_stats",
        "player_" .. tostring(player_id),
        combat_stat_projection.for_ui(payload.snapshot)
    )
    -- NetTable is the single regular synchronization path. Selected-unit
    -- requests still use their direct response event for immediate feedback.
end

function M.init()
    debug_state = {}
    event_bus.subscribe(events.HERO_COMBAT_STATS_CHANGED, publish)
    event_bus.subscribe(events.HERO_SUMMONED, on_hero_summoned)
    event_bus.subscribe(events.COMBAT_DAMAGE_RESOLVED, on_damage)
    event_bus.subscribe(events.TECHNOLOGY_CHANGED, on_technology_changed)
    event_bus.subscribe(events.TECHNOLOGY_STATS_CHANGED, function(payload)
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
        publish_debug(player_id)
    end)
end

return M
