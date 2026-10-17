package.path = "scripts/vscripts/?.lua;" .. package.path
Vector = function(x, y, z) return {x = x, y = y, z = z or 0} end
local mode, old_policy_calls, blocked, traversable = "standard", 0, false, true
package.loaded["systems/match_setup_service"] = {get_mode = function() return mode end}
package.loaded["systems/forbidden_region_service"] = {validate_hero_position = function(point)
    old_policy_calls = old_policy_calls + 1
    return point.y > -2000, point.y > -2000 and nil or "outside_hero_region"
end}
GridNav = {IsTraversable = function() return traversable end, IsBlocked = function() return blocked end}
local service = require("systems/destination_validation_service")
local origin, rich_city, another_island = Vector(0, 0, 384), Vector(-2752, -9984, 128), Vector(-2752, -7000, 128)
local unit = {position = origin, survival_hero_id = "swordmaster"}
function unit:IsNull() return false end
function unit:GetAbsOrigin() return self.position end
function unit:SetOrigin(point) self.position = point end
local adjusted = nil
FindClearSpaceForUnit = function(value, point) value.position = adjusted or point end
assert(not service.validate(rich_city, unit) and not service.validate_hero_position(rich_city), "normal mode keeps its old region policy")
local calls = old_policy_calls
mode = "rich"
assert(service.validate(rich_city, unit) and service.validate_hero_position(rich_city))
assert(service.validate(another_island, unit), "only builders are component-constrained; rich heroes may enter other legal navigation")
assert(old_policy_calls == calls, "rich heroes do not re-enter the ordinary-island whitelist")
assert(service.teleport(unit, rich_city) and unit:GetAbsOrigin() == rich_city, "hero summons can land at the rich main city")
blocked = true
assert(not service.teleport(unit, another_island) and unit:GetAbsOrigin() == rich_city)
blocked = false; traversable = false
assert(not service.validate_hero_position(rich_city) and not service.validate(rich_city, unit))
traversable = true
adjusted = Vector(999, 999, 128)
GridNav.IsBlocked = function(_, point) return point == adjusted end
local ok, reason = service.teleport(unit, another_island)
assert(not ok and reason == "final_destination_blocked" and unit:GetAbsOrigin() == rich_city, "clear-space landing still receives navigation validation and rollback")
mode = "standard"; adjusted = nil
assert(not service.teleport(unit, another_island) and old_policy_calls > calls, "switching back restores the original region gate")
print("RICH_HERO_DESTINATIONS_PASS: rich city summon, free hero region travel, live navigation, final landing rollback and unchanged ordinary gate")
