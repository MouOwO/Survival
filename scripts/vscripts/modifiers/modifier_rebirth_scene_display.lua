modifier_rebirth_scene_display = class({})

function modifier_rebirth_scene_display:IsHidden() return true end
function modifier_rebirth_scene_display:IsPurgable() return false end
function modifier_rebirth_scene_display:RemoveOnDeath() return false end

function modifier_rebirth_scene_display:CheckState()
    return {
        [MODIFIER_STATE_INVULNERABLE] = true,
        -- Inspectable arena previews; combat and orders remain disabled.
        [MODIFIER_STATE_NO_HEALTH_BAR] = true,
        [MODIFIER_STATE_NO_UNIT_COLLISION] = true,
        [MODIFIER_STATE_NOT_ON_MINIMAP] = true,
        [MODIFIER_STATE_COMMAND_RESTRICTED] = true,
        [MODIFIER_STATE_DISARMED] = true,
        [MODIFIER_STATE_SILENCED] = true,
        [MODIFIER_STATE_MUTED] = true,
        [MODIFIER_STATE_PASSIVES_DISABLED] = true,
        [MODIFIER_STATE_ROOTED] = true,
    }
end

return modifier_rebirth_scene_display
