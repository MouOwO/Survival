modifier_single_health_bar = class({})

function modifier_single_health_bar:IsHidden() return true end
function modifier_single_health_bar:IsPurgable() return false end
function modifier_single_health_bar:RemoveOnDeath() return false end
function modifier_single_health_bar:GetAttributes()
    return MODIFIER_ATTRIBUTE_PERMANENT
end

local function valid(unit)
    return unit and not unit:IsNull()
end

function modifier_single_health_bar:OnCreated(kv)
    if not IsServer() then return end
    local parent = self:GetParent()
    self.unit_key = "unit_" .. tostring(parent:entindex())
    self:StartIntervalThink(0.1)
    self:Publish(false)
end

function modifier_single_health_bar:CheckState()
    -- Panorama owns every combat unit's overhead health bar. Hiding the engine
    -- bar prevents survival-scale health values from creating segmented pips.
    return { [MODIFIER_STATE_NO_HEALTH_BAR] = true }
end

function modifier_single_health_bar:Publish(removed)
    if not IsServer() or not self.unit_key then return end
    local parent = self:GetParent()
    if removed or not valid(parent) then
        CustomNetTables:SetTableValue(
            "survival_hero_health_bar",
            self.unit_key,
            { removed = 1 }
        )
        return
    end
    local health = math.max(0, tonumber(parent:GetHealth()) or 0)
    local max_health = math.max(1, tonumber(parent:GetMaxHealth()) or 1)
    local alive = parent:IsAlive() and 1 or 0
    if self.last_health and self.last_max_health
        and self.last_health < self.last_max_health - 0.5
        and health >= max_health - 0.5
        and health > self.last_health + 0.5 then
        print(string.format(
            "[UNIT_HEALTH_WATCH] entindex=%s health=%.1f->%.1f max=%.1f",
            tostring(parent:entindex()),
            self.last_health, health, max_health
        ))
    end
    if self.last_health == health and self.last_max_health == max_health
        and self.last_alive == alive then return end
    self.last_health = health
    self.last_max_health = max_health
    self.last_alive = alive
    CustomNetTables:SetTableValue(
        "survival_hero_health_bar",
        self.unit_key,
        {
            entindex = parent:entindex(),
            health = health,
            max_health = max_health,
            alive = alive,
            team = parent:GetTeamNumber(),
            removed = 0,
        }
    )
end

function modifier_single_health_bar:OnIntervalThink()
    self:Publish(false)
end

function modifier_single_health_bar:OnDestroy()
    if IsServer() then self:Publish(true) end
end

return modifier_single_health_bar