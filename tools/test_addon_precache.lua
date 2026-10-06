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
assert(calls["particles/survival/skills/earth_phoenix_impact_core.vpcf"] == 1,
    "Earth Line must preload the complete elevated Phoenix explosion core")
for _, radius in ipairs({75, 125, 300}) do
    assert(calls["particles/survival/skills/earth_phoenix_impact_" .. radius .. ".vpcf"] == 1,
        "each authored Earth Line Phoenix impact must be precached once")
end
assert(calls["particles/survival_earth_line/survival_earth_line_chaos_meteor.vpcf"] == 1,
    "Earth Line must retain the complete rolling meteor and native trail")
assert(calls["particles/basic_projectile/basic_projectile_explosion.vpcf"] == nil,
    "the retired Earth Line explosion must not be precached")
assert(calls["particles/survival/skills/meteor_lava.vpcf"]==1)
for _, path in ipairs({
    "particles/units/heroes/hero_snapfire/snapfire_lizard_blobs_arced.vpcf",
    "particles/units/heroes/hero_snapfire/hero_snapfire_ultimate_impact.vpcf",
    "particles/units/heroes/hero_snapfire/hero_snapfire_ultimate_linger.vpcf",
}) do
    assert(calls[path]==1, "complete original Snapfire roots must each be precached once")
end
for _, path in ipairs({
    "particles/units/heroes/hero_snapfire/hero_snapfire_ultimate_impact_directional.vpcf",
    "particles/units/heroes/hero_snapfire/hero_snapfire_ultimate_shockwave.vpcf",
    "particles/units/heroes/hero_snapfire/hero_snapfire_ultimate_impact_burst.vpcf",
    "particles/units/heroes/hero_snapfire/hero_snapfire_ult_ground_splash_liquid.vpcf",
    "particles/units/heroes/hero_snapfire/hero_snapfire_ult_ground_splash.vpcf",
    "particles/units/heroes/hero_snapfire/hero_snapfire_ult_ground_bubble.vpcf",
}) do
    assert(calls[path]==nil, "Arcane preloads the complete linger graph without separate child roots")
end
for _, path in ipairs({
    "particles/survival/skills/arcane_snapfire_fall.vpcf",
    "particles/survival/skills/arcane_snapfire_impact.vpcf",
    "particles/survival/skills/arcane_snapfire_linger.vpcf",
    "particles/survival/skills/arcane_silver_squall_impact.vpcf",
    "particles/survival/skills/arcane_silver_squall_field.vpcf",
    "particles/survival/skills/ice_cone_silver_squall_fall.vpcf",
    "particles/survival/skills/ice_cone_silver_squall_impact.vpcf",
    "particles/survival/skills/ice_cone_silver_squall_field.vpcf",
    "particles/survival/skills/frost_tusk_snowball.vpcf",
}) do
    assert(calls[path]==nil, "retired Arcane fire particles must not be precached")
end
assert(calls["particles/survival/skills/arcane_gyro_impact.vpcf"]==nil,
    "the retired arcane Gyrocopter impact root must not be precached")
assert(calls["particles/units/heroes/hero_skywrath_mage/skywrath_mage_mystic_flare.vpcf"]==nil,
    "the retired arcane Mystic Flare root must not be precached")
for _, path in ipairs({
    "particles/econ/items/snapfire/snapfire_frostivus_2023/snapfire_frostivus_ultimate_lizard_blobs_arced.vpcf",
    "particles/econ/items/snapfire/snapfire_frostivus_2023/snapfire_frostivus_ultimate_impact.vpcf",
    "particles/units/heroes/hero_winter_wyvern/wyvern_winters_curse_ground.vpcf",
    "particles/units/heroes/hero_winter_wyvern/wyvern_winters_curse.vpcf",
    "particles/status_fx/status_effect_wyvern_curse_target.vpcf",
}) do
    assert(calls[path]==1, "Ice Cone must precache its original Silver Squall resources once")
end
for _, suffix in ipairs({
    "linger_shockwave", "linger_impact_burst", "linger_ground_shockwave",
    "linger_impact_glow", "linger_torns", "linger_ground_sparks",
}) do
    local path = "particles/econ/items/snapfire/snapfire_frostivus_2023/snapfire_frostivus_ultimate_"
        .. suffix .. ".vpcf"
    assert(calls[path] == 1, "Ice Cone must precache each complete native landing layer once: " .. suffix)
end
assert(calls["particles/econ/items/snapfire/snapfire_frostivus_2023/snapfire_frostivus_ultimate_linger.vpcf"]==nil,
    "Ice Cone must not preload the retired Silver Squall ground ring")
assert(calls["particles/units/heroes/hero_winter_wyvern/wyvern_winters_curse_proj.vpcf"]==nil,
    "Ice Cone preloads the complete Winter's Curse ground graph rather than its isolated projection")
assert(calls["particles/econ/items/crystal_maiden/crystal_maiden_maiden_of_icewrack/maiden_freezing_field_explosion_arcana1.vpcf"]==nil,
    "the retired ice cone Freezing Field impact must not be precached")
assert(calls["particles/survival/skills/blade_swashbuckle.vpcf"]==1,
    "the blade Pangolier Swashbuckle root must be precached once")
assert(calls["particles/units/heroes/hero_magnataur/magnataur_shockwave.vpcf"]==nil,
    "the retired blade Magnus Shockwave root must not be precached")
assert(calls["particles/survival/skills/tusk_snowball_fixed_size.vpcf"]==1,
    "the fixed-birth-size Tusk root and its native endcap dependencies must be precached once")
assert(calls["particles/units/heroes/hero_tusk/tusk_snowball.vpcf"]==nil,
    "the growing original Tusk root must be replaced by its fixed-size variant")
assert(calls["particles/units/heroes/hero_tusk/tusk_snowball_impact.vpcf"]==1,
    "the original native Tusk impact fallback must remain precached once")
assert(calls["particles/units/heroes/hero_puck/puck_illusory_orb_main.vpcf"]==nil,
    "the retired moving ice ball Puck Orb root must not be precached")
assert(calls["particles/survival/skills/poison_sullen_shroud.vpcf"]==1,
    "the poison Sullen Rampart Ghost Shroud root must be precached once")
assert(calls["particles/units/heroes/hero_viper/viper_nethertoxin.vpcf"]==nil,
    "the retired poison Viper Nethertoxin root must not be precached")
assert(calls["particles/survival_tornado/survival_tornado_follow.vpcf"]==1,
    "the ordinary Invoker Tornado wrapper must be precached once")
assert(calls["particles/survival/skills/void_world_chasm.vpcf"]==nil,
    "the retired World Chasm replacement must not be precached")
assert(calls["particles/survival/skills/meteor_impact.vpcf"]==nil
    and calls["particles/survival/skills/meteor_impact_sparks.vpcf"]==nil,
    "retired custom explosion roots must not be precached")
assert(phases["asset_preload_service.precache_initial"])
assert(phases["systems/startup_asset_preload_service.precache"], "must reach final startup preload after all direct resources")
-- The original four-argument shape must fail this harness, not silently pass.
local ok=pcall(env.PrecacheResource,"particle","ground.vpcf","snow.vpcf",context)
assert(not ok)
local count=0;for _ in pairs(calls) do count=count+1 end
print("ADDON_PRECACHE_ENTRY_PASS: strict API signatures, current skill roots including poison Sullen Shroud without retired resources, tail startup preload; resources="..count)
