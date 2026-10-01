-- Attack-triggered Ensnare. The modifier owns the native net for its lifetime;
-- refreshing the duration reuses it without a thinker or extra particles.
modifier_tower_drag_net = class({})
local M = modifier_tower_drag_net

function M:IsHidden() return false end
function M:IsDebuff() return true end
function M:IsPurgable() return true end
function M:GetTexture() return "naga_siren_ensnare" end

function M:CheckState()
    return {
        [MODIFIER_STATE_ROOTED] = true,
        [MODIFIER_STATE_INVISIBLE] = false,
    }
end

function M:OnCreated()
    if not IsServer() then return end
    local parent = self:GetParent()
    local particle = ParticleManager:CreateParticle(
        "particles/units/heroes/hero_siren/siren_net.vpcf",
        PATTACH_ABSORIGIN_FOLLOW, parent
    )
    -- Native net children use the target's hitboxes/bones at CP0. Binding the
    -- entity keeps the net on flying models rather than on the ground below.
    ParticleManager:SetParticleControlEnt(
        particle, 0, parent, PATTACH_ABSORIGIN_FOLLOW, "",
        parent:GetAbsOrigin(), true
    )
    self:AddParticle(particle, false, false, -1, false, false)
end

return M
