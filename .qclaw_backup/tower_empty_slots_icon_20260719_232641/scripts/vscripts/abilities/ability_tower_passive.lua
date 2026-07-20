local M = class({})

function M:GetBehavior()
    return DOTA_ABILITY_BEHAVIOR_PASSIVE
end

function M:GetManaCost()
    return 0
end

_G.ability_tower_passive = M
return M
