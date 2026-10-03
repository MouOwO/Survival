-- Run the actual router request/change events and regular NetTable publisher.
-- Mock engine entities and unrelated request systems; use the real asset
-- catalog, portrait metadata, stat projection and event bus.
package.path = "scripts/vscripts/?.lua;" .. package.path

local listeners, sent, tables, entities = {}, {}, {}, {}
local player = {}
local clock_reads, entity_reads = 0, 0
PlayerResource = {
    IsValidPlayerID = function(_, id) return id == 0 end,
    GetPlayer = function(_, id) if id == 0 then return player end end,
    GetTeam = function() return 2 end,
}
GameRules = {GetGameTime = function() clock_reads = clock_reads + 1; return 999 end}
CustomGameEventManager = {
    RegisterListener = function(_, name, callback) listeners[name] = callback end,
    Send_ServerToPlayer = function(_, handle, name, payload)
        assert(handle == player)
        sent[#sent + 1] = {name = name, snapshot = payload}
    end,
}
CustomNetTables = {SetTableValue = function(_, name, key, snapshot)
    tables[#tables + 1] = {name = name, key = key, snapshot = snapshot}
end}
EntIndexToHScript = function(index)
    entity_reads = entity_reads + 1
    if index == 1001 then error("removed entity lookup") end
    return entities[index]
end
for _, name in ipairs({"systems/building_system", "ui/weapon_synthesis_snapshot_service",
    "systems/hero_summon_projection", "systems/building_batch_upgrade_service",
    "systems/gold_mine_batch_upgrade_service"}) do
    package.loaded[name] = {}
end
package.loaded["systems/startup_loading_service"] = {is_player_ready = function() return true end}

local bus = require("core/event_bus")
local events = require("core/events")
local projection = require("ui/combat_stat_projection")
local metadata = require("ui/portrait_metadata")
local scheduler = require("core/scheduler")
local router = require("ui/ui_request_router")
local publisher = require("ui/combat_stats_ui_service")
assert(router._test.apply_portrait_metadata == metadata.apply, "router seam must use the shared mapping")

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, nested in pairs(value) do result[key] = clone(nested) end
    return result
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b or (a ~= a and b ~= b) end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local visual_fields = {model_asset_id = true, portrait_unit_name = true, portrait_item_def = true}
local transport_fields = {success = true, source = true, reason = true, push_phase = true}
local function stats_only(snapshot)
    local result = {}
    for key, value in pairs(snapshot) do
        if not visual_fields[key] and not transport_fields[key] then result[key] = value end
    end
    return result
end
local function portrait(snapshot)
    return {model_asset_id = snapshot.model_asset_id,
        portrait_unit_name = snapshot.portrait_unit_name,
        portrait_item_def = snapshot.portrait_item_def}
end
local raw
local function initialize(publisher_first)
    bus.reset()
    sent, tables, listeners = {}, {}, {}
    bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST, function(payload)
        assert(payload.player_id == 0)
        return {ok = true, snapshot = raw}
    end)
    if publisher_first then publisher.init(); router.init()
    else router.init(); publisher.init() end
end
local function snapshot_for(hero_id, index, version)
    return {hero_id = hero_id, entindex = index, refresh_version = version,
        unit_name = "hero_engine_unit", display_name = hero_id, level = 8,
        attack_min = 120.5, attack_max = 240.75, health = 700, max_health = 1000,
        strength = 41, agility = 23, intellect = 67, attack_speed = 1.25,
        runtime_armor = 4.5, armor_mapping_version = 1,
        reason = "weapon_growth_changed", server_time = 125.25, cast_at = 80.4,
        damage_total = 4321, damage_tick = 6, damage_breakdown = {base = 100, critical = 200}}
end
local heroes = {
    {id = "hero_doom", portrait = "npc_dota_hero_doom_bringer"},
    {id = "hero_blademaster", portrait = "npc_dota_hero_juggernaut"},
    {id = "hero_shadow_fiend", portrait = ""}, -- historical ID now uses Keeper of the Light
    {id = "hero_axe", portrait = ""},
    {id = "hero_drow_ranger", portrait = ""},
    {id = "hero_monkey_king", portrait = ""},
}
local index = 200
for _, publisher_first in ipairs({false, true}) do
    initialize(publisher_first)
    for _, hero in ipairs(heroes) do
        index = index + 1
        entities[index] = {survival_hero_id = hero.id, IsNull = function() return false end}
        for _, version in ipairs({7, 7, 8}) do
            raw = snapshot_for(hero.id, index, version)
            local before = clone(raw)
            local projected = projection.for_ui(raw)
            local send_count, table_count = #sent, #tables
            assert(pcall(listeners.ui_selected_unit_stats_request, nil, {PlayerID = 0, entindex = index}))
            assert(#sent == send_count + 1)
            local requested = sent[#sent].snapshot
            assert(sent[#sent].name == "ui_selected_unit_stats_snapshot" and requested.success == 1)
            assert(requested.model_asset_id == "hero_permanent_" .. hero.id)
            assert(requested.portrait_unit_name == hero.portrait and requested.portrait_item_def == "")
            assert(equal(stats_only(requested), stats_only(projected)), "request changed combat data")
            assert(equal(raw, before) and requested ~= raw, "request mutated the authoritative snapshot")
            bus.emit(events.HERO_COMBAT_STATS_CHANGED, {player_id = 0, snapshot = raw})
            assert(#tables == table_count + 1 and #sent == send_count + 2,
                "both actual change-event channels must publish")
            local regular, selected = tables[#tables].snapshot, sent[#sent].snapshot
            assert(tables[#tables].name == "survival_combat_stats" and tables[#tables].key == "player_0")
            assert(equal(portrait(regular), portrait(requested)) and equal(portrait(selected), portrait(requested)),
                "same entity/version must never receive conflicting portrait metadata")
            assert(equal(stats_only(regular), stats_only(projected)) and equal(stats_only(selected), stats_only(projected)),
                "visual decoration changed damage, version, stats or timestamps")
            assert(equal(raw, before) and regular ~= raw and selected ~= raw,
                "publish mutated the authoritative snapshot")
        end
    end
end
print("PORTRAIT_METADATA_CHANNELS_PASS: Doom/Juggernaut stable identity, four native fallbacks, equal/new versions, both registration orders, raw combat data unchanged")

-- Invalid/removed entities must still publish current combat data safely,
-- clearing stale visual identity rather than guessing from a previous hero.
entities[1000] = {IsNull = function() return true end}
entities[1002] = {IsNull = function() error("invalid handle IsNull") end}
entities[1003] = {}
local invalid_indices = {999, 1000, 1001, 1002, 1003, -1, 1.5, "not_an_index", math.huge, 0 / 0}
for _, invalid_index in ipairs(invalid_indices) do
    raw = snapshot_for("hero_doom", invalid_index, 9)
    raw.model_asset_id, raw.portrait_unit_name, raw.portrait_item_def = "stale_asset", "stale_unit", "stale_item"
    local before, count = clone(raw), #tables
    bus.emit(events.HERO_COMBAT_STATS_CHANGED, {player_id = 0, snapshot = raw})
    assert(#tables == count + 1, "invalid entity interrupted regular stat publication")
    local regular = tables[#tables].snapshot
    assert(regular.model_asset_id == "" and regular.portrait_unit_name == "" and regular.portrait_item_def == "")
    assert(equal(stats_only(regular), stats_only(projection.for_ui(raw))))
    assert(equal(raw, before), "invalid entity fallback mutated raw data")
end
raw = snapshot_for("hero_doom", nil, 9)
local reads, count = entity_reads, #tables
bus.emit(events.HERO_COMBAT_STATS_CHANGED, {player_id = 0, snapshot = raw})
assert(#tables == count + 1 and entity_reads == reads)
assert(tables[#tables].snapshot.portrait_unit_name == "")
for _, invalid_index in ipairs({999, 1000, 1001}) do
    local sent_count = #sent
    assert(pcall(listeners.ui_selected_unit_stats_request, nil, {PlayerID = 0, entindex = invalid_index}))
    assert(#sent == sent_count + 1 and sent[#sent].snapshot.success == 0)
    assert(sent[#sent].snapshot.error == "invalid_unit")
end
assert(clock_reads == 0 and scheduler.task_count() == 0, "portrait projection added clock reads or polling")
print("PORTRAIT_METADATA_INVALID_ENTITY_PASS: missing/removed/throwing entities, explicit native fallback, immutable raw values, zero timers/clock reads")

-- Existing custom tower/challenge identities and identity fallback sources
-- must continue working when the mapping moves out of the request router.
local tower = router._test.apply_portrait_metadata({survival_model_asset_id = "tower_keeper_of_the_light"}, {})
assert(tower.model_asset_id == "tower_keeper_of_the_light" and tower.portrait_unit_name == "npc_dota_hero_tinker")
local challenge = metadata.apply({survival_model_asset_id = "challenge_monster_beastmaster_legacy"}, {})
assert(challenge.portrait_unit_name == "npc_dota_hero_beastmaster" and challenge.portrait_item_def == "21396")
local boss = metadata.apply({survival_monster_default_wearable_asset_id = "monster_boss_rebirth_01_phalanx"}, {})
assert(boss.portrait_unit_name == "npc_dota_hero_undying" and boss.portrait_item_def == "")
local fallback = metadata.apply({survival_hero_id = "hero_doom", survival_model_asset_id = "missing_asset"}, {})
assert(fallback.model_asset_id == "hero_permanent_hero_doom" and fallback.portrait_unit_name == "npc_dota_hero_doom_bringer")
local snapshot_fallback = metadata.apply({}, {hero_id = "hero_blademaster"})
assert(snapshot_fallback.portrait_unit_name == "npc_dota_hero_juggernaut")
local clone_fallback = metadata.apply({survival_monkey_king_clone = true}, {})
assert(clone_fallback.model_asset_id == "hero_permanent_hero_monkey_king" and clone_fallback.portrait_unit_name == "")
local monster_fallback = metadata.apply({survival_monster_default_wearable_asset_id = "challenge_monster_terrorblade_fractal_horns"}, {})
assert(monster_fallback.portrait_unit_name == "npc_dota_hero_terrorblade")
print("PORTRAIT_METADATA_MAPPING_PASS: existing tower/boss/challenge portraits, hero/clone/monster identity fallbacks")
