-- One critical rule for native tower attacks and scripted replacement hits.
local event_bus = require("core/event_bus")
local events = require("core/events")
local tower_skills = require("systems/tower_skill_runtime")
local tree_damage_rules = require("systems/tree_damage_rules")
local M = {}
local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive() and not tree_damage_rules.is_tree(unit)
end
function M.roll(tower, target)
    if not valid(target) then return 1, nil end
    local special = event_bus.request(events.TOWER_CRITICAL_QUERY, {
        tower = tower,
        target = target,
        skills = tower_skills.get(tower),
    })
    local multiplier = special and tonumber(special.multiplier_pct) or 0
    local source = special and special.source or nil
    local inherited_chance = math.max(
        0, tonumber(tower.survival_inherited_critical_chance_pct) or 0
    )
    if multiplier <= 100 and inherited_chance > 0
        and RandomFloat(0, 100) < inherited_chance then
        multiplier = math.max(
            100,
            tonumber(tower.survival_inherited_critical_damage_pct) or 200
        )
        source = "monkey_king_r"
    end
    local research_chance = math.max(
        0, tonumber(tower.survival_super_tower_crit_chance) or 0
    )
    if RandomFloat(0, 100) < research_chance and multiplier < 200 then
        multiplier = math.max(200,
            tonumber(tower.survival_gameplay_critical_damage_pct) or 200)
        source = "research_critical"
    end
    return multiplier > 100 and multiplier / 100 or 1, source
end

return M
