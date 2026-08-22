package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local registry_source = assert(io.open(
    "scripts/vscripts/systems/rogue_effect_registry.lua", "rb"
)):read("*a")
local upgrade_source = assert(io.open(
    "scripts/vscripts/systems/building_upgrade_system.lua", "rb"
)):read("*a")
local effect_config = assert(io.open(
    "scripts/vscripts/config/generated/rogue_reward_effects.lua", "rb"
)):read("*a")
local item_kv = assert(io.open("scripts/npc/npc_items_custom.txt", "rb")):read("*a")
local item_actions = assert(io.open(
    "scripts/vscripts/items/item_survival_rogue_actions.lua", "rb"
)):read("*a")

assert(effect_config:find(
    'effect_id = "construction_order_action", card_id = "construction_order", effect_type = "grant_building_upgrade_action", execution_mode = "instant_transaction"',
    1,
    true
), "generated construction order config must be an immediate player upgrade entitlement")
assert(not item_kv:find("item_survival_rogue_construction_order", 1, true),
    "construction order must not grant a target item")
assert(not item_actions:find("item_survival_rogue_construction_order", 1, true),
    "construction order target-item implementation must be removed")
assert(registry_source:find("handlers.grant_building_upgrade_action", 1, true),
    "construction order entitlement handler is missing")
local _, handler_count = registry_source:gsub(
    "handlers%.grant_building_upgrade_action%s*=", ""
)
assert(handler_count == 1,
    "construction order entitlement handler must be registered exactly once")
assert(registry_source:find("effect_state.add_numeric", 1, true),
    "construction order must retain its count in player effect state")
assert(upgrade_source:find("rogue_effect_state.numeric", 1, true),
    "building upgrade must read the construction order entitlement")
assert(upgrade_source:find("requested_mode = \"one\"", 1, true),
    "construction order must force exactly one upgrade level")
assert(upgrade_source:find("rogue_effect_state.consume_numeric", 1, true),
    "successful free upgrade must consume exactly one entitlement")
assert(upgrade_source:find("payload.system_free_upgrade ~= true", 1, true),
    "system free upgrades must not consume construction order entitlement")
assert(upgrade_source:find("state.free_upgrade_request = nil", 1, true),
    "free-upgrade flag must be cleared after every request")
assert(upgrade_source:find("population = cost.population or 0", 1, true),
    "free construction order upgrade must consume configured population")

local effect_state = require("systems/rogue_effect_state_service")
effect_state.reset()
assert(effect_state.add_numeric(3, "grant_building_upgrade_action", 1),
    "could not grant construction order entitlement")
assert(effect_state.numeric(3, "grant_building_upgrade_action") == 1,
    "construction order entitlement count was not retained")
assert(effect_state.consume_numeric(3, "grant_building_upgrade_action", 1),
    "could not consume construction order entitlement")
assert(effect_state.numeric(3, "grant_building_upgrade_action") == 0,
    "construction order entitlement was not consumed")

print("ROGUE_CONSTRUCTION_ORDER_LUA51_PASS")