local event_bus = require("core/event_bus")
local events = require("core/events")

local M = class({})
ability_upgrade_gold_mine = M

function ability_upgrade_gold_mine:OnSpellStart()
    local caster = self:GetCaster()
    local result = event_bus.request(events.GOLD_MINE_LEVEL_UPGRADE_REQUEST, {
        entindex = caster:entindex(),
    })
    if result and not result.ok then
        local player_id = caster:GetPlayerOwnerID()
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = player_id,
            message = result.error or "金矿升级失败",
            level = "error",
        })
    end
end

return M
