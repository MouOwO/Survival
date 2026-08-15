local config = require("config/research_technology_config")
local armor_balance = require("config/armor_balance")

local M = {}
M.__index = M

local function empty_projection()
    return {
        wall = { health_bonus_pct = 0, technology_health_bonus_pct = 0,
            technology_armor_bonus = 0 },
        tower = { critical_chance_pct = 0, attack_flat = 0,
            attack_bonus_pct = 0, critical_damage_multiplier = 2,
            attack_speed_bonus_pct = 0, attacks_per_second_bonus = 0,
            attack_range_bonus = 0 },
        lumberjack = { attack_flat = 0, attack_gain_per_attack = 0,
            wood_per_hit_bonus = 0, attack_speed_bonus_pct = 0,
            attack_interval_flat = 0, critical_chance_pct = 0,
            armor_reduction_per_attack = 0 },
        hero = { attack_gain_per_second = 0, attributes_gain_per_second = 0,
            attack_flat = 0, damage_multiplier_bonus = 0,
            final_damage_bonus_pct = 0,
            attack_bonus_pct = 0, critical_chance_pct = 0,
            armor_reduction_per_attack = 0 },
    }
end

local function legacy_projection(values)
    local result = empty_projection()
    local function value(key) return tonumber(values[key]) or 0 end
    result.lumberjack.attack_speed_bonus_pct = value("lumberjack_attack_speed_pct") * 100
    result.lumberjack.attack_interval_flat = -value("lumberjack_attack_interval_reduction")
    result.lumberjack.critical_chance_pct = value("lumberjack_wood_crit_chance_pct") * 100
    result.lumberjack.wood_per_hit_bonus = value("lumberjack_wood_per_gather_flat")
        + value("lumberjack_wood_per_gather_advanced_flat")
        + value("lumberjack_wood_per_gather_growth_flat")
    result.lumberjack.attack_gain_per_attack = value("lumberjack_attack_growth_per_hit")
    result.lumberjack.armor_reduction_per_attack = value("tree_armor_shred_per_hit")
        + armor_balance.from_war3(-value("war3_tree_armor_shred_per_hit"))
    result.tower.attack_flat = value("tower_attack_flat")
        + value("tower_attack_advanced_flat") + value("tower_attack_super_flat")
    result.tower.attack_range_bonus = value("tower_attack_range_flat")
    result.tower.critical_chance_pct = value("tower_crit_chance_pct") * 100
    result.tower.attack_bonus_pct = value("tower_attack_bonus_pct") * 100
    result.wall.health_bonus_pct = (value("wall_health_pct")
        + value("wall_health_advanced_pct")) * 100
    result.wall.technology_health_bonus_pct = (value("wall_health_super_pct")
        + value("wall_health_bonus_pct")) * 100
    result.wall.technology_armor_bonus = value("wall_armor_flat")
        + armor_balance.from_war3(value("war3_wall_armor_flat"))
    result.hero.final_damage_bonus_pct = value("hero_final_damage_pct") * 100
    result.hero.attack_bonus_pct = value("hero_attack_bonus_pct") * 100
    result.hero.attack_flat = value("hero_attack_flat")
    result.hero.critical_chance_pct = value("hero_crit_chance_pct") * 100
    result.hero.armor_reduction_per_attack = value("hero_armor_shred_flat")
        + armor_balance.from_war3(value("war3_hero_armor_shred_flat"))
    return result
end

function M.new(repository)
    return setmetatable({ repository = repository, snapshots = {} }, M)
end

function M:Reset()
    self.snapshots = {}
end

function M:Recalculate(player_id)
    local values = {}
    local levels = self.repository:GetAllLevels(player_id)
    for _, definition in ipairs(config.technologies) do
        local level = tonumber(levels[definition.tech_id]) or 0
        for _, effect in ipairs(definition.effects) do
            local contribution = config.effect_value(effect, level)
            values[effect.key] = (values[effect.key] or 0) + contribution
        end
    end
    local snapshot = {
        levels = levels,
        values = values,
        legacy = legacy_projection(values),
    }
    local team = self.repository:GetTeam(player_id)
    if team ~= nil then self.snapshots[team] = snapshot end
    return snapshot
end

function M:Get(player_id)
    local team = self.repository:GetTeam(player_id)
    return team ~= nil and self.snapshots[team] or self:Recalculate(player_id)
end

return M