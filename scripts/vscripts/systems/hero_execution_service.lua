-- Judgment is resolved after actual hero damage, never through aura scans.
local tree_rules = require('systems/tree_damage_rules')
local M = {}
local executing = setmetatable({}, {__mode = 'k'})
local function valid(unit)
    return unit and unit.IsNull and not unit:IsNull()
end
function M.try_execute(payload, threshold)
    threshold = tonumber(threshold) or 0
    if threshold ~= threshold or threshold <= 0 or threshold > 100 then return false end
    local hero = payload and payload.owner_hero
    local target = payload and payload.target
    if not valid(hero) or payload.attacker ~= hero or not valid(target)
        or hero == target or executing[target] then return false end
    local damage = tonumber(payload.final_damage) or 0
    if damage ~= damage or damage <= 0 or damage == math.huge then return false end
    if hero.IsIllusion and hero:IsIllusion() then return false end
    if hero.survival_visual_only or hero.survival_is_native_wearable_visual then return false end
    if not target.IsAlive or not target:IsAlive()
        or not hero.GetTeamNumber or not target.GetTeamNumber
        or hero:GetTeamNumber() == target:GetTeamNumber() then return false end
    -- Resource trees and training props are not combat enemies.
    if tree_rules.is_tree(target) or target.survival_training_owner_player_id ~= nil
        or target.survival_is_building == true
        or (target.IsBuilding and target:IsBuilding()) then return false end
    if target.HasModifier and (target:HasModifier('modifier_rogue_training_dummy')
        or target:HasModifier('modifier_endless_training_target')) then return false end
    if not target.GetHealth or not target.GetMaxHealth or not target.Kill then return false end
    local health, maximum = tonumber(target:GetHealth()), tonumber(target:GetMaxHealth())
    if not health or not maximum or health ~= health or maximum ~= maximum
        or maximum <= 0 or maximum == math.huge or health <= 0
        or health / maximum >= threshold / 100 then return false end
    -- Do not exclude bosses. Kill supplies the attacking hero to the engine's
    -- normal entity_killed path, preserving boss drops, archives and victory.
    -- ForceKill/UTIL_Remove would bypass parts of that path in this project.
    executing[target] = true
    local ok, reason = pcall(target.Kill, target, nil, hero)
    executing[target] = nil
    if not ok then error(reason) end
    return not target:IsAlive()
end
return M
