-- Cash checkout is available only to explicit local developer builds.
-- Client flags, sv_cheats, host privileges and a payment token cannot enable it.
local release = require("core/release_policy")
local M = {}

function M.real_money_allowed()
    if not release.development_allowed() then return false end
    -- Offline profiles are match-local memory, even if this process has a
    -- previously configured payment token. Keep every cash route offline too.
    if require("debug/offline_logic_test").is_enabled() then return false end
    local acceptance = package.loaded["debug/mode_unlock_test"]
    if acceptance and acceptance.is_enabled() then return false end
    return true
end

return M
