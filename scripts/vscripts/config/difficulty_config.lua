local progression_rules = require("config/mode_progression")
local release = require("config/mode_release_config")
local rules = require("config/human_monster_rules")
local names = { standard="常规", pure="纯净", rich="丰饶", cold="极寒",
    scourge="天灾", ruins="归墟", celestial="天域" }
local M = { default_id = "N1", rows_by_mode = {}, by_mode = {} }
for mode_id, values in pairs(rules.data.modes) do
    local rows, by_id = {}, {}
    for number = 1, #values do
        local value, id = values[number], "N" .. number
        local definition = { difficulty_id=id, display_name=id, mode_id=mode_id,
            subtitle=tostring(value.total_waves) .. " 波",
            description="使用" .. names[mode_id] .. "模式 " .. id .. " 的属性与出怪规则。",
            source_difficulty_id=id, total_waves=value.total_waves,
            stat_multiplier=1, enabled=true, wave_overrides={} }
        rows[#rows + 1], by_id[id] = definition, definition
    end
    M.rows_by_mode[mode_id], M.by_mode[mode_id] = rows, by_id
end
M.rows, M.by_id = M.rows_by_mode.standard, M.by_mode.standard

function M.get(difficulty_id, mode_id)
    local rows = M.by_mode[mode_id or "standard"]
    return rows and rows[difficulty_id] or nil
end

-- Progression is read from the authenticated permanent profile, even when the
-- selected mode suppresses archive bonuses. Client-supplied counts never enter
-- this function through the selection request.
function M.is_unlocked(difficulty_id, progression, mode_id)
    mode_id = mode_id or type(progression) == "table" and progression.mode_id or "standard"
    if not M.get(difficulty_id, mode_id) then return false end
    -- The standalone settlement worker never loads this engine-only service.
    local mode_test = package.loaded["debug/mode_unlock_test"]
    if mode_test and mode_test.is_enabled() then return true end
    if release.is_difficulty_open(mode_id) then
        return progression_rules.entry_unlocked(mode_id, progression) == true
    end
    return progression_rules.difficulty_unlocked(mode_id, difficulty_id, progression) == true
end

function M.client_options(progression, mode_id)
    mode_id = mode_id or type(progression) == "table" and progression.mode_id or "standard"
    local options = {}
    for _, definition in ipairs(M.rows_by_mode[mode_id] or {}) do
        if definition.enabled ~= false then
            local unlocked = M.is_unlocked(definition.difficulty_id, progression, mode_id)
            local number = tonumber(definition.difficulty_id:match("^N(%d+)$")) or 1
            local hint = progression_rules.parent_mode(mode_id)
                and (not progression_rules.entry_unlocked(mode_id, progression)
                    and progression_rules.entry_hint(mode_id)
                    or progression_rules.difficulty_hint(mode_id, definition.difficulty_id))
                or ("通关 N" .. (number - 1) .. " 解锁")
            options[#options + 1] = {
                difficulty_id = definition.difficulty_id,
                display_name = definition.display_name,
                subtitle = definition.subtitle,
                description = definition.description,
                source_difficulty_id = definition.source_difficulty_id,
                temporary_config = 0,
                total_waves = definition.total_waves,
                unlocked = unlocked and 1 or 0,
                unlock_hint = unlocked and "" or hint,
            }
        end
    end
    return options
end

return M
