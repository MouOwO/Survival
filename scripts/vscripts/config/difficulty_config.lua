local M = {
    default_id = "N1",
    rows = {
        {
            difficulty_id = "N1",
            display_name = "N1 标准难度",
            subtitle = "25 波",
            description = "标准怪物属性与标准波次。",
            source_difficulty_id = "N1",
            total_waves = 25,
            stat_multiplier = 1.0,
            enabled = true,
            wave_overrides = {},
        },
        {
            difficulty_id = "N2",
            display_name = "N2 挑战难度",
            subtitle = "30 波",
            description = "生命、攻击和护甲提升至 1.5 倍；第25至30波进一步强化。",
            source_difficulty_id = "N1",
            total_waves = 30,
            stat_multiplier = 1.5,
            enabled = true,
            wave_overrides = {
                {
                    target_start = 25,
                    target_end = 30,
                    source_start = 20,
                    stat_multiplier = 2.0,
                },
            },
        },
        -- Reserved definitions stay disabled until their balance rules are
        -- finalized. Enabling them requires no wave-system or Panorama change.
        {
            difficulty_id = "N3",
            display_name = "N3 高难度",
            subtitle = "30 波",
            description = "使用N3独立波次属性、数量与Boss配置。",
            source_difficulty_id = "N3",
            total_waves = 30,
            stat_multiplier = 1.0,
            enabled = true,
            wave_overrides = {},
        },
        {
            difficulty_id = "N4",
            display_name = "N4",
            subtitle = "开发中",
            description = "预留难度。",
            source_difficulty_id = "N1",
            total_waves = 30,
            stat_multiplier = 1.0,
            enabled = false,
            wave_overrides = {},
        },
    },
}

M.by_id = {}
for _, definition in ipairs(M.rows) do
    M.by_id[definition.difficulty_id] = definition
end

function M.get(difficulty_id)
    local definition = M.by_id[difficulty_id]
    if not definition or definition.enabled == false then return nil end
    return definition
end

function M.client_options()
    local options = {}
    for _, definition in ipairs(M.rows) do
        if definition.enabled ~= false then
            options[#options + 1] = {
                difficulty_id = definition.difficulty_id,
                display_name = definition.display_name,
                subtitle = definition.subtitle,
                description = definition.description,
                total_waves = definition.total_waves,
            }
        end
    end
    return options
end

return M