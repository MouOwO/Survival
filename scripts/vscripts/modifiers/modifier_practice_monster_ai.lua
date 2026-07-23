modifier_practice_monster_ai = class({})
_G.modifier_practice_monster_ai = modifier_practice_monster_ai

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
    self.returning_home = false
    self:StartIntervalThink(0.5)
end

function modifier_practice_monster_ai:OnIntervalThink()
    local unit = self:GetParent()
    if not valid(unit) then return end

    local hero = self.hero_entindex > 0
        and EntIndexToHScript(self.hero_entindex) or nil
    local from_home = (unit:GetAbsOrigin() - self.home):Length2D()
    local hero_distance = valid(hero)
        and (hero:GetAbsOrigin() - unit:GetAbsOrigin()):Length2D() or 999999

    if from_home > self.leash_radius or not valid(hero)
        or hero_distance > self.leash_radius then
        if self.has_target then
            unit:SetForceAttackTarget(nil)
            self.has_target = false
        end
        if from_home > 64 then
            if not self.returning_home then
                unit:MoveToPosition(self.home)
                self.returning_home = true
            end
        else
            self.returning_home = false
        end
        return
    end

    if hero_distance <= self.aggro_radius then
        self.returning_home = false
        if not self.has_target then
            unit:SetForceAttackTarget(hero)
            self.has_target = true
        end
    elseif self.has_target then
        unit:SetForceAttackTarget(nil)
        self.has_target = false
        if not self.returning_home then
            unit:MoveToPosition(self.home)
            self.returning_home = true
        end
    elseif from_home <= 64 then
        self.returning_home = false
    end
end

function modifier_practice_monster_ai:OnDestroy()
    if IsServer() and valid(self:GetParent()) then
        self:GetParent():SetForceAttackTarget(nil)
    end
end

return modifier_practice_monster_ai