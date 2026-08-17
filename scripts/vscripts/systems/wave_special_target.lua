local M = {}

local function role_for_wave(wave)
    local role = nil
    for _, row in ipairs((wave and wave.batches) or {}) do
        if row.member_role == "assault_boss" then
            return "assault_boss"
        elseif row.member_role == "wave_leader" then
            role = "wave_leader"
        end
    end
    return role
end

function M.find(waves, current_wave, total_waves)
    local wave_number = (tonumber(current_wave) or 0) + 1
    local maximum = tonumber(total_waves) or 0
    while wave_number <= maximum do
        local wave = waves[wave_number]
        if wave then
            local role = role_for_wave(wave)
            if role then return wave_number, role end
        end
        wave_number = wave_number + 1
    end
    return nil, nil
end

return M