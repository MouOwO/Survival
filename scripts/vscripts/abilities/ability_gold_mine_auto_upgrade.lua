local event_bus = require("core/event_bus")
local events = require("core/events")

local M = class({})
ability_gold_mine_auto_upgrade = M
ability_gold_mine_stop_auto_upgrade = M

function ability_gold_mine_auto_upgrade:OnSpellStart()
    local caster = self:GetCaster()
    local result = event_bus.request(events.GOLD_MINE_AUTO_UPGRADE_REQUEST, {
        entindex = caster:entindex(),
    })
    if result and result.message then
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = caster:GetPlayerOwnerID(),
            message = result.message,
            level = result.ok and "info" or "error",
        })
    end
end

return M