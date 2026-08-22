local M = {}

function M.configured_base_attack_time(definition, fallback)
    local attacks_per_second = tonumber(definition and definition.attack_speed) or 0
    if attacks_per_second > 0 then return 1 / attacks_per_second end
    return math.max(0.1, tonumber(fallback) or 2)
end

function M.attacks_per_second(base_attack_time, attack_speed_pct)
    local interval = math.max(0.1, tonumber(base_attack_time) or 2)
    local speed_multiplier = math.max(0.01,
        1 + (tonumber(attack_speed_pct) or 0) / 100)
    return speed_multiplier / interval
end

function M.damage_multiplier(definition, global_multiplier)
    return (tonumber(definition and definition.damage_multiplier) or 1)
        * (tonumber(global_multiplier) or 1)
end

function M.engine_base_damage(logical_damage, damage_multiplier)
    return (tonumber(logical_damage) or 0)
        * (tonumber(damage_multiplier) or 1)
end

function M.strength_health_bonus(strength, health_per_point)
    return (tonumber(strength) or 0) * (tonumber(health_per_point) or 0)
end

function M.intellect_attack_bonus(intellect, attack_per_point)
    return (tonumber(intellect) or 0) * (tonumber(attack_per_point) or 0)
end

return M