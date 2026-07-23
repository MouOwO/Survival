local event_bus = require("core/event_bus")
local events = require("core/events")
local M = class({})

function M:GetBehavior() return DOTA_ABILITY_BEHAVIOR_NO_TARGET end
function M:GetManaCost() return 0 end
function M:OnSpellStart()
    print("[MainCityAbility] lumberjack cast entindex="
        .. tostring(self:GetCaster():entindex()))
    event_bus.emit(events.WORKER_TRAIN_REQUEST, {
        city = self:GetCaster(),
        training_id = "train_lumberjack_01",
    })
end

_G.ability_train_lumberjack = M
return M
