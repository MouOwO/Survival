package.path = "scripts/vscripts/?.lua;" .. package.path
local events = require("core/events")
local handlers, wood, awarded, number_calls = {}, {}, 0, 0
local frame, wall_reads, scans = 10, 0, 0
local next_index = 0
local function entity(fields)
    local result = fields or {}
    next_index = next_index + 1
    result.index = next_index
    function result:IsNull() return self.removed == true end
    function result:entindex() return self.index end
    function result:GetHealth() return self.health or 100 end
    function result:IsAlive() return self.alive ~= false end
    function result:GetAttackTarget() return self.target end
    return result
end
local walls = {[0] = entity(), [1] = entity()}
local enemy = entity({survival_is_wave_monster = true, target = walls[1]})
local ambient = entity({target = walls[0]})
local enemies = {enemy, ambient}
local tree = entity()
local worker = entity({allowed = true})
GameRules = { GetGameTime = function() return frame end }
Entities = { FindAllByClassname = function(_, name)
    assert(name == "npc_dota_creature")
    scans = scans + 1
    return enemies
end }
PlayerResource = {GetPlayer = function(_, id) return {id = id} end}
RandomFloat = function() return 99 end
package.loaded["systems/tree_damage_rules"] = {is_allowed_tree_attacker = function(unit) return unit.allowed end}
package.loaded["systems/rogue_effect_state_service"] = {numeric = function(_, key)
    return key == "builder_peaceful_wood_per_hit" and 2 or 0
end}
package.loaded["core/particle_manager"] = {show_green_number = function(_, amount, player)
    assert(player and amount > 0)
    number_calls = number_calls + 1
end}
package.loaded["core/event_bus"] = {
    subscribe = function(event, callback) handlers[event] = callback end,
    emit = function() end,
    request = function(event, payload)
        if event == events.BUILDING_LIST_REQUEST then
            wall_reads = wall_reads + 1
            return {buildings = walls[payload.player_id] and {{building_id = "wall", unit = walls[payload.player_id]}} or {}}
        elseif event == events.RESOURCE_ADD_REQUEST then
            wood[payload.player_id] = (wood[payload.player_id] or 0) + payload.wood
            awarded = awarded + 1
            return {ok = true}
        elseif event == events.GRID_OCCUPY_REQUEST then return {ok = true}
        else error("Unexpected request: " .. tostring(event)) end
    end,
}
local service = require("systems/tree_system")
service.init()
service._reset_for_test(1, tree)
local function hit(player, count, attacker, target)
    for _ = 1, count or 1 do
        handlers[events.TREE_HIT]({player_id = player, team = 2,
            attacker = attacker or worker, target = target or tree,
            source = "lumberjack", base_lumber_efficiency = 3})
    end
end

-- 100 real settlements remain 100 settlements/numbers, while repeated queries
-- share one frame snapshot. Other players still use their own wall and bonus.
hit(0, 100)
assert(wood[0] == 500 and awarded == 100 and number_calls == 100)
assert(scans == 1 and wall_reads == 1)
hit(1, 100)
assert(wood[1] == 300 and awarded == 200)
assert(scans == 1 and wall_reads == 2)
enemy.target = nil
frame = frame + 0.03
hit(1)
assert(wood[1] == 305 and scans == 2 and wall_reads == 3, "next frame must see target changes")

-- No wall also caches the empty lookup, but does not invent another player's
-- under-attack state. Dead/ambient creatures do not suppress the bonus.
hit(2, 20)
assert(wood[2] == 100 and wall_reads == 4 and scans == 2)
enemy.target, enemy.alive = walls[0], false
frame = frame + 0.03
hit(0)
assert(wood[0] == 505 and scans == 3)
enemy.alive, enemy.survival_is_wave_monster, enemy.survival_is_challenge_monster = true, false, true
frame = frame + 0.03
hit(0)
assert(wood[0] == 508 and scans == 4)

-- Init clears an otherwise identical game-time cache; invalid callers and
-- unrelated targets cannot cause harvesting or whole-map scans.
local before_scans, before_wood = scans, wood[0]
service.init()
service._reset_for_test(1, tree)
enemy.target = nil
hit(0)
assert(wood[0] == before_wood + 5 and scans == before_scans + 1)
local settled = awarded
hit(0, 10, entity())
hit(0, 10, worker, entity())
assert(awarded == settled and scans == before_scans + 1)

-- Without a real simulation clock no data can become permanently cached.
GameRules = nil
local fallback_scans = scans
hit(0)
enemy.target = walls[0]
hit(0)
assert(scans == fallback_scans + 2)
assert(wood[0] == before_wood + 13)
print("TREE_HIT_SCAN_COALESCING_PASS: 200 hits retain exact player rewards; 1 shared scan and 2 wall lookups per frame")
