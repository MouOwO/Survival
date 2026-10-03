-- Native attack evidence only; fixture state belongs to the temporary unit,
-- never a file-local captured by the engine's separate modifier environment.
modifier_wall_crowd_probe=class({})
_G.modifier_wall_crowd_probe=modifier_wall_crowd_probe
function modifier_wall_crowd_probe:IsHidden() return true end
function modifier_wall_crowd_probe:IsPurgable() return false end
function modifier_wall_crowd_probe:DeclareFunctions() return {MODIFIER_EVENT_ON_ATTACK_LANDED} end
function modifier_wall_crowd_probe:OnAttackLanded(event)
    if not IsServer() or event.attacker~=self:GetParent() then return end
    local u=event.attacker
    local s=u.survival_crowd_probe
    if not s or event.target~=s.wall then return end
    local m=u:FindModifierByName('modifier_enemy_wall_ai')
    local p=u:GetAbsOrigin()
    local q=m and m.contact_move
    if not m or not m.contact_locked or not q or (p.x-q.x)^2+(p.y-q.y)^2>4 then
        s.invalid_hits=s.invalid_hits+1
    end
    local id=u:entindex()
    s.hits[id]=(s.hits[id] or 0)+1
    if s.hits[id]==1 then
        s.first_hit_orders[id]=m and m.last_order_time
        print('WALL_CROWD_FIRST_HIT',s.phase,id,GameRules:GetGameTime()-s.started,
            'relative',p.x-s.origin.x,p.y-s.origin.y,'range',u:Script_GetAttackRange())
    end
end
