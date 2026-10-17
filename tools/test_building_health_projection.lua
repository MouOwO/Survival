-- Exact contract values independent of the production arithmetic path.
package.path = "scripts/vscripts/?.lua;" .. package.path
local projection = dofile(arg[1] or "scripts/vscripts/systems/building_health_projection.lua")
local cases = {
    { 3000, 147, 131, 7541 },
    { 2000, 256.9, 1000, 8138 },
    { 2000, 256.9, 999.999999, 8137 },
    { 8137.999999, 0, 0, 8137 },
    { 8137.99999999, 0, 0, 8137 },
    { 3000, 147, 131.2, 7541 },
    { 3000, 147, 131.999, 7541 },
    { 3000, 147, 132, 7542 },
    { 3000, 147.01, 131, 7541 },
    { 3000, 147, -131, 7410 },
    { 3000, -50, 131, 1631 },
    { 3000, -150, 131, 1 },
    { 3000, -50, -131, 1500 },
    { 3000, 0, 131.9, 3131 },
    { 3000, 0, -131, 3000 },
    { 9007199254740991, 0, 0, 9007199254740991 },
    { 9007199254740990, 0, 0.25, 9007199254740990 },
    { 1000000000.5, 0, 0, 1000000000 },
}
for i, case in ipairs(cases) do
    local actual = projection.maximum_with_flat_bonus(case[1], case[2], case[3])
    assert(actual == case[4], "case " .. i .. " expected " .. case[4] .. ", got " .. actual)
end
local oracle_path = "output/four_player_stress_20261012/technology_health_decimal_oracle.json"
local oracle_file = io.open(oracle_path, "rb")
if oracle_file then
    local oracle = require("core/json_decoder").decode(oracle_file:read("*a")); oracle_file:close()
    for i, case in ipairs(oracle.cases) do
        local actual = projection.maximum_with_flat_bonus(case.base, case.percent, case.flat)
        assert(actual == case.expected, "Decimal oracle " .. i .. " expected " .. case.expected .. ", got " .. actual)
    end
    print("BUILDING_HEALTH_DECIMAL_ORACLE_PASS cases=" .. #oracle.cases)
end
assert(projection.maximum_with_flat_bonus() == 1)
assert(projection.maximum_with_flat_bonus(3000, 147, 131) - 3000 == 4541,
    "HUD static bonus must use the same exact maximum as actual HP")
local unit = { maximum = 3000, health = 2000,
    GetMaxHealth = function(self) return self.maximum end,
    GetHealth = function(self) return self.health end,
    SetHealth = function(self, value) self.health = value end }
projection.apply_maximum_health_increase(unit, function()
    unit.maximum = projection.maximum_with_flat_bonus(3000, 147, 131)
end)
assert(unit.maximum == 7541 and unit.health == 6541,
    "upgrade maximum increase preserves the existing 1000 missing HP")
print("BUILDING_HEALTH_PROJECTION_PASS exact integer HP/bonus, fractional floor, negative percent/flat clamp, defaults, upgrade missing HP")
