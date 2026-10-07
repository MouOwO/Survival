-- Read-only static bonus arithmetic. Growth counters never enter these inputs.
local health_projection = require("systems/building_health_projection")
local M = {}
local function number(value) return tonumber(value) or 0 end
function M.tower(base, tech, permanent)
    tech, permanent = tech or {}, permanent or {}
    local flat = number(tech.attack_flat) + number(permanent.tower_attack_flat)
    local pct = number(tech.attack_bonus_pct) + number(permanent.tower_attack_bonus_pct)
    return {attack_bonus=(base+flat)*(1+pct/100)-base, attack_pct=pct, attack_flat=flat,
        attack_technology_flat=number(tech.attack_flat), attack_technology_pct=number(tech.attack_bonus_pct),
        attack_permanent_flat=number(permanent.tower_attack_flat), attack_permanent_pct=number(permanent.tower_attack_bonus_pct)}
end
function M.wall(base_health, base_armor, tech, permanent, rogue_health)
    tech, permanent = tech or {}, permanent or {}
    local pct = number(tech.health_bonus_pct) + number(tech.technology_health_bonus_pct)
        + number(permanent.wall_health_bonus_pct)
    local health = health_projection.maximum_with_flat_bonus(base_health,pct,
        number(rogue_health)+number(permanent.wall_initial_health))
    return {health_bonus=health-base_health, health_pct=pct,
        health_technology_pct=number(tech.health_bonus_pct)+number(tech.technology_health_bonus_pct),
        health_permanent_pct=number(permanent.wall_health_bonus_pct),
        health_permanent_flat=number(permanent.wall_initial_health), health_talent_flat=number(rogue_health),
        armor_technology_flat=number(tech.technology_armor_bonus)*3,
        armor_permanent_flat=number(permanent.wall_armor)+number(permanent.team_hero_wall_armor_bonus),
        armor_permanent_pct=number(permanent.wall_armor_bonus_pct),
        armor_pct=number(permanent.wall_armor_bonus_pct),
        armor_bonus=number(tech.technology_armor_bonus)*3+number(permanent.wall_armor)
            +number(permanent.team_hero_wall_armor_bonus)+base_armor*number(permanent.wall_armor_bonus_pct)/100}
end
return M
