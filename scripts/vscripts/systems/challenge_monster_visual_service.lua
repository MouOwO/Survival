local building_visual = require("systems/building_visual_service")
local logger = require("core/logger")

local M = {}
local RANGE_MODIFIER = "modifier_survival_hero_attack_range"
local SPEED_MODIFIER = "modifier_survival_hero_projectile_speed"

local function safe_call(target, method_name, ...)
    local method = target and target[method_name]
    if type(method) ~= "function" then return false end
    return pcall(method, target, ...)
end

local function apply_attack_presentation(unit, archetype)
    local ranged = archetype.attack_type == "ranged"
    local native_ranged = archetype.native_attack_presentation_policy == "ranged_v1"
    local capability = ranged
        and rawget(_G, "DOTA_UNIT_CAP_RANGED_ATTACK")
        or rawget(_G, "DOTA_UNIT_CAP_MELEE_ATTACK")
    if capability ~= nil then
        safe_call(unit, "SetAttackCapability", capability)
    end

    if not ranged then
        safe_call(unit, "SetRangedProjectileName", "")
        unit.survival_projectile_speed = nil
        return
    end

    -- Live creatures have no attack-range setter. Use the same replicated
    -- base override as heroes/towers after initializing the melee stat template.
    local reach = tonumber(archetype.attack_range)
    if native_ranged and reach and reach > 0 then
        local modifier = unit.FindModifierByName and unit:FindModifierByName(RANGE_MODIFIER)
        if modifier and modifier.SetAttackRange then
            modifier:SetAttackRange(reach)
        elseif unit.AddNewModifier then
            unit:AddNewModifier(unit, nil, RANGE_MODIFIER, {attack_range = reach})
        end
    end

    local projectile = tostring(archetype.projectile_model or "")
    if projectile ~= "" then
        safe_call(unit, "SetRangedProjectileName", projectile)
    end
    local speed = tonumber(archetype.projectile_speed)
    if speed and speed > 0 then
        unit.survival_projectile_speed = speed
        if not safe_call(unit, "SetProjectileSpeed", speed) and native_ranged
            and unit.GetProjectileSpeed and unit.AddNewModifier then
            local modifier = unit.FindModifierByName and unit:FindModifierByName(SPEED_MODIFIER)
            local previous = modifier and modifier:GetStackCount() or 0
            local bonus = speed - (unit:GetProjectileSpeed() - previous)
            if modifier then
                modifier:SetProjectileSpeedBonus(bonus)
            elseif bonus ~= 0 then
                unit:AddNewModifier(unit, nil, SPEED_MODIFIER, {projectile_speed_bonus = bonus})
            end
            safe_call(unit, "CalculateStatBonus", true)
        end
    end
end

function M.apply(unit, archetype, options)
    if not unit or type(archetype) ~= "table" then
        return false, "invalid_arguments"
    end

    apply_attack_presentation(unit, archetype)

    local asset_id = tostring(archetype.model_asset_id or "")
    if asset_id == "" then return true, "attack_only" end
    local ok, applied, status = pcall(building_visual.apply, unit, {
        model_asset_id = asset_id,
        model_name = archetype.model_path,
        model_scale = tonumber(archetype.model_scale),
    }, options)
    if not ok or not applied then
        logger.warn("ChallengeMonsterVisual", "bundle apply failed asset="
            .. asset_id .. " status=" .. tostring(status or applied))
        return false, status or "visual_apply_failed"
    end
    unit.survival_challenge_monster_visual = true
    return true, status
end

function M.on_death(unit)
    if not unit then return false end
    if unit.survival_challenge_monster_visual == nil
        and unit.survival_model_asset_id ~= nil then
        unit.survival_challenge_monster_visual = true
    end
    if unit.survival_challenge_monster_visual ~= true then return true end
    building_visual.stop_particles(unit)
    if unit.survival_monster_corpse == true
        and unit.survival_wave_cleanup ~= true then return true end
    return M.clear(unit)
end

function M.clear(unit)
    if not unit then return false end
    -- Default hero outfits and attack-only creatures do not belong to this
    -- service. Avoid a second appearance clear or legacy world discovery.
    if unit.survival_challenge_monster_visual == false then return true end
    if unit.survival_challenge_monster_visual ~= true
        and unit.survival_model_asset_id == nil then return true end
    unit.survival_challenge_monster_visual = false
    local ok = pcall(building_visual.clear, unit)
    return ok
end

return M
