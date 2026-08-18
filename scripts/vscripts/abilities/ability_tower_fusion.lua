local event_bus = require("core/event_bus")
local events = require("core/events")

ability_tower_fusion = class({})

function ability_tower_fusion:GetBehavior()
    return DOTA_ABILITY_BEHAVIOR_NO_TARGET
end

function ability_tower_fusion:GetManaCost() return 0 end
function ability_tower_fusion:GetCooldown() return 0 end

function ability_tower_fusion:OnSpellStart()
    local result = event_bus.request(events.TOWER_FUSION_REQUEST, {
        caster = self:GetCaster(),
        ability = self,
    })
    if not result or not result.ok then
        -- The request can fail after the engine has invalidated/replaced the
        -- dynamic ability handle. Do not let cooldown rollback hide the real
        -- fusion error with "Invalid object passed to EndCooldown".
        local ok, is_null = pcall(function() return self:IsNull() end)
        if ok and not is_null then
            pcall(function() self:EndCooldown() end)
        end
    end
end

function ability_tower_fusion:OnProjectileHit_ExtraData(target, location, data)
    return require("systems/tower_fusion_service")
        .on_projectile_hit(self, target, location, data)
end

return ability_tower_fusion