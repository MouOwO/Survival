local event_bus = require("core/event_bus")
local events = require("core/events")

local M = class({})
_G.ability_survival_rogue_reward = M

function M:OnSpellStart()
    local caster = self:GetCaster()
    local player_id = caster and caster:GetPlayerOwnerID() or -1
    local result = event_bus.request(events.ROGUE_REWARD_OPEN_REQUEST, {
        player_id = player_id, source = "builder",
    })
    if result and result.ok and caster and not caster:IsNull() then
        caster:RemoveAbility(self:GetAbilityName())
    end
end

return M