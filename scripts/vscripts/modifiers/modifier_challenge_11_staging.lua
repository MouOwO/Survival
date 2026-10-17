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

-- Independent Tools experiments, sampled once for a newly staged formal unit.
-- Stack bit 1 is replicated so OUT_OF_GAME agrees in the server/client VMs.
-- Stack bit 2 records the separate server-side custom-health-bar experiment.
local function selected_probe(unit)
    local probe = rawget(_G, "SURVIVAL_CHALLENGE_STAGING_PROBE")
    if type(probe) ~= "table"
        or (probe.out_of_game ~= true and probe.pause_health_bar ~= true) then return nil end
    if not IsInToolsMode or not IsInToolsMode() or not GameRules
        or not GameRules.GetGameModeEntity or not GetMapName
        or GetMapName() ~= "template_map" then return nil end
    local mode = GameRules:GetGameModeEntity()
    local guard = rawget(_G, "SURVIVAL_REAL_GAME_STRESS_ISOLATION")
    if probe.mode ~= mode or probe.guard ~= guard or not guard or guard.mode ~= mode then return nil end
    if not unit or unit:IsNull() or unit.survival_challenge_11_staged ~= true
        or unit.survival_challenge_teardown == true
        or unit:GetClassname() ~= "npc_dota_creature"
        or unit:IsRealHero() ~= false or unit:GetTeamNumber() ~= DOTA_TEAM_BADGUYS then return nil end
    local number = tonumber(tostring(unit:GetUnitName()):match("^npc_survival_named_ten_sin_(%d%d)$"))
    local owner = tonumber(unit.survival_challenge_11_staged_owner)
    if not number or number < 1 or number > 10 or not owner or owner < 0
        or owner ~= math.floor(owner) then return nil end
    return probe, mode
end

function modifier_challenge_11_staging:OnCreated()
    if not IsServer() then return end
    local unit = self:GetParent()
    local ok, probe, mode = pcall(selected_probe, unit)
    if not ok or not probe then return end
    self.survival_staging_probe_sampled = true
    self.survival_staging_probe_mode = mode
    self.survival_staging_probe_out_of_game = probe.out_of_game == true
    self.survival_staging_probe_pause_health_bar = probe.pause_health_bar == true
    self:SetStackCount((self.survival_staging_probe_out_of_game and 1 or 0)
        + (self.survival_staging_probe_pause_health_bar and 2 or 0))
    if self.survival_staging_probe_pause_health_bar then
        unit.survival_challenge_staging_health_bar_paused = true
        unit.survival_challenge_staging_pause_modifier = self
        unit.survival_challenge_staging_pause_mode = mode
        local bar = unit.FindModifierByName and unit:FindModifierByName("modifier_single_health_bar")
        if bar and not bar:IsNull() and type(bar.PauseForChallengeStaging) == "function" then
            bar:PauseForChallengeStaging()
        end
    end
end

function modifier_challenge_11_staging:OnDestroy()
    if not IsServer() or self.survival_staging_probe_pause_health_bar ~= true then return end
    local unit = self:GetParent()
    if not unit or unit:IsNull() or unit.survival_challenge_staging_pause_modifier ~= self then return end
    unit.survival_challenge_staging_health_bar_paused = nil
    unit.survival_challenge_staging_pause_modifier = nil
    unit.survival_challenge_staging_pause_mode = nil
    local bar = unit.FindModifierByName and unit:FindModifierByName("modifier_single_health_bar")
    if bar and not bar:IsNull() and type(bar.ResumeAfterChallengeStaging) == "function" then
        bar:ResumeAfterChallengeStaging()
    end
end

function modifier_challenge_11_staging:CheckState()
    local states = {
        [MODIFIER_STATE_INVULNERABLE] = true,
        -- Idle presentation stays alive; disable combat/orders without a stun pose.
        [MODIFIER_STATE_DISARMED] = true,
        [MODIFIER_STATE_SILENCED] = true,
        [MODIFIER_STATE_MUTED] = true,
        [MODIFIER_STATE_ROOTED] = true,
        [MODIFIER_STATE_COMMAND_RESTRICTED] = true,
    }
    local stack = self.GetStackCount and self:GetStackCount() or 0
    if stack % 2 == 1 and MODIFIER_STATE_OUT_OF_GAME ~= nil then
        states[MODIFIER_STATE_OUT_OF_GAME] = true
    end
    return states
end

return modifier_challenge_11_staging
