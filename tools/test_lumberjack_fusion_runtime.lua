package.path = "scripts/vscripts/?.lua;" .. package.path
local builder = require("ui/ability_runtime_builder")
local definitions = require("config/generated/lumberjack_fusion_definitions")
local caster = {survival_player_id = 0, survival_worker_type = "lumberjack"}
function caster:IsNull() return false end
function caster:IsAlive() return true end
function caster:entindex() return 42 end
function caster:GetTeamNumber() return 2 end
local state = {player_id = 0, unit = caster}
for _, row in ipairs(definitions.rows) do
    caster.survival_lumberjack_level = row.level
    local snapshot = {city_level = row.required_city_level,
        counts = {[row.level] = row.required_count}, eligible = {[42] = true}}
    local function build(wallet) return builder.build(row.ability_id, state, wallet, snapshot) end
    local runtime = build({gold = 0, wood = 0})
    assert(runtime.available == 1 and runtime.prerequisite_met == 1)
    assert(runtime.can_afford == 1 and runtime.resource_check_on_cast == 1)
    assert(runtime.cost_gold == row.gold_cost and runtime.cost_wood == row.wood_cost)
    assert(runtime.fields[2].value == tostring(row.required_count) .. "/" .. tostring(row.required_count))
    assert(runtime.status_text == build({gold = 1e15, wood = 1e15}).status_text,
        "wallet updates do not replace the ready status")
    snapshot.counts[row.level] = row.required_count - 1
    assert(build().prerequisite_met == 0 and build().available == 0)
    snapshot.counts[row.level] = row.required_count
    snapshot.city_level = row.required_city_level - 1
    assert(build().prerequisite_met == 0 and build().available == 0)
end
print("FUSION_RUNTIME_GATES_PASS: all eight live unit projections, count/city authority, costs and wallet-independent click-time validation")
