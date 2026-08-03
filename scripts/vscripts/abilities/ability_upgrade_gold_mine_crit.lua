local event_bus = require("core/event_bus")
local events = require("core/events")

local M = class({})
ability_upgrade_gold_mine_crit = M

function ability_upgrade_gold_mine_crit:OnSpellStart()
    local caster = self:GetCaster()
    if caster.survival_upgrade_in_progress then
        self:EndCooldown()
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = caster:GetPlayerOwnerID(),
            message = "金矿正在升级中",
            level = "error",
        })
        return
    end
    local result, request_error = event_bus.request(events.TECHNOLOGY_PURCHASE_NEXT_REQUEST, {
        player_id = caster:GetPlayerOwnerID(),
        technology_group = "gold_mine_crit",
        source = "gold_mine_ability",
        entindex = caster:entindex(),
        request_id = "gold_mine_e_" .. tostring(caster:entindex()) .. "_" .. tostring(GameRules:GetGameTime()),
    })
    if not result or not result.ok then
        self:EndCooldown()
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = caster:GetPlayerOwnerID(),
            message = result and result.error
                or request_error
                or "采集暴击率升级失败",
            level = "error",
        })
    end
end

return M
