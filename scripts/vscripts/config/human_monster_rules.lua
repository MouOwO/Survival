local data = require("config/generated/human_monster_spec")
local M = { data = data }

function M.number(value)
    local number = type(value) == "number" and value
        or type(value) == "string" and tonumber(value:match("^[Nn](%d+)$"))
    if not number or number ~= math.floor(number) or number < 1 then return nil end
    return number
end

function M.mode(mode_id, difficulty_id)
    local rows = data.modes[mode_id or "standard"]
    return rows and rows[M.number(difficulty_id) or 0] or nil
end

function M.wave_base(wave)
    return data.waves[tonumber(wave)]
end

function M.wave_armor(mode_id, difficulty_id, wave)
    local mode, base = M.mode(mode_id, difficulty_id), M.wave_base(wave)
    if not mode or not base then return nil end
    return base.war3_armor * mode.armor_multiplier * (mode_id == "scourge" and 2 or 1)
end

function M.count(mode_id, difficulty_id, wave)
    local number = M.number(difficulty_id)
    if not M.mode(mode_id, difficulty_id) then return nil end
    wave = tonumber(wave)
    for _, row in ipairs(data.counts) do
        if row.mode_id == mode_id and number >= row.min_difficulty and number <= row.max_difficulty
            and wave and wave >= row.min_wave and wave <= row.max_wave then
            return { count = row.count, spawn_interval = row.spawn_interval }
        end
    end
    return nil
end

function M.challenge_attack_multiplier(mode_id, difficulty_id, room)
    local number = M.number(difficulty_id)
    if not M.mode(mode_id, difficulty_id) then return nil end
    if not room and (mode_id == "scourge" or mode_id == "ruins" or mode_id == "celestial") then
        return 3 + number
    end
    return 1.8 + 0.2 * number
end

return M
