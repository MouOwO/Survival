local global_rules = require("config/global_rules")

local M = {
    initial_wood = global_rules.number("initial_wood", 10),
    initial_gold = global_rules.number("initial_gold", 0),
    initial_population = global_rules.number("initial_population", 0),
    initial_max_population = global_rules.number("initial_max_population", 0),
}

return M
