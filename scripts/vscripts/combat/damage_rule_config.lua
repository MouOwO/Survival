local M = {}

M.debug_enabled = true
M.maximum_recursion_depth = 6
M.minimum_post_multiplier = 0.10
M.global_post_bonus_pct = 0.0
M.boss_rules = {
    enabled = true,
    default_damage_taken_multiplier = 1.0,
}
M.source_kind_rules = {
    reflection = { can_trigger_reflection = false },
    dot = { can_crit = false },
    splash = { can_trigger_splash = false },
}

return M
