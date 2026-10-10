-- Identical cosmetic bullets submitted in one simulation frame overlap.
-- Damage stays in the existing tower callbacks/timers, one hit per request.
local catalog = require("config/asset_catalog")
local M = {}
local function path(value) return type(value)=="string" and value~="" and value or nil end
function M.resolve(tower, fallback)
    local asset=catalog.get(tower.survival_model_asset_id)
    return path(asset and asset.attack and asset.attack.projectile)
        or path(tower.survival_projectile_model) or fallback
end
function M.emit(tower, target, effect, speed, attachment)
    assert(path(effect), "Tower cosmetic projectile requires a nonempty effect")
    local time=GameRules and GameRules.GetGameTime and GameRules:GetGameTime()
    if time then
        local frame=tower.survival_cosmetic_projectile_frame
        if not frame or frame.time~=time then
            frame={time=time,targets={}}
            tower.survival_cosmetic_projectile_frame=frame
        end
        local previous=frame.targets[target]
        if previous and previous.effect==effect and previous.speed==speed
            and previous.attachment==attachment then return false end
        frame.targets[target]={effect=effect,speed=speed,attachment=attachment}
    end
    ProjectileManager:CreateTrackingProjectile({Source=tower,Target=target,
        Ability=nil,EffectName=effect,iMoveSpeed=speed,bIsAttack=false,
        bDodgeable=false,bProvidesVision=false,iSourceAttachment=attachment})
    return true
end
function M.clear(tower)
    if tower then tower.survival_cosmetic_projectile_frame=nil end
end
function M.precache(context)
    PrecacheResource("particle","particles/units/heroes/hero_sniper/sniper_base_attack.vpcf",context)
    PrecacheResource("particle","particles/units/heroes/hero_drow/drow_base_attack.vpcf",context)
end
return M
