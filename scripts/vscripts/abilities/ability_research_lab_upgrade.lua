local M = class({})

for _, ability_name in ipairs({
    "ability_research_lumberjack_speed",
    "ability_research_advanced_lumberjack_speed",
    "ability_research_lumberjack_crit",
    "ability_research_lumberjack_efficiency",
    "ability_research_advanced_lumberjack_efficiency",
    "ability_research_tower_attack",
    "ability_research_advanced_tower_attack",
    "ability_research_wall_health",
    "ability_research_advanced_wall_health",
    "ability_research_ars_01",
    "ability_research_ars_02",
    "ability_research_ars_03",
    "ability_research_ars_04",
    "ability_research_ars_05",
    "ability_research_ars_06",
    "ability_research_ars_07",
    "ability_research_ars_08",
    "ability_research_ars_09",
    "ability_research_ars_10",
}) do
    _G[ability_name] = M
end

function M:OnSpellStart()
    -- Creature building actions are dispatched by ui_request_router.
end

return M