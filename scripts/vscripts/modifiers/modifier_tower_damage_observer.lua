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
        -- Capability comes only from this fresh native modifier's OnCreated.
        -- Service init/reload must never advertise it for a cached old holder.
        if type(observer.route_wall_feedback)=="function" then
            holder.survival_wall_feedback_observer_version=1
        end
        if type(observer.route_corrosive_shield)=="function" then
            holder.survival_corrosive_shield_observer_version=1
        end
        -- Only a fresh native carrier created from this class has the new
        -- existing OnTakeDamage route. Service reload cannot upgrade old ones.
        if IsInToolsMode and IsInToolsMode() then
            holder.survival_hero_equipment_damage_observer_version=1
            holder.survival_weapon_projection_damage_observer_version=1
        end
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
function modifier_tower_damage_observer:OnAttack(params)
    -- Reuse this already-declared native release event only in the opt-in
    -- Workshop experiment. Normal matches pay only this flag comparison.
    if _G.SURVIVAL_RANGED_STATIONARY_PROBE==true and type(observer.route_enemy_fired)=="function" then
        observer.route_enemy_fired(self:GetParent(),params)
    end
    forward(self,"OnAttack",params)
    if not IsServer() or not params then return end
    if _G.SURVIVAL_SHARED_CORROSIVE_SHIELD_PROBE==true and type(observer.count_corrosive_shield_event)=="function" then
        observer.count_corrosive_shield_event(self:GetParent())
    end
    -- Existing shared receivers must still run after admission is disabled.
    if params.attacker and params.attacker.survival_shared_corrosive_shield_owner
        and type(observer.route_corrosive_shield)=="function" then
        observer.route_corrosive_shield(self:GetParent(),params)
    end
end
function modifier_tower_damage_observer:OnAttackFail(params) forward(self,"OnAttackFail",params) end
function modifier_tower_damage_observer:OnAttackLanded(params)
    forward(self,"OnAttackLanded",params)
    if not IsServer() or not params then return end
    if _G.SURVIVAL_SHARED_WALL_FEEDBACK_PROBE==true and type(observer.count_wall_feedback_event)=="function" then
        observer.count_wall_feedback_event(self:GetParent(),"OnAttackLanded")
    end
    if params.target and params.target.survival_shared_wall_sound_owner and type(observer.route_wall_feedback)=="function" then
        observer.route_wall_feedback(self:GetParent(),"OnAttackLanded",params)
    end
end
function modifier_tower_damage_observer:CheckState()
    return {[MODIFIER_STATE_INVULNERABLE]=true,[MODIFIER_STATE_UNSELECTABLE]=true,
        [MODIFIER_STATE_NO_HEALTH_BAR]=true,[MODIFIER_STATE_OUT_OF_GAME]=true}
end
local function forward_commerce_damage(self,params)
    if not IsServer() or not params or (tonumber(params.damage) or 0)<=0 then return end
    local tower,target=params.attacker,params.unit
    if not tower or tower:IsNull() or not tower.survival_global_tower_damage
        or not target or target:IsNull() or target:GetTeamNumber()==tower:GetTeamNumber() then return end
    if not observer.is_authoritative(self:GetParent()) then return end
    bus.emit("commerce.tower_damage",{tower=tower,target=target,damage=params.damage})
end
function modifier_tower_damage_observer:OnTakeDamage(params)
    forward_commerce_damage(self,params)
    if not IsServer() or not params then return end
    if _G.SURVIVAL_SHARED_WALL_FEEDBACK_PROBE==true and type(observer.count_wall_feedback_event)=="function" then
        observer.count_wall_feedback_event(self:GetParent(),"OnTakeDamage")
    end
    if params.unit and params.unit.survival_shared_wall_sound_owner and type(observer.route_wall_feedback)=="function" then
        observer.route_wall_feedback(self:GetParent(),"OnTakeDamage",params)
    end
    -- Exact attacker registration, not the damaged victim. No module load or
    -- extra global listener in default production; existing routes survive off.
    if params.attacker and params.attacker.survival_shared_hero_equipment_damage_registration then
        local equipment=package.loaded["systems/hero_equipment_damage_observer"]
        if equipment and type(equipment.route)=="function" then equipment.route(self:GetParent(),params) end
    end
    -- This receiver covers every owned attacker, not just the exact hero.
    -- Unknown ownership retains the original same-team receiver fanout.
    local projection=package.loaded["systems/weapon_projection_damage_observer"]
    if projection and type(projection.route)=="function" then projection.route(self:GetParent(),params) end
end
