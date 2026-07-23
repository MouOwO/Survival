local M = {}

function M:Apply(context)
    if type(context) ~= "table" then return { ok = false, error = "invalid_context" } end
    if not context.attacker or context.attacker:IsNull()
        or not context.victim or context.victim:IsNull() then
        return { ok = false, error = "invalid_entity" }
    end
    if type(context.damage) ~= "number" or context.damage < 0 then
        return { ok = false, error = "invalid_damage" }
    end
    ApplyDamage({
        attacker = context.attacker,
        victim = context.victim,
        ability = context.ability,
        damage = context.damage,
        damage_type = context.damage_type,
        damage_flags = context.damage_flags,
    })
    return { ok = true }
end

return M
