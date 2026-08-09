local event_bus = require("core/event_bus")
local events = require("core/events")
local M = class({})

function M:GetBehavior() return DOTA_ABILITY_BEHAVIOR_NO_TARGET end
function M:GetManaCost() return 0 end
function M:OnSpellStart()
    local result = event_bus.request(events.WORKER_TRAIN_REQUEST, {
        city = self:GetCaster(),
        training_id = "train_population_auto",
        source_ability = self,
    })
    if not result or not result.ok then self:EndCooldown() end
end

_G.ability_train_population = M
return M