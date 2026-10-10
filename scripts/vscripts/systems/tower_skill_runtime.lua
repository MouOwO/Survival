local skill_config = require("config/generated/tower_skill_definitions")
local M = {}

local function valid(unit)
    return unit and not unit:IsNull()
end

local function find(skill_id)
    if skill_config.by_id then return skill_config.by_id[skill_id] end
    for _, row in ipairs(skill_config.rows) do
        if row.skill_id == skill_id then return row end
    end
    return nil
end

function M.apply(unit, skill_ids)
    if not valid(unit) then return end
    local skills = {}
    for _, skill_id in ipairs(skill_ids or {}) do
        local row = find(skill_id)
        if row and row.enabled then
            skills[skill_id] = row
        end
    end
    -- Own the snapshot on the entity. Recycled entity indexes must never
    -- inherit a retired tower's skills, and dead entities need no global row.
    unit.survival_tower_skill_snapshot = skills
    unit.survival_tower_skill_matches = {}
end

function M.get(unit)
    if not valid(unit) then return {} end
    if not unit.survival_tower_skill_snapshot then
        unit.survival_tower_skill_snapshot = {}
        unit.survival_tower_skill_matches = {}
    end
    -- Callers read this snapshot; changes go through apply to invalidate matches.
    return unit.survival_tower_skill_snapshot
end

function M.matching(unit, prefix)
    if not valid(unit) then return nil end
    local skills = M.get(unit)
    local matches = unit.survival_tower_skill_matches
    local cached = matches[prefix]
    if cached ~= nil then return cached or nil end
    for _, row in pairs(skills) do
        if row.skill_id and string.match(row.skill_id, "^" .. prefix) then
            matches[prefix] = row
            return row
        end
    end
    matches[prefix] = false
    return nil
end

function M.get_skill(unit, skill_id)
    local skills = M.get(unit)
    return skills[skill_id]
end

return M
