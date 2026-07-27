local event_bus = require("core/event_bus")
local events = require("core/events")

local attack_sequence = 0
local secondary_records = {}

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

function modifier_weapon_attack_tracker.MarkSecondaryAttackRecord(record)
    if record ~= nil then secondary_records[tostring(record)] = true end
end

function modifier_weapon_attack_tracker.ClearSecondaryAttackRecord(record)
    if record ~= nil then secondary_records[tostring(record)] = nil end
end

local function is_secondary_attack(params, attacker)
    if params.is_multishot_secondary == true
        or params.is_multishot_secondary == 1 then
        return true
    end
    if attacker.survival_is_multishot_secondary == true then return true end
    return params.record ~= nil and secondary_records[tostring(params.record)] == true
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
    attack_sequence = attack_sequence + 1
    local attack_id = string.format(
        "hero_attack:%d:%s:%d",
        tonumber(self.player_id) or -1,
        tostring(params.record or "none"),
        attack_sequence
    )
    local secondary = is_secondary_attack(params, self:GetParent())
    local payload = {
        player_id = self.player_id,
        attacker = self:GetParent(),
        target = target,
        record = params.record,
        attack_id = attack_id,
        is_main_attack = not secondary,
        is_multishot_secondary = secondary,
        target_was_killed = target.IsAlive and not target:IsAlive() or false,
    }
    event_bus.emit(events.WEAPON_ATTACK_LANDED, payload)
    if not secondary then
        event_bus.emit(events.HERO_MAIN_ATTACK_LANDED, payload)
    end
    modifier_weapon_attack_tracker.ClearSecondaryAttackRecord(params.record)
    event_bus.emit(events.TREE_HIT, {
        player_id = self.player_id,
        attacker = self:GetParent(),
        target = target,
        team = self:GetParent():GetTeamNumber(),
        source = "hero",
    })
end
