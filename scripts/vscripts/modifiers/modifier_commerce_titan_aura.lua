local values=require('systems/commerce_titan_aura_values')
local armor=require('config/armor_balance')
local bus=require('core/event_bus')
local events=require('core/events')
local scheduler=require('core/scheduler')
modifier_commerce_titan_aura=class({})
modifier_commerce_titan_aura_effect=class({})
local A=modifier_commerce_titan_aura
local B=modifier_commerce_titan_aura_effect
local recipients=setmetatable({},{__mode='k'})
local sequence=0

function A:IsHidden() return true end
function A:IsPurgable() return false end
function A:RemoveOnDeath() return true end
function A:IsAura() return self:GetParent():IsAlive() end
function A:GetModifierAura() return 'modifier_commerce_titan_aura_effect' end
function A:GetAuraRadius() return values.radius end
function A:GetAuraDuration() return 0.5 end
function A:GetAuraSearchTeam() return DOTA_UNIT_TARGET_TEAM_BOTH end
function A:GetAuraSearchType()
    return DOTA_UNIT_TARGET_HERO+DOTA_UNIT_TARGET_BASIC+DOTA_UNIT_TARGET_BUILDING
end
function A:GetAuraSearchFlags() return DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES end
function A:GetAuraEntityReject(unit)
    return not unit or unit:IsNull() or not unit:IsAlive()
        or unit.survival_visual_only==true or unit.survival_tree_owner_id~=nil
        or unit.survival_commerce_aura_excluded==true
end

local function valid(unit) return unit and not unit:IsNull() end
local function publish(parent)
    local index=parent:entindex()
    -- Coalesce transitions; no per-frame stat publications or spatial scans.
    scheduler.after(0,function()
        if valid(parent) then
            bus.emit(events.UNIT_COMBAT_STATS_CHANGED,{unit=parent,entindex=index,
                reason='commerce_titan_armor_changed'})
        end
    end,'commerce_titan_armor_'..tostring(index))
end
local function elect(parent)
    local modifiers=recipients[parent] or {}
    local winner
    for modifier in pairs(modifiers) do
        if not winner or modifier.serial<winner.serial then winner=modifier end
    end
    local bonus=winner and (winner.friendly and values.friendly_armor or values.enemy_armor) or 0
    for modifier in pairs(modifiers) do
        modifier:SetStackCount(modifier==winner and (modifier.friendly and 1 or 2) or 0)
    end
    local previous=values.bonus(parent)
    parent.survival_commerce_titan_armor=bonus~=0 and bonus or nil
    if previous~=bonus and valid(parent) then publish(parent) end
end

function B:IsHidden() return false end
function B:IsPurgable() return false end
function B:RemoveOnDeath() return true end
function B:GetTexture() return 'item_assault' end
function B:IsDebuff() return self:GetStackCount()==2 end
function B:DeclareFunctions()
    return {MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS,MODIFIER_PROPERTY_HEALTH_REGEN_CONSTANT}
end
function B:OnCreated()
    if not IsServer() then return end
    local parent,caster=self:GetParent(),self:GetCaster()
    if not valid(parent) or not valid(caster) then return end
    sequence=sequence+1;self.serial=sequence
    self.friendly=parent:GetTeamNumber()==caster:GetTeamNumber()
    recipients[parent]=recipients[parent] or {};recipients[parent][self]=true
    elect(parent)
end
function B:OnRefresh()
    if not IsServer() then return end
    if not self.serial then self:OnCreated();return end
    local parent,caster=self:GetParent(),self:GetCaster()
    if valid(parent) and valid(caster) then
        self.friendly=parent:GetTeamNumber()==caster:GetTeamNumber()
        elect(parent)
    end
end
function B:OnDestroy()
    if not IsServer() then return end
    local parent=self:GetParent()
    if not parent then return end
    if recipients[parent] then
        recipients[parent][self]=nil
        elect(parent)
        if not next(recipients[parent]) then recipients[parent]=nil end
    end
end
function B:GetModifierPhysicalArmorBonus()
    local stack=self:GetStackCount()
    return armor.from_war3_linear(stack==1 and values.friendly_armor or stack==2 and values.enemy_armor or 0)
end
function B:GetModifierConstantHealthRegen()
    return self:GetStackCount()==1 and values.friendly_regen or 0
end
return A
