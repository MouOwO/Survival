-- Cash checkout is available only to explicit local developer builds.
-- Client flags, sv_cheats, host privileges and a payment token cannot enable it.
local release = require("core/release_policy")
local M = {}

function M.real_money_allowed()
    local acceptance = package.loaded["debug/mode_unlock_test"]
    if acceptance and acceptance.is_enabled() then return false end
    return release.development_allowed()
end

return M
