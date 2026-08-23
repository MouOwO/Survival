local global_rules = require("config/global_rules")

local M = {
    -- These are business defaults, not player profile defaults. Profile CSV
    -- values are intentionally zero so permanent rewards remain authoritative.
    initial_wood = global_rules.number("initial_wood", 10),
    initial_gold = global_rules.number("initial_gold", 0),
    initial_population = global_rules.number("initial_population", 0),
    initial_max_population = global_rules.number("initial_max_population", 0),
}

return M
