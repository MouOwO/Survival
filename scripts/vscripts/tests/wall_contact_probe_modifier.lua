modifier_wall_contact_probe_v2=class({})
_G.modifier_wall_contact_probe_v2=modifier_wall_contact_probe_v2
function modifier_wall_contact_probe_v2:IsHidden() return true end
function modifier_wall_contact_probe_v2:DeclareFunctions() return {MODIFIER_EVENT_ON_ATTACK_LANDED,MODIFIER_PROPERTY_ATTACK_RANGE_BONUS} end
function modifier_wall_contact_probe_v2:GetModifierAttackRangeBonus() return self:GetParent().survival_probe_range_bonus or 0 end
function modifier_wall_contact_probe_v2:OnAttackLanded(p)
    local unit=self:GetParent()
    if p.attacker==unit and unit.survival_contact_probe then
        local state=unit.survival_contact_probe
        if not state.hits[unit:entindex()] then
            state.hits[unit:entindex()]=true
            local d=unit:GetAbsOrigin()-state.wall:GetAbsOrigin()
            print("WALL_CONTACT_HIT",unit:entindex(),d:Length2D(),d.x,d.y)
        end
    end
end
