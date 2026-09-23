package.path = "scripts/vscripts/?.lua;" .. package.path

-- Exercise the actual engine order filter. Loading must stop commands before
-- repair/lumberjack side effects, then preserve ownership and movement checks.
local ready, admitted = false, { [0] = true }
local effects = { lumber = 0, repair = 0, destination = 0 }
local units = {
    [101] = { owner = 0, constrained = true },
    [102] = { owner = 1 },
}
local destination_allowed, repair_handled = true, false
package.loaded["systems/startup_loading_service"] = {
    is_ready = function() return ready end,
    is_player_ready = function(player_id) return admitted[player_id] == true end,
}
package.loaded["systems/tree_damage_rules"] = {
    is_arrow_tower = function() return false end,
    is_tree = function() return false end,
}
package.loaded["systems/lumberjack_order_service"] = {
    process = function() effects.lumber = effects.lumber + 1 end,
}
package.loaded["systems/repair_order_service"] = {
    process = function() effects.repair = effects.repair + 1 return repair_handled end,
}
package.loaded["systems/destination_validation_service"] = {
    is_constrained_hero = function(unit) return unit.constrained == true end,
    validate = function()
        effects.destination = effects.destination + 1
        return destination_allowed
    end,
}
package.loaded["systems/anti_air_rules"] = { is_anti_air_tower = function() return false end }
package.loaded["systems/player_context_service"] = {
    owner_player_id = function(unit) return unit.owner end,
}
DOTA_UNIT_ORDER_MOVE_TO_POSITION = 1
DOTA_UNIT_ORDER_ATTACK_MOVE = 2
DOTA_UNIT_ORDER_ATTACK_TARGET = 3
Vector = function(x, y, z) return { x = x, y = y, z = z } end
EntIndexToHScript = function(index) return units[index] end

local installed, registrations
registrations = 0
GameRules = { GetGameModeEntity = function()
    return { SetExecuteOrderFilter = function(_, callback, context)
        registrations = registrations + 1
        installed = function(keys) return callback(context, keys) end
    end }
end }
local orders = require("systems/tree_attack_order_filter")
assert(orders.register() and orders.register())
assert(registrations == 1 and installed, "filter installs once, through the engine API")

local function move(player_id, unit)
    return { issuer_player_id_const = player_id, units = { ["0"] = unit or 101 },
        order_type = DOTA_UNIT_ORDER_MOVE_TO_POSITION, position_x = 10, position_y = 20, position_z = 0 }
end
assert(installed(move(0)) == false, "known player's move is blocked until everyone is ready")
assert(installed(move(-1)) == false, "server/AI orders also wait for the global gate")
assert(installed({ issuer_player_id_const = 0, units = { ["0"] = 101 }, order_type = 99 }) == false,
    "non-movement commands cannot bypass loading")
assert(effects.lumber == 0 and effects.repair == 0 and effects.destination == 0,
    "loading rejects commands before any gameplay side effects")

ready = true
assert(installed(move(2)) == false, "late entrant outside the frozen ready roster is blocked")
assert(installed(move(0, 102)) == false, "admitted player cannot issue orders for another player's unit")
assert(effects.lumber == 0 and effects.repair == 0, "identity rejection has no order side effects")
assert(installed(move(0)) == true, "admitted player's owned hero can move")
assert(effects.destination == 1, "normal destination validation is still enforced")
destination_allowed = false
assert(installed(move(0)) == false, "opening the startup gate does not bypass forbidden destinations")
destination_allowed = true
repair_handled = true
assert(installed(move(0)) == false, "handled repair commands still consume the native order")
repair_handled = false
admitted[0] = false
local before = effects.lumber
assert(installed(move(0)) == false, "a disconnected or identity-changed player cannot continue ordering")
assert(effects.lumber == before, "revoked readiness is checked before gameplay work")
assert(installed(move(-1, 102)) == true, "server-driven AI remains usable after startup release")

print("STARTUP_ORDER_GATE_PASS: engine registration, pre-ready side-effect prevention, frozen roster, ownership, destinations, repair and AI")
