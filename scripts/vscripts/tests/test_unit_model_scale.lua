package.path = "scripts/vscripts/?.lua;" .. package.path
local scale = require("visual/model_scale")
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.000001, tostring(actual) .. " ~= " .. tostring(expected))
end
local function unit(name, size)
    local value = {name = name, scale = size or 1, writes = 0,
        hull = 64, attack_range = 500, footprint = {x = 4, y = 4}}
    function value:IsNull() return self.removed == true end
    function value:IsBaseNPC() return true end
    function value:GetUnitName() return self.name end
    function value:GetClassname() return self.classname or "npc_dota_creature" end
    function value:GetModelScale() return self.scale end
    function value:SetModelScale(next_scale)
        if self.fail then return false end
        self.scale = next_scale; self.writes = self.writes + 1
    end
    return value
end

local body = unit("building_main_city", 1.5)
assert(scale.ensure(body)); near(body.scale, 1)
assert(scale.ensure(body)); assert(body.writes == 1, "duplicate birth must be idle")
assert(scale.apply(body, 2.4)); near(body.scale, 1.6)
assert(scale.apply(body, 2.4)); near(body.scale, 1.6)
near(scale.original(body), 2.4)
assert(body.hull == 64 and body.attack_range == 500 and body.footprint.x == 4)
body.scale = 2.4 -- Native respawn restored the authored model scale.
assert(scale.ensure(body)); near(body.scale, 1.6)

for _, name in ipairs({"building_arrow_tower", "npc_dota_unit_ultimate_tower", "building_wall"}) do
    local tower = unit(name, 1.8)
    assert(scale.ensure(tower)); near(tower.scale, 1.8)
    assert(scale.apply(tower, 2.5)); near(tower.scale, 2.5)
end
local renamed = unit("native_tower_variant", 1.7)
renamed.survival_building_id = "arrow_tower"
assert(scale.ensure(renamed)); near(renamed.scale, 1.7)
local preview = unit("npc_survival_grid_preview_proxy")
assert(scale.apply(preview, 1.9, "arrow_tower")); near(preview.scale, 1.9)
assert(scale.copy_final(preview, 1.9, "arrow_tower")); near(preview.scale, 1.9)
assert(scale.apply(preview, 2.2, "wall")); near(preview.scale, 2.2)

local archetypes = require("config/generated/monster_archetypes")
local monster_count = 0
for _, definition in ipairs(archetypes.rows) do
    local monster = unit(definition.unit_name, definition.model_scale)
    assert(scale.ensure(monster)); near(monster.scale, definition.model_scale)
    assert(scale.apply(monster, definition.model_scale)); near(monster.scale, definition.model_scale)
    near(scale.original(monster), definition.model_scale)
    assert(monster.survival_visual_scale_multiplier == 1, definition.unit_name)
    assert(monster.hull == 64 and monster.attack_range == 500 and monster.footprint.x == 4)
    monster_count = monster_count + 1
end
assert(monster_count > 0)
local heroes = require("config/generated/hero_definitions")
local hero_count = 0
for _, definition in ipairs(heroes.rows) do
    local combat_hero = unit(definition.unit_name, 1.5)
    assert(scale.ensure(combat_hero)); near(combat_hero.scale, 1.5)
    assert(scale.apply(combat_hero, 2.2)); near(combat_hero.scale, 2.2)
    assert(scale.ensure(combat_hero)); near(combat_hero.scale, 2.2)
    near(scale.original(combat_hero), 2.2)
    assert(combat_hero.hull == 64 and combat_hero.attack_range == 500 and combat_hero.footprint.x == 4)
    hero_count = hero_count + 1
end
assert(hero_count > 0)
local native_hero = unit("renamed_native_hero", 1.4)
function native_hero:IsHero() return true end
assert(scale.ensure(native_hero)); near(native_hero.scale, 1.4)
local custom_hero = unit("renamed_addon_hero", 1.3)
custom_hero.survival_hero_id = "hero_drow_ranger"
assert(scale.ensure(custom_hero)); near(custom_hero.scale, 1.3)
for _, name in ipairs({"npc_survival_worker", "npc_survival_builder_proxy", "building_hero_altar",
    "npc_archive_challenge_1", "asset_proxy_monster_undying_golem"}) do
    local other = unit(name, 1.5)
    other.owner = native_hero
    other.model = "models/heroes/drow/drow_base.vmdl"
    assert(scale.ensure(other)); near(other.scale, 1)
end
for _, flag in ipairs({"survival_is_wave_monster", "survival_is_challenge_monster",
    "survival_rebirth_scene_display"}) do
    local renamed_monster = unit("renamed_monster", 1.5)
    renamed_monster[flag] = true
    assert(scale.ensure(renamed_monster)); near(renamed_monster.scale, 1.5)
end

local mirror = unit("npc_survival_visual_copy")
assert(scale.copy_final(mirror, body:GetModelScale())); near(mirror.scale, 1.6)
assert(scale.ensure(mirror)); near(mirror.scale, 1.6)
near(scale.original(mirror), 2.4)
local failed = unit("monster_test"); failed.fail = true
assert(not scale.apply(failed, 3)); assert(failed.survival_visual_final_scale == nil)
assert(not scale.apply(body, -1)); assert(not scale.apply(body, 0/0))
assert(not scale.apply(body, math.huge))

local existing, spawned = unit("npc_dota_hero_doom_bringer", 1.2), unit("npc_survival_wave_monster", 3)
local callback, listeners, scans = nil, 0, 0
ListenToGameEvent = function(name, fn)
    assert(name == "npc_spawned"); callback = fn; listeners = listeners + 1
end
Entities = {FindAllByClassname = function(_, name)
    scans = scans + 1; return name == "npc_dota_hero" and {existing} or {}
end}
EntIndexToHScript = function(id) return id == 12 and spawned or nil end
local service = require("systems/unit_model_scale_service")
service.init(); service.init()
assert(listeners == 1 and scans == 3); near(existing.scale, 1.2)
callback({entindex = 12}); callback({entindex = 12}); near(spawned.scale, 3)
assert(spawned.writes == 1)
assert(scale.apply(spawned, 4.5)); near(spawned.scale, 4.5)
callback({entindex = 12}); near(spawned.scale, 4.5)
local illusion = unit("npc_dota_hero_doom_bringer", existing.scale)
function illusion:IsIllusion() return true end
function illusion:GetReplicatingOtherHero() return existing end
assert(service.apply(illusion)); near(illusion.scale, existing.scale)
assert(service.apply(illusion)); near(illusion.scale, existing.scale)
assert(illusion.survival_visual_scale_multiplier == 1)
near(scale.original(illusion), 1.2)
for _, name in ipairs({"npc_survival_grid_preview_proxy", "npc_survival_upgrade_material"}) do
    local helper = unit(name); assert(not service.apply(helper)); assert(helper.writes == 0)
end
local thinker = unit("thinker"); thinker.classname = "npc_dota_thinker"
assert(not service.apply(thinker)); assert(thinker.writes == 0)
print("UNIT_MODEL_SCALE_PASS: " .. hero_count .. " heroes and " .. monster_count .. " monsters at original size, towers and walls exempt, workers/buildings at two-thirds, unchanged geometry and spawn idempotence")
