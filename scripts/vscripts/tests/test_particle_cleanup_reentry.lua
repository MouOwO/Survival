package.path = 'scripts/vscripts/?.lua;' .. package.path
local function load_service(name)
    local base = rawget(_G, 'PARTICLE_TEST_BASE') or 'scripts/vscripts'
    return assert(loadfile(base .. '/' .. name .. '.lua'))()
end
package.loaded['config/hero_cosmetics_config'] = {test = {particles = {{path = 'test_ambient'}}}}
package.loaded['config/asset_catalog'] = {resolve_bundle = function() return nil end}
package.loaded['core/scheduler'] = {cancel = function() end}
package.loaded['core/logger'] = {info = function() end, warn = function() end}
package.loaded['config/monster_visual_config'] = {}
package.loaded['systems/asset_preload_service'] = {}
package.loaded['config/global_rules'] = {}
local next_id, destroys, releases, callback = 0, {}, {}, nil
ParticleManager = {
    CreateParticle = function() next_id = next_id + 1; return next_id end,
    SetParticleControl = function() end,
    DestroyParticle = function(_, id)
        destroys[id] = (destroys[id] or 0) + 1
        local reenter = callback; callback = nil
        if reenter then reenter() end
    end,
    ReleaseParticleIndex = function(_, id) releases[id] = (releases[id] or 0) + 1 end,
}
local unit = {
    IsNull = function() return false end, entindex = function() return 7 end,
    SetModel = function() return true end, SetOriginalModel = function() return true end,
    GetPlayerOwnerID = function() return 0 end, IsHero = function() return true end,
    GetAttackRange = function() return 600 end,
}
local function once(id, label)
    assert(destroys[id] == 1, label .. ': engine re-entry must not destroy twice')
    assert(releases[id] == 1, label .. ': engine re-entry must not release twice')
end
local hero = load_service('systems/hero_cosmetic_service')
assert(hero.apply(unit, 'test'))
local id = next_id
callback = function() hero.clear(unit) end
hero.clear(unit); hero.clear(unit); once(id, 'hero cosmetics')
-- Retiring the old state must not erase a replacement created by a callback.
assert(hero.apply(unit, 'test')); id = next_id
callback = function() assert(hero.apply(unit, 'test')) end
hero.clear(unit); once(id, 'replaced hero old state')
hero.clear(unit); once(next_id, 'replaced hero new state')
local monster = load_service('systems/monster_visual_service')
assert(monster.apply(unit, {model_path = 'test.vmdl', effects = {{particle_path = 'test'}}}))
id = next_id; callback = function() monster.cleanup(unit) end
monster.cleanup(unit); monster.cleanup(unit); once(id, 'monster visuals')
local details = load_service('visual/monster_cosmetic_details')
details.apply(unit, {effects = {{effect_group_id = 'wave_cosmetic_ambient', particle_path = 'test'}}}, {})
id = next_id; callback = function() details.clear(unit) end
details.clear(unit); details.clear(unit); once(id, 'monster outfit')
local listener, disconnect
CustomGameEventManager = {RegisterListener = function(_, _, fn) listener = fn end}
ListenToGameEvent = function(_, fn) disconnect = fn end
EntIndexToHScript = function() return unit end
Vector = function(x, y, z) return {x = x, y = y, z = z} end
local ranges = load_service('systems/attack_range_display_service')
ranges.init(); listener(0, {visible = 1, entindex = 7})
id = next_id; callback = function() disconnect({PlayerID = 0}) end
listener(0, {visible = 0}); disconnect({PlayerID = 0}); once(id, 'attack range')
print('PARTICLE_CLEANUP_REENTRY_PASS four owners, duplicate cleanup, replacement survives')
