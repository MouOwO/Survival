package.path = "scripts/vscripts/?.lua;" .. package.path
class = function() return {} end
IsServer = function() return true end
local values, writes, projections = {}, 0, 0
local publish = function(_, _, key, value)
    values[key] = value
    writes = writes + 1
end
CustomNetTables = {SetTableValue = publish}
local projection = require("combat/endless_stat_projection")
local project = projection.for_ui
projection.for_ui = function(...)
    projections = projections + 1
    return project(...)
end
local definition = require("modifiers/modifier_single_health_bar")
local function make_unit(id)
    local unit = {health = 50, max_health = 100, alive = true, team = 2, name = "worker"}
    function unit:IsNull() return self.invalid end
    function unit:entindex() assert(not self.invalid); return id end
    function unit:GetHealth() return self.health end
    function unit:GetMaxHealth() return self.max_health end
    function unit:IsAlive() return self.alive end
    function unit:GetTeamNumber() return self.team end
    function unit:GetUnitName() return self.name end
    local modifier = setmetatable({GetParent = function() return unit end,
        StartIntervalThink = function(_, interval) assert(interval == 0.1) end}, {__index = definition})
    return unit, modifier
end

local unit, modifier = make_unit(42)
modifier:OnCreated()
assert(values.unit_42.health == 50 and writes == 1 and projections == 2)
for _ = 1, 100 do modifier:OnIntervalThink() end
assert(writes == 1 and projections == 2, "stable samples skip publishing and formatting")

for _, change in ipairs({
    {"health", 40}, {"health", 70}, {"max_health", 120},
    {"alive", false}, {"alive", true}, {"team", 3}, {"name", "upgraded_worker"},
}) do
    local before = writes
    unit[change[1]] = change[2]
    modifier:OnIntervalThink()
    assert(writes == before + 1, change[1] .. " must update on the next sample")
    modifier:OnIntervalThink()
    assert(writes == before + 1, "identical consecutive sample must not republish")
end

local before = writes
unit.survival_endless_health_scale = 1
modifier:OnIntervalThink()
assert(writes == before + 1 and values.unit_42.health == "70")
unit.health, unit.max_health, unit.survival_endless_health_scale = 100000000, 100000000, 10
modifier:OnIntervalThink()
assert(values.unit_42.health == "1000000000" and values.unit_42.max_health == "1000000000")
unit.survival_endless_health_scale = 20
modifier:OnIntervalThink()
assert(values.unit_42.health == "2000000000" and values.unit_42.health_scale == "20")

unit.survival_hide_custom_health_bar = true
modifier:OnIntervalThink()
assert(values.unit_42.removed == 1)
before = writes
for _ = 1, 100 do modifier:OnIntervalThink() end
assert(writes == before, "hidden units must not send repeated tombstones")
unit.survival_hide_custom_health_bar = nil
modifier:OnIntervalThink()
assert(writes == before + 1 and values.unit_42.health == "2000000000")
unit.invalid = true
modifier:OnIntervalThink()
assert(values.unit_42.removed == 1, "expired parent is cleared with cached entity id")
before = writes
modifier:OnIntervalThink(); modifier:OnDestroy()
assert(writes == before, "expired parent and destroy must publish only one removal")

unit, modifier = make_unit(42)
modifier:OnCreated()
assert(values.unit_42.health == 50 and values.unit_42.removed == nil)
unit.invalid = true
modifier:OnDestroy()
assert(values.unit_42.removed == 1, "direct destruction after handle expiry is preserved")

unit, modifier = make_unit(43)
CustomNetTables = {}
before = writes
modifier:OnCreated()
assert(writes == before)
CustomNetTables.SetTableValue = publish
modifier:OnIntervalThink()
assert(writes == before + 1 and values.unit_43.health == 50)

local bars = {}
before = writes
local projection_before = projections
for id = 100, 299 do
    local _, bar = make_unit(id)
    bar:OnCreated(); bars[#bars + 1] = bar
end
for _ = 1, 100 do for _, bar in ipairs(bars) do bar:OnIntervalThink() end end
assert(writes - before == 200 and projections - projection_before == 400)
print("HEALTH_BAR_CLEANUP_PASS: 200 stable units/100 polls => 200 initial writes, 0 repeated writes; damage/heal/scale/remove/reuse/transport recovery")
