-- One native attack/hurt listener replaces global listeners on every tower.
-- Keep the exact post-damage event (including native attacks and blocked hits).
local M = {}
local NAME = "modifier_tower_damage_observer"
local HOLDER_KEY = "survival_tower_damage_observer_holder"
local function valid(unit) return unit and not unit:IsNull() end
local function current_world()
    if not GameRules or type(GameRules.GetGameModeEntity) ~= "function" then return nil end
    local mode = GameRules:GetGameModeEntity()
    if mode and (not mode.IsNull or not mode:IsNull()) then return mode end
end
local function installed(unit)
    if not valid(unit) or type(unit.HasModifier) ~= "function" then return false end
    local ok, result = pcall(unit.HasModifier, unit, NAME)
    return ok and result == true
end

function M.is_ready()
    local mode = current_world()
    return mode ~= nil and installed(mode[HOLDER_KEY]) or false
end

function M.is_authoritative(unit)
    local mode = current_world()
    return mode ~= nil and mode[HOLDER_KEY] == unit and installed(unit) or false
end

function M.can_route_auto_attack()
    local mode = current_world()
    local holder = mode and mode[HOLDER_KEY]
    -- Only the real modifier's creation callback advertises its native route.
    -- Reloading this Lua service cannot upgrade an existing engine-cached holder.
    return mode ~= nil and installed(holder)
        and holder.survival_tower_auto_attack_observer_version == 1 or false
end

function M.register_auto_attack(unit, modifier)
    if not valid(unit) or not modifier or (modifier.IsNull and modifier:IsNull())
        or not M.can_route_auto_attack() then return false end
    -- A targeting-only tower needs no attack-effects modifier to receive the
    -- same native events. Keep its current owner on the attacker itself.
    unit.survival_tower_auto_attack_owner = modifier
    return true
end

function M.unregister_auto_attack(unit, modifier)
    if valid(unit) and unit.survival_tower_auto_attack_owner == modifier then
        unit.survival_tower_auto_attack_owner = nil
    end
end

function M.init()
    local current = current_world()
    if not current then return false end
    -- Reuse this GameMode's exact entity across module reloads. Do not recover
    -- a previous map's entity by index, and do not trust an empty thinker.
    if installed(current[HOLDER_KEY]) then return true end
    current[HOLDER_KEY] = nil
    local ok, unit = pcall(function()
        LinkLuaModifier(NAME, "modifiers/modifier_tower_damage_observer", LUA_MODIFIER_MOTION_NONE)
        return CreateModifierThinker(nil, nil, NAME, {}, Vector(0, 0, -10000), DOTA_TEAM_NEUTRALS, false)
    end)
    if ok and installed(unit) and current_world() == current then
        current[HOLDER_KEY] = unit
        return true
    end
    if ok and valid(unit) and type(UTIL_Remove) == "function" then pcall(UTIL_Remove, unit) end
    print("[TowerDamageObserver] unavailable; retaining per-tower native damage callbacks")
    return false
end
return M
