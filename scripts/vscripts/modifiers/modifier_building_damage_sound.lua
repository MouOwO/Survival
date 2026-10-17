if LinkLuaModifier then
    LinkLuaModifier(
        "modifier_building_damage_sound",
        "modifiers/modifier_building_damage_sound",
        LUA_MODIFIER_MOTION_NONE
    )
end

modifier_building_damage_sound = class({})
_G.modifier_building_damage_sound = modifier_building_damage_sound
local M = modifier_building_damage_sound
local building_sound = require("systems/building_sound_service")
local observer = require("systems/tower_damage_observer")

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:DeclareFunctions()
    -- Native may query declarations before OnCreated. Commit only once for
    -- each new instance; an existing engine-cached legacy modifier never moves.
    if self ~= M and not self.wall_feedback_mode_decided and self.GetParent then
        local world = type(observer.choose_wall_feedback) == "function"
            and type(observer.register_wall_feedback) == "function"
            and observer.choose_wall_feedback(self:GetParent()) or nil
        self.wall_feedback_mode_decided = true
        self.shared_wall_feedback_observer = world ~= nil
        self.wall_feedback_declared_world = world
    end
    if self ~= M and self.shared_wall_feedback_observer == true then return {} end
    return { MODIFIER_EVENT_ON_TAKEDAMAGE, MODIFIER_EVENT_ON_ATTACK_LANDED }
end

function M:OnCreated()
    if not IsServer() then return end
    if not self.wall_feedback_mode_decided then self:DeclareFunctions() end
    if self.shared_wall_feedback_observer == true then
        self.wall_feedback_registration_failed = not observer.register_wall_feedback(
            self:GetParent(), self, self.wall_feedback_declared_world)
    end
end

function M:OnRefresh()
    -- Lua reload/refresh cannot upgrade a native declaration cached previously.
    if not self.wall_feedback_mode_decided then
        self.wall_feedback_mode_decided = true
        self.shared_wall_feedback_observer = false
    end
end

function M:OnDestroy()
    if not IsServer() then return end
    self.wall_feedback_destroyed = true
    if type(observer.unregister_wall_feedback) == "function" then observer.unregister_wall_feedback(self) end
end

function M:HandleAttackLanded(params)
    if not IsServer() or params.target ~= self:GetParent() then return end
    require("systems/wall_hit_effect").play(self:GetParent(),params.attacker)
end

function M:HandleTakeDamage(params)
    if not IsServer() then return end
    local wall = self:GetParent()
    if params.unit ~= wall or (tonumber(params.damage) or 0) <= 0 then return end
    building_sound.wall_damaged(wall)
    local wakeup = package.loaded["systems/repair_worker_wakeup"]
    if wakeup then wakeup.wall_damaged(wall) end
end

function M:OnAttackLanded(params)
    if self.shared_wall_feedback_observer == true then return end
    self:HandleAttackLanded(params)
end

function M:OnTakeDamage(params)
    if self.shared_wall_feedback_observer == true then return end
    self:HandleTakeDamage(params)
end

return M
