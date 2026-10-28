local M = {}

-- Only formal wave units are restricted. Heroes, towers and separate
-- challenge enemies keep their existing combat rules.
function M.can_attack(attacker, target)
    if not attacker or attacker.survival_is_wave_monster ~= true then return true end
    return target ~= nil and not target:IsNull() and target:IsAlive()
        and target.survival_building_id == "wall"
end

return M
