local M = {
    default_id = "N1",
    rows = {
        {
            difficulty_id = "N1",
            display_name = "N1",
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
            display_name = "N2",
            subtitle = "30 波",
            description = "使用N2独立波次属性、数量与Boss配置。",
            source_difficulty_id = "N2",
            total_waves = 30,
            stat_multiplier = 1.0,
            enabled = true,
            wave_overrides = {},
        },
        {
            difficulty_id = "N3",
            display_name = "N3",
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
            subtitle = "30 波",
            description = "使用N4独立波次属性、数量与Boss配置。",
            source_difficulty_id = "N4",
            total_waves = 30,
            stat_multiplier = 1.0,
            enabled = true,
            wave_overrides = {},
        },
        {
            difficulty_id = "N5",
            display_name = "N5",
            subtitle = "30 波",
            description = "使用N5独立波次属性、数量与Boss配置。",
            source_difficulty_id = "N5",
            total_waves = 30,
            stat_multiplier = 1.0,
            enabled = true,
            wave_overrides = {},
        },
    },
}

-- N6-N10 currently have independent CSV copies of N5 for archive unlock testing.
for number = 6, 10 do
    M.rows[#M.rows + 1] = {
        difficulty_id = "N" .. number, display_name = "N" .. number, subtitle = "30 波",
        description = "当前使用N5的测试数值。", source_difficulty_id = "N5",
        total_waves = 30, stat_multiplier = 1.0, enabled = true, wave_overrides = {},
    }
end
M.by_id = {}
for _, definition in ipairs(M.rows) do
    M.by_id[definition.difficulty_id] = definition
end

function M.get(difficulty_id)
    local definition = M.by_id[difficulty_id]
    if not definition or definition.enabled == false then return nil end
    return definition
end

-- Progression is read from the authenticated permanent profile, even when the
-- selected mode suppresses archive bonuses. Client-supplied counts never enter
-- this function through the selection request.
function M.is_unlocked(difficulty_id, progression)
    if not M.get(difficulty_id) then return false end
    local number = tonumber(difficulty_id:match("^N(%d+)$"))
    if not number then return false end
    if number <= 5 then return true end
    local counts = type(progression) == "table" and progression.loaded == true
        and progression.clear_counts or nil
    local count = type(counts) == "table" and counts["n" .. (number - 1)] or nil
    return type(count) == "number" and count == count and count < math.huge
        and count >= 1 and count == math.floor(count)
end

function M.client_options(progression)
    local options = {}
    for _, definition in ipairs(M.rows) do
        if definition.enabled ~= false then
            local unlocked = M.is_unlocked(definition.difficulty_id, progression)
            local number = tonumber(definition.difficulty_id:match("^N(%d+)$")) or 1
            options[#options + 1] = {
                difficulty_id = definition.difficulty_id,
                display_name = definition.display_name,
                subtitle = definition.subtitle,
                description = definition.description,
                total_waves = definition.total_waves,
                unlocked = unlocked and 1 or 0,
                unlock_hint = unlocked and "" or ("通关 N" .. (number - 1) .. " 解锁"),
            }
        end
    end
    return options
end

return M
