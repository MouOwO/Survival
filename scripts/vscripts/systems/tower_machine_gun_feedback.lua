-- Presentation only: never attacks, applies damage, grants gold, or changes speed.
local asset_catalog = require("config/asset_catalog")
local sound_service = require("core/sound_service")
local scheduler = require("core/scheduler")
local M = { GOLD_PARTICLE = "particles/generic_gameplay/lasthit_coins.vpcf" }

function M.shot(tower, target)
    local asset = asset_catalog.get(tower.survival_model_asset_id)
    local projectile = asset and asset.attack and asset.attack.projectile
    local speed = 2000
    if type(tower.GetProjectileSpeed) == "function" then
        local ok, value = pcall(tower.GetProjectileSpeed, tower)
        if ok and (tonumber(value) or 0) > 0 then speed = value end
    end
    -- The native attack projectile is suppressed by the attack modifier. These
    -- per-hit projectiles are visual only, so they cannot add hits or delay DPS.
    ProjectileManager:CreateTrackingProjectile({
        Source = tower, Target = target, Ability = nil,
        EffectName = projectile or "particles/units/heroes/hero_sniper/sniper_base_attack.vpcf",
        iMoveSpeed = speed, bIsAttack = false, bDodgeable = false,
        bProvidesVision = false,
        iSourceAttachment = rawget(_G, "DOTA_PROJECTILE_ATTACHMENT_ATTACK_1"),
    })
    sound_service.play("tower_machine_gun", {source=tower, unit=tower})
end

function M.flush_gold(state, tower)
    if state.gold_number_task then
        scheduler.cancel(state.gold_number_task)
        state.gold_number_task = nil
    end
    local amount = math.floor((tonumber(state.pending_gold_number) or 0) + 0.000001)
    if amount <= 0 then return end
    if not tower or tower:IsNull() or type(SendOverheadEventMessage) ~= "function" then return end
    local player_id = tonumber(tower.survival_player_id)
    local player = player_id and player_id >= 0 and PlayerResource and PlayerResource:GetPlayer(player_id) or nil
    -- The number belongs to this tower, and counts successful rewards only.
    SendOverheadEventMessage(player, OVERHEAD_ALERT_GOLD, tower, amount, nil)
    state.pending_gold_number = math.max(0, (state.pending_gold_number or 0) - amount)
end

function M.gold(state, tower, amount)
    local now = GameRules:GetGameTime()
    local sequence = tonumber(state.machine_gun_sequence) or 0
    state.pending_gold_number = (tonumber(state.pending_gold_number) or 0) + math.max(0, tonumber(amount) or 0)
    -- Machine-gun rounds flush on their final actual hit (or cancellation).
    -- Fusion towers inherit bounty hits without rounds; coalesce those by time.
    if sequence == 0 and not state.gold_number_task then
        state.gold_number_task = scheduler.after(0.8, function()
            state.gold_number_task = nil
            M.flush_gold(state, tower)
        end)
    end
    if now < (state.next_gold_feedback_at or 0)
        or (sequence > 0 and state.gold_feedback_sequence == sequence) then return false end
    state.next_gold_feedback_at = now + 0.8
    state.gold_feedback_sequence = sequence
    local origin = tower:GetAbsOrigin()
    local height = 155
    if type(tower.GetBoundingMaxs) == "function" then
        local ok, bounds = pcall(tower.GetBoundingMaxs, tower)
        if ok and bounds then height = math.max(120, math.min(240, (tonumber(bounds.z) or 135) + 20)) end
    end
    local position = Vector(origin.x, origin.y, origin.z + height)
    local index
    local ok = pcall(function()
        index = ParticleManager:CreateParticle(M.GOLD_PARTICLE, PATTACH_CUSTOMORIGIN, tower)
        -- Native last-hit coin models are emitted around CP1, not CP0.
        ParticleManager:SetParticleControl(index, 0, position)
        ParticleManager:SetParticleControl(index, 1, position)
    end)
    if type(index) == "number" and index >= 0 then
        if not ok then pcall(ParticleManager.DestroyParticle, ParticleManager, index, true) end
        pcall(ParticleManager.ReleaseParticleIndex, ParticleManager, index)
    end
    sound_service.play("tower_bounty_machine_gun", {
        source=tower, unit=tower,
        limiter_scope="tower_gold_player:" .. tostring(tower.survival_player_id or tower:GetTeamNumber()),
    })
    return ok
end

return M
