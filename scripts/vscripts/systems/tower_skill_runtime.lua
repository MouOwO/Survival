local skill_config = require("config/generated/tower_skill_definitions")
local M = {}
local active = {}

local function valid(unit)
    return unit and not unit:IsNull()
end

local function find(skill_id)
    for _, row in ipairs(skill_config.rows) do
        if row.skill_id == skill_id then return row end
    end
    return nil
end

function M.apply(unit, skill_ids)
    if not valid(unit) then return end
    active[unit:entindex()] = {}
    for _, skill_id in ipairs(skill_ids or {}) do
        local row = find(skill_id)
        if row and row.enabled then
            active[unit:entindex()][skill_id] = row
        end
    end
end

function M.get(unit)
    return valid(unit) and active[unit:entindex()] or {}
end

function M.get_skill(unit, skill_id)
    local skills = M.get(unit)
    return skills[skill_id]
end

return M
