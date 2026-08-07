local root = assert(arg[1], "workspace root argument is required")
package.path = root .. "/scripts/vscripts/?.lua;"
    .. root .. "/scripts/vscripts/?/init.lua;"
    .. package.path

local repair_math = require("core/repair_math")

local function close(actual, expected, message)
    assert(math.abs(actual - expected) < 0.000001,
        string.format("%s: expected %.6f, got %.6f", message, expected, actual))
end

close(repair_math.amount_for_interval(10000, 2, 1), 200,
    "one second repairs two percent")
close(repair_math.amount_for_interval(10000, 2, 0.25), 50,
    "quarter-second tick repairs half a percent")
close(repair_math.amount_for_interval(250000, 2, 0.25), 1250,
    "repair scales with target max health")
close(repair_math.amount_for_interval(10000, -2, 1), 0,
    "negative percentage is clamped")
close(repair_math.amount_for_interval(-10000, 2, 1), 0,
    "negative max health is clamped")

local repaired = 0
local remainder = 0
for _ = 1, 4 do
    local amount
    amount, remainder = repair_math.whole_amount_for_interval(
        101,
        2,
        0.25,
        remainder
    )
    repaired = repaired + amount
end
assert(repaired == 2,
    string.format("fractional ticks: expected 2, got %d", repaired))
close(remainder, 0.02, "fractional ticks preserve their remainder")

repaired = 0
remainder = 0
for _ = 1, 200 do
    local amount
    amount, remainder = repair_math.whole_amount_for_interval(
        101,
        2,
        0.25,
        remainder
    )
    repaired = repaired + amount
end
assert(repaired == 101,
    string.format("long-term percentage rate: expected 101, got %d", repaired))
close(remainder, 0, "long-term percentage rate consumes the remainder")

print("REPAIR_WORKER_PERCENTAGE_MATH_OK")