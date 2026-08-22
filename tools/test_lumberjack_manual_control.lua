local root = assert(arg[1], "workspace root argument is required")
package.path = root .. "/scripts/vscripts/?.lua;"
    .. root .. "/scripts/vscripts/?/init.lua;"
    .. package.path

DOTA_UNIT_ORDER_MOVE_TO_POSITION = 1
DOTA_UNIT_ORDER_ATTACK_TARGET = 2
MODIFIER_ATTRIBUTE_PERMANENT = 1
MODIFIER_EVENT_ON_ATTACK_LANDED = 2

function class(definition) return definition end
function IsServer() return true end

local now = 0
GameRules = { GetGameTime = function() return now end }

local entities = {}
function EntIndexToHScript(entindex) return entities[tonumber(entindex)] end

local issued_orders = {}
function ExecuteOrderFromTable(order)
    issued_orders[#issued_orders + 1] = order
end

package.loaded["core/sound_service"] = { play = function() end }

local tree = { index = 20, alive = true }
function tree:IsNull() return false end
function tree:IsAlive() return self.alive end
function tree:entindex() return self.index end
function tree:GetTeamNumber() return 3 end
entities[tree.index] = tree

local worker = {
    index = 10,
    alive = true,
    idle = false,
    attack_target = nil,
    modifier = nil,
}
function worker:IsNull() return false end
function worker:IsAlive() return self.alive end
function worker:entindex() return self.index end
function worker:IsIdle() return self.idle end
function worker:GetAttackTarget() return self.attack_target end
function worker:GetTeamNumber() return 2 end
function worker:CanEntityBeSeenByMyTeam() return true end
function worker:FindModifierByName(name)
    if name == "modifier_lumberjack_ai" then return self.modifier end
end
entities[worker.index] = worker

local modifier_class = require("modifiers/modifier_lumberjack_ai")
local modifier = setmetatable({}, { __index = modifier_class })
function modifier:GetParent() return worker end
function modifier:StartIntervalThink(interval) self.interval = interval end
worker.modifier = modifier
modifier:OnCreated({ tree_entindex = tree.index, player_id = 0 })

local order_service = require("systems/lumberjack_order_service")
assert(order_service.process({
    order_type = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
    units = { worker.index },
}) == false, "lumberjack observer consumed a player movement order")

modifier:OnIntervalThink()
assert(#issued_orders == 0,
    "automatic chopping overrode a player movement order")

worker.idle = true
now = 10
modifier:OnIntervalThink()
now = 12.99
modifier:OnIntervalThink()
assert(#issued_orders == 0,
    "automatic chopping resumed before three idle seconds")

now = 13
modifier:OnIntervalThink()
assert(#issued_orders == 1
    and issued_orders[1].OrderType == DOTA_UNIT_ORDER_ATTACK_TARGET
    and issued_orders[1].TargetIndex == tree.index,
    "automatic chopping did not resume after three idle seconds")

worker.attack_target = tree
modifier:OnIntervalThink()
modifier:OnIntervalThink()
assert(#issued_orders == 1,
    "continuous chopping repeatedly reissued the same attack order")

worker.attack_target = nil
worker.idle = true
order_service.process({
    order_type = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
    units = { worker.index },
})
now = 20
modifier:OnIntervalThink()
now = 22
order_service.process({
    order_type = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
    units = { worker.index },
})
worker.idle = false
modifier:OnIntervalThink()
worker.idle = true
now = 23
modifier:OnIntervalThink()
now = 25.99
modifier:OnIntervalThink()
assert(#issued_orders == 1,
    "continued manual commands did not reset the idle timer")
now = 26
modifier:OnIntervalThink()
assert(#issued_orders == 2,
    "automatic chopping did not recover after the reset idle deadline")

worker.survival_lumberjack_internal_order = true
modifier.manual_control = false
order_service.process({
    order_type = DOTA_UNIT_ORDER_ATTACK_TARGET,
    entindex_target = tree.index,
    units = { worker.index },
})
assert(modifier.manual_control == false,
    "internal attack order was mistaken for a player command")

worker.survival_lumberjack_internal_order = nil
modifier.manual_control = true
order_service.process({
    order_type = DOTA_UNIT_ORDER_ATTACK_TARGET,
    entindex_target = tree.index,
    units = { worker.index },
})
assert(modifier.manual_control == false,
    "manual attack on the resource tree was treated as idle work")

print("LUMBERJACK_MANUAL_CONTROL_PASS")