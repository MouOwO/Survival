local event_bus = require("core/event_bus")
local events = require("core/events")

local M = class({})

function M:GetBehavior() return DOTA_ABILITY_BEHAVIOR_NO_TARGET end
function M:GetManaCost() return 0 end
function M:GetCooldown() return 0 end

function M:OnSpellStart()
    local result = event_bus.request(events.LUMBERJACK_FUSION_REQUEST, {
        caster = self:GetCaster(),
        ability = self,
    })
    if not result or not result.ok then self:EndCooldown() end
end

_G.ability_fuse_lumberjack = M
for level = 1, 8 do
    _G["ability_fuse_lumberjack_" .. string.format("%02d", level)] = M
end
return M