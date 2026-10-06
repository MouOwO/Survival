-- Shared target policy for native attacks and the remaining shots in a burst.
local combat = require("config/tower_combat_rules")
local trees = require("systems/tree_damage_rules")
local air = require("systems/anti_air_rules")
local M = {}
local function legal(tower, target, excluded)
    return target ~= excluded and target and not target:IsNull() and target:IsAlive()
        and not trees.is_tree(target) and target:GetTeamNumber() ~= tower:GetTeamNumber()
        and air.can_attack(tower, target)
end

local function squared_distance(left, right)
    local dx, dy = left.x-right.x, left.y-right.y
    return dx*dx + dy*dy
end

function M.in_range(tower, target, extra_range)
    if not target or target:IsNull() then return false end
    local range = combat.current_attack_range(tower) + (extra_range or 0)
    return squared_distance(target:GetAbsOrigin(), tower:GetAbsOrigin()) <= range*range
end

function M.valid(tower, target, excluded)
    return legal(tower, target, excluded) and M.in_range(tower, target)
end

function M.select(tower, excluded)
    local range = combat.current_attack_range(tower)
    local range_squared = range*range
    local origin = tower:GetAbsOrigin()
    local units = FindUnitsInRadius(tower:GetTeamNumber(), origin, nil,
        range, DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO+DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_ANY_ORDER, false)
    local best, best_distance, dummy, dummy_distance
    for _, target in ipairs(units or {}) do
        if legal(tower,target,excluded) then
            local position = target:GetAbsOrigin()
            local score = squared_distance(position, origin)
            if score <= range_squared then
                if target.survival_is_training_dummy then
                    if not dummy_distance or score < dummy_distance then
                        dummy, dummy_distance = target, score
                    end
                elseif not best_distance or score < best_distance
                    or (score == best_distance and target:entindex() < best:entindex()) then
                    best, best_distance = target, score
                end
            end
        end
    end
    return best or dummy
end
-- Compatibility for existing live modifier instances during a Lua reload.
M.closest = M.select
return M
