local building_visual = require("systems/building_visual_service")
local logger = require("core/logger")

local M = {}

local function safe_call(target, method_name, ...)
    local method = target and target[method_name]
    if type(method) ~= "function" then return false end
    return pcall(method, target, ...)
end

local function apply_attack_presentation(unit, archetype)
    local ranged = archetype.attack_type == "ranged"
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

    local projectile = tostring(archetype.projectile_model or "")
    if projectile ~= "" then
        safe_call(unit, "SetRangedProjectileName", projectile)
    end
    local speed = tonumber(archetype.projectile_speed)
    if speed and speed > 0 then
        safe_call(unit, "SetProjectileSpeed", speed)
        unit.survival_projectile_speed = speed
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
