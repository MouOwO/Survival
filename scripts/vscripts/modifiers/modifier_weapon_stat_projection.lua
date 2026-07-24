LinkLuaModifier("modifier_weapon_stat_projection", "modifiers/modifier_weapon_stat_projection", LUA_MODIFIER_MOTION_NONE)

local event_bus = require("core/event_bus")
local events = require("core/events")

modifier_weapon_stat_projection = class({})

function modifier_weapon_stat_projection:IsHidden() return true end
function modifier_weapon_stat_projection:IsPurgable() return false end
function modifier_weapon_stat_projection:RemoveOnDeath() return false end

function modifier_weapon_stat_projection:OnCreated(kv)
    if IsServer() then
        self.player_id = tonumber(kv.player_id)
            or self:GetParent():GetPlayerOwnerID()
    end
end

function modifier_weapon_stat_projection:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE,
        MODIFIER_EVENT_ON_TAKEDAMAGE,
    }
end

local function snapshot(self)
    if not IsServer() then
        return {}
    end
    local result = event_bus.request(
        events.HERO_COMBAT_STATS_GET_REQUEST,
        { player_id = self.player_id }
    )
    return result and result.snapshot or {}
end

function modifier_weapon_stat_projection:GetModifierPreAttack_BonusDamage()
    local stats = snapshot(self)
    return (tonumber(stats.engine_weapon_attack_bonus) or 0)
        + (tonumber(stats.engine_research_attack_bonus) or 0)
end

function modifier_weapon_stat_projection:OnTakeDamage(params)
    if not IsServer() or params.attacker ~= self:GetParent() then return end
    local victim = params.unit
    if not victim or victim:IsNull() then return end
    local ability = params.inflictor
    event_bus.emit(events.COMBAT_DAMAGE_RESOLVED, {
        player_id = self.player_id,
        attacker_entindex = params.attacker:entindex(),
        victim_entindex = victim:entindex(),
        damage_kind = ability and not ability:IsNull() and "ability" or "attack",
        damage_type = tonumber(params.damage_type) or DAMAGE_TYPE_PHYSICAL,
        final_damage = tonumber(params.damage) or 0,
        victim_armor = victim.GetPhysicalArmorValue
            and victim:GetPhysicalArmorValue(false) or 0,
        ability_name = ability and not ability:IsNull()
            and ability:GetAbilityName() or "",
    })
end
