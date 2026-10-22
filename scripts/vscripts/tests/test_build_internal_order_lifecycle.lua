-- Real order filter + repair service: delayed build moves must not cancel the
-- task that issued them, while subsequent player orders still cancel it.
package.path = "scripts/vscripts/?.lua;" .. package.path
local clock = 10
GameRules = {GetGameTime = function() return clock end}
DOTA_UNIT_ORDER_MOVE_TO_POSITION, DOTA_UNIT_ORDER_ATTACK_MOVE = 1, 2
DOTA_UNIT_ORDER_ATTACK_TARGET, DOTA_UNIT_ORDER_STOP = 3, 4
DOTA_UNIT_ORDER_MOVE_TO_TARGET = 5
Vector = function(x, y, z) return {x=x, y=y, z=z} end
local builder = {survival_player_id=0}
function builder:IsNull() return false end
function builder:FindModifierByName() return nil end
EntIndexToHScript = function(index) return index == 101 and builder or nil end
package.loaded["systems/tree_damage_rules"] = {
    is_arrow_tower = function() return false end,
    is_tree = function() return false end,
}
package.loaded["systems/lumberjack_order_service"] = {process = function() end}
package.loaded["systems/destination_validation_service"] = {is_constrained_hero = function() return false end}
package.loaded["systems/anti_air_rules"] = {is_anti_air_tower = function() return false end}
package.loaded["systems/player_context_service"] = {
    owner_player_id = function(unit) return unit.survival_player_id end,
    is_defeated = function() return false end,
}
package.loaded["systems/startup_loading_service"] = {
    is_ready = function() return true end,
    is_player_ready = function() return true end,
}
local service = require("systems/repair_order_service")
local filter = require("systems/tree_attack_order_filter")._filter_for_test
local function task()
    local value = {timeout_at=20, internal_move_order={x=96, y=128, expires_at=10.5}}
    builder.survival_build_task = value
    builder.survival_build_internal_order = nil
    return value
end
local function order(kind, x, y, issuer)
    return filter(nil, {issuer_player_id_const=issuer or 0,
        units={["0"]=101}, order_type=kind, position_x=x, position_y=y})
end
local accepted = task()
assert(order(DOTA_UNIT_ORDER_MOVE_TO_POSITION, 96, 128), "internal move reaches the engine")
assert(builder.survival_build_task == accepted,
    "deferred internal move with owner issuer must preserve its originating build task")
assert(accepted.internal_move_order == nil, "signature is consumed once")
assert(order(DOTA_UNIT_ORDER_MOVE_TO_POSITION, 96, 128))
assert(builder.survival_build_task == nil, "a later player move to the same point still cancels")

for _, kind in ipairs({DOTA_UNIT_ORDER_STOP, DOTA_UNIT_ORDER_ATTACK_TARGET,
    DOTA_UNIT_ORDER_ATTACK_MOVE, DOTA_UNIT_ORDER_MOVE_TO_TARGET}) do
    task();order(kind, 96, 128)
    assert(builder.survival_build_task == nil, "a real player order cannot be hidden by the build signature")
end
task();order(DOTA_UNIT_ORDER_MOVE_TO_POSITION, 160, 128)
assert(builder.survival_build_task == nil, "a different player move cancels even before the internal move arrives")

accepted=task();clock=10.6;order(DOTA_UNIT_ORDER_MOVE_TO_POSITION, 96, 128)
assert(builder.survival_build_task == nil and accepted.internal_move_order == nil,
    "expired signature never preserves a build")
clock=10;accepted=task();accepted.timeout_at=10
order(DOTA_UNIT_ORDER_MOVE_TO_POSITION, 96, 128)
assert(builder.survival_build_task == nil, "expired task cannot consume an internal signature")

accepted=task();assert(order(DOTA_UNIT_ORDER_MOVE_TO_POSITION, 96, 128, -1))
assert(builder.survival_build_task == accepted and accepted.internal_move_order == nil,
    "server-issuer move consumes its signature too")
order(DOTA_UNIT_ORDER_MOVE_TO_POSITION, 96, 128)
assert(builder.survival_build_task == nil, "no signature lingers after normal server filtering")

accepted=task();builder.survival_build_internal_order=true
order(DOTA_UNIT_ORDER_MOVE_TO_POSITION, 96, 128)
builder.survival_build_internal_order=nil
assert(builder.survival_build_task == accepted and accepted.internal_move_order == nil,
    "synchronous internal order remains supported")
assert(service.expect_build_move(builder, accepted, Vector(320, 640, 0)))
assert(not service.expect_build_move(builder, {}, Vector(320, 640, 0)), "stale task cannot arm a move")
assert(not order(DOTA_UNIT_ORDER_MOVE_TO_POSITION, 320, 640, 1), "ownership gate still rejects another player")
assert(builder.survival_build_task == accepted, "ownership rejection cannot consume the owner's expected move")
assert(order(DOTA_UNIT_ORDER_MOVE_TO_POSITION, 320, 640))
assert(builder.survival_build_task == accepted and accepted.internal_move_order == nil)
print("BUILD_INTERNAL_ORDER_PASS: delayed owner/server/synchronous moves, one-shot task binding, expiry, real player cancellation and ownership")
