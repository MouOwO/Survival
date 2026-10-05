package.path = "scripts/vscripts/?.lua;" .. package.path
local runtime = require("ui/ability_runtime_builder")
local buildings = require("config/buildings_config")
local effects = require("systems/rogue_effect_state_service")
local state = {player_id = 0, city_level = 0, hero_summoned = 0, building_counts = {}}
local empty = {wood = 0, gold = 0, population = 0, max_population = 0}
local function altar(view) return runtime.build("ability_build_hero_altar", view or state, empty) end
effects.reset()
assert(altar().available == 0)
effects.add_numeric(0, "builder_free_hero_altar", 1)
local free = altar()
assert(free.available == 1 and free.can_afford == 1, "free altar must pass both client cast gates before a city exists")
assert(free.cost_gold == 0 and free.cost_wood == 0)
assert(free.fields[1].value:find("天赋", 1, true), "tooltip must expose the actual unlock rule")
assert(altar({player_id = 1, city_level = 0, building_counts = {}}).available == 0,
    "another player's talent cannot unlock this builder")
state.building_counts.hero_altar = 1
assert(altar().available == 0, "free access still enforces the unique altar limit")
state.building_counts.hero_altar = 0;state.hero_summoned = 1
assert(altar().available == 0, "free access must respect the closed post-summon entrance")
state.hero_summoned = 0
assert(effects.consume_numeric(0, "builder_free_hero_altar", 1))
assert(altar().available == 0, "consumed free charge must restore the city prerequisite")
state.city_level = 3
local paid = altar()
assert(paid.available == 1 and paid.cost_wood == buildings.hero_altar.build_cost.wood
    and paid.cost_gold == buildings.hero_altar.build_cost.gold, "normal access restores configured prices")
print("FREE_ALTAR_RUNTIME_PASS: city0/no resources, private talent unlock, zero price, unique/summoned gates, consumed charge restores normal rules")
