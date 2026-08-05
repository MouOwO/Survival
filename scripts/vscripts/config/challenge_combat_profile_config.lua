local generated = require("config/generated/challenge_combat_profiles")

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

function M.resolve(member_id, difficulty_id)
    local profiles = M.by_member[tostring(member_id or "")]
    if not profiles then return nil, nil end
    local profile = profiles[tostring(difficulty_id or "")]
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