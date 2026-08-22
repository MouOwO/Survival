package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local collision = require("systems/wave_monster_collision")
local hull_scale = require("systems/monster_hull_scale")

local ground = { movement_type = "ground", rank = "normal" }
local flying = { movement_type = "flying", rank = "normal" }

local normal_profile = collision.profile({ member_role = "normal" }, ground)
assert(normal_profile.movement_type == "ground"
        and normal_profile.base_hull_radius == 32
        and normal_profile.no_unit_collision == false,
    "ground normal collision profile changed")

local leader_profile = collision.profile({ member_role = "wave_leader" }, ground)
assert(leader_profile.base_hull_radius == 32
        and leader_profile.no_unit_collision == false,
    "ground wave leader collision profile changed")

local boss_profile = collision.profile({ member_role = "assault_boss" }, ground)
assert(boss_profile.base_hull_radius == 32
        and boss_profile.no_unit_collision == false,
    "ground assault boss collision profile changed")

local challenge_profile = collision.profile({
    member_role = "assault_boss",
    is_challenge_monster = true,
}, ground)
assert(challenge_profile.base_hull_radius == 0
        and challenge_profile.no_unit_collision == true,
    "ground challenge monster did not receive zero-hull collision profile")

local flying_profile = collision.profile({ member_role = "normal" }, flying)
assert(flying_profile.movement_type == "flying"
        and flying_profile.base_hull_radius == 10
        and flying_profile.no_unit_collision == false,
    "normal flying archetype did not receive hull 10")

local flying_challenge_profile = collision.profile({
    member_role = "assault_boss",
    is_challenge_monster = true,
}, flying)
assert(flying_challenge_profile.movement_type == "flying"
        and flying_challenge_profile.base_hull_radius == 0
        and flying_challenge_profile.no_unit_collision == true,
    "flying challenge monster did not receive zero-hull collision profile")

local challenge_unit = { hull = 32 }
function challenge_unit:IsNull() return false end
function challenge_unit:GetHullRadius() return self.hull end
function challenge_unit:SetHullRadius(value) self.hull = value end
local challenge_hull_ok, challenge_radius, challenge_base_radius
    = hull_scale.apply(
        challenge_unit,
        1,
        challenge_profile.base_hull_radius
    )
assert(challenge_hull_ok and challenge_radius == 0
        and challenge_base_radius == 0 and challenge_unit.hull == 0,
    "challenge monster hull was not applied as zero")

local override_profile = collision.profile({
    member_role = "normal",
    movement_type_override = "flying",
}, ground)
assert(override_profile.base_hull_radius == 10
        and override_profile.no_unit_collision == false,
    "normal flying movement override did not receive hull 10")

local flying_leader_profile = collision.profile({
    member_role = "wave_leader",
}, flying)
assert(flying_leader_profile.base_hull_radius == 10
        and flying_leader_profile.no_unit_collision == false,
    "flying wave leader collision differs from normal flying monsters")

local unit = { hull = 32 }
function unit:IsNull() return false end
function unit:GetHullRadius() return self.hull end
function unit:SetHullRadius(value) self.hull = value end
local hull_ok, radius, base_radius = hull_scale.apply(
    unit,
    4,
    flying_profile.base_hull_radius
)
assert(hull_ok and radius == 40 and base_radius == 10 and unit.hull == 40,
    "normal flying hull did not use the configured base")
local reapplied, reapplied_radius = hull_scale.apply(unit, 0.5)
assert(reapplied and reapplied_radius == 5 and unit.hull == 5,
    "later monster hull scaling did not reuse the normal flying base")

LUA_MODIFIER_MOTION_NONE = 0
MODIFIER_ATTRIBUTE_PERMANENT = 1
MODIFIER_STATE_NO_UNIT_COLLISION = 2
LinkLuaModifier = function() end
class = function(value) return value end
IsServer = function() return true end
package.loaded["modifiers/modifier_enemy_wall_ai"] = nil
local modifier_class = require("modifiers/modifier_enemy_wall_ai")

local modifier = setmetatable({}, { __index = modifier_class })
function modifier:StartIntervalThink() end
modifier:OnCreated({ wall_entindex = -1, no_unit_collision = 0 })
assert(next(modifier:CheckState()) == nil,
    "normal flying wave AI modifier incorrectly disabled unit collision")

local legacy_flying_modifier = setmetatable({}, { __index = modifier_class })
function legacy_flying_modifier:StartIntervalThink() end
legacy_flying_modifier:OnCreated({ wall_entindex = -1, no_unit_collision = 1 })
assert(legacy_flying_modifier:CheckState()[MODIFIER_STATE_NO_UNIT_COLLISION] == true,
    "flying elite/Boss AI modifier lost no-unit-collision")

local ground_modifier = setmetatable({}, { __index = modifier_class })
function ground_modifier:StartIntervalThink() end
ground_modifier:OnCreated({ wall_entindex = -1, no_unit_collision = 0 })
assert(next(ground_modifier:CheckState()) == nil,
    "ground wave AI modifier incorrectly disabled unit collision")

print("WAVE_FLYING_COLLISION_PASS")