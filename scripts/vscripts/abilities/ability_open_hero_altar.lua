local event_bus = require("core/event_bus")
local events = require("core/events")

local M = class({})

function M:CastFilterResult()
    if not IsServer() then
        return UF_SUCCESS
    end

    local caster = self:GetCaster()
    local player_id = caster and caster:GetPlayerOwnerID() or -1
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
    return UF_SUCCESS
end

function M:GetCustomCastError()
    return self.cast_error or "无法使用英雄祭坛"
end

function M:OnSpellStart()
    local caster = self:GetCaster()
    if not caster or caster:IsNull() then
        return
    end
    event_bus.emit(events.HERO_ALTAR_OPEN_REQUEST, {
        player_id = caster:GetPlayerOwnerID(),
        team = caster:GetTeamNumber(),
        altar = caster,
    })
end

_G.ability_open_hero_altar = M
return M
