local M = {}

-- OnTakeDamage reports health removed in the victim's native health units.
-- Restore its logical damage before converting to the attacker's health units;
-- the damage filter has already restored any outgoing attack scale.
function M.calculate(attacker, victim, damage, percent)
    local victim_scale = math.max(1, tonumber(victim and victim.survival_endless_health_scale) or 1)
    local attacker_scale = math.max(1, tonumber(attacker and attacker.survival_endless_health_scale) or 1)
    return math.max(0, tonumber(damage) or 0) * math.max(0, tonumber(percent) or 0)
        / 100 * victim_scale / attacker_scale
end

return M
