-- Execute the real addon precache entry body with strict engine signatures.
-- Subsystem internals have separate tests; this covers the orchestration itself.
package.path = "scripts/vscripts/?.lua;" .. package.path
local f = assert(io.open("scripts/vscripts/addon_game_mode.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local first = assert(source:find("function M.precache(context)", 1, true))
local last = assert(source:find("-- Keep each initialization phase", first, true))
local body = source:sub(first, last - 1)
local context, calls, phases = {}, {}, {}
local function service(name)
    return setmetatable({rows={}}, {__index=function(_, method)
        return function(actual)
            assert(actual == context, name .. "." .. method .. " lost engine context")
            phases[name .. "." .. method] = true
        end
    end})
end
local env = setmetatable({M={}}, {__index=function(_, key)
    if _G[key] ~= nil then return _G[key] end
    return service(key)
end})
env.require = function(name)
    if name:find("config/",1,true)==1 then return require(name) end
    return service(name)
end
env.PrecacheResource = function(...)
    assert(select('#',...)==3, "PrecacheResource must have exactly 3 arguments")
    local kind,path,actual=...
    assert(actual==context and type(path)=="string" and path~="")
    assert(kind=="model" or kind=="particle" or kind=="soundfile")
    calls[path]=(calls[path] or 0)+1
end
env.PrecacheUnitByNameSync = function(...)
    assert(select('#',...)==2)
    local name,actual=...;assert(type(name)=="string" and actual==context)
end
local chunk=assert(loadstring(body,"@addon_precache_entry"));setfenv(chunk,env);chunk()
env.M.precache(context)
assert(calls["particles/survival/skills/blizzard_ground.vpcf"]==1)
assert(calls["particles/survival/skills/wyvern_blizzard_snow.vpcf"]==1)
assert(calls["particles/survival/skills/meteor_phoenix_fall.vpcf"]==1)
assert(calls["particles/survival/skills/meteor_phoenix_impact.vpcf"]==1,
    "the complete Phoenix impact must be precached once with the native context")
assert(calls["particles/survival/skills/meteor_lava.vpcf"]==1)
assert(calls["particles/survival/skills/meteor_impact.vpcf"]==nil
    and calls["particles/survival/skills/meteor_impact_sparks.vpcf"]==nil,
    "retired custom explosion roots must not be precached")
assert(phases["asset_preload_service.precache_initial"])
assert(phases["systems/startup_asset_preload_service.precache"], "must reach final startup preload after all direct resources")
-- The original four-argument shape must fail this harness, not silently pass.
local ok=pcall(env.PrecacheResource,"particle","ground.vpcf","snow.vpcf",context)
assert(not ok)
local count=0;for _ in pairs(calls) do count=count+1 end
print("ADDON_PRECACHE_ENTRY_PASS: strict API signatures, both blizzard resources, complete meteor roots without retired explosion, tail startup preload; resources="..count)
