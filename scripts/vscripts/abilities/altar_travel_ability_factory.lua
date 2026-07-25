local training_room_service = require("systems/training_room_service")

local M = {}

function M.create(action_id)
    local ability_class = class({})

    function ability_class:OnSpellStart()
        if not IsServer() then return end
        local caster = self:GetCaster()
        local player_id = caster and caster:GetPlayerOwnerID() or -1
        local result = training_room_service.enter(player_id, action_id)
        if not result or not result.ok then
            self:EndCooldown()
            local event_bus = require("core/event_bus")
            local events = require("core/events")
            event_bus.emit(events.UI_NOTIFICATION, {
                player_id = player_id,
                message = result and result.error or "传送失败",
                level = "error",
            })
        end
    end

    return ability_class
end

return M