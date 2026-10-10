-- One native landed listener for all workers; no polling or entity searches.
local M = {}
local NAME = "modifier_lumberjack_attack_observer"
local HOLDER_KEY = "survival_lumberjack_attack_observer_holder"
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

function M.init()
    local current = current_world()
    if not current then return false end
    -- GameMode owns the handle across Lua module reloads. A new map has its
    -- own GameMode; never recover another world's handle by entity index.
    if installed(current[HOLDER_KEY]) then return true end
    current[HOLDER_KEY] = nil
    local ok, unit = pcall(function()
        LinkLuaModifier(NAME, "modifiers/modifier_lumberjack_attack_observer", LUA_MODIFIER_MOTION_NONE)
        return CreateModifierThinker(nil, nil, NAME, {}, Vector(0, 0, -10000), DOTA_TEAM_NEUTRALS, false)
    end)
    if ok and installed(unit) and current_world() == current then
        current[HOLDER_KEY] = unit
        return true
    end
    -- A thinker handle can exist even when loading its Lua modifier failed.
    -- Never suppress per-worker event declarations on that false success.
    if ok and valid(unit) and type(UTIL_Remove) == "function" then pcall(UTIL_Remove, unit) end
    print("[LumberjackAttackObserver] unavailable; retaining per-worker landed callbacks")
    return false
end

return M
