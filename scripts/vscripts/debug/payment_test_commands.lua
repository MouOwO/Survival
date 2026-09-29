-- TODO(PAYMENT_TEST_ONLY): remove this module/registration before public release.
local M = {}
local initialized = false
function M.init()
    if initialized or not IsInToolsMode or not IsInToolsMode() then return end
    initialized = true
    ListenToGameEvent("player_chat", function(keys)
        local command = tostring(keys and keys.text or ""):lower():match("^%s*%-?([a-z]+)%s*$")
        if command ~= "refreshdata" and command ~= "refreshmoney" then return end
        -- Engine chat event owns the sender; the text cannot name another account.
        local id = tonumber(keys.playerid or keys.player_id or keys.PlayerID)
        if not id or not PlayerResource:IsValidPlayerID(id) then return end
        local ok,err = require("systems/payment_service").reset_player({player_id=id,args={}},command)
        if not ok then
            require("core/event_bus").emit(require("core/events").UI_NOTIFICATION, {
                player_id=id, message="测试清理暂未执行："..tostring(err), level="error",
            })
        end
    end, nil)
end
return M
