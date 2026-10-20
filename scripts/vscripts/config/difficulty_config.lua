local progression_rules = require("config/mode_progression")
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
function M.is_unlocked(difficulty_id, progression, mode_id)
    if not M.get(difficulty_id) then return false end
    mode_id = mode_id or type(progression) == "table" and progression.mode_id
    local advanced = progression_rules.difficulty_unlocked(mode_id, difficulty_id, progression)
    if advanced ~= nil then return advanced end
    local number = tonumber(difficulty_id:match("^N(%d+)$"))
    if not number then return false end
    if number <= 5 then return true end
    local counts = type(progression) == "table" and progression.loaded == true
        and progression.clear_counts or nil
    local count = type(counts) == "table" and counts["n" .. (number - 1)] or nil
    return type(count) == "number" and count == count and count < math.huge
        and count >= 1 and count == math.floor(count)
end

function M.client_options(progression, mode_id)
    mode_id = mode_id or type(progression) == "table" and progression.mode_id
    local advanced_name = ({rich="丰饶模式", cold="极寒模式", scourge="天灾模式"})[mode_id]
    local recorded = (mode_id == "cold" or mode_id == "scourge") and require("config/recorded_mode_balance") or nil
    local options = {}
    for _, definition in ipairs(M.rows) do
        if definition.enabled ~= false then
            local unlocked = M.is_unlocked(definition.difficulty_id, progression, mode_id)
            local number = tonumber(definition.difficulty_id:match("^N(%d+)$")) or 1
            local hint = progression_rules.parent_mode(mode_id)
                and (not progression_rules.entry_unlocked(mode_id, progression)
                    and progression_rules.entry_hint(mode_id)
                    or progression_rules.difficulty_hint(mode_id, definition.difficulty_id))
                or ("通关 N" .. (number - 1) .. " 解锁")
            local source_id = recorded and recorded.source_difficulty(mode_id, definition.difficulty_id)
                or advanced_name and definition.difficulty_id or definition.source_difficulty_id
            local temporary = recorded and source_id ~= definition.difficulty_id or false
            local description = advanced_name
                and (temporary and recorded.configuration_note(mode_id, definition.difficulty_id)
                    or ("使用" .. advanced_name .. " " .. definition.difficulty_id .. " 独立波次与怪物属性。"))
                or definition.description
            options[#options + 1] = {
                difficulty_id = definition.difficulty_id,
                display_name = definition.display_name,
                subtitle = definition.subtitle,
                description = description,
                source_difficulty_id = source_id,
                temporary_config = temporary and 1 or 0,
                total_waves = definition.total_waves,
                unlocked = unlocked and 1 or 0,
                unlock_hint = unlocked and "" or hint,
            }
        end
    end
    return options
end

return M
