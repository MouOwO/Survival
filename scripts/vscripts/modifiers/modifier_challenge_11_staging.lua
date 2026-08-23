LinkLuaModifier("modifier_challenge_11_staging", "modifiers/modifier_challenge_11_staging", LUA_MODIFIER_MOTION_NONE)

modifier_challenge_11_staging = class({})

function modifier_challenge_11_staging:IsHidden()
    return true
end

function modifier_challenge_11_staging:IsPurgable()
    return false
end

function modifier_challenge_11_staging:RemoveOnDeath()
    return false
end

function modifier_challenge_11_staging:CheckState()
    return {
        [MODIFIER_STATE_INVULNERABLE] = true,
        [MODIFIER_STATE_STUNNED] = true,
        [MODIFIER_STATE_ROOTED] = true,
        [MODIFIER_STATE_COMMAND_RESTRICTED] = true,
    }
end

return modifier_challenge_11_staging