modifier_tower_damage_observer=class({})
local bus=require("core/event_bus")
local observer=require("systems/tower_damage_observer")
function modifier_tower_damage_observer:IsHidden() return true end
function modifier_tower_damage_observer:IsPurgable() return false end
function modifier_tower_damage_observer:RemoveOnDeath() return false end
function modifier_tower_damage_observer:OnCreated()
    if not IsServer() then return end
    local holder=self:GetParent()
    if holder and not holder:IsNull() then
        holder.survival_tower_auto_attack_observer_version=1
    end
end
function modifier_tower_damage_observer:DeclareFunctions()
    return {MODIFIER_EVENT_ON_TAKEDAMAGE,MODIFIER_EVENT_ON_ATTACK_START,
        MODIFIER_EVENT_ON_ATTACK,MODIFIER_EVENT_ON_ATTACK_FAIL,MODIFIER_EVENT_ON_ATTACK_LANDED}
end
local function forward(self,name,params)
    if not IsServer() or not params then return end
    local tower=params.attacker
    if not tower or tower:IsNull() then return end
    local auto=(name=="OnAttackStart" or name=="OnAttack")
        and tower.survival_tower_auto_attack_owner or nil
    if not auto and not tower.survival_global_tower_damage then return end
    if not observer.is_authoritative(self:GetParent()) then return end
    if auto and auto.shared_attack_observer==true and not auto.destroyed
        and (not auto.IsNull or not auto:IsNull()) then
        local methods=_G.modifier_tower_auto_attack
        local callback=methods and methods[name=="OnAttackStart" and "HandleAttackStart" or "HandleAttack"]
        if callback then callback(auto,params) end
    end
    if not tower.survival_global_tower_damage then return end
    local owner=tower.survival_global_tower_damage_owner
    if not owner or (owner.IsNull and owner:IsNull()) then return end
    local methods=_G.modifier_tower_attack_effects
    local callback=methods and methods[name]
    if callback then callback(owner,params) end
end
function modifier_tower_damage_observer:OnAttackStart(params) forward(self,"OnAttackStart",params) end
function modifier_tower_damage_observer:OnAttack(params) forward(self,"OnAttack",params) end
function modifier_tower_damage_observer:OnAttackFail(params) forward(self,"OnAttackFail",params) end
function modifier_tower_damage_observer:OnAttackLanded(params) forward(self,"OnAttackLanded",params) end
function modifier_tower_damage_observer:CheckState()
    return {[MODIFIER_STATE_INVULNERABLE]=true,[MODIFIER_STATE_UNSELECTABLE]=true,
        [MODIFIER_STATE_NO_HEALTH_BAR]=true,[MODIFIER_STATE_OUT_OF_GAME]=true}
end
function modifier_tower_damage_observer:OnTakeDamage(params)
    if not IsServer() or not params or (tonumber(params.damage) or 0)<=0 then return end
    local tower,target=params.attacker,params.unit
    if not tower or tower:IsNull() or not tower.survival_global_tower_damage
        or not target or target:IsNull() or target:GetTeamNumber()==tower:GetTeamNumber() then return end
    if not observer.is_authoritative(self:GetParent()) then return end
    bus.emit("commerce.tower_damage",{tower=tower,target=target,damage=params.damage})
end
