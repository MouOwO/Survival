modifier_practice_monster_ai = class({})
_G.modifier_practice_monster_ai = modifier_practice_monster_ai
local shared_boss = require("systems/shared_challenge_boss_registry")

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
end

function modifier_practice_monster_ai:IsHidden() return true end
function modifier_practice_monster_ai:IsPurgable() return false end

function modifier_practice_monster_ai:OnCreated(params)
    if not IsServer() then return end
    self.hero_entindex = tonumber(params and params.hero_entindex) or -1
    self.home = Vector(
        tonumber(params and params.home_x) or 0,
        tonumber(params and params.home_y) or 0,
        tonumber(params and params.home_z) or 0
    )
    self.aggro_radius = math.max(100, tonumber(params and params.aggro_radius) or 700)
    self.leash_radius = math.max(
        self.aggro_radius, tonumber(params and params.leash_radius) or 1200
    )
    self.has_target = false
    self.target_entindex = nil
    self.returning_home = false
    local unit = self:GetParent()
    self.staging = unit and unit.HasModifier
        and unit:HasModifier("modifier_challenge_11_staging") or false
    if not self.staging then self:StartIntervalThink(0.5) end
end

function modifier_practice_monster_ai:Resume()
    if not IsServer() or self.destroyed then return false end
    local unit = self:GetParent()
    if not valid(unit) or (unit.HasModifier
        and unit:HasModifier("modifier_challenge_11_staging")) then return false end
    unit:SetForceAttackTarget(nil)
    self.has_target = false
    self.target_entindex = nil
    self.returning_home = false
    self.staging = false
    self:StartIntervalThink(0.5)
    return true
end

function modifier_practice_monster_ai:OnIntervalThink()
    if self.staging or self.destroyed then return end
    local unit = self:GetParent()
    if not valid(unit) then return end

    local position = unit:GetAbsOrigin()
    local hero
    if unit.survival_shared_challenge_boss then
        hero = shared_boss.target_for(unit, position, self.leash_radius)
    else
        hero = self.hero_entindex > 0 and EntIndexToHScript(self.hero_entindex) or nil
    end
    local home_x, home_y = position.x - self.home.x, position.y - self.home.y
    local from_home_sq = home_x * home_x + home_y * home_y
    local hero_distance_sq = math.huge
    if valid(hero) then
        local hero_position = hero:GetAbsOrigin()
        local x, y = hero_position.x - position.x, hero_position.y - position.y
        hero_distance_sq = x * x + y * y
    end
    local leash_sq = self.leash_radius * self.leash_radius

    if from_home_sq > leash_sq or not valid(hero)
        or hero_distance_sq > leash_sq then
        if self.has_target then
            unit:SetForceAttackTarget(nil)
            self.has_target = false
        end
        if from_home_sq > 4096 then
            if not self.returning_home then
                unit:MoveToPosition(self.home)
                self.returning_home = true
            end
        else
            self.returning_home = false
        end
        return
    end

    if hero_distance_sq <= self.aggro_radius * self.aggro_radius then
        self.returning_home = false
        if not self.has_target or self.target_entindex ~= hero:entindex() then
            unit:SetForceAttackTarget(hero)
            self.has_target = true
            self.target_entindex = hero:entindex()
        end
    elseif self.has_target then
        unit:SetForceAttackTarget(nil)
        self.has_target = false
        if not self.returning_home then
            unit:MoveToPosition(self.home)
            self.returning_home = true
        end
    elseif from_home_sq <= 4096 then
        self.returning_home = false
    end
end

function modifier_practice_monster_ai:OnDestroy()
    self.destroyed = true
    if IsServer() and valid(self:GetParent()) then
        self:GetParent():SetForceAttackTarget(nil)
    end
end

return modifier_practice_monster_ai
