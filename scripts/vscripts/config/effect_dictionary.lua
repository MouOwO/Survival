-- 手工维护的效果协议。未登记的 effect_type 必须拒绝执行（fail-closed）。
local M = {}

M.unknown_policy = {
    enabled = false,
    action = "reject",
    error = "unknown_effect_type",
}

M.definitions = {
    attack_flat = { value_type = "number", target = "owner_hero", mode = "snapshot", parameters = { "value", "source" }, stacking = "replace_by_source" },
    attack_speed_pct = { value_type = "percent", target = "owner_hero", mode = "snapshot", parameters = { "value", "source" }, stacking = "replace_by_source" },
    armor_flat = { value_type = "number", target = "owner_hero", mode = "snapshot", parameters = { "value", "source" }, stacking = "replace_by_source" },
    health_flat = { value_type = "number", target = "owner_hero", mode = "snapshot", parameters = { "value", "source" }, stacking = "replace_by_source" },
    all_attributes_flat = { value_type = "number", target = "owner_hero", mode = "snapshot", parameters = { "value", "source" }, stacking = "replace_by_source" },
    lifesteal_pct = { value_type = "percent", target = "owner_hero", mode = "damage_conversion", parameters = { "value", "source" }, stacking = "replace_by_source" },
    critical_chance_pct = { value_type = "percent", target = "owner_hero", mode = "proc_chance", parameters = { "probability", "source" }, stacking = "replace_by_source" },
    critical_multiplier = { value_type = "number", target = "owner_hero", mode = "damage_multiplier", parameters = { "multiplier", "source" }, stacking = "replace_by_source" },
    attack_gain_on_attack = { value_type = "number", target = "owner_hero", mode = "growth", event = "normal_attack_landed", parameters = { "value", "stacking", "source" }, stacking = "add_per_event" },
    attack_gain_on_player_kill = { value_type = "number", target = "owner_hero", mode = "growth", event = "valid_enemy_death", attribution = "owner_player", parameters = { "value", "stacking", "source" }, stacking = "add_per_event" },
    attributes_gain_on_attack = { value_type = "number", target = "owner_hero", mode = "growth", event = "normal_attack_landed", parameters = { "value", "stacking", "source" }, stacking = "add_per_event" },
    aura_attribute_damage = { value_type = "object", target = "nearby_enemies", mode = "periodic", parameters = { "range", "multiplier", "internal_cooldown", "stacking", "source" }, stacking = "single_aura_per_source" },
    proc_attribute_damage = { value_type = "object", target = "nearby_enemies", mode = "proc", event = "normal_attack_landed", parameters = { "probability", "range", "multiplier", "internal_cooldown", "stacking", "source" }, stacking = "independent_proc_per_source" },
}

function M.get(effect_type)
    return M.definitions[effect_type] or M.unknown_policy
end

function M.is_supported(effect_type)
    return M.definitions[effect_type] ~= nil
end

return M
