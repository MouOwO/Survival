modifier_enemy_attack_observer = class({})
local M = modifier_enemy_attack_observer
local observer = require("systems/enemy_attack_observer")
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end
function M:OnCreated()
    if IsServer() then self:GetParent().survival_enemy_death_observer_version=1 end
end
function M:DeclareFunctions() return {MODIFIER_EVENT_ON_ATTACK_START, MODIFIER_EVENT_ON_ATTACK_LANDED, MODIFIER_EVENT_ON_DEATH} end
function M:CheckState()
    return {[MODIFIER_STATE_INVULNERABLE] = true, [MODIFIER_STATE_UNSELECTABLE] = true,
        [MODIFIER_STATE_NO_HEALTH_BAR] = true, [MODIFIER_STATE_OUT_OF_GAME] = true}
end

local function forward(self, name, params)
    if not IsServer() or not params then return end
    local attacker = params.attacker
    if not attacker or attacker:IsNull() then return end
    local owner = attacker.survival_enemy_attack_owner
    if not owner or (owner.IsNull and owner:IsNull()) or not owner.shared_attack_observer then return end
    if not observer.is_authoritative(self:GetParent()) then return end
    -- Challenge enemies also own this AI. Only the AI's existing boss reward
    -- branch filters wave/boss flags; activity notifications must reach both.
    local methods = _G.modifier_enemy_wall_ai
    if methods and methods[name] then methods[name](owner, params) end
end

function M:OnAttackStart(params) forward(self, "HandleAttackStart", params) end
function M:OnAttackLanded(params) forward(self, "HandleAttackLanded", params) end
function M:OnDeath(params)
    if not IsServer() or type(observer.dispatch_death)~='function' then return end
    observer.dispatch_death(self:GetParent(),params,function(owner,event)
        local methods=_G.modifier_enemy_wall_ai
        if methods and methods.HandleDeath then methods.HandleDeath(owner,event) end
    end)
end
return M
