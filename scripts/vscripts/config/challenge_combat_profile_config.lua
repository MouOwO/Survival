local generated = require("config/generated/challenge_combat_profiles")
local difficulties = require("config/difficulty_config")

local M = {
    by_member = {},
}

for _, row in ipairs(generated.rows or {}) do
    if row.enabled ~= false then
        local member_id = tostring(row.member_id or "")
        local difficulty_id = tostring(row.difficulty_id or "")
        if member_id ~= "" and difficulty_id ~= "" then
            M.by_member[member_id] = M.by_member[member_id] or {}
            M.by_member[member_id][difficulty_id] = row
        end
    end
end

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

function M.resolve(member_id, difficulty_id, mode_id)
    local profiles = M.by_member[tostring(member_id or "")]
    if not profiles then return nil, nil end
    if mode_id == "rich" and (difficulty_id == "N2" or difficulty_id == "N3") then
        local rich = require("config/generated/rich_monster_profiles")
        local difficulty = rich.difficulties[difficulty_id]
        local profile = difficulty and difficulty.encounters[tostring(member_id)]
        if not profile then
            return nil, "rich_monster_profile_missing:"
                .. tostring(member_id) .. ":" .. tostring(difficulty_id)
        end
        -- Rich profiles contain final panel values, including any explicit
        -- estimate. They never pass through the ordinary difficulty ratios.
        return clone(profile), nil
    end
    local profile = profiles[tostring(difficulty_id or "")]
    if not profile then
        -- N6-N10 explicitly reuse N5 balance while testing unlocks. Resolve
        -- the same source difficulty as waves instead of rejecting every room.
        local difficulty = difficulties.get(difficulty_id)
        local source = difficulty and difficulty.source_difficulty_id
        if source and source ~= difficulty_id then profile = profiles[source] end
    end
    if not profile then
        return nil, "challenge_combat_profile_missing:"
            .. tostring(member_id) .. ":" .. tostring(difficulty_id)
    end
    return profile, nil
end

function M.has_member(member_id)
    return M.by_member[tostring(member_id or "")] ~= nil
end

return M
