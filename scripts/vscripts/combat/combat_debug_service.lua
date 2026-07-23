local M = {}
local config = nil

function M.init(rule_config)
    config = rule_config
end

function M.log(result)
    if not config or not config.debug_enabled or not result then return end
    print(string.format(
        "[CombatDamage] transaction_id=%s attacker=%s victim=%s source_kind=%s base_damage=%s pre_bonus=%s critical=%s critical_multiplier=%s submitted_damage=%s damage_type=%s engine_damage=%s post_multiplier=%s final_damage=%s recursion_depth=%s",
        tostring(result.transaction_id), tostring(result.attacker),
        tostring(result.victim), tostring(result.source_kind),
        tostring(result.base_damage), tostring(result.pre_bonus_pct),
        tostring(result.critical), tostring(result.critical_multiplier),
        tostring(result.submitted_damage), tostring(result.damage_type),
        tostring(result.engine_damage), tostring(result.post_multiplier),
        tostring(result.final_damage), tostring(result.recursion_depth)
    ))
end

return M
