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

function M.apply(unit, archetype)
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
    })
    if not ok or not applied then
        logger.warn("ChallengeMonsterVisual", "bundle apply failed asset="
            .. asset_id .. " status=" .. tostring(status or applied))
        return false, status or "visual_apply_failed"
    end
    return true, status
end

function M.clear(unit)
    if not unit then return false end
    local ok = pcall(building_visual.clear, unit)
    return ok
end

return M