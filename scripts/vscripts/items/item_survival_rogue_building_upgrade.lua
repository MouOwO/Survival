local event_bus = require("core/event_bus")
local events = require("core/events")

item_survival_rogue_building_upgrade = class({})
local M = item_survival_rogue_building_upgrade

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
end

local function quote(item, target)
    local caster = item:GetCaster()
    if not valid(caster) or not valid(target) then
        return { ok = false, error = "请选择存活的己方建筑" }
    end
    local builder = event_bus.request(events.BUILDER_GET_REQUEST, { builder = caster })
    if not builder or not builder.ok or builder.builder ~= caster then
        return { ok = false, error = "建造密令只能由建造者使用" }
    end
    local state = event_bus.request(events.BUILDING_QUERY_REQUEST, { entindex = target:entindex() })
    if not state or tonumber(state.player_id) ~= tonumber(builder.player_id) then
        return { ok = false, error = "只能升级自己的建筑" }
    end
    if target:HasModifier("modifier_building_under_construction") then
        return { ok = false, error = "建筑尚未建造完成" }
    end
    local request = {
        building = target, entindex = target:entindex(), player_id = builder.player_id,
        upgrade_mode = "one", reason = "rogue_reward:construction_order",
    }
    local quote_event = state.building_id == "gold_mine"
        and events.GOLD_MINE_LEVEL_UPGRADE_QUOTE_REQUEST or events.BUILDING_UPGRADE_QUOTE_REQUEST
    local result = event_bus.request(quote_event, request)
        or { ok = false, error = "建筑升级服务暂不可用" }
    return result, request, state.building_id
end

function M:CastFilterResultTarget(target)
    if not IsServer() then return UF_SUCCESS end
    local result = quote(self, target)
    self.survival_upgrade_error = result.error
    return result.ok and UF_SUCCESS or UF_FAIL_CUSTOM
end

function M:GetCustomCastErrorTarget()
    return self.survival_upgrade_error or "请选择可升级的己方建筑"
end

function M:OnSpellStart()
    if not IsServer() or self.survival_upgrade_consumed then return end
    -- Recheck ownership, completion and upgrade eligibility at the commit point.
    local result, request, building_id = quote(self, self:GetCursorTarget())
    if result.ok then
        request.system_free_upgrade = true
        request.silent_notification = true
        local upgrade_event = building_id == "gold_mine"
            and events.GOLD_MINE_LEVEL_UPGRADE_REQUEST or events.BUILDING_UPGRADE_FREE_REQUEST
        result = event_bus.request(upgrade_event, request)
            or { ok = false, error = "建筑升级服务暂不可用" }
    end
    local caster = self:GetCaster()
    if result.ok then
        local charges = self:GetCurrentCharges()
        if charges > 1 then
            self:SetCurrentCharges(charges - 1)
        else
            self.survival_upgrade_consumed = true
            caster:RemoveItem(self)
        end
    else
        self:EndCooldown()
    end
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = tonumber(caster and caster.survival_player_id),
        message = result.ok and "建造密令已使用：建筑开始免费升级1级" or result.error,
        level = result.ok and "info" or "error",
    })
end

return M
