-- Loaded only by the explicitly invoked Tools stress fixture. No interval think,
-- invulnerability, armor/health edits, damage reduction, or native attack changes.
modifier_manual_real_game_stress_wall=class({})
_G.modifier_manual_real_game_stress_wall=modifier_manual_real_game_stress_wall
local M=modifier_manual_real_game_stress_wall
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:IsPurgeException() return false end
function M:RemoveOnDeath() return false end
function M:OnCreated()
    if not IsServer() then return end
    self.scene=_G.SURVIVAL_REAL_GAME_STRESS
    self.guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    self:SetStackCount(1)
end
function M:DeclareFunctions() return {MODIFIER_PROPERTY_MIN_HEALTH} end
function M:GetMinHealth()
    if not IsServer() then return self:GetStackCount()==1 and 1 or 0 end
    local parent=self:GetParent()
    local scene,guard=self.scene,self.guard
    if IsInToolsMode() and scene and guard and parent and not parent:IsNull()
        and parent.survival_building_id=='wall'
        and scene==_G.SURVIVAL_REAL_GAME_STRESS and guard==_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
        and scene.mode==GameRules:GetGameModeEntity() and guard.mode==scene.mode
        and (scene.status=='preparing' or scene.status=='ready')
        and guard.wall_targets[parent]==scene then return 1 end
    -- A stale engine/scene binding immediately becomes an ordinary modifier,
    -- even if an explicit stop could not execute during map shutdown.
    self:SetStackCount(0)
    return 0
end
return M
