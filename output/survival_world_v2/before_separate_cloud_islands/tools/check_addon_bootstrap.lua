-- Run from the addon root with Lua 5.1. Use real gameplay/config modules;
-- mock only engine globals needed while loading them. This does not run a map.
package.path = "scripts/vscripts/?.lua;" .. package.path

function class(definition) return definition or {} end
function LinkLuaModifier() end
function IsServer() return true end
function Vector(x, y, z) return { x = x, y = y, z = z } end
function GetMapName() return "template_map" end

local calls = {}
local mode = {
    SetCustomGameForceHero = function(_, hero) calls.force_hero = hero end,
}
GameRules = { GetGameModeEntity = function() return mode end }
for _, name in ipairs({
    "SetCustomGameSetupTimeout", "SetHeroSelectionTime", "SetShowcaseTime",
    "SetStrategyTime", "SetCustomGameTeamMaxPlayers",
    "EnableCustomGameSetupAutoLaunch", "SetCustomGameSetupAutoLaunchDelay",
}) do
    local key = name
    GameRules[key] = function(_, value) calls[key] = value end
end
setmetatable(_G, { __index = function(_, key)
    if key:match("^DOTA_") or key:match("^LUA_MODIFIER_")
        or key:match("^MODIFIER_") or key:match("^PATTACH_")
        or key:match("^DAMAGE_TYPE_") or key:match("^ACT_") then
        return 0
    end
end })

local ok, err = xpcall(function()
    local addon = require("addon_game_mode")
    assert(type(addon.activate) == "function", "activation callback missing")
    assert(type(Activate) == "function", "engine Activate callback missing")
    assert(type(Precache) == "function", "engine Precache callback missing")
    assert(calls.SetHeroSelectionTime == 0, "hero selection must be skipped")
    assert(calls.SetStrategyTime == 0, "strategy must be skipped")
    assert(calls.SetShowcaseTime == 0, "showcase must be skipped")
    assert(calls.force_hero == "npc_dota_hero_undying", "starting hero missing")
    assert(calls.EnableCustomGameSetupAutoLaunch == true, "auto launch missing")
end, debug.traceback)
if not ok then
    io.stderr:write(tostring(err), "\n")
    os.exit(1)
end
print("ADDON_FULL_MODULE_BOOTSTRAP_PASS")
