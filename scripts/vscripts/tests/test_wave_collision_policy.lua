-- Use the shipped configuration, including every enabled wave batch and
-- challenge appearance; fixture-only arrays can miss a phased spawn branch.
package.path = "scripts/vscripts/?.lua;" .. package.path
DOTA_UNIT_CAP_MOVE_GROUND = 1
local collision = require("systems/wave_monster_collision")
local navigation = require("systems/monster_navigation_policy")
local hull = require("systems/monster_hull_scale")
local scale = require("visual/model_scale")
local rules = require("config/global_rules")
local archetypes = require("config/generated/monster_archetypes")
local visuals = require("config/monster_visual_config")
local counts = { wave = 0, building = 0, archive = 0, endless = 0, encounter = 0 }
local used_archetypes, models, behavior = {}, {}, {}
assert(rules.wave_ground_monster_hull_radius == 32,
    "the released fixed native wall-attacker body must remain Hull32")

local function check(row, definition, is_wave, label, authored_scale)
    local profile = collision.profile(row, definition, is_wave)
    assert(profile.base_hull_radius == 32, label .. " lost its fixed native body")
    assert(profile.no_unit_collision == false, label .. " may pass through a living monster")
    local unit = { radius = 64, survival_is_challenge_monster = true }
    function unit:IsNull() return false end
    function unit:GetHullRadius() return self.radius end
    function unit:SetHullRadius(value) self.radius = value end
    function unit:SetMoveCapability(value) self.move = value end
    function unit:SetModelScale(value) self.scale = value end
    navigation.apply(unit)
    assert(hull.apply(unit, 1, profile.base_hull_radius))
    assert(scale.apply(unit, authored_scale or definition.model_scale or 1))
    assert(unit.radius == 32 and unit.survival_monster_hull_radius == 32,
        label .. " visual scale changed native collision")
    assert(unit.move == DOTA_UNIT_CAP_MOVE_GROUND,
        label .. " flying appearance bypassed terrain navigation")
    return profile
end

for _, row in ipairs(require("config/generated/wave_definitions").rows) do
    if row.enabled ~= false then
        local definition = assert(archetypes.by_id[row.archetype_id], row.wave_id)
        assert(definition.enabled ~= false, row.wave_id .. " has disabled archetype")
        assert(definition.attack_type == "melee" and definition.attack_range == 128,
            row.wave_id .. " must use the common melee combat policy")
        local profile = check(row, definition, true, row.wave_id,
            (definition.model_scale or 1) * (row.model_scale_multiplier or 1))
        used_archetypes[row.archetype_id] = true
        models[definition.model_path] = true
        behavior[profile.movement_type .. "/" .. definition.attack_type] = true
        -- The real role resolver may replace the authored model in early waves.
        for instance = 1, math.max(1, row.monster_count or 1) do
            local visual = visuals.resolve(row.wave_number, row.member_role, instance)
            if visual then
                models[visual.model_path] = true
                check(row, definition, true, row.wave_id .. ":visual", visual.model_scale)
            end
        end
        counts.wave = counts.wave + 1
    end
end

for _, definition in ipairs(require("config/generated/building_challenge_definitions").rows) do
    if definition.enabled ~= false then
        check({ is_challenge_monster = true }, definition, false, definition.challenge_id)
        counts.building = counts.building + 1
    end
end
for _, definition in ipairs(require("config/generated/archive_challenge_definitions").rows) do
    if definition.enabled ~= false then
        -- Match archive_challenge_service's wall factory classification.
        check({ is_challenge_monster = true }, definition, false, definition.challenge_id)
        counts.archive = counts.archive + 1
    end
end
for _, visual in ipairs(require("config/generated/archive_endless_visuals").rows) do
    if visual.enabled ~= false then
        -- archive_endless_service creates this same ground melee factory type;
        -- every one of its 200 shipped bodies must preserve the common hull.
        check({ is_challenge_monster = true }, {
            endless = true, movement_type = "ground", model_path = visual.model_path,
            model_scale = visual.base_scale,
        }, false, visual.visual_id)
        counts.endless = counts.endless + 1
    end
end

-- Independent encounter/room NPCs have no wall AI. Preserve their authored
-- practice/flying policy while checking all actual enabled room members.
for _, member in ipairs(require("config/generated/encounter_members").rows) do
    if member.enabled ~= false then
        local definition = assert(archetypes.by_id[member.archetype_id], member.member_id)
        local profile = collision.profile(member, definition)
        local movement = member.movement_type_override or definition.movement_type or "ground"
        local expected = member.collision_profile == "practice" and rules.practice_monster_hull_radius
            or (movement == "flying" and 10 or rules.wave_ground_monster_hull_radius)
        assert(profile.base_hull_radius == expected and profile.no_unit_collision == false,
            member.member_id .. " independent encounter policy changed")
        counts.encounter = counts.encounter + 1
    end
end
local function size(values) local n = 0; for _ in pairs(values) do n = n + 1 end; return n end
assert(counts.wave > 800 and size(used_archetypes) >= 44 and size(behavior) == 2
    and behavior["ground/melee"] and behavior["flying/melee"],
    "the shipped formal-wave matrix was not exercised")
assert(counts.building == 5 and counts.archive >= 20 and counts.endless == 200
    and counts.encounter > 0, "the shipped challenge matrix was not exercised")
print(string.format("WAVE_COLLISION_POLICY_PASS waves=%d archetypes=%d models=%d behavior=%d"
    .. " building=%d archive=%d endless=%d encounters=%d; solid Hull32 wall attackers,"
    .. " ground navigation, unchanged independent encounter policy",
    counts.wave, size(used_archetypes), size(models), size(behavior), counts.building,
    counts.archive, counts.endless, counts.encounter))
