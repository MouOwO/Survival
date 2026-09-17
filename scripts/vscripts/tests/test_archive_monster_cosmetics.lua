package.path = "scripts/vscripts/?.lua;" .. package.path
local defs = require("config/generated/archive_challenge_definitions")
local catalog = require("config/asset_catalog")
local hero_visual = require("systems/monster_hero_visual_service")
local next_id, spawned, rewarded, deaths = 0, nil, 0, 0
local function noop() end
local function entity()
    next_id = next_id + 1
    local unit = { id = next_id, abilities = {} }
    function unit:IsNull() return false end
    function unit:entindex() return self.id end
    function unit:IsAlive() return not self.dead end
    function unit:GetAbsOrigin() return { x = 0, y = 0, z = 0 } end
    function unit:FindAbilityByName(name) return self.abilities[name] end
    function unit:AddAbility(name)
        local ability = { IsNull = function() return false end, SetLevel = noop,
            SetActivated = noop, StartCooldown = noop,
            GetCaster = function() return self end,
            GetAbilityName = function() return name end }
        self.abilities[name] = ability
        return ability
    end
    unit.SetControllableByPlayer, unit.SetModel = noop, noop
    unit.SetOriginalModel, unit.SetModelScale, unit.AddNewModifier = noop, noop, noop
    return unit
end
GameRules = { GetGameTime = function() return 0 end }
Vector = function(x, y, z) return { x = x, y = y, z = z } end
CreateUnitByName = entity
package.loaded["systems/player_context_service"] = {
    register_unit = noop, owner_player_id = function() return 0 end,
}
package.loaded["systems/wave_system"] = {
    get_player_spawn_marker = entity,
    spawn_challenge_monster = function(stats, definition)
        local asset = assert(hero_visual.resolve(definition, {
            challenge = true, allow_outside_formal_wave = true,
            model_path = definition.model_path,
        }), "summon did not forward a resolvable outfit")
        assert(asset.primary_model == definition.model_path)
        assert(stats.health > 0 and stats.attack > 0)
        spawned = entity()
        spawned.asset_id = asset.asset_id
        return spawned
    end,
}
package.loaded["systems/archive_service"] = {
    record_challenge = function() rewarded = rewarded + 1 end,
}
package.loaded["systems/archive_endless_service"] = { init = noop, is_running = function() return false end }
package.loaded["systems/archive_endless_config"] = { group = function() return {} end,
    rules = { model_path = "models/heroes/nevermore/nevermore.vmdl" } }
local precached = {}
PrecacheResource = function(kind, path) precached[kind .. ":" .. path] = true end
local bus = require("core/event_bus")
local events = require("core/events")
local service = require("systems/archive_challenge_service")
service.init()
service.precache({})
assert(service.begin({ difficulty_id = "N10", player_ids = { 0 } }).keep_running)
local original_death = hero_visual.on_death
hero_visual.on_death = function() deaths = deaths + 1 end
local count = 0
for _, row in ipairs(defs.rows) do
    local asset = assert(catalog.resolve(row.default_wearable_asset_id))
    assert(asset.portrait_unit_name:match("^npc_dota_hero_") and not asset.portrait_item_def,
        "archive outfit must use an unmodified hero portrait")
    assert(precached["model:" .. asset.primary_model])
    local slots = {}
    for _, c in ipairs(asset.components or {}) do
        assert(not slots[c.component_id], "duplicate component slot")
        slots[c.component_id] = true
        assert(precached["model:" .. c.model_path], "component not precached")
    end
    for _, fx in ipairs(asset.effects or {}) do
        assert(precached["particle:" .. fx.particle_path], "particle not precached")
    end
    local hub = service._test.players()[0].hubs[row.building_id]
    assert(service.summon(hub, row.challenge_id, hub:FindAbilityByName("ability_archive_" .. row.challenge_id)))
    assert(spawned.asset_id == row.default_wearable_asset_id)
    spawned.dead = true
    bus.emit(events.ENGINE_ENTITY_KILLED, { victim = spawned })
    count = count + 1
    assert(rewarded == count and deaths == count, "death did not preserve visual lifecycle/rewards")
end
hero_visual.on_death = original_death
assert(count == 25)
for i = 1, 3 do
    assert(catalog.resolve("monster_archive_cage_" .. i).model_skin == i - 1)
end
assert(catalog.resolve("monster_archive_hunt_08").model_skin == 2, "Pudge must use Grand Abscess skin")
local requested_items = {
    { "01", "weapon", "7876" }, { "02", "weapon", "13572" },
    { "03", "weapon", "4446" }, { "04", "weapon", "6894" },
    { "05", "weapon", "4020" }, { "06", "weapon", "8271" },
    { "06", "offhand_weapon", "8324" }, { "07", "weapon", "5321" },
    { "08", "weapon", "4007" }, { "09", "head", "7813" },
    { "10", "weapon", "5810" }, { "11", "weapon", "13009" },
    { "12", "back", "12451" }, { "12", "weapon", "9521" },
}
for _, expected in ipairs(requested_items) do
    local asset = catalog.resolve("monster_archive_hunt_" .. expected[1])
    local found = false
    for _, component in ipairs(asset.components) do
        if component.component_id == expected[2] then
            found = component.notes:find("ItemDef=" .. expected[3], 1, true) ~= nil
        end
    end
    assert(found, "requested item missing or overwritten: " .. table.concat(expected, ":"))
end
print("ARCHIVE_MONSTER_COSMETICS_PASS count=" .. count)
