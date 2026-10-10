package.path = "scripts/vscripts/?.lua;" .. package.path
local runtime = require("systems/tower_skill_runtime")
local config = require("config/generated/tower_skill_definitions")
local function unit(index)
    return { IsNull = function(self) return self.removed == true end,
        entindex = function() return index end }
end
local original = unit(73)
runtime.apply(original, {"laser_lv01", "multi_attack_lv01", "missing"})
assert(runtime.matching(original, "laser_") == config.by_id.laser_lv01)
assert(runtime.get_skill(original, "missing") == nil)
assert(runtime.matching(original, "critical_strike_") == nil)
-- A newly created entity can reuse a dead tower's index before skills are applied.
original.removed = true
local replacement = unit(73)
assert(next(runtime.get(replacement)) == nil, "entity index reuse must not inherit old skills")
assert(runtime.matching(original, "laser_") == nil, "removed entities cannot expose old skills")
runtime.apply(replacement, {"laser_lv02", "critical_strike_lv01"})
assert(runtime.matching(replacement, "critical_strike_") == config.by_id.critical_strike_lv01)
assert(runtime.matching(replacement, "laser_") == config.by_id.laser_lv02)
-- Upgrade/removal invalidates positive and negative cached lookups together.
runtime.apply(replacement, {"laser_lv03", "machine_gun_lv01"})
assert(runtime.matching(replacement, "laser_") == config.by_id.laser_lv03)
assert(runtime.matching(replacement, "critical_strike_") == nil)
assert(runtime.matching(replacement, "machine_gun_") == config.by_id.machine_gun_lv01)
runtime.apply(replacement, {})
assert(runtime.matching(replacement, "laser_") == nil)
assert(runtime.get_skill(replacement, "machine_gun_lv01") == nil)
-- The registry must not retain retired entities, including after a matched lookup.
local weak = setmetatable({}, {__mode = "v"})
do
    local ephemeral = unit(74)
    runtime.apply(ephemeral, {"laser_lv01"})
    runtime.matching(ephemeral, "laser_")
    weak[1] = ephemeral
end
collectgarbage("collect")
assert(weak[1] == nil, "retired tower must be collectible")
-- Repeated hits and misses must not scan skill IDs during attacks/property queries.
runtime.apply(replacement, {"laser_lv04", "multi_attack_lv01"})
runtime.matching(replacement, "laser_")
runtime.matching(replacement, "critical_strike_")
local old_match = string.match
string.match = function() error("unexpected hot-loop skill rescan") end
for i = 1, 10000 do
    assert(runtime.matching(replacement, "laser_") == config.by_id.laser_lv04)
    assert(runtime.matching(replacement, "critical_strike_") == nil)
end
string.match = old_match
assert(runtime.matching(nil, "laser_") == nil)
print("TOWER_SKILL_RUNTIME_PASS: recycled entities, upgrade/removal, matched/missing snapshots, retired collection")
