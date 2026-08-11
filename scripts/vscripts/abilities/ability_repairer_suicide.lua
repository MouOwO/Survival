local event_bus = require("core/event_bus")
local events = require("core/events")
local M = class({})

function M:GetBehavior()
    return DOTA_ABILITY_BEHAVIOR_NO_TARGET
        + DOTA_ABILITY_BEHAVIOR_IMMEDIATE
end

function M:GetManaCost()
    return 0
end

function M:OnSpellStart()
    local caster = self:GetCaster()
    if not caster or caster:IsNull()
        or caster.survival_worker_type ~= "repairer" then
        self:EndCooldown()
        return
    end

    local result = event_bus.request(events.WORKER_DISMISS_REQUEST, {
        worker = caster,
        reason = "repairer_suicide",
    })
    if not result or not result.ok then
        self:EndCooldown()
    end
end

_G.ability_repairer_suicide = M
return M