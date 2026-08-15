local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local function player_id_from_caster(caster)
    if not caster or caster:IsNull() then
        return -1
    end
    return caster:GetPlayerOwnerID()
end

function M.create(hero_id)
    local ability_class = class({})

    function ability_class:CastFilterResult()
        if not IsServer() then
            return UF_SUCCESS
        end

        local player_id = player_id_from_caster(self:GetCaster())
        local ability = self
        local result = event_bus.request(
            events.HERO_SUMMON_SNAPSHOT_REQUEST,
            { player_id = player_id }
        )
        local snapshot = result and result.snapshot or nil

        if not snapshot or snapshot.altar_built ~= 1 then
            self.cast_error = "英雄祭坛不可用"
            return UF_FAIL_CUSTOM
        end
        if snapshot.hero_summoned == 1 then
            self.cast_error = "已经召唤过英雄"
            return UF_FAIL_CUSTOM
        end

        for _, option in pairs(snapshot.heroes or {}) do
            if option.hero_id == hero_id then
                if option.available ~= 1 then
                    self.cast_error =
                        option.disabled_reason or "当前不可召唤"
                    return UF_FAIL_CUSTOM
                end
                return UF_SUCCESS
            end
        end

        self.cast_error = "英雄配置不存在"
        return UF_FAIL_CUSTOM
    end

    function ability_class:GetCustomCastError()
        return self.cast_error or "当前不可召唤"
    end

    function ability_class:OnSpellStart()
        if not IsServer() then
            return
        end

        local player_id = player_id_from_caster(self:GetCaster())
        local result = event_bus.request(
            events.HERO_SUMMON_REQUEST,
            {
                player_id = player_id,
                hero_id = hero_id,
                source = "altar_ability",
                on_completed = function(final_result)
                    if final_result and final_result.ok then return end
                    if ability and not ability:IsNull() then
                        ability:EndCooldown()
                    end
                    local message = final_result and final_result.error or nil
                    if message and not string.find(message,
                            "^hero_resource_load_failed:") then
                        event_bus.emit(events.UI_NOTIFICATION, {
                            player_id = player_id,
                            message = message,
                            level = "error",
                        })
                    end
                end,
            }
        )

        if not result or not result.ok then
            self:EndCooldown()
        end
    end

    return ability_class
end

return M
