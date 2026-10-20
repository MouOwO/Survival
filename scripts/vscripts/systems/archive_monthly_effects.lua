-- Extra monthly-pass effects are derived from the combat profile, never saved.
-- Expiry and entitlement refresh remove this layer without altering earned stats.
local work = require("config/generated/archive_work_items")
local calendar = require("systems/archive_calendar")
local M = {}
function M.project(profile)
    if not calendar.has_pass(profile) then return {} end
    local save = profile and profile.save or {}
    local online = save.archive and save.archive.online or {}
    local result = {}
    local function add(item, count)
        if item.enabled == false or count <= 0 then return end
        for index, field in ipairs(item.effect_ids or {}) do
            result[field] = (result[field] or 0) + count * (tonumber(item.effect_values[index]) or 0)
        end
    end
    for _, item in ipairs(work.rows) do
        local count = tonumber((online.work_levels or {})[item.item_id]) or 0
        add(item, math.min(item.max_level, math.max(0, math.floor(count))))
    end
    return result
end
return M
