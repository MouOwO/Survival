-- Cash checkout is available only to explicit local developer builds.
-- Client flags, sv_cheats, host privileges and a payment token cannot enable it.
local release = require("core/release_policy")
local M = {}

function M.real_money_allowed()
    return release.development_allowed()
end

return M
