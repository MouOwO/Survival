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

local mirror = unit("npc_dota_hero_axe")
assert(scale.copy_final(mirror, body:GetModelScale())); near(mirror.scale, 1.6)
assert(scale.ensure(mirror)); near(mirror.scale, 1.6)
near(scale.original(mirror), 2.4)
local failed = unit("monster_test"); failed.fail = true
assert(not scale.apply(failed, 3)); assert(failed.survival_visual_final_scale == nil)
assert(not scale.apply(body, -1)); assert(not scale.apply(body, 0/0))
assert(not scale.apply(body, math.huge))

local existing, spawned = unit("npc_dota_hero_doom_bringer", 1.2), unit("monster_boss", 3)
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
assert(listeners == 1 and scans == 3); near(existing.scale, 0.8)
callback({entindex = 12}); callback({entindex = 12}); near(spawned.scale, 2)
assert(spawned.writes == 1)
assert(scale.apply(spawned, 4.5)); near(spawned.scale, 3)
callback({entindex = 12}); near(spawned.scale, 3)
local illusion = unit("npc_dota_hero_doom_bringer", existing.scale)
function illusion:IsIllusion() return true end
function illusion:GetReplicatingOtherHero() return existing end
assert(service.apply(illusion)); near(illusion.scale, existing.scale)
assert(service.apply(illusion)); near(illusion.scale, existing.scale)
for _, name in ipairs({"npc_survival_grid_preview_proxy", "npc_survival_upgrade_material"}) do
    local helper = unit(name); assert(not service.apply(helper)); assert(helper.writes == 0)
end
local thinker = unit("thinker"); thinker.classname = "npc_dota_thinker"
assert(not service.apply(thinker)); assert(thinker.writes == 0)
print("UNIT_MODEL_SCALE_PASS: two-thirds output, towers and walls exempt, refresh/respawn idempotence, exact copies, unchanged gameplay geometry, one spawn hook and no polling")
