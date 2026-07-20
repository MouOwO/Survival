local event_bus = require("core/event_bus")
local events = require("core/events")

modifier_weapon_attack_tracker = class({})

function modifier_weapon_attack_tracker:IsHidden() return true end
function modifier_weapon_attack_tracker:IsPurgable() return false end
function modifier_weapon_attack_tracker:RemoveOnDeath() return false end

function modifier_weapon_attack_tracker:OnCreated(kv)
    if IsServer() then
        self.player_id = tonumber(kv.player_id)
            or self:GetParent():GetPlayerOwnerID()
    end
end

function modifier_weapon_attack_tracker:DeclareFunctions()
    return { MODIFIER_EVENT_ON_ATTACK_LANDED }
end

function modifier_weapon_attack_tracker:OnAttackLanded(params)
    if not IsServer() or params.attacker ~= self:GetParent() then
        return
    end
    local target = params.target
    if not target or target:IsNull()
        or target:GetTeamNumber() == self:GetParent():GetTeamNumber() then
        return
    end
    event_bus.emit(events.WEAPON_ATTACK_LANDED, {
        player_id = self.player_id,
        attacker = self:GetParent(),
        target = target,
        record = params.record,
    })
    event_bus.emit(events.TREE_HIT, {
        player_id = self.player_id,
        attacker = self:GetParent(),
        target = target,
        team = self:GetParent():GetTeamNumber(),
        source = "hero",
    })
end
