-- Local functional edition of the video P016 privilege; no cosmetic promise.
local M = {radius=2000, friendly_armor=100, friendly_regen=1000, enemy_armor=-30}

function M.bonus(unit)
    return tonumber(unit and unit.survival_commerce_titan_armor) or 0
end

-- Custom War3 targets intentionally bypass native armor in DamageFilter.
-- Keep the temporary aura separate from persistent research/poison accumulators.
function M.custom_armor(unit, fallback)
    return (tonumber(unit and unit.survival_effective_war3_armor)
        or tonumber(unit and unit.survival_war3_armor)
        or tonumber(fallback) or 0) + M.bonus(unit)
end

function M.for_ui(snapshot, unit)
    if not snapshot or not unit then return snapshot end
    local bonus=M.bonus(unit)
    local previous=tonumber(snapshot.commerce_titan_armor) or 0
    if bonus==previous then return snapshot end
    local result={}
    for key,value in pairs(snapshot) do result[key]=value end
    result.armor=(tonumber(snapshot.armor) or 0)+bonus-previous
    result.commerce_titan_armor=bonus
    return result
end
return M
