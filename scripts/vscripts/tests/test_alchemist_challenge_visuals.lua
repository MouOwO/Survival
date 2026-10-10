package.path = "scripts/vscripts/?.lua;" .. package.path

local pending = {}
package.loaded["core/logger"] = { info = function() end, warn = function() end }
package.loaded["core/scheduler"] = {
    after = function(_, callback) pending[#pending + 1] = callback end,
}

local catalog = require("config/asset_catalog")
local challenges = require("config/generated/building_challenge_definitions")
local visual = require("systems/monster_hero_visual_service")
local appearance = require("visual/model_appearance_service")
local definition = assert(challenges.by_id.challenge_monster_05)
assert(definition.default_wearable_asset_id == "monster_default_alchemist",
    "building Alchemist challenge must declare its default wearable package")
local asset = assert(catalog.resolve(definition.default_wearable_asset_id))
assert(asset.primary_model == definition.model_path)
assert(asset.load_group == "monster_default_wearables")
assert(asset.async_unit_name == "asset_proxy_monster_default_alchemist")

-- Valve default ItemDefs 117 through 125 include both independent heads and
-- the goblin's body. Equipping only the two heads leaves the outfit incomplete.
local expected = {
    back = "alchemist_goblin_body",
    weapon = "alchemist_scabbard",
    armor = "alchemist_saddlehat",
    arms = "alchemist_gauntlets",
    neck = "alchemist_goblinhat",
    offhand_weapon = "alchemist_leftbottle",
    head = "alchemist_goblin_head",
    body_head = "alchemist_ogre_head",
    shoulder = "alchemist_shoulderbottles",
}
for slot, name in pairs(expected) do
    expected[slot] = "models/heroes/alchemist/" .. name .. ".vmdl"
end
assert(#asset.components == 9, "Alchemist default outfit needs all nine pieces")
local declared = {}
for _, component in ipairs(asset.components) do
    assert(expected[component.component_id] == component.model_path,
        "unexpected Alchemist default component " .. component.component_id)
    assert(not declared[component.component_id], "duplicate Alchemist component")
    assert(component.entity_class == "prop_dynamic" and component.attach_mode == "bone_merge")
    declared[component.component_id] = true
end
for slot in pairs(expected) do assert(declared[slot], "missing default component " .. slot) end

local id = 0
local function entity(model)
    id = id + 1
    local value = { index = id, model = model, skin = 0, activities = {} }
    function value:IsNull() return self.removed == true end
    function value:entindex() return self.index end
    function value:GetUnitName() return definition.unit_name end
    function value:SetModel(path) self.model = path end
    value.SetOriginalModel = value.SetModel
    function value:GetModelName() return self.model end
    function value:SetOwner(owner) self.owner = owner end
    function value:GetOwner() return self.owner end
    function value:SetParent(parent) self.parent = parent end
    function value:FollowEntity(parent, merge)
        assert(merge and parent == self.parent)
        self.follow = parent
    end
    function value:SetSkin(skin) self.skin = skin end
    function value:GetSkin() return self.skin end
    function value:SetModelScale(scale) self.scale = scale end
    function value:AddActivityModifier(name) self.activities[name] = true end
    function value:ClearActivityModifiers() self.activities = {} end
    function value:ResetSequence(sequence) self.sequence = sequence end
    function value:SetSolid() end
    function value:SetPlaybackRate() end
    return value
end

local spawned = {}
SpawnEntityFromTableSynchronous = function(class_name, data)
    assert(class_name == "prop_dynamic")
    local component = entity(data.model)
    spawned[#spawned + 1] = component
    return component
end
UTIL_Remove = function(value) value.removed = true end

local unit = entity(definition.model_path)
unit:SetModelScale(definition.model_scale)
local options = {
    challenge = true,
    allow_outside_formal_wave = true,
    model_path = definition.model_path,
    default_wearable_asset_id = definition.default_wearable_asset_id,
}
local ok, status = visual.apply(unit, definition, options)
assert(ok, tostring(status))
assert(status == asset.asset_id and unit.survival_monster_default_wearable_asset_id == asset.asset_id)
assert(appearance._count_for_test(unit) == 9 and #spawned == 9)
local attached = {}
for _, component in ipairs(spawned) do
    local slot = component.survival_model_component_id
    assert(expected[slot] == component:GetModelName())
    assert(component.owner == unit and component.parent == unit and component.follow == unit)
    attached[slot] = component
end
assert(attached.head and attached.body_head, "both Alchemist heads must be attached")

for _, callback in ipairs(pending) do callback() end
assert(visual.apply(unit, definition, options))
assert(#spawned == 9 and appearance._count_for_test(unit) == 9,
    "reapplying a complete default outfit must retain the same components")
for _, component in ipairs(spawned) do assert(not component.removed) end

unit.survival_monster_corpse = true
assert(visual.on_death(unit))
assert(appearance._count_for_test(unit) == 9,
    "tracked corpse must keep its default wearable outfit until final cleanup")
assert(unit.survival_monster_default_wearable_asset_id == asset.asset_id)
for _, component in ipairs(spawned) do assert(not component.removed) end
assert(visual.clear(unit))
assert(appearance._count_for_test(unit) == 0)
assert(unit.survival_monster_default_wearable_asset_id == nil)
assert(unit.survival_monster_cosmetic_details == nil)
for _, component in ipairs(spawned) do assert(component.removed) end
for _, callback in ipairs(pending) do callback() end
assert(#spawned == 9 and appearance._count_for_test(unit) == 0,
    "delayed verification must not recreate components after corpse cleanup")

-- Use the same synchronous preload group as addon Precache(context), so the
-- building challenge's new package cannot be omitted from initial resources.
local context, precached = {}, {}
PrecacheResource = function(resource_type, path, actual_context)
    assert(actual_context == context)
    precached[resource_type .. ":" .. path] = true
end
require("systems/asset_preload_service").precache_group(context, "monster_default_wearables")
assert(precached["model:" .. asset.primary_model], "Alchemist body missing from initial preload")
for slot, model_path in pairs(expected) do
    assert(precached["model:" .. model_path], "Alchemist component missing from initial preload: " .. slot)
end

print("ALCHEMIST_CHALLENGE_VISUALS_PASS: nine default pieces, both heads, stable reapply, corpse retention, cleanup, initial preload")
