package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local function vector(x, y, z)
    local value = { x = x, y = y, z = z or 0 }
    local mt = {}
    function mt.__sub(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end
    function mt.__add(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end
    function mt.__mul(a, b)
        if type(a) == "number" then a, b = b, a end
        return vector(a.x * b, a.y * b, a.z * b)
    end
    function value:Length2D() return math.sqrt(self.x * self.x + self.y * self.y) end
    function value:Normalized()
        local length = self:Length2D()
        return vector(self.x / length, self.y / length, self.z / length)
    end
    return setmetatable(value, mt)
end

Vector = vector

local armor = require("systems/war3_armor_target")
local unit = { native_armor = -1 }
function unit:IsNull() return false end
function unit:SetPhysicalArmorBaseValue(value) self.native_armor = value end
local ok, effective = armor.apply(unit, 30, 6)
assert(ok and effective == 36, "wall effective War3 armor")
assert(unit.native_armor == 0, "wall native armor must be zero")
assert(unit.survival_war3_armor_target == true, "wall identity")
local armor_balance = require("config/armor_balance")
local full_damage = 100 * armor_balance.war3_physical_damage_multiplier(effective, 0)
local pierced_damage = 100 * armor_balance.war3_physical_damage_multiplier(effective, 50)
assert(math.abs(full_damage - (100 / 1.72)) < 0.0001, "wall physical damage")
assert(math.abs(pierced_damage - (100 / 1.36)) < 0.0001, "wall armor penetration")

local blink = require("systems/blink_destination")
local target, distance = blink.clamp(vector(0, 0, 4), vector(3000, 4000, 9), 1000)
assert(math.abs(target.x - 600) < 0.001 and math.abs(target.y - 800) < 0.001,
    "1000 range clamp")
assert(target.z == 9 and distance == 1000, "clamp metadata")
local hero_target = blink.clamp(vector(0, 0, 0), vector(0, 1600, 7), 800)
assert(hero_target.y == 800 and hero_target.z == 7, "800 hero clamp")
local near = blink.clamp(vector(0, 0, 0), vector(3, 4, 6), 1000)
assert(near.x == 3 and near.y == 4 and near.z == 6, "in-range target")

local collision = require("systems/wave_monster_collision")
for _, profile in ipairs({
    collision.profile({}, { movement_type = "ground" }),
    collision.profile({}, { movement_type = "ground", rank = "elite" }),
    collision.profile({ member_role = "wave_leader" }, { movement_type = "ground" }),
    collision.profile({ member_role = "assault_boss", is_boss = true },
        { movement_type = "ground", rank = "boss" }),
}) do
    assert(profile.base_hull_radius == 32, "official ground hull")
end
assert(collision.profile({}, { movement_type = "flying" }).base_hull_radius == 10,
    "normal flying hull")
assert(collision.profile({ member_role = "assault_boss" },
    { movement_type = "flying" }).base_hull_radius == 0, "boss flying hull")

print("WALL_COLLISION_BLINK_LUA51_PASS")