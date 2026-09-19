-- Exercise real definition files in independent server/client environments,
-- including engine script scopes after Lua's require cache is populated.
local function make_vm(server)
    local env = {}
    for key, value in pairs(_G) do env[key] = value end
    env._G = env
    env.class = function(value) return value end
    env.IsServer = function() return server end
    env.LinkLuaModifier = function() end
    local cache = {}
    env.require = function(path)
        if cache[path] ~= nil then return cache[path] end
        local chunk = assert(loadfile("scripts/vscripts/" .. path .. ".lua"))
        setfenv(chunk, env)
        cache[path] = chunk() or true
        return cache[path]
    end
    return env
end

local names = {
    "modifier_weapon_stat_projection", "modifier_research_technology",
    "modifier_equipment_effects", "modifier_survival_hero_base_health",
    "modifier_single_health_bar",
}
local server_vm, client_vm = make_vm(true), make_vm(false)
for _, vm in ipairs({server_vm, client_vm}) do
    for _, name in ipairs(names) do
        local path = "modifiers/" .. name
        vm.require(path)
        local cached = vm[name]
        assert(type(cached) == "table" and type(cached.OnCreated) == "function", name)
        for attempt = 1, 2 do
            local scope = setmetatable({}, {__index = vm})
            local chunk = assert(loadfile("scripts/vscripts/" .. path .. ".lua"))
            setfenv(chunk, scope); chunk()
            assert(rawget(scope, name) == cached, "engine scope lost class identity: " .. name)
            assert(vm[name] == cached, "a relink replaced the live class: " .. name)
        end
    end
end
for _, name in ipairs(names) do
    assert(server_vm[name] ~= client_vm[name], "VMs must not share class tables")
end
print("MODIFIER_DEFINITION_SCOPES_PASS: real files, independent VMs, cached require, stable classes")
