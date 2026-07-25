local config = require("config/research_technology_config")

local M = {}

local COPY = {
    ["RS-01"] = { scope = "所有伐木工", note = "即时刷新当前与后续训练的伐木工。" },
    ["RS-02"] = { scope = "所有伐木工", note = "攻击间隔最低为0.05秒。" },
    ["RS-03"] = { scope = "所有伐木工", note = "采集暴击时获得2倍木材。" },
    ["RS-04"] = { scope = "所有伐木工", note = "增加每次有效攻击大树获得的木材。" },
    ["RS-05"] = { scope = "所有伐木工", note = "与伐木效率叠加。" },
    ["RS-06"] = { scope = "所有防御塔", note = "即时刷新当前与后续建造的防御塔。" },
    ["RS-07"] = { scope = "所有防御塔", note = "与防御塔强化叠加。" },
    ["RS-08"] = { scope = "所有城墙", note = "提升基础最大生命，刷新时保持当前生命比例。" },
    ["RS-09"] = { scope = "所有城墙", note = "与墙强化叠加，刷新时保持当前生命比例。" },
    ["ARS-01"] = { scope = "所有伐木工", note = "仅在有效攻击大树后增加永久攻击力。" },
    ["ARS-02"] = { scope = "所有伐木工", note = "每次命中大树叠加减甲，大树护甲最低为100。" },
    ["ARS-03"] = { scope = "所有城墙", note = "两项生命加成共同计入基础最大生命，刷新时保持当前生命比例。" },
    ["ARS-04"] = { scope = "所有城墙", note = "使用Dota实际护甲；生命刷新时保持当前比例。" },
    ["ARS-05"] = { scope = "所有防御塔", note = "与普通及高级防御塔强化叠加。" },
    ["ARS-06"] = { scope = "所有防御塔", note = "同时提高攻击距离和自动搜索范围。" },
    ["ARS-07"] = { scope = "所有防御塔与英雄", note = "科技暴击造成2倍伤害。" },
    ["ARS-08"] = { scope = "所有英雄", note = "由统一伤害结算在最终阶段生效。" },
    ["ARS-09"] = { scope = "所有英雄", note = "每次普通攻击命中敌人时叠加减甲。" },
    ["ARS-10"] = { scope = "所有英雄", note = "按英雄基础攻击与武器攻击之和计算。" },
}

local EFFECTS = {
    lumberjack_attack_speed_pct = { label = "攻击速度", kind = "percent" },
    lumberjack_attack_interval_reduction = {
        label = "攻击间隔缩短", kind = "seconds", absolute = true,
    },
    lumberjack_wood_crit_chance_pct = { label = "采集暴击率", kind = "percent" },
    lumberjack_wood_per_gather_flat = { label = "每次采集木材", kind = "flat" },
    lumberjack_wood_per_gather_advanced_flat = { label = "每次采集木材", kind = "flat" },
    lumberjack_attack_growth_per_hit = { label = "每次有效攻击永久攻击", kind = "flat" },
    lumberjack_wood_per_gather_growth_flat = { label = "每次采集木材", kind = "flat" },
    tree_armor_shred_per_hit = { label = "每次攻击大树减甲", kind = "flat", absolute = true },
    tower_attack_flat = { label = "攻击力", kind = "flat" },
    tower_attack_advanced_flat = { label = "攻击力", kind = "flat" },
    tower_attack_super_flat = { label = "攻击力", kind = "flat" },
    tower_attack_range_flat = { label = "攻击距离", kind = "flat" },
    tower_crit_chance_pct = { label = "防御塔暴击率", kind = "percent" },
    tower_attack_bonus_pct = { label = "防御塔攻击力", kind = "percent" },
    hero_crit_chance_pct = { label = "英雄暴击率", kind = "percent" },
    hero_attack_bonus_pct = { label = "英雄攻击力", kind = "percent" },
    wall_health_pct = { label = "最大生命", kind = "percent" },
    wall_health_advanced_pct = { label = "最大生命", kind = "percent" },
    wall_health_super_pct = { label = "最大生命", kind = "percent" },
    wall_health_bonus_pct = { label = "额外最大生命", kind = "percent" },
    wall_armor_flat = { label = "护甲", kind = "flat" },
    hero_final_damage_pct = { label = "最终伤害", kind = "percent" },
    hero_armor_shred_flat = { label = "每次攻击减甲", kind = "flat" },
}

local function compact_number(value)
    value = math.abs(tonumber(value) or 0)
    if math.abs(value - math.floor(value + 0.5)) < 0.000001 then
        return tostring(math.floor(value + 0.5))
    end
    local text = string.format("%.4f", value)
    return (text:gsub("0+$", ""):gsub("%.$", ""))
end

local function format_value(value, kind)
    if kind == "percent" then
        return compact_number((tonumber(value) or 0) * 100) .. "%"
    end
    if kind == "seconds" then
        return compact_number(value) .. "秒"
    end
    return compact_number(value)
end

local function contribution(effect, level)
    if effect.mode == "constant" then
        return level > 0 and effect.value_per_level or 0
    end
    return (tonumber(effect.value_per_level) or 0) * level
end

local function effect_parts(definition, level, per_level)
    local parts = {}
    for _, effect in ipairs(definition.effects or {}) do
        local metadata = EFFECTS[effect.key]
        if metadata then
            local value = per_level and effect.value_per_level
                or contribution(effect, level)
            if metadata.absolute then value = math.abs(value) end
            parts[#parts + 1] = metadata.label .. "+"
                .. format_value(value, metadata.kind)
        end
    end
    return parts
end

function M.effect_summary(definition, level)
    definition = definition or {}
    level = math.max(0, tonumber(level) or 0)
    if level == 0 then return "尚未生效" end
    return table.concat(effect_parts(definition, level, false), "，")
end

function M.build(definition, current_level, target_level)
    local copy = COPY[definition.tech_id] or { scope = "对应单位", note = "" }
    current_level = math.max(0, tonumber(current_level) or 0)
    target_level = math.max(current_level, tonumber(target_level) or current_level)
    local per_level = table.concat(effect_parts(definition, 1, true), "，")
    local text = copy.scope .. "：每级" .. per_level .. "。"
        .. "当前Lv." .. tostring(current_level) .. "："
        .. M.effect_summary(definition, current_level) .. "。"
        .. "升级至Lv." .. tostring(target_level) .. "："
        .. M.effect_summary(definition, target_level) .. "。"
    return text .. copy.note
end

function M.condition_text(definition)
    local required = definition.prerequisite or {}
    local parts = {}
    if required.tech_id then
        local prerequisite = config.by_id[required.tech_id]
        parts[#parts + 1] = (prerequisite and prerequisite.display_name
            or required.tech_id) .. " Lv." .. tostring(required.required_level or 0)
    end
    if (tonumber(required.reincarnation_level) or 0) > 0 then
        parts[#parts + 1] = "完成" .. tostring(required.reincarnation_level) .. "转"
    end
    return #parts > 0 and table.concat(parts, " · ") or "无"
end

function M.fields(definition, current_level, target_level)
    return {
        { label = "科技编号", value = definition.tech_id },
        { label = "等级上限", value = definition.max_level },
        { label = "当前累计", value = M.effect_summary(definition, current_level) },
        { label = "升级后累计", value = M.effect_summary(definition, target_level) },
    }
end

return M