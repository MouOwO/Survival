package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local rows = require("config/generated/wave_definitions").rows
local finder = require("systems/wave_special_target")

local function waves_for(difficulty_id)
    local waves = {}
    local maximum = 0
    for _, row in ipairs(rows or {}) do
        if row.enabled ~= false and row.difficulty_id == difficulty_id then
            local number = tonumber(row.wave_number)
            waves[number] = waves[number] or { batches = {} }
            waves[number].batches[#waves[number].batches + 1] = row
            maximum = math.max(maximum, number)
        end
    end
    return waves, maximum
end

local n1, n1_maximum = waves_for("N1")
local wave_number, role = finder.find(n1, 0, n1_maximum)
assert(wave_number == 5 and role == "assault_boss",
    "N1 opening did not skip normal-only waves and prefer wave 5 assault boss")

wave_number, role = finder.find(n1, 5, n1_maximum)
assert(wave_number == 6 and role == "wave_leader",
    "N1 post-boss search did not fall back to the next wave leader")

wave_number, role = finder.find(n1, n1_maximum, n1_maximum)
assert(wave_number == nil and role == nil,
    "search after final wave unexpectedly returned a special target")

print("WAVE_SPECIAL_TARGET_LUA51_PASS")