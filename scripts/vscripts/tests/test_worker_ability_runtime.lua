package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local training = {
    training_id = "train_lumberjack_04",
    level = 4,
    name = "农民LV4",
    count = 0,
    max_count = 3,
    unlimited = 0,
    requires_city_level = 2,
    wood_cost = 1000,
    gold_cost = 0,
    population_cost = 2,
    wood_per_hit = 5,
    base_attack = 502,
}

package.loaded["core/event_bus"] = {
    request = function(_, payload)
        assert(payload.team == 2, "runtime builder queried the wrong team")
        return training
    end,
}

local builder = require("ui/ability_runtime_builder")
local resources = {
    wood = 10000,
    gold = 10000,
    population = 2,
    max_population = 20,
}

training = {
    training_id = "train_lumberjack_01",
    level = 1,
    name = "农民LV1",
    count = 0,
    max_count = 5,
    unlimited = 0,
    requires_city_level = 1,
    wood_cost = 10,
    gold_cost = 0,
    population_cost = 1,
    wood_per_hit = 1,
    base_attack = 22,
}
local level_one = builder.build("ability_train_lumberjack", {
    team = 2,
    building_id = "main_city",
    level = 1,
}, resources)
assert(string.find(level_one.status_text, "0/5", 1, true),
    "LV1 runtime did not expose the configured max_count")

training = {
    training_id = "train_lumberjack_04",
    level = 4,
    name = "农民LV4",
    count = 0,
    max_count = 3,
    unlimited = 0,
    requires_city_level = 2,
    wood_cost = 1000,
    gold_cost = 0,
    population_cost = 2,
    wood_per_hit = 5,
    base_attack = 502,
}

local locked = builder.build("ability_train_lumberjack", {
    team = 2,
    building_id = "main_city",
    level = 1,
}, resources)
assert(locked.available == 0 and locked.can_afford == 1,
    "LV4 button did not expose the main-city prerequisite")
assert(locked.display_name == "训练农民LV4" and locked.current_level == 4,
    "training button did not expose its current worker tier")
assert(locked.cost_wood == 1000 and locked.population == 2,
    "training button did not expose current tier costs")
assert(string.find(locked.status_text, "LV2", 1, true),
    "locked training button did not explain its prerequisite")

local available = builder.build("ability_train_lumberjack", {
    team = 2,
    building_id = "main_city",
    level = 2,
}, resources)
assert(available.available == 1 and available.can_afford == 1,
    "LV4 button did not unlock at main-city LV2")
assert(string.find(available.status_text, "0/3", 1, true),
    "training button did not expose cumulative tier progress")

training = {
    training_id = "train_lumberjack_08",
    level = 8,
    name = "农民LV8",
    count = 12,
    max_count = -1,
    unlimited = 1,
    requires_city_level = 4,
    wood_cost = 50000,
    gold_cost = 5000,
    population_cost = 3,
    wood_per_hit = 80,
    base_attack = 8002,
}
resources.wood = 50000
local final = builder.build("ability_train_lumberjack", {
    team = 2,
    building_id = "main_city",
    level = 4,
}, resources)
assert(final.available == 1 and final.can_afford == 1,
    "LV8 button should remain trainable")
assert(final.display_name == "训练农民LV8"
    and string.find(final.status_text, "无限训练", 1, true),
    "LV8 button did not expose its unlimited state")
assert(final.cost_wood == 50000 and final.cost_gold == 5000,
    "LV8 button did not expose its configured costs")

training = {
    training_id = "train_repairer_01",
    level = 1,
    name = "修理工1",
    count = 0,
    max_count = 5,
    completed = 0,
    requires_city_level = 1,
    wood_cost = 100,
    gold_cost = 0,
    population_cost = 1,
    repair_max_health_pct_per_second = 1.4,
    repair_range = 600,
}
local normal_repairer = builder.build("ability_train_repairer", {
    team = 2,
    building_id = "main_city",
    level = 1,
}, { wood = 100, gold = 0, population = 0, max_population = 1 })
assert(normal_repairer.available == 1
    and normal_repairer.can_afford == 1
    and normal_repairer.population == 1
    and normal_repairer.cost_wood == 100,
    "normal repairer button did not expose configured costs")
assert(string.find(normal_repairer.status_text, "0/5", 1, true),
    "normal repairer button did not expose independent progress")
assert(normal_repairer.fields[2].label == "人口消耗"
    and normal_repairer.fields[2].value == 1
    and normal_repairer.fields[5].value == "1.4%最大生命/秒"
    and normal_repairer.fields[6].value == 600,
    "normal repairer button did not expose population and repair stats")

training = {
    training_id = "train_repairer_02",
    level = 2,
    name = "修理工2",
    count = 0,
    max_count = 2,
    completed = 0,
    requires_city_level = 1,
    wood_cost = 0,
    gold_cost = 1000,
    population_cost = 1,
    repair_max_health_pct_per_second = 2,
    repair_range = 600,
}
local advanced_repairer = builder.build("ability_train_advanced_repairer", {
    team = 2,
    building_id = "main_city",
    level = 1,
}, { wood = 0, gold = 1000, population = 0, max_population = 1 })
assert(advanced_repairer.available == 1
    and advanced_repairer.can_afford == 1
    and advanced_repairer.population == 1
    and advanced_repairer.cost_gold == 1000,
    "advanced repairer button did not expose direct-training costs")
assert(string.find(advanced_repairer.status_text, "0/2", 1, true),
    "advanced repairer button did not expose its current living count")
assert(advanced_repairer.fields[2].label == "人口消耗"
    and advanced_repairer.fields[2].value == 1,
    "repairer button did not expose population consumption")
assert(advanced_repairer.fields[5].value == "2%最大生命/秒"
    and advanced_repairer.fields[6].value == 600,
    "advanced repairer button did not expose repair stats")

training.count = 2
training.completed = 1
local advanced_repairer_full = builder.build("ability_train_advanced_repairer", {
    team = 2,
    building_id = "main_city",
    level = 1,
}, { wood = 0, gold = 1000, population = 0, max_population = 3 })
assert(advanced_repairer_full.available == 0
    and string.find(advanced_repairer_full.status_text, "数量已达上限", 1, true),
    "advanced repairer button did not disable at its living-worker limit")

training.count = 1
training.completed = 0
local advanced_repairer_reopened = builder.build("ability_train_advanced_repairer", {
    team = 2,
    building_id = "main_city",
    level = 1,
}, { wood = 0, gold = 1000, population = 0, max_population = 3 })
assert(advanced_repairer_reopened.available == 1
    and string.find(advanced_repairer_reopened.status_text, "1/2", 1, true),
    "advanced repairer button did not reopen after a worker death")

print("WORKER_ABILITY_RUNTIME_PASS")