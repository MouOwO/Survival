package.path = "scripts/vscripts/?.lua;" .. package.path
local damage = require("systems/tower_laser_damage")
local times = {0, 1, 5, 10, 90}
-- Golden totals include the immediate hit at t=0 and the hit at each boundary.
local cases = {
    {1.2, {120, 245, 795, 1595, 30870}},
    {1.4, {140, 285, 915, 1815, 32360}},
    {1.6, {160, 325, 1035, 2035, 33770}},
    {1.8, {180, 365, 1155, 2255, 35100}},
}
for _, case in ipairs(cases) do
    for index, seconds in ipairs(times) do
        local total = 0
        for tick = 0, seconds do
            total = total + 100 * damage.multiplier(case[1], 0.05, 5, tick, 1)
        end
        assert(math.abs(total - case[2][index]) < 0.00001,
            tostring(case[1]) .. " at " .. seconds .. "s: " .. total)
    end
end
assert(damage.multiplier(1.2, 0.05, 5, 100000, 1) == 5)
print("TOWER_LASER_DAMAGE_PASS: original immediate hit and one-second cumulative totals, all multipliers and cap")
