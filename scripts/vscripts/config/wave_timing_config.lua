local generated = require("config/generated/wave_timing_rules")

local M = {}
local definition = generated.by_id.default

assert(definition and definition.enabled ~= false,
    "enabled default wave timing rule is required")

M.initial_delay_seconds = math.max(
    0,
    tonumber(definition.initial_delay_seconds) or 0
)
M.dev_wave_preload_timeout_seconds = math.max(
    0,
    tonumber(definition.dev_wave_preload_timeout_seconds) or 0
)
M.formal_wave_preload_lead_seconds = math.max(
    0,
    tonumber(definition.formal_wave_preload_lead_seconds) or 0
)

function M.interval_after_wave(wave_number)
    local number = tonumber(wave_number) or 0
    local early_last = tonumber(definition.early_wave_last_number) or 0
    if number <= early_last then
        return math.max(0, tonumber(definition.early_interval_seconds) or 0)
    end
    return math.max(0, tonumber(definition.late_interval_seconds) or 0)
end

return M