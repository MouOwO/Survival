local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local Tracker = class({})
_G.modifier_weapon_growth_tracker = Tracker

function Tracker:IsHidden() return true end
function Tracker:IsPurgable() return false end
function Tracker:RemoveOnDeath() return false end

function Tracker:OnCreated(kv)
    if IsServer() then
        self.player_id = tonumber(kv.player_id) or self:GetParent():GetPlayerOwnerID()
        self.records = {}
    end
end

function Tracker:DeclareFunctions()
    return { MODIFIER_EVENT_ON_DEATH }
end

function Tracker:OnDeath(params)
    if not IsServer() or not params.unit or params.unit:IsNull() then return end
    local attacker = params.attacker
    if not attacker or attacker:IsNull() then return end
    local owner = attacker.GetOwnerEntity and attacker:GetOwnerEntity() or nil
    if attacker ~= self:GetParent() and owner ~= self:GetParent() then return end
    if params.unit:GetTeamNumber() == self:GetParent():GetTeamNumber() then return end
    if params.unit.IsRealHero and params.unit:IsRealHero() then return end
    event_bus.emit(events.WEAPON_ENEMY_KILLED, {
        player_id = self.player_id, victim = params.unit, attacker = attacker,
        victim_entindex = params.unit:entindex(), source = "weapon_growth_tracker",
    })
end

M.class = Tracker
return M
