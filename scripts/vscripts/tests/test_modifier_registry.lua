package.path = "scripts/vscripts/?.lua;" .. package.path
local file = assert(io.open("scripts/vscripts/core/modifier_registry.lua", "rb"))
local source = file:read("*a"); file:close()
local by_path, names, paths = {}, {}, {}
for name, path in source:gmatch('name%s*=%s*"([^"]+)"%s*,%s*path%s*=%s*"([^"]+)"') do
    if not by_path[path] then by_path[path] = {}; paths[#paths+1] = path end
    by_path[path][#by_path[path]+1] = name
    names[#names+1] = name
end
assert(#names > 20)
local loads, links, bindings = 0, 0, {}
LUA_MODIFIER_MOTION_NONE = 0
LUA_MODIFIER_MOTION_HORIZONTAL = 1
package.loaded["core/logger"] = { info = function() end }
for path, list in pairs(by_path) do
    local module_path, module_names = path, list
    package.preload[module_path] = function()
        loads = loads + 1
        for _, name in ipairs(module_names) do _G[name] = {} end
        -- A late dependency reload may replace an earlier class. The engine
        -- must receive that final class, not an earlier or missing table.
        if loads == #paths then _G[names[1]] = { final = true } end
        return true
    end
end
LinkLuaModifier = function(name, path, motion)
    assert(loads == #paths, "binding happened before all definitions loaded")
    assert(type(_G[name]) == "table" and path == "modifier_bindings/" .. name)
    assert(motion == 0 or motion == 1)
    -- Engine script scopes are separate from Lua's cached module globals.
    local scope = setmetatable({}, { __index = _G })
    local entry = assert(loadfile("scripts/vscripts/" .. path .. ".lua"))
    setfenv(entry, scope); entry()
    assert(rawget(scope, name) == _G[name], "class was not exported into engine scope")
    bindings[name] = rawget(scope, name); links = links + 1
end
local registry = require("core/modifier_registry")
assert(links == 0 and loads == 0, "requiring registry must not partially bootstrap")
assert(registry.register())
assert(links == #names and bindings[names[1]].final)
local reported = {
    "wall_collision_barrier",
    "single_health_bar", "debug_attack_cap", "survival_hero_attack_range",
    "survival_hero_base_health", "survival_hero_mana_standard", "weapon_stat_projection",
    "equipment_effects", "weapon_attack_tracker", "research_technology",
    "survival_hero_skill", "monkey_king_clone", "debug_fixed_attack_rate",
}
for _, suffix in ipairs(reported) do assert(bindings["modifier_" .. suffix], suffix) end
bindings = {} -- Simulate engine bindings needing refresh, Lua cache intact.
assert(registry.register())
assert(loads == #paths and links == #names * 2)
for _, name in ipairs(names) do assert(bindings[name] == _G[name]) end
_G[names[1]] = true
assert(not registry.validate())
local before = links
local ok, message = pcall(registry.register)
assert(not ok and tostring(message):find(names[1], 1, true))
assert(links == before, "invalid definitions must fail before partial registration")
print("MODIFIER_REGISTRY_PASS: load ordering, reported modifiers, cache refresh, validation")
