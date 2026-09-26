local event_bus = require("core/event_bus")
local events = require("core/events")
local M = class({})

function M:GetAbilityTextureName()
    local runtime = CustomNetTables and CustomNetTables:GetTableValue(
        "survival_ability_runtime", tostring(self:entindex())) or {}
    local level = math.max(1, math.min(8, tonumber(runtime.current_level) or 1))
    return "survival/native/train_lumberjack_" .. string.format("%02d", level)
end

function M:GetBehavior() return DOTA_ABILITY_BEHAVIOR_NO_TARGET end
function M:GetManaCost() return 0 end
function M:OnSpellStart()
    print("[MainCityAbility] lumberjack cast entindex="
        .. tostring(self:GetCaster():entindex()))
    local result = event_bus.request(events.WORKER_TRAIN_REQUEST, {
        city = self:GetCaster(),
        training_id = "train_lumberjack_auto",
        source_ability = self,
    })
    if not result or not result.ok then self:EndCooldown() end
end

_G.ability_train_lumberjack = M
return M
